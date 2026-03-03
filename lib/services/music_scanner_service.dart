import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:async/async.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../models/music_model.dart';
import '../models/settings_model.dart';
import 'id3_parser.dart';

/// Music scanner service that handles scanning music folders
/// across different platforms (PC/Desktop and Mobile) with optimized performance
class MusicScannerService {
  /// Supported audio file extensions
  static const List<String> supportedExtensions = [
    '.mp3',
    '.m4a',
    '.wav',
    '.flac',
    '.aac',
    '.ogg',
    '.wma',
  ];

  /// Debug flag - when true, prints all music paths found
  static bool debugMode = true;

  // Internal quick lookup set for performance
  static final Set<String> _extSet =
      supportedExtensions.map((e) => e.toLowerCase()).toSet();

  // Database instance for caching
  static Database? _cacheDb;

  // Cancellation token for scanning
  static CancelableOperation? _scanOperation;

  // Batch update interval (milliseconds)
  static const int _batchUpdateInterval = 1000;

  // Maximum parallel workers for metadata extraction
  static const int _maxParallelWorkers = 3;

  // Metadata extraction timeout (milliseconds)
  static const int _metadataTimeout = 500;

  // Minimum file size (bytes) to consider as valid audio file
  static const int _minFileSize = 1024;

  // OnAudioQuery instance for querying audio files
  static final OnAudioQuery _audioQuery = OnAudioQuery();

