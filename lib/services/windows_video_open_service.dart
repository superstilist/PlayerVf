import 'package:media_kit/media_kit.dart';

import '../models/music_model.dart';

class WindowsVideoOpenService {
  static Future<void> openSimple({
    required Player player,
    required Music track,
    required Map<String, dynamic> extras,
    required bool play,
    required void Function(String message) debug,
  }) async {
    final path = _localPathFromTrackPath(track.filePath);
    if (path.isEmpty) {
      throw StateError('Video path is empty.');
    }

    if (_isRemoteMediaPath(path)) {
      debug('WINDOWS_VIDEO_OPEN: open remote="$path" play=$play');
      try {
        await player.open(
          Media(
            path,
            extras: extras,
            httpHeaders: track.httpHeaders.isEmpty ? null : track.httpHeaders,
          ),
          play: play,
        );
        debug('WINDOWS_VIDEO_OPEN: success remote="$path"');
        return;
      } catch (error) {
        debug('WINDOWS_VIDEO_OPEN: remote failed error=$error');
        throw StateError('Could not open remote video: $error');
      }
    }

    final uriSource = Uri.file(path).toString();
    debug('WINDOWS_VIDEO_OPEN: open uri="$uriSource" play=$play');
    try {
      await player.open(
        Media(
          uriSource,
          extras: extras,
          httpHeaders: track.httpHeaders.isEmpty ? null : track.httpHeaders,
        ),
        play: play,
      );
      debug('WINDOWS_VIDEO_OPEN: success uri="$uriSource"');
      return;
    } catch (firstError) {
      debug('WINDOWS_VIDEO_OPEN: uri failed error=$firstError');
    }

    debug('WINDOWS_VIDEO_OPEN: fallback open path="$path" play=$play');
    await player.open(
      Media(
        path,
        extras: extras,
        httpHeaders: track.httpHeaders.isEmpty ? null : track.httpHeaders,
      ),
      play: play,
    );
    debug('WINDOWS_VIDEO_OPEN: success path="$path"');
  }

  static String _localPathFromTrackPath(String rawPath) {
    final trimmed = rawPath.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.isScheme('file')) {
      return uri.toFilePath(windows: true);
    }
    return trimmed;
  }

  static bool _isRemoteMediaPath(String path) {
    final lower = path.trim().toLowerCase();
    return lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('blob:');
  }
}
