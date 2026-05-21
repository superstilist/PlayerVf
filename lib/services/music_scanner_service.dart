import 'dart:io';
import 'dart:convert';
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
import 'youtube_music_service.dart';

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
    '.mp4',
    '.mkv',
    '.webm',
    '.avi',
  ];

  /// Debug flag - when true, prints all music paths found
  static bool debugMode = false;

  // Internal quick lookup set for performance
  static final Set<String> _extSet =
      supportedExtensions.map((e) => e.toLowerCase()).toSet();

  // Database instance for caching
  static Database? _cacheDb;
  static Future<Database>? _cacheDbOpening;

  // Cancellation token for scanning
  static CancelableOperation? _scanOperation;

  // Batch update interval (milliseconds)
  static const int _batchUpdateInterval = 1000;

  // Maximum parallel workers for metadata extraction
  static const int _maxParallelWorkers = 3;

  // Metadata extraction timeout (milliseconds)
  static const int _metadataTimeout = 3500;
  static const int _durationRepairTimeout = 2500;

  // Minimum file size (bytes) to consider as valid audio file
  static const int _minFileSize = 1024;

  // OnAudioQuery instance for querying audio files
  static final OnAudioQuery _audioQuery = OnAudioQuery();
  static final Map<String, _AndroidMediaStoreHint> _androidMediaStoreHints = {};

  /// Initialize the cache database
  static Future<Database> _initializeCacheDb() async {
    if (_cacheDb != null) {
      return _cacheDb!;
    }
    final opening = _cacheDbOpening;
    if (opening != null) {
      return opening;
    }

    final documentsDirectory = await getApplicationDocumentsDirectory();
    final dbPath = p.join(documentsDirectory.path, 'music_scan_cache.db');

    _cacheDbOpening = openDatabase(
      dbPath,
      version: 3,
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
            duration_ms INTEGER,
            cover_path TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _addColumnIfMissing(db, 'file_cache', 'title', 'TEXT');
          await _addColumnIfMissing(db, 'file_cache', 'artist', 'TEXT');
          await _addColumnIfMissing(db, 'file_cache', 'album', 'TEXT');
          await _addColumnIfMissing(db, 'file_cache', 'genre', 'TEXT');
          await _addColumnIfMissing(db, 'file_cache', 'cover_path', 'TEXT');
        }
        if (oldVersion < 3) {
          await _addColumnIfMissing(db, 'file_cache', 'duration_ms', 'INTEGER');
        }
      },
    );

    try {
      _cacheDb = await _cacheDbOpening!;
    } finally {
      _cacheDbOpening = null;
    }
    return _cacheDb!;
  }

  static Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any((row) => row['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
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
          cached['title'] != null &&
          (cached['duration_ms'] as int?) != null &&
          (cached['duration_ms'] as int) > 0) {
        if (_hasWeakCachedMetadata(file, cached)) return null;
        return Music(
          id: p.basenameWithoutExtension(file.path),
          title: cached['title'] as String,
          artist: cached['artist'] as String,
          album: cached['album'] as String,
          genre: cached['genre'] as String? ?? 'Unknown',
          filePath: file.path,
          coverPath: cached['cover_path'] as String? ?? '',
          duration: Duration(milliseconds: cached['duration_ms'] as int),
        );
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static bool _hasWeakCachedMetadata(File file, Map<String, Object?> cached) {
    final extension = p.extension(file.path).toLowerCase();
    final isMp4Audio =
        extension == '.m4a' || extension == '.m4b' || extension == '.aac';
    final isSyncedFile = p
        .split(file.path)
        .map((part) => part.toLowerCase())
        .contains('playervf sync');
    if (!isMp4Audio && !isSyncedFile) return false;

    final title = cached['title']?.toString().trim() ?? '';
    final artist = cached['artist']?.toString().trim() ?? '';
    final album = cached['album']?.toString().trim() ?? '';
    final fileName = p.basenameWithoutExtension(file.path).trim();
    final titleIsFileName = title.toLowerCase() == fileName.toLowerCase();
    final unknownArtist = artist.isEmpty || artist == 'Unknown Artist';
    final unknownAlbum = album.isEmpty || album == 'Unknown Album';

    return title.isEmpty || (titleIsFileName && unknownArtist && unknownAlbum);
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
          'duration_ms': music.duration?.inMilliseconds,
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

      if (await _isNonPrimaryPlayervfQuality(file)) {
        return false;
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

  static Future<bool> _isNonPrimaryPlayervfQuality(File file) async {
    final manifest = await _findPlayervfManifest(file.path);
    if (manifest == null) return false;
    try {
      final decoded =
          jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
      if (decoded['type'] != 'playervf.youtubeVideoSet') return false;
      final qualities = decoded['qualities'] as List? ?? const [];
      if (qualities.isEmpty) return false;
      final primary = qualities.first;
      if (primary is! Map) return false;
      final primaryPath = primary['path']?.toString() ?? '';
      if (primaryPath.isEmpty) return false;
      return !p.equals(p.normalize(primaryPath), p.normalize(file.path));
    } catch (_) {
      return false;
    }
  }

  static Future<File?> _findPlayervfManifest(String filePath) async {
    final direct = File('${p.withoutExtension(filePath)}.playervf.json');
    if (await direct.exists()) return direct;
    final dir = p.dirname(filePath);
    final stem = p.basenameWithoutExtension(filePath);
    final baseStem =
        stem.replaceFirst(RegExp(r'\.(auto|\d+p)$', caseSensitive: false), '');
    final grouped = File(p.join(dir, '$baseStem.playervf.json'));
    if (await grouped.exists()) return grouped;
    return null;
  }

  /// Scan system music folders and user-defined paths
  static Future<List<String>> scanSystemMusicFolders({
    Function(String)? onProgress,
    List<String>? customPaths,
  }) async {
    if (kIsWeb) return [];

    final stopwatch = Stopwatch()..start();
    final Set<String> musicPathsSet = <String>{};

    final settings = SettingsModel();
    await settings.loadSettings();
    final youtubeDownloadPath = settings.youtubeMusicDownloadPath.isNotEmpty
        ? settings.youtubeMusicDownloadPath
        : await YoutubeMusicService.defaultYoutubeMusicDownloadDirectory();
    final playerVfSyncPath = await playerVfSyncDirectoryPath();

    // Scan user-defined paths from settings OR customPaths.
    // Always include the YouTube Music download folder so downloaded files show up after refresh.
    if (customPaths != null && customPaths.isNotEmpty) {
      final futures = <Future<List<String>>>[];
      final pathsToScan = <String>{
        ...customPaths,
        youtubeDownloadPath,
        playerVfSyncPath,
      }.where((path) => path.trim().isNotEmpty);
      for (final path in pathsToScan) {
        onProgress?.call(path);
        final dir = Directory(path);
        futures.add(_scanDirectoryIfExists(dir));
      }
      final results = await Future.wait(futures);
      for (final list in results) {
        musicPathsSet.addAll(list);
      }
    } else {
      final pathsToScan = <String>{
        ...settings.musicSourcePaths,
        youtubeDownloadPath,
        playerVfSyncPath,
      }.where((path) => path.trim().isNotEmpty).toList();

      if (pathsToScan.isNotEmpty) {
        final futures = <Future<List<String>>>[];
        for (final path in pathsToScan) {
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
        final results =
            await _scanAndroidMusicWithMediaStore(onProgress: onProgress);
        musicPathsSet.addAll(results);
        if (musicPathsSet.isEmpty) {
          final fallbackResults =
              await _scanAndroidMusicFallback(onProgress: onProgress);
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

  static Future<String> playerVfSyncDirectoryPath() async {
    final documents = await getApplicationDocumentsDirectory();
    return p.join(documents.path, 'PlayerVF Sync');
  }

  static Future<List<String>> _scanAndroidMusicWithMediaStore(
      {Function(String)? onProgress}) async {
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
        if (await File(filePath).exists()) {
          final duration = _durationFromMilliseconds(song.duration);
          _androidMediaStoreHints[filePath] = _AndroidMediaStoreHint(
            mediaStoreId: song.id,
            title: _cleanMediaStoreText(song.title),
            artist: _cleanMediaStoreText(song.artist),
            album: _cleanMediaStoreText(song.album),
            genre: _cleanMediaStoreText(song.genre),
            duration: duration,
          );
          musicPathsSet.add(filePath);
        }
      }
    } catch (e) {
      if (kDebugMode) print('MediaStore scan failed: $e');
    }
    return musicPathsSet.toList();
  }

  static Future<List<String>> _scanAndroidMusicFallback(
      {Function(String)? onProgress}) async {
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
    for (final list in results) {
      musicPathsSet.addAll(list);
    }
    return musicPathsSet.toList();
  }

  static Future<bool> checkPermissions() async {
    if (kIsWeb) return true;
    if (!Platform.isAndroid) return true;
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    final sdk = androidInfo.version.sdkInt;
    if (sdk >= 33) return await Permission.audio.request().isGranted;
    return await Permission.storage.request().isGranted;
  }

  static Future<List<String>> _scanIOSMusicFolders(
      {Function(String)? onProgress}) async {
    final docDir = await getApplicationDocumentsDirectory();
    onProgress?.call(docDir.path);
    return await _scanDirectoryIfExists(Directory(docDir.path));
  }

  static Future<List<String>> _scanWindowsMusicFolders(
      {Function(String)? onProgress}) async {
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

  static Future<List<String>> _scanMacOSMusicFolders(
      {Function(String)? onProgress}) async {
    final homeDir = Platform.environment['HOME'] ?? '';
    final dirsToScan = [
      p.join(homeDir, 'Music'),
      p.join(homeDir, 'Downloads'),
      p.join(homeDir, 'Desktop')
    ];
    final futures = dirsToScan.map((d) {
      onProgress?.call(d);
      return _scanDirectoryIfExists(Directory(d));
    }).toList();
    final results = await Future.wait(futures);
    return results.expand((x) => x).toList();
  }

  static Future<List<String>> _scanLinuxMusicFolders(
      {Function(String)? onProgress}) async {
    final homeDir = Platform.environment['HOME'] ?? '';
    final dirsToScan = [
      p.join(homeDir, 'Music'),
      p.join(homeDir, 'Downloads'),
      p.join(homeDir, 'Desktop')
    ];
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
    } catch (e) {
      if (kDebugMode) print('Directory scan failed for ${dir.path}: $e');
    }
    return files;
  }

  static Future<List<String>> _scanDirectoryIfExists(Directory dir) async {
    if (await dir.exists()) return await _scanDirectory(dir);
    return [];
  }

  /// Create Music objects from file paths with optimized parallel processing and caching
  static Future<List<Music>> createMusicListFromPaths(List<String> paths,
      {Function(List<Music>)? onBatchUpdate}) async {
    if (kIsWeb) return [];

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
        if (await _isNonPrimaryPlayervfQuality(file)) return null;
        final cached = await _getCachedMusic(file);
        if (cached != null) {
          final cachedWithHint = _mergeAndroidMediaStoreHint(cached, path);
          // Verify if cover still exists if path is not empty
          if (cachedWithHint.coverPath.isNotEmpty) {
            final cachedCover = File(cachedWithHint.coverPath);
            final isNativeCoverCache =
                p.basename(cachedWithHint.coverPath).contains('_cover_native');
            if (isNativeCoverCache && await cachedCover.exists()) {
              return cachedWithHint;
            }
            // If cover is missing, re-parse to extract it
          } else {
            return cachedWithHint;
          }
        }

        final tags = await Future.any([
          parser.parseTagsFromFile(path),
          Future.delayed(const Duration(milliseconds: _metadataTimeout),
              () => <String, dynamic>{}),
        ]);

        var music =
            parser.createMusicFromTags(path, tags, coverDirectory: coversDir);
        music = _mergeAndroidMediaStoreHint(music, path);
        if (Platform.isAndroid && music.coverPath.isEmpty) {
          final androidCover = await _extractAndroidArtwork(path, coversDir);
          if (androidCover != null) {
            music = _copyMusicWith(music, coverPath: androidCover);
          }
        }
        if (music.duration == null || music.duration! <= Duration.zero) {
          final repairedDuration = await Future.any([
            parser.parseDurationFromFile(path),
            Future<Duration?>.delayed(
              const Duration(milliseconds: _durationRepairTimeout),
              () => null,
            ),
          ]);
          if (repairedDuration != null && repairedDuration > Duration.zero) {
            music = _copyMusicWith(music, duration: repairedDuration);
          }
        }
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
      final end = (i + _maxParallelWorkers > paths.length)
          ? paths.length
          : i + _maxParallelWorkers;
      final sub = paths.sublist(i, end);
      final currentBatchResults =
          await Future.wait(sub.map((p) => processPath(p)));
      final validResults = currentBatchResults.whereType<Music>().toList();
      batchResults.addAll(validResults);
      results.addAll(validResults);

      if (DateTime.now().difference(lastUpdateTime).inMilliseconds >=
          _batchUpdateInterval) {
        lastUpdateTime = DateTime.now();
        onBatchUpdate?.call(List.from(batchResults));
        batchResults.clear();
      }
    }

    if (batchResults.isNotEmpty) onBatchUpdate?.call(batchResults);
    stopwatch.stop();
    return results;
  }

  static Music _mergeAndroidMediaStoreHint(Music music, String path) {
    final hint = _androidMediaStoreHints[path];
    if (hint == null) return music;
    return _copyMusicWith(
      music,
      title: _preferKnown(
          music.title, hint.title, p.basenameWithoutExtension(path)),
      artist: _preferKnown(music.artist, hint.artist, 'Unknown Artist'),
      album: _preferKnown(music.album, hint.album, 'Unknown Album'),
      genre: _preferKnown(music.genre, hint.genre, 'Unknown'),
      duration: _validDuration(music.duration) ?? hint.duration,
    );
  }

  static Music _copyMusicWith(
    Music music, {
    String? title,
    String? artist,
    String? album,
    String? genre,
    Duration? duration,
    String? coverPath,
  }) {
    return Music(
      id: music.id,
      title: title ?? music.title,
      artist: artist ?? music.artist,
      album: album ?? music.album,
      filePath: music.filePath,
      coverPath: coverPath ?? music.coverPath,
      genre: genre ?? music.genre,
      duration: duration ?? music.duration,
      isFavorite: music.isFavorite,
      playCount: music.playCount,
      lastPlayed: music.lastPlayed,
      dateAdded: music.dateAdded,
    );
  }

  static String? _cleanMediaStoreText(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty || text == '<unknown>') return null;
    return text;
  }

  static String _preferKnown(String current, String? hint, String unknown) {
    final trimmedCurrent = current.trim();
    if (trimmedCurrent.isNotEmpty && trimmedCurrent != unknown) {
      return current;
    }
    return hint ?? current;
  }

  static Duration? _durationFromMilliseconds(int? value) {
    if (value == null || value <= 0) return null;
    return Duration(milliseconds: value);
  }

  static Duration? _validDuration(Duration? duration) {
    if (duration == null || duration <= Duration.zero) return null;
    return duration;
  }

  static Future<String?> _extractAndroidArtwork(
      String path, String coversDir) async {
    final hint = _androidMediaStoreHints[path];
    if (hint == null) return null;
    try {
      final artwork = await _audioQuery.queryArtwork(
        hint.mediaStoreId,
        ArtworkType.AUDIO,
        format: ArtworkFormat.JPEG,
        quality: 100,
      );
      if (artwork == null || artwork.isEmpty) return null;
      final fileName = '${path.hashCode.abs().toRadixString(16)}_android.jpg';
      final file = File(p.join(coversDir, fileName));
      if (!await file.exists()) {
        await file.writeAsBytes(artwork, flush: false);
      }
      return file.path;
    } catch (e) {
      if (kDebugMode) print('Android artwork read failed: $e');
    }
    return null;
  }

  /// Start scanning with cancellation support
  static Future<List<Music>> startScanning({
    Function(String)? onProgress,
    Function(List<Music>)? onBatchUpdate,
    List<String>? customPaths,
  }) async {
    if (kIsWeb) return [];

    await cancelScanning();
    _scanOperation = CancelableOperation.fromFuture(
      () async {
        final paths = await scanSystemMusicFolders(
            onProgress: onProgress, customPaths: customPaths);
        return await createMusicListFromPaths(paths,
            onBatchUpdate: onBatchUpdate);
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
    if (kIsWeb) return;

    try {
      final db = await _initializeCacheDb();
      await db.delete('file_cache');

      final appDocDir = await getApplicationDocumentsDirectory();
      final coversDir = Directory(p.join(appDocDir.path, 'covers'));
      if (await coversDir.exists()) {
        await coversDir.delete(recursive: true);
      }
    } catch (e) {
      if (kDebugMode) print('Cache cleanup failed: $e');
    }
  }
}

class _AndroidMediaStoreHint {
  final int mediaStoreId;
  final String? title;
  final String? artist;
  final String? album;
  final String? genre;
  final Duration? duration;

  const _AndroidMediaStoreHint({
    required this.mediaStoreId,
    required this.title,
    required this.artist,
    required this.album,
    required this.genre,
    required this.duration,
  });
}
