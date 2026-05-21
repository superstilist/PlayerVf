import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/settings_model.dart';

class YoutubeMusicResult {
  final String resultType;
  final String title;
  final String artist;
  final String duration;
  final String videoId;
  final String browseId;
  final String thumbnailUrl;
  final Map<String, dynamic> raw;

  const YoutubeMusicResult({
    required this.resultType,
    required this.title,
    required this.artist,
    required this.duration,
    required this.videoId,
    required this.browseId,
    required this.thumbnailUrl,
    required this.raw,
  });

  factory YoutubeMusicResult.fromMap(Map<String, dynamic> map) {
    return YoutubeMusicResult(
      resultType: map['resultType']?.toString() ?? '',
      title: map['title']?.toString() ?? 'Unknown title',
      artist: map['artist']?.toString() ?? '',
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

  const YoutubeVideoQuality({
    required this.label,
    required this.height,
    required this.url,
    required this.formatId,
    required this.ext,
    this.hasAudio = true,
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
  final String album;
  final String thumbnailUrl;
  final int durationSeconds;
  final String videoId;
  final bool isVideo;
  final String qualityLabel;
  final List<YoutubeVideoQuality> qualities;
  final List<YoutubeSubtitleOption> subtitles;

  const YoutubeMusicStream({
    required this.url,
    required this.title,
    required this.artist,
    required this.album,
    required this.thumbnailUrl,
    required this.durationSeconds,
    required this.videoId,
    required this.isVideo,
    this.qualityLabel = 'Auto',
    this.qualities = const [],
    this.subtitles = const [],
  });

  factory YoutubeMusicStream.fromMap(Map<String, dynamic> map) {
    final rawQualities = map['qualities'] as List? ?? const [];
    final rawSubtitles = map['subtitles'] as List? ?? const [];
    return YoutubeMusicStream(
      url: map['url']?.toString() ?? '',
      title: map['title']?.toString() ?? 'YouTube Music',
      artist: map['artist']?.toString() ?? 'YouTube Music',
      album: map['album']?.toString() ?? '',
      thumbnailUrl: map['thumbnailUrl']?.toString() ?? '',
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
    );
  }
}

class YoutubeMusicService {
  static const MethodChannel platform = MethodChannel('python_channel');
  static const int _maxStreamCacheEntries = 12;

  final Map<String, Future<YoutubeMusicStream>> _streamFutures = {};
  final Map<String, YoutubeMusicStream> _streamCache = {};

  static bool get isSupported =>
      !kIsWeb &&
      (Platform.isAndroid ||
          Platform.isWindows ||
          Platform.isLinux ||
          Platform.isMacOS);

  static bool get usesNativeChannel => !kIsWeb && Platform.isAndroid;

  Future<int> add(int a, int b) async {
    if (!usesNativeChannel) {
      final output = await _runPython(['add', '$a', '$b']);
      return int.tryParse(output.trim()) ?? 0;
    }

    final result = await platform.invokeMethod<int>('add', {'a': a, 'b': b});
    return result ?? 0;
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
      if (usesNativeChannel) {
        response = await platform.invokeMethod<List<dynamic>>(
              'searchYoutubeMusic',
              {'query': query, 'filter': filter, 'limit': limit},
            ) ??
            const [];
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
      throw StateError(_friendlyPythonError(error.toString()));
    }
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

    try {
      final Map<dynamic, dynamic> response;
      final outputDir = await _resolveDownloadDirectory();
      if (usesNativeChannel) {
        final channelMap = result.toChannelMap()
          ..['outputDir'] = outputDir
          ..['video'] = video
          ..['qualityHeight'] = qualityHeight
          ..['qualityHeights'] = qualityHeights
          ..['subtitlesOnly'] = subtitlesOnly
          ..['includeSubtitles'] = includeSubtitles
          ..['subtitleLanguage'] = subtitleLanguage
          ..['subtitleLanguages'] = subtitleLanguages
          ..['automaticSubtitles'] = automaticSubtitles;
        onProgress?.call(null, 'Starting download...');
        response = await platform.invokeMethod<Map<dynamic, dynamic>>(
              'downloadYoutubeMusic',
              channelMap,
            ) ??
            const {};
        onProgress?.call(1, 'Download finished.');
      } else {
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
        response = Map<dynamic, dynamic>.from(jsonDecode(output) as Map);
      }

      return YoutubeMusicDownload.fromMap(Map<String, dynamic>.from(response));
    } catch (error) {
      throw StateError(_friendlyPythonError(error.toString()));
    }
  }

  Future<String> resolvedDownloadDirectory() => _resolveDownloadDirectory();

  Future<YoutubeMusicStream> stream(YoutubeMusicResult result) async {
    final key = _cacheKey(result);
    final cached = _streamCache[key];
    if (cached != null) {
      return cached;
    }

    final pending = _streamFutures[key];
    if (pending != null) {
      return pending;
    }

    final future = _resolveStream(result);
    _streamFutures[key] = future;
    try {
      final stream = await future;
      _streamCache[key] = stream;
      _trimStreamCache();
      return stream;
    } finally {
      _streamFutures.remove(key);
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
      final key = _cacheKey(result);
      if (_streamCache.containsKey(key) || _streamFutures.containsKey(key)) {
        continue;
      }
      final future = _resolveStream(result);
      _streamFutures[key] = future;
      future.then((stream) {
        _streamCache[key] = stream;
        _trimStreamCache();
      }).catchError((Object _) {
        // Warm-up failures are intentionally quiet; tapping still reports them.
      }).whenComplete(() {
        _streamFutures.remove(key);
      });
    }
  }

  Future<YoutubeMusicStream> _resolveStream(
    YoutubeMusicResult result, {
    int? maxHeight,
  }) async {
    if (!isSupported) {
      throw UnsupportedError(
          'YouTube Music is not available on this platform yet.');
    }

    try {
      final Map<dynamic, dynamic> response;
      if (usesNativeChannel) {
        response = await platform.invokeMethod<Map<dynamic, dynamic>>(
              'streamYoutubeMusic',
              result.toChannelMap(),
            ) ??
            const {};
      } else {
        final args = [
          'stream',
          '--item-json',
          jsonEncode(result.toChannelMap()),
        ];
        if (maxHeight != null && maxHeight > 0) {
          args.addAll(['--quality-height', '$maxHeight']);
        }
        final output = await _runPython(args);
        response = Map<dynamic, dynamic>.from(jsonDecode(output) as Map);
      }

      return YoutubeMusicStream.fromMap(Map<String, dynamic>.from(response));
    } catch (error) {
      throw StateError(_friendlyPythonError(error.toString()));
    }
  }

  Future<String> _resolveDownloadDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(SettingsModel.youtubeMusicDownloadPathKey);
    if (saved != null && saved.trim().isNotEmpty) {
      return _ensureWritableDirectory(saved.trim());
    }

    final defaultDir = await defaultYoutubeMusicDownloadDirectory();
    final resolvedDefault = await _ensureWritableDirectory(defaultDir);
    await prefs.setString(
        SettingsModel.youtubeMusicDownloadPathKey, resolvedDefault);
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
    } else if (Platform.isMacOS || Platform.isLinux) {
      final homeDir = Platform.environment['HOME'];
      if (homeDir != null && homeDir.isNotEmpty) {
        return p.join(homeDir, 'Music', 'PlayerVf YouTube Music');
      }
    }

    final musicDir = await getApplicationDocumentsDirectory();
    return p.join(musicDir.path, 'PlayerVf', 'YouTube Music');
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

  Future<String> _runPython(
    List<String> args, {
    void Function(double? progress, String message)? onProgress,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError(
          'YouTube Music downloads and streaming are not available on web.');
    }

    final script = await _pythonScriptPath();
    final executable = await _desktopPythonExecutable(script, args);
    final Process process;
    try {
      process = await Process.start(executable, [script, ...args]);
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
      } catch (_) {
        // Keep non-JSON stderr for error reporting below.
      }

      stderrBuffer.writeln(line);
    });

    final exitCode = await process.exitCode;
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

    if (args.isNotEmpty && args.first == 'add') {
      return Platform.isWindows ? 'python' : 'python3';
    }

    final projectRoot = Directory(p.dirname(p.dirname(p.dirname(script))));
    final envDir =
        Directory(p.join(projectRoot.path, '.dart_tool', 'playervf_python'));
    final pythonExe = Platform.isWindows
        ? File(p.join(envDir.path, 'Scripts', 'python.exe'))
        : File(p.join(envDir.path, 'bin', 'python'));
    final marker = File(p.join(envDir.path, '.player_vf_ready'));

    if (await pythonExe.exists() && await marker.exists()) {
      return pythonExe.path;
    }

    await envDir.parent.create(recursive: true);
    final basePython = Platform.isWindows ? 'python' : 'python3';
    if (!await pythonExe.exists()) {
      final venv = await Process.run(basePython, ['-m', 'venv', envDir.path]);
      if (venv.exitCode != 0) {
        throw StateError(_friendlyPythonError(
          '${venv.stderr}\n${venv.stdout}'.trim(),
        ));
      }
    }

    final requirements = p.join(p.dirname(script), 'requirements.txt');
    final install = await Process.run(pythonExe.path, [
      '-m',
      'pip',
      'install',
      '--upgrade',
      '-r',
      requirements,
    ]);
    if (install.exitCode != 0) {
      throw StateError(_friendlyPythonError(
        '${install.stderr}\n${install.stdout}'.trim(),
      ));
    }

    await marker.writeAsString(DateTime.now().toIso8601String());
    return pythonExe.path;
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

    final supportDir = await getApplicationSupportDirectory();
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
      return 'Python dependencies are not installed yet. Restart the app and try Search again.';
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
