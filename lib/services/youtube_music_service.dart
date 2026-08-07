import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/settings_model.dart';
import 'app_directories.dart';
import 'cpp_core_bridge_io.dart';

class YoutubeMusicResult {
  final String resultType;
  final String title;
  final String artist;
  final String titleRomaji;
  final String artistRomaji;
  final String displayTitle;
  final String displayArtist;
  final String duration;
  final String videoId;
  final String browseId;
  final String thumbnailUrl;
  final Map<String, dynamic> raw;

  const YoutubeMusicResult({
    required this.resultType,
    required this.title,
    required this.artist,
    this.titleRomaji = '',
    this.artistRomaji = '',
    String? displayTitle,
    String? displayArtist,
    required this.duration,
    required this.videoId,
    required this.browseId,
    required this.thumbnailUrl,
    required this.raw,
  })  : displayTitle = displayTitle ?? title,
        displayArtist = displayArtist ?? artist;

  factory YoutubeMusicResult.fromMap(Map<String, dynamic> map) {
    return YoutubeMusicResult(
      resultType: map['resultType']?.toString() ?? '',
      title: map['title']?.toString() ?? 'Unknown title',
      artist: map['artist']?.toString() ?? '',
      titleRomaji: map['titleRomaji']?.toString() ?? '',
      artistRomaji: map['artistRomaji']?.toString() ?? '',
      displayTitle: map['displayTitle']?.toString(),
      displayArtist: map['displayArtist']?.toString(),
      duration: map['duration']?.toString() ?? '',
      videoId: map['videoId']?.toString() ?? '',
      browseId: map['browseId']?.toString() ?? '',
      thumbnailUrl: map['thumbnailUrl']?.toString() ?? '',
      raw: Map<String, dynamic>.from(map['raw'] as Map? ?? map),
    );
  }

  Map<String, dynamic> toChannelMap() => {
        'resultType': resultType,
        'title': title,
        'artist': artist,
        'titleRomaji': titleRomaji,
        'artistRomaji': artistRomaji,
        'displayTitle': displayTitle,
        'displayArtist': displayArtist,
        'duration': duration,
        'videoId': videoId,
        'browseId': browseId,
        'thumbnailUrl': thumbnailUrl,
        'raw': raw,
      };
}

class YoutubeMusicDownload {
  final List<String> files;
  final List<String> libraryFiles;
  final String downloadDir;
  final String message;

  const YoutubeMusicDownload({
    required this.files,
    this.libraryFiles = const [],
    required this.downloadDir,
    required this.message,
  });

  factory YoutubeMusicDownload.fromMap(Map<String, dynamic> map) {
    final rawFiles = map['files'] as List? ?? const [];
    final rawLibraryFiles = map['libraryFiles'] as List? ?? const [];
    return YoutubeMusicDownload(
      files: rawFiles.map((item) => item.toString()).toList(),
      libraryFiles: rawLibraryFiles.map((item) => item.toString()).toList(),
      downloadDir: map['downloadDir']?.toString() ?? '',
      message: map['message']?.toString() ?? '',
    );
  }
}

class YoutubeVideoQuality {
  final String label;
  final int height;
  final String url;
  final String formatId;
  final String ext;
  final bool hasAudio;
  final bool streamable;

  const YoutubeVideoQuality({
    required this.label,
    required this.height,
    required this.url,
    required this.formatId,
    required this.ext,
    this.hasAudio = true,
    this.streamable = true,
  });

  factory YoutubeVideoQuality.fromMap(Map<String, dynamic> map) {
    final height = (map['height'] as num?)?.toInt() ?? 0;
    return YoutubeVideoQuality(
      label: map['label']?.toString() ?? (height > 0 ? '${height}p' : 'Auto'),
      height: height,
      url: map['url']?.toString() ?? '',
      formatId: map['formatId']?.toString() ?? '',
      ext: map['ext']?.toString() ?? '',
      hasAudio: map['hasAudio'] != false,
      streamable: map['streamable'] != false,
    );
  }
}

class YoutubeSubtitleOption {
  final String language;
  final String label;
  final String url;
  final bool automatic;

  const YoutubeSubtitleOption({
    required this.language,
    required this.label,
    required this.url,
    required this.automatic,
  });

  factory YoutubeSubtitleOption.fromMap(Map<String, dynamic> map) {
    return YoutubeSubtitleOption(
      language: map['language']?.toString() ?? '',
      label: map['label']?.toString() ?? 'Subtitles',
      url: map['url']?.toString() ?? '',
      automatic: map['automatic'] == true,
    );
  }
}

class YoutubeMusicStream {
  final String url;
  final String title;
  final String artist;
  final String titleRomaji;
  final String artistRomaji;
  final String displayTitle;
  final String displayArtist;
  final String album;
  final String thumbnailUrl;
  final Map<String, String> httpHeaders;
  final int durationSeconds;
  final String videoId;
  final bool isVideo;
  final String qualityLabel;
  final List<YoutubeVideoQuality> qualities;
  final List<YoutubeSubtitleOption> subtitles;
  final String cacheStatus;
  final String cacheStatePath;
  final String cacheRawPath;

