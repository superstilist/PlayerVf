import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import '../models/music_model.dart';
import '../models/settings_model.dart';
import 'windows_video_open_service.dart';

class VideoPlaybackService {
  Player _player;
  final DecoderMode Function() videoDecoderMode;
  final void Function(String message) debug;
  final VoidCallback? onChanged;

  VideoController? _controller;
  bool _controllerReady = false;
  bool _hasVideoTrack = false;
  Timer? _surfaceSizeProbeTimer;
  bool _surfaceSizeProbeActive = false;
  int? _lastSurfaceWidth;
  int? _lastSurfaceHeight;

  VideoPlaybackService({
    required Player player,
    required this.videoDecoderMode,
    required this.debug,
    this.onChanged,
  }) : _player = player;

  VideoController? get controller => _controller;
  bool get controllerReady => _controllerReady;
  bool get hasVideoTrack => _hasVideoTrack;

  void attachPlayer(Player player) {
    if (identical(_player, player)) return;
    _player = player;
    _cancelSurfaceSizeProbe();
    _controller = null;
    _controllerReady = false;
    _lastSurfaceWidth = null;
    _lastSurfaceHeight = null;
    onChanged?.call();
  }

  void setCurrentTrack(Music track) {
    final isVideo = isVideoTrack(track);
    _hasVideoTrack = isVideo;
    if (!isVideo) {
      _controller = null;
      _controllerReady = false;
    }
    onChanged?.call();
  }

  void reset() {
    _cancelSurfaceSizeProbe();
    _hasVideoTrack = false;
    _controller = null;
    _controllerReady = false;
    _lastSurfaceWidth = null;
    _lastSurfaceHeight = null;
    onChanged?.call();
  }

  void dispose() {
    reset();
  }

  bool isVideoTrack(Music music) => isVideoMedia(music);

  static bool isVideoMedia(Music music) {
    final genre = music.genre.trim().toLowerCase();
    if (genre.contains('video')) return true;
    if (genre == 'youtube music') return false;
    if (hasPlayervfAudioSidecar(music.filePath)) return false;

    final ext = mediaPathExtension(music.filePath);
    if (const {'.mp3', '.m4a', '.flac', '.wav', '.ogg', '.opus', '.aac', '.wma'}
        .contains(ext)) {
      return false;
    }
    if (const {
      '.mp4',
      '.mkv',
      '.webm',
      '.avi',
      '.mov',
      '.m4v',
      '.wmv',
      '.flv',
      '.ts',
      '.m2ts',
      '.3gp',
      '.m3u8',
    }.contains(ext)) {
      return true;
    }
    return false;
  }

  static String mediaPathExtension(String path) {
    final target = (localFilePathFromMediaPath(path) ?? path).trim();
    if (target.isEmpty) return '';
    final parsed = Uri.tryParse(target);
    final candidate = parsed != null && parsed.hasScheme
        ? parsed.path
        : target.split('?').first.split('#').first;
    return p.extension(candidate).toLowerCase();
  }

  static bool hasPlayervfAudioSidecar(String filePath) {
    if (filePath.trim().isEmpty) return false;
    final sidecar = File('${p.withoutExtension(filePath)}.playervf.audio.json');
    if (!sidecar.existsSync()) return false;
    try {
      final decoded = jsonDecode(sidecar.readAsStringSync());
      return decoded is Map && decoded['type'] == 'playervf.youtubeAudio';
    } catch (_) {
      return true;
    }
  }

  static String? localFilePathFromMediaPath(String path) {
    final target = path.trim();
    if (!target.startsWith('file://')) return null;
    final uri = Uri.tryParse(target);
    if (uri == null || !uri.isScheme('file')) return null;
    try {
      return uri.toFilePath(windows: !kIsWeb && Platform.isWindows);
    } catch (_) {
      return null;
    }
  }

