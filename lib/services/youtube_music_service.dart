import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  final String downloadDir;
  final String message;

  const YoutubeMusicDownload({
    required this.files,
    required this.downloadDir,
    required this.message,
  });

  factory YoutubeMusicDownload.fromMap(Map<String, dynamic> map) {
    final rawFiles = map['files'] as List? ?? const [];
    return YoutubeMusicDownload(
      files: rawFiles.map((item) => item.toString()).toList(),
      downloadDir: map['downloadDir']?.toString() ?? '',
      message: map['message']?.toString() ?? '',
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

  const YoutubeMusicStream({
    required this.url,
    required this.title,
    required this.artist,
    required this.album,
    required this.thumbnailUrl,
    required this.durationSeconds,
    required this.videoId,
    required this.isVideo,
  });

  factory YoutubeMusicStream.fromMap(Map<String, dynamic> map) {
    return YoutubeMusicStream(
      url: map['url']?.toString() ?? '',
      title: map['title']?.toString() ?? 'YouTube Music',
      artist: map['artist']?.toString() ?? 'YouTube Music',
      album: map['album']?.toString() ?? '',
      thumbnailUrl: map['thumbnailUrl']?.toString() ?? '',
      durationSeconds: (map['durationSeconds'] as num?)?.toInt() ?? 0,
      videoId: map['videoId']?.toString() ?? '',
      isVideo: map['isVideo'] == true,
    );
  }
}

class YoutubeMusicService {
  static const MethodChannel platform = MethodChannel('python_channel');

  static bool get isSupported =>
      Platform.isAndroid ||
      Platform.isWindows ||
      Platform.isLinux ||
      Platform.isMacOS;

  static bool get usesNativeChannel => Platform.isAndroid;

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
    void Function(double? progress, String message)? onProgress,
  }) async {
    if (!isSupported) {
      throw UnsupportedError(
          'YouTube Music is not available on this platform yet.');
    }

    try {
      final Map<dynamic, dynamic> response;
      if (usesNativeChannel) {
        onProgress?.call(null, 'Starting download...');
        response = await platform.invokeMethod<Map<dynamic, dynamic>>(
              'downloadYoutubeMusic',
              result.toChannelMap(),
            ) ??
            const {};
        onProgress?.call(1, 'Download finished.');
      } else {
        final outputDir = await _desktopDownloadDirectory();
        final output = await _runPython([
          'download',
          '--item-json',
          jsonEncode(result.toChannelMap()),
          '--output-dir',
          outputDir,
        ], onProgress: onProgress);
        response = Map<dynamic, dynamic>.from(jsonDecode(output) as Map);
      }

      return YoutubeMusicDownload.fromMap(Map<String, dynamic>.from(response));
    } catch (error) {
      throw StateError(_friendlyPythonError(error.toString()));
    }
  }

  Future<YoutubeMusicStream> stream(YoutubeMusicResult result) async {
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
        final output = await _runPython([
          'stream',
          '--item-json',
          jsonEncode(result.toChannelMap()),
        ]);
        response = Map<dynamic, dynamic>.from(jsonDecode(output) as Map);
      }

      return YoutubeMusicStream.fromMap(Map<String, dynamic>.from(response));
    } catch (error) {
      throw StateError(_friendlyPythonError(error.toString()));
    }
  }

  Future<String> _desktopDownloadDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(SettingsModel.youtubeMusicDownloadPathKey);
    if (saved != null && saved.trim().isNotEmpty) {
      return saved;
    }

    final defaultDir = await defaultYoutubeMusicDownloadDirectory();
    await prefs.setString(
        SettingsModel.youtubeMusicDownloadPathKey, defaultDir);
    return defaultDir;
  }

  static Future<String> defaultYoutubeMusicDownloadDirectory() async {
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

  Future<String> _runPython(
    List<String> args, {
    void Function(double? progress, String message)? onProgress,
  }) async {
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
