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
      version: 2, // Increment version
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE file_cache (
            file_path TEXT PRIMARY KEY,
            last_modified INTEGER,
            file_size INTEGER,
            title TEXT,
            artist TEXT,
            album TEXT,
            genre TEXT,
            cover_path TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE file_cache ADD COLUMN title TEXT');
          await db.execute('ALTER TABLE file_cache ADD COLUMN artist TEXT');
          await db.execute('ALTER TABLE file_cache ADD COLUMN album TEXT');
          await db.execute('ALTER TABLE file_cache ADD COLUMN genre TEXT');
          await db.execute('ALTER TABLE file_cache ADD COLUMN cover_path TEXT');
        }
      },
    );

    return _cacheDb!;
  }

  /// Get cached music data if it exists and file is unchanged
  static Future<Music?> _getCachedMusic(File file) async {
    try {
      final db = await _initializeCacheDb();
      final result = await db.query(
        'file_cache',
        where: 'file_path = ?',
        whereArgs: [file.path],
      );

      if (result.isEmpty) return null;

      final stat = await file.stat();
      final cached = result.first;
      
      final cachedModified = cached['last_modified'] as int;
      final cachedSize = cached['file_size'] as int;

      if (stat.modified.millisecondsSinceEpoch == cachedModified &&
          stat.size == cachedSize &&
          cached['title'] != null) {
        
        return Music(
          id: p.basenameWithoutExtension(file.path),
          title: cached['title'] as String,
          artist: cached['artist'] as String,
          album: cached['album'] as String,
          genre: cached['genre'] as String? ?? 'Unknown',
          filePath: file.path,
          coverPath: cached['cover_path'] as String? ?? '',
        );
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Update or insert music data into cache
  static Future<void> cacheMusic(Music music, File file) async {
    try {
      final db = await _initializeCacheDb();
      final stat = await file.stat();
      
      await db.insert(
        'file_cache',
        {
          'file_path': file.path,
          'last_modified': stat.modified.millisecondsSinceEpoch,
          'file_size': stat.size,
          'title': music.title,
          'artist': music.artist,
          'album': music.album,
          'genre': music.genre,
          'cover_path': music.coverPath,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      if (kDebugMode) print('Error caching music: $e');
    }
  }

  /// Check if file should be processed (valid extension, size >= 1KB)
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

      return true;
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

  /// Scan system music folders and user-defined paths
  static Future<List<String>> scanSystemMusicFolders({
    Function(String)? onProgress,
    List<String>? customPaths,
  }) async {
    final stopwatch = Stopwatch()..start();
    final Set<String> musicPathsSet = <String>{};

    // Scan user-defined paths from settings OR customPaths
    if (customPaths != null && customPaths.isNotEmpty) {
       final futures = <Future<List<String>>>[];
       for (final path in customPaths) {
         onProgress?.call(path);
         final dir = Directory(path);
         futures.add(_scanDirectoryIfExists(dir));
       }
       final results = await Future.wait(futures);
       for (final list in results) {
         musicPathsSet.addAll(list);
       }
    } else {
      final settings = SettingsModel();
      await settings.loadSettings();

      if (settings.musicSourcePaths.isNotEmpty) {
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
    }

    if (musicPathsSet.isEmpty) {
      if (Platform.isAndroid) {
        final results = await _scanAndroidMusicWithMediaStore(onProgress: onProgress);
        musicPathsSet.addAll(results);
        if (musicPathsSet.isEmpty) {
          final fallbackResults = await _scanAndroidMusicFallback(onProgress: onProgress);
          musicPathsSet.addAll(fallbackResults);
        }
      } else if (Platform.isIOS) {
        final results = await _scanIOSMusicFolders(onProgress: onProgress);
        musicPathsSet.addAll(results);
      } else if (Platform.isWindows) {
        final results = await _scanWindowsMusicFolders(onProgress: onProgress);
        musicPathsSet.addAll(results);
      } else if (Platform.isMacOS) {
        final results = await _scanMacOSMusicFolders(onProgress: onProgress);
        musicPathsSet.addAll(results);
      } else if (Platform.isLinux) {
        final results = await _scanLinuxMusicFolders(onProgress: onProgress);
        musicPathsSet.addAll(results);
      }
    }

    final musicPaths = musicPathsSet.toList()..sort();
    stopwatch.stop();
    return musicPaths;
  }

  static Future<List<String>> _scanAndroidMusicWithMediaStore({Function(String)? onProgress}) async {
    final Set<String> musicPathsSet = <String>{};
    final permissionsGranted = await checkPermissions();
    if (!permissionsGranted) return [];
    try {
      onProgress?.call('Querying audio files...');
      final audioFiles = await _audioQuery.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );
      for (final song in audioFiles) {
        final String filePath = song.data;
        if (filePath.isEmpty || !_isSupportedExtension(filePath)) continue;
        if (await File(filePath).exists()) musicPathsSet.add(filePath);
      }
    } catch (e) {}
    return musicPathsSet.toList();
  }

  static Future<List<String>> _scanAndroidMusicFallback({Function(String)? onProgress}) async {
    final Set<String> musicPathsSet = <String>{};
    final permissionsGranted = await checkPermissions();
    if (!permissionsGranted) return [];
    final List<String> androidMusicDirs = [
      '/storage/emulated/0/Music',
      '/storage/emulated/0/Download',
      '/storage/emulated/0/DCIM',
    ];
    final uniqueDirs = androidMusicDirs.toSet().toList();
    final futures = uniqueDirs.map((dirPath) {
      onProgress?.call(dirPath);
      return _scanDirectoryIfExists(Directory(dirPath));
    }).toList();
    final results = await Future.wait(futures);
    for (final list in results) musicPathsSet.addAll(list);
    return musicPathsSet.toList();
  }

  static Future<bool> checkPermissions() async {
    if (!Platform.isAndroid) return true;
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    final sdk = androidInfo.version.sdkInt;
    if (sdk >= 33) return await Permission.audio.request().isGranted;
    return await Permission.storage.request().isGranted;
  }

  static Future<List<String>> _scanIOSMusicFolders({Function(String)? onProgress}) async {
    final docDir = await getApplicationDocumentsDirectory();
    onProgress?.call(docDir.path);
    return await _scanDirectoryIfExists(Directory(docDir.path));
  }

  static Future<List<String>> _scanWindowsMusicFolders({Function(String)? onProgress}) async {
    final userDir = Platform.environment['USERPROFILE'] ?? '';
    final dirsToScan = [
      p.join(userDir, 'Music'),
      p.join(userDir, 'Downloads'),
      'C:\\Users\\Public\\Music',
      p.join(userDir, 'Desktop')
    ];
    final futures = dirsToScan.map((d) {
      onProgress?.call(d);
      return _scanDirectoryIfExists(Directory(d));
    }).toList();
    final results = await Future.wait(futures);
    return results.expand((x) => x).toList();
  }

  static Future<List<String>> _scanMacOSMusicFolders({Function(String)? onProgress}) async {
    final homeDir = Platform.environment['HOME'] ?? '';
    final dirsToScan = [p.join(homeDir, 'Music'), p.join(homeDir, 'Downloads'), p.join(homeDir, 'Desktop')];
    final futures = dirsToScan.map((d) {
      onProgress?.call(d);
      return _scanDirectoryIfExists(Directory(d));
    }).toList();
    final results = await Future.wait(futures);
    return results.expand((x) => x).toList();
  }

  static Future<List<String>> _scanLinuxMusicFolders({Function(String)? onProgress}) async {
    final homeDir = Platform.environment['HOME'] ?? '';
    final dirsToScan = [p.join(homeDir, 'Music'), p.join(homeDir, 'Downloads'), p.join(homeDir, 'Desktop')];
    final futures = dirsToScan.map((d) {
      onProgress?.call(d);
      return _scanDirectoryIfExists(Directory(d));
    }).toList();
    final results = await Future.wait(futures);
    return results.expand((x) => x).toList();
  }

  static Future<List<String>> _scanDirectory(Directory dir) async {
    final List<String> files = [];
    try {
      final stream = dir.list(recursive: true, followLinks: false);
      await for (final entity in stream) {
        if (_scanOperation?.isCanceled ?? false) break;
        if (entity is File && await _shouldProcessFile(entity)) {
          files.add(entity.path);
        }
      }
    } catch (e) {}
    return files;
  }

  static Future<List<String>> _scanDirectoryIfExists(Directory dir) async {
    if (await dir.exists()) return await _scanDirectory(dir);
    return [];
  }

  /// Create Music objects from file paths with optimized parallel processing and caching
  static Future<List<Music>> createMusicListFromPaths(List<String> paths,
      {Function(List<Music>)? onBatchUpdate}) async {
    final stopwatch = Stopwatch()..start();
    final parser = ID3Parser();
    final List<Music> results = [];
    
    // Get persistent directory for covers
    final appDocDir = await getApplicationDocumentsDirectory();
    final coversDir = p.join(appDocDir.path, 'covers');
    final dir = Directory(coversDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    Future<Music?> processPath(String path) async {
      if (_scanOperation?.isCanceled ?? false) return null;
      try {
        final file = File(path);
        final cached = await _getCachedMusic(file);
        if (cached != null) {
          // Verify if cover still exists if path is not empty
          if (cached.coverPath.isNotEmpty) {
            if (await File(cached.coverPath).exists()) {
              return cached;
            }
            // If cover is missing, re-parse to extract it
          } else {
             return cached;
          }
        }

        final tags = await Future.any([
          parser.parseTagsFromFile(path),
          Future.delayed(Duration(milliseconds: _metadataTimeout), () => <String, dynamic>{}),
        ]);

        final music = parser.createMusicFromTags(path, tags, coverDirectory: coversDir);
        await cacheMusic(music, file);
        return music;
      } catch (e) {
        return null;
      }
    }

    final batchResults = <Music>[];
    DateTime lastUpdateTime = DateTime.now();

    for (int i = 0; i < paths.length; i += _maxParallelWorkers) {
      if (_scanOperation?.isCanceled ?? false) break;
      final end = (i + _maxParallelWorkers > paths.length) ? paths.length : i + _maxParallelWorkers;
      final sub = paths.sublist(i, end);
      final currentBatchResults = await Future.wait(sub.map((p) => processPath(p)));
      final validResults = currentBatchResults.whereType<Music>().toList();
      batchResults.addAll(validResults);
      results.addAll(validResults);

      if (DateTime.now().difference(lastUpdateTime).inMilliseconds >= _batchUpdateInterval) {
        lastUpdateTime = DateTime.now();
        onBatchUpdate?.call(List.from(batchResults));
        batchResults.clear();
      }
    }

    if (batchResults.isNotEmpty) onBatchUpdate?.call(batchResults);
    stopwatch.stop();
    return results;
  }

  /// Start scanning with cancellation support
  static Future<List<Music>> startScanning({
    Function(String)? onProgress,
    Function(List<Music>)? onBatchUpdate,
    List<String>? customPaths,
  }) async {
    await cancelScanning();
    _scanOperation = CancelableOperation.fromFuture(
          () async {
        final paths = await scanSystemMusicFolders(onProgress: onProgress, customPaths: customPaths);
        return await createMusicListFromPaths(paths, onBatchUpdate: onBatchUpdate);
      }(),
    );
    try {
      return await _scanOperation!.value;
    } catch (e) {
      if (e.toString().toLowerCase().contains('cancel')) return [];
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

  /// Cleanup cache database and delete covers
  static Future<void> cleanupCache() async {
    try {
      final db = await _initializeCacheDb();
      await db.delete('file_cache');
      
      final appDocDir = await getApplicationDocumentsDirectory();
      final coversDir = Directory(p.join(appDocDir.path, 'covers'));
      if (await coversDir.exists()) {
        await coversDir.delete(recursive: true);
      }
    } catch (e) {}
  }
}