  String primaryMediaSource(String filePath) {
    final localPath = localFilePathFromMediaPath(filePath);
    final source = (localPath ?? filePath).trim();
    if (source.isEmpty) return source;
    if (!kIsWeb && Platform.isWindows) {
      return source.replaceAll('/', r'\');
    }
    return source;
  }

  Future<void> prepareForTrack(
    Player player,
    Music track, {
    required double volume,
    required Map<String, dynamic> extras,
    required Future<void> Function(Player player, double volume) setVolume,
    required Future<void> Function(Player player) applyAudioEffects,
    required String audioDecoderThreadValue,
    required String linuxAudioOutputDrivers,
  }) async {
    _hasVideoTrack = isVideoTrack(track);
    await setVolume(player, volume);
    await applyDecoderSettings(
      player,
      audioDecoderThreadValue: audioDecoderThreadValue,
      linuxAudioOutputDrivers: linuxAudioOutputDrivers,
    );
    await openMediaKitPath(player, track, extras: extras, play: false);
    if (isVideoTrack(track)) {
      attachPlayer(player);
      await ensureControllerForCurrentTrack();
    }
    await applySidecarSubtitleIfAvailable(player, track.filePath);
    await applyAudioEffects(player);
  }

  Future<void> openVideoTrack({
    required Player player,
    required Music track,
    required Map<String, dynamic> extras,
    required String audioDecoderThreadValue,
    required String linuxAudioOutputDrivers,
  }) async {
    attachPlayer(player);
    _hasVideoTrack = true;
    _controller = null;
    _controllerReady = false;
    _lastSurfaceWidth = null;
    _lastSurfaceHeight = null;
    onChanged?.call();

    await applyDecoderSettings(
      player,
      audioDecoderThreadValue: audioDecoderThreadValue,
      linuxAudioOutputDrivers: linuxAudioOutputDrivers,
    );
    await applyWindowsVideoStabilityPreset(player, track);
    await ensureControllerForCurrentTrack();
    if (!kIsWeb && Platform.isWindows && _controllerReady) {
      await _forceVideoOutputEnabled(player);
      debug('VideoPlaybackService: opening video with controller attached');
    }
    await openMediaKitPath(player, track, extras: extras, play: false);
    debug('VideoPlaybackService: video open success');
    if (!kIsWeb && Platform.isWindows && _controllerReady) {
      await _forceVideoOutputEnabled(player);
    }
    debug(
      'VideoPlaybackService: video controller ready=$_controllerReady controller=${_controller != null}',
    );
    await applySidecarSubtitleIfAvailable(player, track.filePath);
  }

  Future<void> openMediaKitPath(
    Player player,
    Music track, {
    required Map<String, dynamic> extras,
    required bool play,
  }) async {
    final source = primaryMediaSource(track.filePath);
    final timeout = mediaOpenTimeout(track, source);
    if (!kIsWeb && Platform.isWindows && isVideoTrack(track)) {
      await WindowsVideoOpenService.openSimple(
        player: player,
        track: track,
        extras: extras,
        play: play,
        debug: debug,
      );
      return;
    }

    debug('VideoPlaybackService: open source="$source" play=$play');
    try {
      final openFuture = player.open(
        Media(
          source,
          extras: extras,
          httpHeaders: track.httpHeaders.isEmpty ? null : track.httpHeaders,
        ),
        play: play,
      );
      if (timeout == null) {
        await openFuture;
      } else {
        await openFuture.timeout(timeout);
      }
      debug('VideoPlaybackService: open success source="$source"');
    } catch (error) {
      debug('VideoPlaybackService: open failed source="$source" error=$error');
      throw StateError('Could not open media: $source. $error');
    }
  }

  Duration? mediaOpenTimeout(Music track, String target) {
    if (kIsWeb) return const Duration(seconds: 60);
    if (!isVideoTrack(track)) return const Duration(seconds: 30);
    final normalized = target.trim().toLowerCase();
    final isRemote = normalized.startsWith('http://') ||
        normalized.startsWith('https://') ||
        normalized.startsWith('blob:');
    if (isRemote) return const Duration(seconds: 45);
    return const Duration(seconds: 12);
  }

  Future<void> ensureControllerForCurrentTrack() async {
    if (!_hasVideoTrack) {
      _controller = null;
      _controllerReady = false;
      onChanged?.call();
      return;
    }
    if (_controllerReady && _controller?.player == _player) return;
    await _initVideoController();
  }

  Future<void> _initVideoController() async {
    try {
      _controller = null;
      _controllerReady = false;
      onChanged?.call();
      final forceSoftwareVideo =
          !kIsWeb && (Platform.isLinux || Platform.isWindows);
      final controller = VideoController(
        _player,
        configuration: VideoControllerConfiguration(
          width: !kIsWeb && Platform.isWindows ? 1280 : null,
          height: !kIsWeb && Platform.isWindows ? 720 : null,
          hwdec: _videoHwdecValue(),
          enableHardwareAcceleration: !forceSoftwareVideo,
        ),
      );
      _controller = controller;
      await controller.platform.future;
      if (!identical(_controller, controller)) {
        return;
      }
      _controllerReady = true;
      onChanged?.call();
    } catch (e) {
      debug('VideoController not available on this platform: $e');
      _controller = null;
      _controllerReady = false;
      onChanged?.call();
    }
  }

  Future<void> _forceVideoOutputEnabled(Player player) async {
    final native = player.platform;
    if (native is! NativePlayer) return;
    await _setNativePlayerProperty(native, 'vo', 'libmpv');
    await _setNativePlayerProperty(native, 'vid', 'auto');
    await _setNativePlayerProperty(native, 'video', 'auto');
    try {
      await player
          .setVideoTrack(VideoTrack.auto())
          .timeout(const Duration(seconds: 2));
    } catch (error) {
      debug('VideoPlaybackService: set video track auto failed: $error');
    }
  }

  bool updateSurfaceSize({
    required int? width,
    required int? height,
    String reason = 'stream',
  }) {
    final nextWidth = width ?? 0;
    final nextHeight = height ?? 0;
    if (!_hasVideoTrack ||
        !_controllerReady ||
        _controller == null ||
        nextWidth <= 1 ||
        nextHeight <= 1) {
      return false;
    }

    if (_lastSurfaceWidth == nextWidth && _lastSurfaceHeight == nextHeight) {
      return true;
    }

    _lastSurfaceWidth = nextWidth;
    _lastSurfaceHeight = nextHeight;
    final controller = _controller!;
    debug(
      'VideoPlaybackService: resize surface ${nextWidth}x$nextHeight reason=$reason',
    );
    unawaited(
      controller
          .setSize(width: nextWidth, height: nextHeight)
          .timeout(const Duration(seconds: 2))
          .catchError((Object error) {
        if (identical(_controller, controller)) {
          _lastSurfaceWidth = null;
          _lastSurfaceHeight = null;
        }
        debug('VideoPlaybackService: resize surface failed: $error');
      }),
    );
    return true;
  }

  void startSurfaceSizeProbe({String reason = 'playback'}) {
    if (kIsWeb || !_hasVideoTrack) return;
    _cancelSurfaceSizeProbe();
    var attempts = 0;

    void probe(String label) {
      if (_surfaceSizeProbeActive) return;
      _surfaceSizeProbeActive = true;
      unawaited(_readNativeVideoSize().then((size) {
        if (size == null) return;
        final applied = updateSurfaceSize(
          width: size.width,
          height: size.height,
          reason: label,
        );
        if (applied && size.width > 1 && size.height > 1) {
          _cancelSurfaceSizeProbe();
        }
      }).catchError((Object error) {
        debug('VideoPlaybackService: surface size probe failed: $error');
      }).whenComplete(() {
        _surfaceSizeProbeActive = false;
      }));
    }

    probe('$reason-immediate');
    _surfaceSizeProbeTimer = Timer.periodic(
      const Duration(milliseconds: 150),
      (timer) {
        attempts += 1;
        if (!_hasVideoTrack || !_controllerReady || _controller == null) {
          if (attempts >= 10) {
            _cancelSurfaceSizeProbe();
          }
          return;
        }
        probe('$reason-$attempts');
        if (attempts >= 40) {
          _cancelSurfaceSizeProbe();
        }
      },
    );
  }

  void _cancelSurfaceSizeProbe() {
    _surfaceSizeProbeTimer?.cancel();
    _surfaceSizeProbeTimer = null;
    _surfaceSizeProbeActive = false;
  }

  Future<_VideoSurfaceSize?> _readNativeVideoSize() async {
    final native = _player.platform;
    if (native is! NativePlayer) return null;
    final dynamic nativePlayer = native;
    final width = await _readNativeIntProperty(nativePlayer, 'dwidth') ??
        await _readNativeIntProperty(nativePlayer, 'width');
    final height = await _readNativeIntProperty(nativePlayer, 'dheight') ??
        await _readNativeIntProperty(nativePlayer, 'height');
    if (width == null || height == null || width <= 1 || height <= 1) {
      return null;
    }
    return _VideoSurfaceSize(width, height);
  }

  Future<int?> _readNativeIntProperty(
    dynamic nativePlayer,
    String property,
  ) async {
    final value = await nativePlayer.getProperty(
      property,
      waitForInitialization: false,
    );
    return int.tryParse(value.toString().trim());
  }

  Future<void> applyDecoderSettings(
    Player player, {
    required String audioDecoderThreadValue,
    required String linuxAudioOutputDrivers,
  }) async {
    final native = player.platform;
    if (native is! NativePlayer) return;
    await _setNativePlayerProperty(native, 'hwdec', _videoHwdecValue());
    await _setNativePlayerProperty(native, 'gpu-api', _videoGpuApiValue());
    await _setNativePlayerProperty(
      native,
      'vd-lavc-software-fallback',
      (!kIsWeb && Platform.isLinux) ||
              videoDecoderMode() != DecoderMode.hardware
          ? 'yes'
          : 'no',
    );
    await _setNativePlayerProperty(native, 'vd-lavc-threads',
        videoDecoderMode() == DecoderMode.software ? '1' : '0');
    await _setNativePlayerProperty(native, 'vd-lavc-dr',
        videoDecoderMode() == DecoderMode.software ? 'no' : 'yes');
    await _setNativePlayerProperty(native, 'hwdec-codecs',
        videoDecoderMode() == DecoderMode.software ? 'no' : 'all');
    if (!kIsWeb && Platform.isLinux) {
      await _setNativePlayerProperty(native, 'gpu-hwdec-interop', 'no');
      await _setNativePlayerProperty(native, 'ao', linuxAudioOutputDrivers);
      await _setNativePlayerProperty(native, 'audio-device', 'auto');
    }
    await _setNativePlayerProperty(
      native,
      'ad-lavc-threads',
      audioDecoderThreadValue,
    );
  }

  Future<void> applyWindowsVideoStabilityPreset(
    Player player,
    Music track,
  ) async {
    if (kIsWeb || !Platform.isWindows || !isVideoTrack(track)) return;
    final source = primaryMediaSource(track.filePath);
    if (!_isLocalPath(source)) return;
    final native = player.platform;
    if (native is! NativePlayer) return;
    await _setNativePlayerProperty(native, 'hwdec', 'no');
    await _setNativePlayerProperty(native, 'vd-lavc-software-fallback', 'yes');
    await _setNativePlayerProperty(native, 'vd-lavc-dr', 'no');
    await _setNativePlayerProperty(native, 'hwdec-codecs', 'no');
    await _setNativePlayerProperty(native, 'video-sync', 'audio');
  }

  String _videoHwdecValue() {
    if (!kIsWeb && Platform.isLinux) return 'no';
    if (!kIsWeb && Platform.isWindows && _hasVideoTrack) return 'no';
    if (_shouldPreferWindowsSoftwareVideo()) return 'no';
    switch (videoDecoderMode()) {
      case DecoderMode.hardware:
        return !kIsWeb && Platform.isWindows ? 'd3d11va' : 'auto';
      case DecoderMode.software:
        return 'no';
      case DecoderMode.auto:
        return !kIsWeb && Platform.isWindows ? 'auto' : 'auto-safe';
    }
  }

  String _videoGpuApiValue() {
    if (kIsWeb) return 'auto';
    if (Platform.isWindows && _hasVideoTrack) return 'auto';
    if (_shouldPreferWindowsSoftwareVideo()) return 'auto';
    if (Platform.isWindows && videoDecoderMode() != DecoderMode.software) {
      return 'd3d11';
    }
    return 'auto';
  }

  bool _shouldPreferWindowsSoftwareVideo() {
    return !kIsWeb &&
        Platform.isWindows &&
        _hasVideoTrack &&
        videoDecoderMode() == DecoderMode.auto;
  }

  bool _isLocalPath(String path) {
    final normalized = path.trim().toLowerCase();
    return normalized.isNotEmpty &&
        !normalized.startsWith('http://') &&
        !normalized.startsWith('https://') &&
        !normalized.startsWith('blob:');
  }

  Future<bool> _setNativePlayerProperty(
      NativePlayer native, String property, String value) async {
    try {
      await (native as dynamic).setProperty(property, value);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> loadSubtitleFile(String path) async {
    if (path.trim().isEmpty) return;
    await _player.setSubtitleTrack(
      SubtitleTrack.uri(
        Uri.file(path).toString(),
        title: p.basename(path),
      ),
    );
  }

  Future<void> loadSubtitleUrl(String url, {String? title}) async {
    final normalized = url.trim();
    if (normalized.isEmpty) return;
    await _player.setSubtitleTrack(
      SubtitleTrack.uri(
        normalized,
        title: title?.trim().isNotEmpty == true ? title!.trim() : 'Subtitles',
      ),
    );
  }

  Future<void> disableSubtitles() async {
    await _player.setSubtitleTrack(SubtitleTrack.no());
  }

  Future<void> applySidecarSubtitleIfAvailable(
      Player player, String mediaPath) async {
    if (kIsWeb) return;
    for (final candidate in subtitleSidecarCandidates(mediaPath)) {
      final file = File(candidate);
      if (!await file.exists()) continue;
      await player.setSubtitleTrack(
        SubtitleTrack.uri(
          Uri.file(candidate).toString(),
          title: p.basename(candidate),
        ),
      );
      return;
    }
  }

  List<String> subtitleSidecarCandidates(String mediaPath) {
    final dir = p.dirname(mediaPath);
    final name = p.basenameWithoutExtension(mediaPath);
    return [
      p.join(dir, '$name.srt'),
      p.join(dir, '$name.vtt'),
      p.join(dir, '$name.ass'),
      p.join(dir, '$name.ssa'),
    ];
  }
}

class _VideoSurfaceSize {
  final int width;
  final int height;

  const _VideoSurfaceSize(this.width, this.height);
}