  const YoutubeMusicStream({
    required this.url,
    required this.title,
    required this.artist,
    this.titleRomaji = '',
    this.artistRomaji = '',
    String? displayTitle,
    String? displayArtist,
    required this.album,
    required this.thumbnailUrl,
    this.httpHeaders = const {},
    required this.durationSeconds,
    required this.videoId,
    required this.isVideo,
    this.qualityLabel = 'Auto',
    this.qualities = const [],
    this.subtitles = const [],
    this.cacheStatus = '',
    this.cacheStatePath = '',
    this.cacheRawPath = '',
  })  : displayTitle = displayTitle ?? title,
        displayArtist = displayArtist ?? artist;

  factory YoutubeMusicStream.fromMap(Map<String, dynamic> map) {
    final rawQualities = map['qualities'] as List? ?? const [];
    final rawSubtitles = map['subtitles'] as List? ?? const [];
    return YoutubeMusicStream(
      url: map['url']?.toString() ?? '',
      title: map['title']?.toString() ?? 'YouTube Music',
      artist: map['artist']?.toString() ?? 'YouTube Music',
      titleRomaji: map['titleRomaji']?.toString() ?? '',
      artistRomaji: map['artistRomaji']?.toString() ?? '',
      displayTitle: map['displayTitle']?.toString(),
      displayArtist: map['displayArtist']?.toString(),
      album: map['album']?.toString() ?? '',
      thumbnailUrl: map['thumbnailUrl']?.toString() ?? '',
      httpHeaders: _stringMapFromDynamic(map['httpHeaders']),
      durationSeconds: _secondsFromDynamic(map['durationSeconds']),
      videoId: map['videoId']?.toString() ?? '',
      isVideo: map['isVideo'] == true,
      qualityLabel: map['qualityLabel']?.toString() ?? 'Auto',
      qualities: rawQualities
          .whereType<Map>()
          .map((item) =>
              YoutubeVideoQuality.fromMap(Map<String, dynamic>.from(item)))
          .where((item) => item.url.isNotEmpty)
          .toList(),
      subtitles: rawSubtitles
          .whereType<Map>()
          .map((item) =>
              YoutubeSubtitleOption.fromMap(Map<String, dynamic>.from(item)))
          .where((item) => item.url.isNotEmpty)
          .toList(),
      cacheStatus: map['cacheStatus']?.toString() ?? '',
      cacheStatePath: map['cacheStatePath']?.toString() ?? '',
      cacheRawPath: map['cacheRawPath']?.toString() ?? '',
    );
  }
}

Map<String, String> _stringMapFromDynamic(Object? value) {
  if (value is! Map) return const {};
  final result = <String, String>{};
  for (final entry in value.entries) {
    final key = entry.key?.toString().trim() ?? '';
    final itemValue = entry.value?.toString() ?? '';
    if (key.isNotEmpty && itemValue.isNotEmpty) {
      result[key] = itemValue;
    }
  }
  return result;
}

class YoutubeMusicService {
  static const int _maxStreamCacheEntries = 12;

  final Map<String, Future<YoutubeMusicStream>> _streamFutures = {};
  final Map<String, YoutubeMusicStream> _streamCache = {};

  static bool get isSupported =>
      !kIsWeb &&
      (Platform.isAndroid ||
          Platform.isWindows ||
          Platform.isLinux ||
          Platform.isMacOS);

  static bool get _isDesktop =>
      !kIsWeb &&
      (Platform.isWindows ||
          Platform.isLinux ||
          Platform.isMacOS);

  Future<int> add(int a, int b) async {
    if (!_isDesktop) {
      throw UnsupportedError('Add operation only supported on desktop platforms.');
    }
    final output = await _runPython(['add', '$a', '$b']);
    return int.tryParse(output.trim()) ?? 0;
  }

  Future<List<YoutubeMusicResult>> search({
    required String query,
    required String filter,
    int limit = 20,
  }) async {
    try {
      if (!isSupported) {
        throw UnsupportedError(
            'YouTube Music is not available on this platform yet.');
      }

      final List<dynamic> response;
      if (Platform.isAndroid) {
        response = await _searchViaCppCore(query, filter, limit);
      } else {
        final output = await _runPython([
          'search',
          '--query',
          query,
          '--filter',
          filter,
          '--limit',
          '$limit',
        ]);
        response = jsonDecode(output) as List<dynamic>;
      }

      return response
          .whereType<Map>()
          .map((item) =>
              YoutubeMusicResult.fromMap(Map<String, dynamic>.from(item)))
          .toList();
    } catch (error) {
      if (Platform.isAndroid) {
        throw StateError(error.toString());
      }
      throw StateError(_friendlyPythonError(error.toString()));
    }
  }