  /// Initialize the cache database
  static Future<Database> _initializeCacheDb() async {
    if (_cacheDb != null) {
      return _cacheDb!;
    }

    final documentsDirectory = await getApplicationDocumentsDirectory();
    final dbPath = p.join(documentsDirectory.path, 'music_scan_cache.db');

    _cacheDb = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE file_cache (
            file_path TEXT PRIMARY KEY,
            last_modified INTEGER,
            file_size INTEGER
          )
        ''');
      },
    );

    return _cacheDb!;
  }

  /// Check if file has been modified since last scan
  static Future<bool> _isFileModified(File file) async {
    try {
      final db = await _initializeCacheDb();

      final result = await db.query(
        'file_cache',
        where: 'file_path = ?',
        whereArgs: [file.path],
      );

      final stat = await file.stat();

      if (result.isEmpty) {
        // File not in cache - needs to be processed
        await db.insert(
          'file_cache',
          {
            'file_path': file.path,
            'last_modified': stat.modified.millisecondsSinceEpoch,
            'file_size': stat.size,
          },
        );
        return true;
      }

      final cached = result.first;
      final cachedModified = (cached['last_modified'] is int)
          ? (cached['last_modified'] as int)
          : int.tryParse('${cached['last_modified']}') ?? 0;
      final fileSize = (cached['file_size'] is int)
          ? (cached['file_size'] as int)
          : int.tryParse('${cached['file_size']}') ?? 0;

      if (stat.modified.millisecondsSinceEpoch != cachedModified ||
          stat.size != fileSize) {
        // File has been modified - update cache
        await db.update(
          'file_cache',
          {
            'last_modified': stat.modified.millisecondsSinceEpoch,
            'file_size': stat.size,
          },
          where: 'file_path = ?',
          whereArgs: [file.path],
        );
        return true;
      }

      // File unchanged - skip processing
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('Error checking file modification: $e');
      }
      return true; // Fallback to processing file
    }
  }

  /// Check if file should be processed (valid extension, not hidden, size >= 1KB)
  static Future<bool> _shouldProcessFile(File file) async {
    try {
      final fileName = p.basename(file.path);
      if (fileName.startsWith('.') || fileName.startsWith('~')) {
        return false; // Skip hidden files
      }

      final stat = await file.stat();
      if (stat.size < _minFileSize) {
        return false; // Skip files smaller than 1KB
      }

      final lowerPath = file.path.toLowerCase();
      if (!_extSet.any((ext) => lowerPath.endsWith(ext))) {
        return false; // Skip unsupported file formats
      }

      return await _isFileModified(file);
    } catch (e) {
      if (kDebugMode) {
        print('Error checking file validity: $e');
      }
      return false;
    }
  }

  /// Check if a file extension is supported
  static bool _isSupportedExtension(String filePath) {
    final lowerPath = filePath.toLowerCase();
    return _extSet.any((ext) => lowerPath.endsWith(ext));
  }

  /// Scan system music folders and user-defined paths with optimizations
  /// Returns a list of music file paths
  static Future<List<String>> scanSystemMusicFolders({
    Function(String)? onProgress,
    Function(List<Music>)? onBatchUpdate,
  }) async {
    final stopwatch = Stopwatch()..start();
    final Set<String> musicPathsSet = <String>{};

    if (kDebugMode && debugMode) {
      print('=== Music Scanner Debug ===');
      print('Platform: ${Platform.operatingSystem}');
    }

    // First, scan user-defined paths from settings
    final settings = SettingsModel();
    await settings.loadSettings();

    if (settings.musicSourcePaths.isNotEmpty) {
      if (kDebugMode && debugMode) {
        print('=== Scanning User-Defined Paths ===');
        print('User paths: ${settings.musicSourcePaths}');
      }

      // Scan user paths in parallel (but limited by OS/file system)
      final futures = <Future<List<String>>>[];
      for (final path in settings.musicSourcePaths) {
        onProgress?.call(path);
        final dir = Directory(path);
        futures.add(_scanDirectoryIfExists(dir));
      }

      final results = await Future.wait(futures);
      for (final list in results) {
        musicPathsSet.addAll(list);
      }
    }

    // If no music files were found in user-defined paths, scan system default locations
    if (musicPathsSet.isEmpty) {
      if (kDebugMode && debugMode) {
        print('=== No music found in user paths, scanning system default locations ===');
      }
      
      if (Platform.isAndroid) {
        // Android: Use MediaStore for properscoped storage access
        final results = await _scanAndroidMusicWithMediaStore(onProgress: onProgress);
        musicPathsSet.addAll(results);
        
        // Fallback to file system scan if MediaStore returns nothing
        if (musicPathsSet.isEmpty) {
          if (kDebugMode && debugMode) {
            print('=== MediaStore returned empty, falling back to file system scan ===');
          }
          final fallbackResults = await _scanAndroidMusicFallback(onProgress: onProgress);
          musicPathsSet.addAll(fallbackResults);
        }
      } else if (Platform.isIOS) {
        // iOS: Use app documents directory (limited access)
        final results = await _scanIOSMusicFolders(onProgress: onProgress);
        musicPathsSet.addAll(results);
      } else if (Platform.isWindows) {
        // Windows: Scan user music folder and common locations
        final results = await _scanWindowsMusicFolders(onProgress: onProgress);
        musicPathsSet.addAll(results);
      } else if (Platform.isMacOS) {
        // macOS: Scan user music folder
        final results = await _scanMacOSMusicFolders(onProgress: onProgress);
        musicPathsSet.addAll(results);
      } else if (Platform.isLinux) {
        // Linux: Scan user music folder
        final results = await _scanLinuxMusicFolders(onProgress: onProgress);
        musicPathsSet.addAll(results);
      }
    }

    final musicPaths = musicPathsSet.toList()..sort();

    if (kDebugMode && debugMode) {
      print('=== Total Music Files Found: ${musicPaths.length} ===');
      for (var path in musicPaths) {
        print('Music Path: $path');
      }
      print('===========================');
    }

    stopwatch.stop();
    if (kDebugMode) {
      print('Scan duration: ${stopwatch.elapsedMilliseconds}ms');
    }

    return musicPaths;
  }

  /// Scan Android music using on_audio_query package (recommended for Android)
  static Future<List<String>> _scanAndroidMusicWithMediaStore({
    Function(String)? onProgress,
  }) async {
    final Set<String> musicPathsSet = <String>{};

    if (kDebugMode && debugMode) {
      print('=== Using on_audio_query to scan Android music ===');
    }

    // Request permissions first
    final permissionsGranted = await _requestStoragePermissions();
    
    if (!permissionsGranted) {
      if (kDebugMode) {
        print('Storage permissions not granted, cannot query audio');
      }
      return [];
    }

    try {
      // Query all audio files using on_audio_query
      onProgress?.call('Querying audio files...');
      
      final audioFiles = await _audioQuery.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );
      
      if (kDebugMode && debugMode) {
        print('on_audio_query returned ${audioFiles.length} audio files');
      }

      for (final song in audioFiles) {
        try {
          // Get the file path from the song model
          final String filePath = song.data;
          
          if (filePath.isEmpty) {
            continue;
          }

          // Check if it's a supported audio format
          if (!_isSupportedExtension(filePath)) {
            continue;
          }

          // Skip if file doesn't exist
          if (!await File(filePath).exists()) {
            continue;
          }

          musicPathsSet.add(filePath);
          
          if (kDebugMode && debugMode) {
            print('Found audio file: $filePath');
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error processing audio entry: $e');
          }
        }
      }

      if (kDebugMode && debugMode) {
        print('Android on_audio_query found: ${musicPathsSet.length} files');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error using on_audio_query: $e');
        print('Falling back to file system scan...');
      }
    }

    return musicPathsSet.toList();
  }

  /// Fallback file system scan for Android (for older devices or when MediaStore fails)
  static Future<List<String>> _scanAndroidMusicFallback({
    Function(String)? onProgress,
  }) async {
    final Set<String> musicPathsSet = <String>{};

    if (kDebugMode && debugMode) {
      print('=== Using fallback file system scan for Android ===');
    }

    // Request permissions
    final permissionsGranted = await _requestStoragePermissions();

    if (!permissionsGranted) {
      if (kDebugMode) {
        print('Storage permissions not granted');
      }
      return [];
    }

    // Common Android music directories to scan
    final List<String> androidMusicDirs = [
      '/storage/emulated/0/Music',
      '/storage/emulated/0/Download',
      '/storage/emulated/0/DCIM',
    ];

    // Try to get external storage directories
    try {
      // Get external storage directories
      final extDirs = await getExternalStorageDirectories(type: StorageDirectory.music);
      if (extDirs != null && extDirs.isNotEmpty) {
        for (final d in extDirs) {
          if (d.path.isNotEmpty) {
            androidMusicDirs.add(d.path);
          }
        }
      }

      // Try to get the main external storage directory
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        try {
          // Navigate up to find common music directories
          String currentPath = extDir.path;
          // Go up several levels to get to the root of external storage
          for (int i = 0; i < 5; i++) {
            final parent = Directory(currentPath).parent;
            if (parent.path == currentPath) break; // Reached root
            currentPath = parent.path;
          }
          
          // Add common directories
          androidMusicDirs.add(p.join(currentPath, 'Music'));
          androidMusicDirs.add(p.join(currentPath, 'Download'));
          androidMusicDirs.add(p.join(currentPath, 'Downloads'));
          androidMusicDirs.add(p.join(currentPath, 'Ringtones'));
          androidMusicDirs.add(p.join(currentPath, 'Podcasts'));
          androidMusicDirs.add(p.join(currentPath, 'Alarms'));
          androidMusicDirs.add(p.join(currentPath, 'Notifications'));
        } catch (_) {}
      }
    } catch (e) {
      if (kDebugMode) print('Error getting external storage directories: $e');
    }

    // Also try common paths directly
    try {
      // Check /storage directory
      final storageDir = Directory('/storage');
      if (await storageDir.exists()) {
        await for (final entity in storageDir.list(followLinks: false)) {
          if (entity is Directory) {
            final emulatedDir = Directory(p.join(entity.path, 'emulated'));
            if (await emulatedDir.exists()) {
              await for (final emulatedEntity in emulatedDir.list(followLinks: false)) {
                if (emulatedEntity is Directory) {
                  androidMusicDirs.add(p.join(emulatedEntity.path, 'Music'));
                  androidMusicDirs.add(p.join(emulatedEntity.path, 'Download'));
                  androidMusicDirs.add(p.join(emulatedEntity.path, 'Downloads'));
                }
              }
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error scanning /storage directory: $e');
    }

    // Remove duplicates and scan existing directories
    final uniqueDirs = androidMusicDirs.toSet().toList();
    
    if (kDebugMode && debugMode) {
      print('Scanning directories: $uniqueDirs');
    }

    final futures = <Future<List<String>>>[];

    for (final dirPath in uniqueDirs) {
      onProgress?.call(dirPath);
      final dir = Directory(dirPath);
      futures.add(_scanDirectoryIfExists(dir));
    }

    final results = await Future.wait(futures);
    for (final list in results) {
      musicPathsSet.addAll(list);
    }

    if (kDebugMode && debugMode) {
      print('Android fallback scan found: ${musicPathsSet.length} files');
    }

    return musicPathsSet.toList();
  }

  /// Request storage permissions for Android
  static Future<bool> _requestStoragePermissions() async {
    try {
      if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        final sdk = androidInfo.version.sdkInt;

        if (kDebugMode && debugMode) {
          print('Android SDK: $sdk');
        }

        if (sdk >= 33) {
          // Android 13+ - use READ_MEDIA_AUDIO
          final status = await Permission.audio.status;
          if (status.isGranted) {
            if (kDebugMode && debugMode) print('READ_MEDIA_AUDIO already granted');
            return true;
          } else if (status.isDenied) {
            final req = await Permission.audio.request();
            if (kDebugMode && debugMode) print('READ_MEDIA_AUDIO permission request: $req');
            return req.isGranted;
          }
        } 
        
        if (sdk >= 30) {
          // Android 11-12 - try MANAGE_EXTERNAL_STORAGE or READ_EXTERNAL_STORAGE
          // First try the newer audio permission
          final audioStatus = await Permission.audio.status;
          if (audioStatus.isGranted) {
            if (kDebugMode && debugMode) print('Audio permission granted');
            return true;
          }
          
          // Try manage external storage for full access
          if (await Permission.manageExternalStorage.isGranted) {
            if (kDebugMode && debugMode) print('Manage external storage already granted');
            return true;
          } else {
            final manageStatus = await Permission.manageExternalStorage.request();
            if (kDebugMode && debugMode) {
              print('ManageExternalStorage status: $manageStatus');
            }
            if (manageStatus.isGranted) {
              return true;
            }

            // Fallback to READ_EXTERNAL_STORAGE
            final storageStatus = await Permission.storage.request();
            if (kDebugMode && debugMode) print('Fallback storage status: $storageStatus');
            return storageStatus.isGranted;
          }
        } 
        
        // Android < 11 - use READ_EXTERNAL_STORAGE
        final status = await Permission.storage.status;
        if (status.isGranted) {
          return true;
        } else if (status.isDenied || status.isRestricted) {
          final req = await Permission.storage.request();
          if (kDebugMode && debugMode) print('Storage permission request: $req');
          return req.isGranted;
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error requesting permissions: $e');
    }

    return false;
  }

  /// Scan iOS music folders (limited access)
  static Future<List<String>> _scanIOSMusicFolders({
    Function(String)? onProgress,
  }) async {
    final Set<String> musicPathsSet = <String>{};

    // iOS has limited file system access
    // Try to access app documents directory
    try {
      final docDir = await getApplicationDocumentsDirectory();
      onProgress?.call(docDir.path);

      final dir = Directory(docDir.path);
      final files = await _scanDirectoryIfExists(dir);
      musicPathsSet.addAll(files);
    } catch (e) {
      if (kDebugMode) print('Error scanning iOS directories: $e');
    }

    return musicPathsSet.toList();
  }

  /// Scan Windows music folders
  static Future<List<String>> _scanWindowsMusicFolders({
    Function(String)? onProgress,
  }) async {
    final Set<String> musicPathsSet = <String>{};

    try {
      final userDir = Platform.environment['USERPROFILE'] ?? '';
      final musicDir = p.join(userDir, 'Music');
      final downloadsDir = p.join(userDir, 'Downloads');

      // Prepare list of directories to scan
      final List<String> dirsToScan = [
        musicDir,
        downloadsDir,
        'C:\\Users\\Public\\Music',
        p.join(userDir, 'Desktop')
      ];

      // Scan in parallel
      final futures = <Future<List<String>>>[];
      for (final d in dirsToScan) {
        onProgress?.call(d);
        futures.add(_scanDirectoryIfExists(Directory(d)));
      }

      final results = await Future.wait(futures);
      for (final list in results) {
        musicPathsSet.addAll(list);
      }
    } catch (e) {
      if (kDebugMode) print('Error scanning Windows directories: $e');
    }

    return musicPathsSet.toList();
  }

  /// Scan macOS music folders
  static Future<List<String>> _scanMacOSMusicFolders({
    Function(String)? onProgress,
  }) async {
    final Set<String> musicPathsSet = <String>{};

    try {
      final homeDir = Platform.environment['HOME'] ?? '';
      final musicDir = p.join(homeDir, 'Music');
      final downloadsDir = p.join(homeDir, 'Downloads');
      final desktopDir = p.join(homeDir, 'Desktop');

      final List<String> dirsToScan = [musicDir, downloadsDir, desktopDir];

      final futures = <Future<List<String>>>[];
      for (final d in dirsToScan) {
        onProgress?.call(d);
        futures.add(_scanDirectoryIfExists(Directory(d)));
      }

      final results = await Future.wait(futures);
      for (final list in results) {
        musicPathsSet.addAll(list);
      }
    } catch (e) {
      if (kDebugMode) print('Error scanning macOS directories: $e');
    }

    return musicPathsSet.toList();
  }

  /// Scan Linux music folders
  static Future<List<String>> _scanLinuxMusicFolders({
    Function(String)? onProgress,
  }) async {
    final Set<String> musicPathsSet = <String>{};

    try {
      final homeDir = Platform.environment['HOME'] ?? '';
      final musicDir = p.join(homeDir, 'Music');
      final downloadsDir = p.join(homeDir, 'Downloads');
      final desktopDir = p.join(homeDir, 'Desktop');

      final List<String> dirsToScan = [musicDir, downloadsDir, desktopDir];

      final futures = <Future<List<String>>>[];
      for (final d in dirsToScan) {
        onProgress?.call(d);
        futures.add(_scanDirectoryIfExists(Directory(d)));
      }

      final results = await Future.wait(futures);
      for (final list in results) {
        musicPathsSet.addAll(list);
      }
    } catch (e) {
      if (kDebugMode) print('Error scanning Linux directories: $e');
    }

    return musicPathsSet.toList();
  }

  /// Recursively scan a directory for audio files with optimized performance
  static Future<List<String>> _scanDirectory(Directory dir) async {
    final List<String> files = [];

    try {
      // Use a stream to process files asynchronously
      final stream = dir.list(recursive: true, followLinks: false);

      await for (final entity in stream) {
        if (_scanOperation?.isCanceled ?? false) {
          break;
        }

        try {
          if (entity is File) {
            if (await _shouldProcessFile(entity)) {
              files.add(entity.path);
              if (kDebugMode && debugMode) {
                print('Found music file: ${entity.path}');
              }
            }
          }
        } catch (inner) {
          // ignore errors for individual files (permissions, file gone, etc)
          if (kDebugMode) {
            print('Error processing entity ${entity.path}: $inner');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error scanning directory ${dir.path}: $e');
    }

    return files;
  }

  // Helper: check exists then scan (avoids try/catch at call sites)
  static Future<List<String>> _scanDirectoryIfExists(Directory dir) async {
    try {
      if (await dir.exists()) {
        return await _scanDirectory(dir);
      }
    } catch (e) {
      if (kDebugMode) print('Error accessing directory ${dir.path}: $e');
    }
    return <String>[];
  }

  /// Create Music objects from file paths with optimized parallel processing
  static Future<List<Music>> createMusicListFromPaths(List<String> paths,
      {Function(List<Music>)? onBatchUpdate}) async {
    final stopwatch = Stopwatch()..start();
    final parser = ID3Parser();
    final List<Music> results = [];

    // local helper to process single file path
    Future<Music?> processPath(String path) async {
      if (_scanOperation?.isCanceled ?? false) return null;
      try {
        // Timeout metadata extraction
        final operation = CancelableOperation.fromFuture(
          parser.parseTagsFromFile(path),
          onCancel: () => {},
        );

        final tags = await Future.any([
          operation.value,
          Future.delayed(Duration(milliseconds: _metadataTimeout), () => <String, dynamic>{}),
        ]);

        final music = parser.createMusicFromTags(path, tags);

        if (kDebugMode && debugMode) {
          print('Created Music object: ${music.title} - ${music.artist}');
        }

        return music;
      } catch (e) {
        if (kDebugMode) {
          print('Error creating Music object for $path: $e');
        }
        return null;
      }
    }

    final batchResults = <Music>[];
    DateTime lastUpdateTime = DateTime.now();

    for (int i = 0; i < paths.length; i += _maxParallelWorkers) {
      if (_scanOperation?.isCanceled ?? false) {
        break;
      }

      final end = (i + _maxParallelWorkers > paths.length) ? paths.length : i + _maxParallelWorkers;
      final sub = paths.sublist(i, end);
      final futures = sub.map((p) => processPath(p)).toList();
      final currentBatchResults = await Future.wait(futures);

      final validResults = currentBatchResults.whereType<Music>().toList();
      batchResults.addAll(validResults);
      results.addAll(validResults);

      // Check if we need to send batch update
      final now = DateTime.now();
      if (now.difference(lastUpdateTime).inMilliseconds >= _batchUpdateInterval) {
        lastUpdateTime = now;
        onBatchUpdate?.call(List.from(batchResults));
      }
    }

    // Send final batch update (if anything new)
    if (batchResults.isNotEmpty) {
      onBatchUpdate?.call(batchResults);
    }

    stopwatch.stop();
    if (kDebugMode) {
      print('Metadata extraction duration: ${stopwatch.elapsedMilliseconds}ms');
    }

    return batchResults;
  }

  /// Start scanning with cancellation support
  static Future<List<Music>> startScanning({
    Function(String)? onProgress,
    Function(List<Music>)? onBatchUpdate,
  }) async {
    // Cancel any existing scan
    await cancelScanning();

    // Start new scan with cancellation token
    _scanOperation = CancelableOperation.fromFuture(
          () async {
        final paths = await scanSystemMusicFolders(
          onProgress: onProgress,
        );
        return await createMusicListFromPaths(
          paths,
          onBatchUpdate: onBatchUpdate,
        );
      }(),
      onCancel: () {
        if (kDebugMode) {
          print('Scan cancelled');
        }
      },
    );

    try {
      return await _scanOperation!.value;
    } catch (e) {
      // Check if the exception is a cancellation error
      if (e.toString().toLowerCase().contains('cancel')) {
        return [];
      }
      rethrow;
    }
  }

  /// Cancel ongoing scan
  static Future<void> cancelScanning() async {
    if (_scanOperation != null && !_scanOperation!.isCompleted) {
      await _scanOperation!.cancel();
    }
    _scanOperation = null;
  }

  /// Cleanup cache database
  static Future<void> cleanupCache() async {
    try {
      final db = await _initializeCacheDb();
      await db.delete('file_cache');
    } catch (e) {
      if (kDebugMode) {
        print('Error cleaning up cache: $e');
      }
    }
  }

  /// Print all music paths for debugging
  static void printAllMusicPaths(List<Music> musicList) {
    if (kDebugMode) {
      print('=== DEBUG: All Music Paths ===');
      print('Total music files: ${musicList.length}');
      print('');
      for (int i = 0; i < musicList.length; i++) {
        final music = musicList[i];
        print('[$i] Title: ${music.title}');
        print('    Artist: ${music.artist}');
        print('    Album: ${music.album}');
        print('    Path: ${music.filePath}');
        print('');
      }
      print('===========================');
    }
  }
}