  Future<List<dynamic>> _searchViaCppCore(
      String query, String filter, int limit) async {
    final json = CppCoreBridge.ytmusicSearch(query);
    if (json == null) {
      throw StateError('C++ core returned empty results for query: $query');
    }
    return jsonDecode(json) as List<dynamic>;
  }

  /// Resolve a YouTube videoId via yt-dlp (through the Python bridge).
  ///
  /// Returns the best-matching videoId, or null when unavailable on this
  /// platform or when yt-dlp finds no confident match (score < 40).
  Future<String?> searchVideoIdViaYtDlp({
    required String title,
    required String artist,
    int? durationSeconds,
  }) async {
    if (title.trim().isEmpty) return null;
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) return null;
    try {
      final output = await _runPython([
        'search-video-id',
        '--title',
        title,
        '--artist',
        artist,
        '--duration',
        '${durationSeconds ?? 0}',
      ]);
      final decoded = jsonDecode(output);
      if (decoded is Map<String, dynamic> &&
          decoded['videoId'] is String &&
          (decoded['videoId'] as String).isNotEmpty) {
        final id = decoded['videoId'] as String;
        debugPrint('[YouTubeMusic] yt-dlp videoId: $id '
            '("${decoded['title']}" by "${decoded['artist']}", '
            'score=${decoded['score']})');
        return id;
      }
      debugPrint('[YouTubeMusic] yt-dlp found no confident match for '
          '"$title" by "$artist": ${decoded is Map ? decoded : {}}');
      return null;
    } catch (e) {
      debugPrint('[YouTubeMusic] yt-dlp videoId search error: $e');
      return null;
    }
  }

  /// Search YouTube for the best-matching video for [title] by [artist] and
  /// return its [videoId]. Used to resolve a real YouTube link from local
  /// track metadata so auth-based providers (Cubey/Better Lyrics) can key on
  /// the video. Returns null when no confident match is found.
  ///
  /// Prefers yt-dlp (most reliable, works for non-Latin titles), and falls
  /// back to the general search + scoring when yt-dlp is unavailable.
  Future<String?> searchVideoIdForMetadata({
    required String title,
    required String artist,
    int? durationSeconds,
  }) async {
    if (title.trim().isEmpty) return null;
    if (!isSupported) return null;

    final ytDlpId = await searchVideoIdViaYtDlp(
      title: title,
      artist: artist,
      durationSeconds: durationSeconds,
    );
    if (ytDlpId != null) return ytDlpId;

    try {
      final query = artist.trim().isEmpty ? title.trim() : '$title $artist'.trim();
      final results = await search(query: query, filter: 'songs', limit: 8);
      if (results.isEmpty) return null;

      final targetTitle = _normalize(title);
      final targetArtist = _normalize(artist);

      YoutubeMusicResult? best;
      var bestScore = 0;
      for (final r in results) {
        var score = 0;
        final rt = _normalize(r.title);
        final ra = _normalize(r.artist);
        if (rt.isNotEmpty) {
          if (rt == targetTitle) {
            score += 40;
          } else if (rt.contains(targetTitle) || targetTitle.contains(rt)) {
            score += 20;
          } else {
            score += _tokenOverlap(rt, targetTitle) * 8;
          }
        }
        if (targetArtist.isNotEmpty && ra.isNotEmpty) {
          if (ra == targetArtist) {
            score += 30;
          } else if (ra.contains(targetArtist) || targetArtist.contains(ra)) {
            score += 15;
          } else {
            score += _tokenOverlap(ra, targetArtist) * 6;
          }
        }
        if (durationSeconds != null && durationSeconds > 0) {
          final d = _parseDurationSeconds(r.duration);
          if (d != null && (d - durationSeconds).abs() <= 3) {
            score += 10;
          }
        }
        if (score > bestScore) {
          bestScore = score;
          best = r;
        }
      }

      if (best == null || bestScore < 40 || best.videoId.isEmpty) return null;
      debugPrint('[YouTubeMusic] searchVideoIdForMetadata("$title" by "$artist") '
          '-> ${best.videoId} ("${best.title}" by "${best.artist}", score=$bestScore)');
      return best.videoId;
    } catch (e) {
      debugPrint('[YouTubeMusic] searchVideoIdForMetadata error: $e');
      return null;
    }
  }

  static String _normalize(String s) {
    return s
        .toLowerCase()
        // Keep Unicode letters/numbers (Japanese, Cyrillic, Chinese, etc.);
        // strip punctuation and other symbols only.
        .replaceAll(RegExp(r'[^\p{L}\p{N} ]', unicode: true), '')
        .trim();
  }

  static int _tokenOverlap(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final setA = a.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toSet();
    final setB = b.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toSet();
    if (setA.isEmpty || setB.isEmpty) return 0;
    final intersection = setA.intersection(setB).length;
    return intersection * 4 ~/ (setA.length + setB.length);
  }

  static int? _parseDurationSeconds(String duration) {
    if (duration.isEmpty) return null;
    final parts = duration.split(':').map((p) => int.tryParse(p.trim())).toList();
    if (parts.any((p) => p == null)) return null;
    final nums = parts.cast<int>();
    if (nums.isEmpty) return null;
    if (nums.length == 1) return nums[0];
    if (nums.length == 2) return nums[0] * 60 + nums[1];
    return nums[0] * 3600 + nums[1] * 60 + nums[2];
  }

  Future<YoutubeMusicDownload> download(
    YoutubeMusicResult result, {
    bool video = false,
    int? qualityHeight,
    List<int> qualityHeights = const [],
    bool subtitlesOnly = false,
    bool includeSubtitles = false,
    String? subtitleLanguage,
    List<String> subtitleLanguages = const [],
    bool automaticSubtitles = false,
    void Function(double? progress, String message)? onProgress,
  }) async {
    if (!isSupported) {
      throw UnsupportedError(
          'YouTube Music is not available on this platform yet.');
    }

    if (Platform.isAndroid) {
      throw UnsupportedError(
          'YouTube Music download not available on Android. Use desktop app or wait for C++ core extension.');
    }

    try {
      final outputDir = await _resolveDownloadDirectory();
      final args = [
        'download',
        '--item-json',
        jsonEncode(result.toChannelMap()),
        '--output-dir',
        outputDir,
      ];
      if (video) {
        args.add('--video');
      }
      if (qualityHeight != null && qualityHeight > 0) {
        args.addAll(['--quality-height', '$qualityHeight']);
      }
      if (qualityHeights.isNotEmpty) {
        args.addAll([
          '--quality-heights',
          qualityHeights.where((height) => height > 0).join(',')
        ]);
      }
      if (subtitlesOnly) {
        args.add('--subtitles-only');
      }
      if (includeSubtitles) {
        args.add('--write-subtitles');
        if ((subtitleLanguage ?? '').trim().isNotEmpty) {
          args.addAll(['--subtitle-lang', subtitleLanguage!.trim()]);
        }
        final languages = subtitleLanguages
            .map((language) => language.trim())
            .where((language) => language.isNotEmpty)
            .toSet()
            .join(',');
        if (languages.isNotEmpty) {
          args.addAll(['--subtitle-langs', languages]);
        }
        if (automaticSubtitles) {
          args.add('--auto-subtitles');
        }
      }
      final output = await _runPython(args, onProgress: onProgress);
      final response = Map<dynamic, dynamic>.from(jsonDecode(output) as Map);

      return YoutubeMusicDownload.fromMap(Map<String, dynamic>.from(response));
    } catch (error) {
      throw StateError(_friendlyPythonError(error.toString()));
    }
  }

  Future<String> resolvedDownloadDirectory() => _resolveDownloadDirectory();

  Future<String> streamVideoCacheDirectory() async {
    final cacheDir = await getPlayerVfCacheDirectory();
    return p.join(cacheDir.path, 'youtube_stream_video');
  }

  Future<void> clearStreamVideoCache() async {
    if (kIsWeb) return;
    final path = await streamVideoCacheDirectory();
    final directory = Directory(path);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
    await directory.create(recursive: true);
  }

  Future<YoutubeMusicStream> stream(
    YoutubeMusicResult result, {
    bool audioOnly = false,
  }) async {
    final key = _cacheKey(result);
    final cacheKey = audioOnly ? '$key:audio' : key;
    final cached = _streamCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    final pending = _streamFutures[cacheKey];
    if (pending != null) {
      return pending;
    }

    final future = _resolveStream(result, audioOnly: audioOnly);
    _streamFutures[cacheKey] = future;
    try {
      final stream = await future;
      _streamCache[cacheKey] = stream;
      _trimStreamCache();
      return stream;
    } finally {
      _streamFutures.remove(cacheKey);
    }
  }

  Future<YoutubeMusicStream> streamVideoId(
    String videoId, {
    int? maxHeight,
  }) async {
    final normalized = videoId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('videoId is empty');
    }

    final result = YoutubeMusicResult(
      resultType: 'video',
      title: 'YouTube Video',
      artist: 'YouTube',
      duration: '',
      videoId: normalized,
      browseId: '',
      thumbnailUrl: '',
      raw: {'videoId': normalized},
    );
    return _resolveStream(result, maxHeight: maxHeight);
  }

  void warmStreams(Iterable<YoutubeMusicResult> results, {int limit = 3}) {
    if (!isSupported) return;

    for (final result in results.take(limit)) {
      final key = '${_cacheKey(result)}:audio';
      if (_streamCache.containsKey(key) || _streamFutures.containsKey(key)) {
        continue;
      }
      final future = _resolveStream(result, audioOnly: true);
      _streamFutures[key] = future;
      future
          .then((stream) {
            _streamCache[key] = stream;
            _trimStreamCache();
          })
          .catchError((Object _) {})
          .whenComplete(() {
            _streamFutures.remove(key);
          });
    }
  }

  Future<YoutubeMusicStream> _resolveStream(
    YoutubeMusicResult result, {
    int? maxHeight,
    bool audioOnly = false,
  }) async {
    if (!isSupported) {
      throw UnsupportedError(
          'YouTube Music is not available on this platform yet.');
    }

    if (Platform.isAndroid) {
      throw UnsupportedError(
          'YouTube Music streaming not available on Android. Use desktop app or wait for C++ core extension.');
    }

    try {
      final args = [
        'stream',
        '--item-json',
        jsonEncode(result.toChannelMap()),
      ];
      if (!await _streamVideoCacheEnabled()) {
        args.add('--no-stream-cache');
      }
      if (maxHeight != null && maxHeight > 0) {
        args.addAll(['--quality-height', '$maxHeight']);
      }
      if (audioOnly) {
        args.add('--audio-only');
      }
      final output = await _runPython(
        args,
        timeout: audioOnly
            ? const Duration(seconds: 45)
            : const Duration(minutes: 3),
      );
      final response = Map<dynamic, dynamic>.from(jsonDecode(output) as Map);

      return YoutubeMusicStream.fromMap(Map<String, dynamic>.from(response));
    } catch (error) {
      throw StateError(_friendlyPythonError(error.toString()));
    }
  }

  Future<String> _resolveDownloadDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(SettingsModel.youtubeMusicDownloadPathKey);
    final defaultDir = await defaultYoutubeMusicDownloadDirectory();
    if (saved != null && saved.trim().isNotEmpty) {
      final savedPath = saved.trim();
      final resolvedSaved = _shouldMigrateOldLinuxDefault(savedPath, defaultDir)
          ? defaultDir
          : savedPath;
      final writable = await _ensureWritableDirectory(resolvedSaved);
      if (writable != savedPath) {
        await prefs.setString(
            SettingsModel.youtubeMusicDownloadPathKey, writable);
        await _replaceMusicSourcePath(savedPath, writable);
      }
      return writable;
    }

    final resolvedDefault = await _ensureWritableDirectory(defaultDir);
    await prefs.setString(
        SettingsModel.youtubeMusicDownloadPathKey, resolvedDefault);
    await _addMusicSourcePath(resolvedDefault);
    return resolvedDefault;
  }

  Future<String> _ensureWritableDirectory(String path) async {
    if (kIsWeb) return path;
    final directory = Directory(path);
    await directory.create(recursive: true);
    return directory.path;
  }

  static Future<String> defaultYoutubeMusicDownloadDirectory() async {
    if (kIsWeb) {
      return 'PlayerVf YouTube Music';
    }

    if (Platform.isAndroid) {
      return p.join('/storage', 'emulated', '0', 'Music');
    }

    if (Platform.isWindows) {
      final userDir = Platform.environment['USERPROFILE'];
      if (userDir != null && userDir.isNotEmpty) {
        return p.join(userDir, 'Music', 'PlayerVf YouTube Music');
      }
    } else if (Platform.isLinux) {
      final wslMusicDir = _wslWindowsMusicDirectory();
      if (wslMusicDir != null) {
        return p.join(wslMusicDir, 'PlayerVf YouTube Music');
      }

      final homeDir = Platform.environment['HOME'];
      if (homeDir != null && homeDir.isNotEmpty) {
        return p.join(homeDir, 'Music', 'PlayerVf YouTube Music');
      }
    } else if (Platform.isMacOS) {
      final homeDir = Platform.environment['HOME'];
      if (homeDir != null && homeDir.isNotEmpty) {
        return p.join(homeDir, 'Music', 'PlayerVf YouTube Music');
      }
    }

    final musicDir = await getPlayerVfDocumentsDirectory();
    return p.join(musicDir.path, 'PlayerVf', 'YouTube Music');
  }

  static String? _wslWindowsMusicDirectory() {
    if (!Platform.isLinux) return null;
    final isWsl = Platform.environment.containsKey('WSL_DISTRO_NAME') ||
        Platform.environment.containsKey('WSL_INTEROP') ||
        File('/proc/sys/fs/binfmt_misc/WSLInterop').existsSync();
    if (!isWsl) return null;

    final candidates = <String>[];
    final user = Platform.environment['USER'];
    if (user != null && user.trim().isNotEmpty) {
      candidates.add(p.join('/mnt/c/Users', user.trim(), 'Music'));
    }
    final home = Platform.environment['HOME'];
    if (home != null && home.startsWith('/home/')) {
      candidates.add(p.join('/mnt/c/Users', p.basename(home.trim()), 'Music'));
    }
    final usersRoot = Directory('/mnt/c/Users');
    if (usersRoot.existsSync()) {
      for (final entry in usersRoot.listSync(followLinks: false)) {
        if (entry is! Directory) continue;
        final name = p.basename(entry.path).toLowerCase();
        if (name == 'public' ||
            name == 'default' ||
            name == 'default user' ||
            name == 'all users') {
          continue;
        }
        candidates.add(p.join(entry.path, 'Music'));
      }
    }

    for (final candidate in candidates) {
      final parent = Directory(p.dirname(candidate));
      if (parent.existsSync()) return candidate;
    }
    return null;
  }

  bool _shouldMigrateOldLinuxDefault(String savedPath, String defaultDir) {
    if (!Platform.isLinux) return false;
    final normalizedSaved = p.normalize(savedPath);
    final normalizedDefault = p.normalize(defaultDir);
    if (normalizedSaved == normalizedDefault) return false;
    if (!normalizedDefault.startsWith('/mnt/c/Users/')) return false;

    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      final oldHomeMusic =
          p.normalize(p.join(home, 'Music', 'PlayerVf YouTube Music'));
      final oldFallback = p.normalize(p.join(
          home, '.local', 'share', 'player_vf', 'PlayerVf', 'YouTube Music'));
      return normalizedSaved == oldHomeMusic || normalizedSaved == oldFallback;
    }
    return false;
  }

  Future<void> _addMusicSourcePath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final paths =
        prefs.getStringList(SettingsModel.musicPathsKey) ?? <String>[];
    if (!paths.contains(path)) {
      paths.add(path);
      await prefs.setStringList(SettingsModel.musicPathsKey, paths);
    }
  }

  Future<void> _replaceMusicSourcePath(String oldPath, String newPath) async {
    final prefs = await SharedPreferences.getInstance();
    final paths =
        prefs.getStringList(SettingsModel.musicPathsKey) ?? <String>[];
    var changed = false;
    final next = <String>[];
    for (final path in paths) {
      if (path == oldPath) {
        changed = true;
        continue;
      }
      if (!next.contains(path)) next.add(path);
    }
    if (!next.contains(newPath)) {
      next.add(newPath);
      changed = true;
    }
    if (changed) {
      await prefs.setStringList(SettingsModel.musicPathsKey, next);
    }
  }

  String _cacheKey(YoutubeMusicResult result) {
    if (result.videoId.isNotEmpty) return result.videoId;
    if (result.browseId.isNotEmpty) {
      return '${result.resultType}:${result.browseId}';
    }
    return '${result.resultType}:${result.title}:${result.artist}';
  }

  void _trimStreamCache() {
    while (_streamCache.length > _maxStreamCacheEntries) {
      _streamCache.remove(_streamCache.keys.first);
    }
  }

  Future<Map<String, String>?> _pythonBridgeEnvironment() async {
    if (kIsWeb) return null;
    final env = <String, String>{};
    final cacheDir = _bestEffortCacheDirectory();
    if (cacheDir != null) {
      env['PLAYER_VF_OUTPUT_DIR'] = p.join(cacheDir, 'python_output');
      env['PLAYER_VF_STREAM_VIDEO_CACHE_DIR'] =
          p.join(cacheDir, 'youtube_stream_video');
    }
    env['PLAYER_VF_STREAM_CACHE_ENABLED'] =
        await _streamVideoCacheEnabled() ? '1' : '0';
    if (!Platform.isLinux) return env.isEmpty ? null : env;
    final ffmpeg = _bundledLinuxToolExecutable('ffmpeg');
    if (ffmpeg == null) return env.isEmpty ? null : env;
    final ffprobe = _bundledLinuxToolExecutable('ffprobe');
    env['PLAYER_VF_FFMPEG'] = ffmpeg;
    if (ffprobe != null) env['PLAYER_VF_FFPROBE'] = ffprobe;
    return env;
  }

  Future<bool> _streamVideoCacheEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(SettingsModel.youtubeStreamCacheEnabledKey) ?? true;
  }

  String? _bestEffortCacheDirectory() {
    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null && localAppData.isNotEmpty) {
        return p.join(localAppData, 'PlayerVF', 'Cache');
      }
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return p.join(appData, 'PlayerVF', 'Cache');
      }
    }

    if (Platform.isLinux) {
      final xdgCacheHome = Platform.environment['XDG_CACHE_HOME'];
      if (xdgCacheHome != null && xdgCacheHome.isNotEmpty) {
        return p.join(xdgCacheHome, 'player_vf');
      }
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return p.join(home, '.cache', 'player_vf');
      }
    }

    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return p.join(home, 'Library', 'Caches', 'PlayerVF');
      }
    }
    return null;
  }

  String? _bundledLinuxToolExecutable(String toolName) {
    if (!Platform.isLinux) return null;

    final candidates = <String>[];
    void add(String path) {
      if (path.trim().isEmpty) return;
      if (File(path).existsSync()) candidates.add(path);
    }

    final exeDir = File(Platform.resolvedExecutable).parent;
    for (final base in <Directory>[
      exeDir,
      Directory(p.join(exeDir.path, 'data')),
      Directory.current,
      Directory(p.join(Directory.current.path, 'linux', 'packaged')),
    ]) {
      add(p.join(base.path, 'tools', toolName, 'bin', toolName));
      add(p.join(base.path, toolName, 'bin', toolName));
      add(p.join(base.path, 'tools', toolName, toolName));
      add(p.join(base.path, toolName, toolName));
    }
    return candidates.isEmpty ? null : candidates.first;
  }

  Future<String> _runPython(
    List<String> args, {
    void Function(double? progress, String message)? onProgress,
    Duration? timeout,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError(
          'YouTube Music downloads and streaming are not available on web.');
    }

    final script = await _pythonScriptPath();
    final executable = await _desktopPythonExecutable(script, args);
    final Process process;
    try {
      process = await Process.start(
        executable,
        [script, ...args],
        environment: await _pythonBridgeEnvironment(),
      );
    } catch (error) {
      throw StateError(_friendlyPythonError(error.toString()));
    }
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();

    final stdoutSub =
        process.stdout.transform(utf8.decoder).listen(stdoutBuffer.write);
    final stderrSub = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) return;

      try {
        final event = jsonDecode(trimmed);
        if (event is Map) {
          final percent = (event['percent'] as num?)?.toDouble();
          final status = event['status']?.toString() ?? '';
          final message = status == 'finished'
              ? 'Finishing audio...'
              : percent == null
                  ? 'Downloading...'
                  : 'Downloading ${(percent * 100).clamp(0, 100).toStringAsFixed(0)}%';
          onProgress?.call(percent, message);
          return;
        }
      } catch (_) {}

      stderrBuffer.writeln(line);
    });

    int exitCode;
    try {
      exitCode = timeout == null
          ? await process.exitCode
          : await process.exitCode.timeout(timeout);
    } on TimeoutException {
      process.kill(ProcessSignal.sigterm);
      throw StateError(
          'YouTube video took too long to load. Try again or choose another quality.');
    }
    await stdoutSub.cancel();
    await stderrSub.cancel();

    if (exitCode != 0) {
      final stderr = stderrBuffer.toString().trim();
      final stdout = stdoutBuffer.toString().trim();
      throw StateError(
          _friendlyPythonError(stderr.isNotEmpty ? stderr : stdout));
    }

    return stdoutBuffer.toString();
  }

  Future<String> _desktopPythonExecutable(
      String script, List<String> args) async {
    final override = Platform.environment['PLAYERVF_PYTHON'];
    if (override != null && override.trim().isNotEmpty) {
      return override;
    }

    final projectRoot = Directory(p.dirname(p.dirname(p.dirname(script))));
    final envDir =
        Directory(p.join(projectRoot.path, '.dart_tool', 'playervf_python'));
    final pythonExe = Platform.isWindows
        ? File(p.join(envDir.path, 'Scripts', 'python.exe'))
        : File(p.join(envDir.path, 'bin', 'python'));
    final marker = File(p.join(envDir.path, '.player_vf_ready'));

    if (await pythonExe.exists() && await marker.exists()) {
      if (await _pythonBridgeDependenciesReady(pythonExe.path)) {
        return pythonExe.path;
      }
      await marker.delete().catchError((_) => marker);
    }

    await envDir.parent.create(recursive: true);
    final basePython = Platform.isWindows ? 'python' : 'python3';
    await _ensurePythonAvailable(basePython);
    final requirements = p.join(p.dirname(script), 'requirements.txt');
    if (!await pythonExe.exists()) {
      final venv = await Process.run(basePython, ['-m', 'venv', envDir.path]);
      if (venv.exitCode != 0) {
        if (!Platform.isWindows) {
          return _systemPythonExecutableWithDependencies(
            basePython,
            requirements,
            marker,
          );
        }
        throw StateError(
          _friendlyPythonError('${venv.stderr}\n${venv.stdout}'.trim()),
        );
      }
    }

    final install = await Process.run(pythonExe.path, [
      '-m',
      'pip',
      'install',
      '--upgrade',
      '-r',
      requirements,
    ]);
    if (install.exitCode != 0) {
      if (!Platform.isWindows) {
        return _systemPythonExecutableWithDependencies(
          basePython,
          requirements,
          marker,
        );
      }
      throw StateError(_friendlyPythonError(
        '${install.stderr}\n${install.stdout}'.trim(),
      ));
    }
    if (!await _pythonBridgeDependenciesReady(pythonExe.path)) {
      if (!Platform.isWindows) {
        return _systemPythonExecutableWithDependencies(
          basePython,
          requirements,
          marker,
        );
      }
      throw StateError(
        _friendlyPythonError(
          'Python dependencies are missing after install. '
          'Run: ${pythonExe.path} -m pip install --upgrade -r $requirements',
        ),
      );
    }

    await marker.writeAsString(DateTime.now().toIso8601String());
    return pythonExe.path;
  }

  Future<String> _systemPythonExecutableWithDependencies(
    String executable,
    String requirements,
    File marker,
  ) async {
    if (await marker.exists() &&
        await _pythonBridgeDependenciesReady(executable)) {
      return executable;
    }

    if (!await _pythonBridgeDependenciesReady(executable)) {
      final installed = await _installRequirementsForSystemPython(
        executable,
        requirements,
      );
      if (!installed && !await _pythonBridgeDependenciesReady(executable)) {
        throw StateError(
          _friendlyPythonError(
            'Python dependencies are missing and automatic user install failed. '
            'Run: $executable -m pip install --user -r $requirements',
          ),
        );
      }
    }

    await marker.writeAsString(DateTime.now().toIso8601String());
    return executable;
  }

  Future<bool> _pythonBridgeDependenciesReady(String executable) async {
    final result = await Process.run(executable, [
      '-c',
      'import ytmusicapi, yt_dlp, requests, mutagen, pypinyin, pykakasi',
    ]);
    return result.exitCode == 0;
  }

  Future<bool> _installRequirementsForSystemPython(
    String executable,
    String requirements,
  ) async {
    final first = await Process.run(executable, [
      '-m',
      'pip',
      'install',
      '--user',
      '--upgrade',
      '-r',
      requirements,
    ]);
    if (first.exitCode == 0) return true;

    final output = '${first.stderr}\n${first.stdout}'.toLowerCase();
    if (!output.contains('externally-managed-environment')) {
      return false;
    }

    final second = await Process.run(executable, [
      '-m',
      'pip',
      'install',
      '--user',
      '--break-system-packages',
      '--upgrade',
      '-r',
      requirements,
    ]);
    return second.exitCode == 0;
  }

  Future<void> _ensurePythonAvailable(String executable) async {
    try {
      final result = await Process.run(executable, ['--version']);
      if (result.exitCode == 0) return;
      throw StateError('${result.stderr}\n${result.stdout}'.trim());
    } catch (error) {
      throw StateError(_friendlyPythonError(error.toString()));
    }
  }

  Future<String> _pythonScriptPath() async {
    final startDirs = <Directory>{
      Directory.current,
      File(Platform.resolvedExecutable).parent,
    };

    for (final startDir in startDirs) {
      Directory? dir = startDir;
      while (dir != null) {
        final scriptPath =
            p.normalize(p.join(dir.path, 'lib', 'python', 'api.py'));
        final requirementsPath =
            p.normalize(p.join(dir.path, 'lib', 'python', 'requirements.txt'));
        if (File(scriptPath).existsSync() &&
            File(requirementsPath).existsSync()) {
          return scriptPath;
        }

        final parent = dir.parent;
        if (parent.path == dir.path) {
          dir = null;
        } else {
          dir = parent;
        }
      }
    }

    final supportDir = await getPlayerVfSupportDirectory();
    final bridgeDir = Directory(p.join(supportDir.path, 'python_bridge'));
    await bridgeDir.create(recursive: true);

    final scriptPath = p.join(bridgeDir.path, 'api.py');
    final requirementsPath = p.join(bridgeDir.path, 'requirements.txt');
    await File(scriptPath)
        .writeAsString(await rootBundle.loadString('lib/python/api.py'));
    await File(requirementsPath).writeAsString(
        await rootBundle.loadString('lib/python/requirements.txt'));
    return scriptPath;
  }

  String _friendlyPythonError(String output) {
    final lower = output.toLowerCase();
    if (lower.contains('no address associated with hostname') ||
        lower.contains('failed host lookup') ||
        lower.contains('temporary failure in name resolution') ||
        lower.contains('nodename nor servname provided') ||
        lower.contains('getaddrinfo failed') ||
        lower.contains('name or service not known') ||
        lower.contains('network is unreachable') ||
        lower.contains('connection reset') ||
        lower.contains('connection timed out')) {
      return 'Network/DNS error. Check your internet connection, DNS/VPN/proxy, then try YouTube Music search again.';
    }
    if (output.contains('Cannot find lib/python/api.py')) {
      return 'YouTube Music bridge was not found. Rebuild the app so the bundled Python bridge assets are included.';
    }
    if (output.contains("No module named 'ytmusicapi'") ||
        output.contains('No module named "ytmusicapi"')) {
      return 'Python dependencies are missing. PlayerVF will try to repair them automatically on the next search. If it still fails, run: python3 -m pip install --user ytmusicapi yt-dlp requests mutagen';
    }
    if (lower.contains('no module named venv') ||
        lower.contains('ensurepip is not available') ||
        lower.contains('python3-venv')) {
      return 'Python venv support is missing. On Debian/Ubuntu install it with: sudo apt install python3 python3-venv python3-pip';
    }
    if (lower.contains('no such file or directory') &&
        lower.contains('python3')) {
      return 'Python 3 is missing. Install it with: sudo apt install python3 python3-venv python3-pip';
    }
    if (output.contains('No module named')) {
      return 'Python dependency is missing: $output';
    }
    return output;
  }
}

int _secondsFromDynamic(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toInt();

  final text = value.toString().trim();
  if (text.isEmpty) return 0;
  final numeric = int.tryParse(text);
  if (numeric != null) {
    return numeric > 10000 ? numeric ~/ 1000 : numeric;
  }

  final parts = text.split(':');
  if (parts.length < 2 || parts.length > 3) return 0;
  var total = 0;
  for (final part in parts) {
    final parsed = int.tryParse(part);
    if (parsed == null) return 0;
    total = (total * 60) + parsed;
  }
  return total;
}
