import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import 'package:smtc_windows/smtc_windows.dart' as smtc;

import '../models/music_model.dart';

late PlayerAudioHandler playerAudioHandler;

Future<PlayerAudioHandler> initPlayerAudioHandler() async {
  if (!kIsWeb && Platform.isWindows) {
    await smtc.SMTCWindows.initialize();
  }

  return AudioService.init(
    builder: PlayerAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.untitled.audio',
      androidNotificationChannelName: 'PlayerVf playback',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
    ),
  );
}

class PlayerAudioHandler extends BaseAudioHandler with SeekHandler {
  PlayerAudioHandler() {
    _init();
  }

  final AudioPlayer player = AudioPlayer();
  final BehaviorSubject<double> volume = BehaviorSubject.seeded(1.0);
  final _recentSubject = BehaviorSubject.seeded(<MediaItem>[]);

  smtc.SMTCWindows? _windowsSmtc;
  StreamSubscription? _windowsButtonsSub;
  Timer? _windowsTimelineTimer;
  bool _windowsSmtcDisabled = false;
  DateTime _lastPlayPauseToggle = DateTime.fromMillisecondsSinceEpoch(0);
  bool _completionReported = false;

  Future<void> Function()? onTogglePlayPauseCommand;
  Future<void> Function()? onPlayCommand;
  Future<void> Function()? onPauseCommand;
  Future<void> Function()? onNextCommand;
  Future<void> Function()? onPreviousCommand;
  Future<void> Function(Duration position)? onSeekCommand;
  Future<void> Function()? onCompleted;

  Stream<Duration> get positionStream => player.positionStream;
  Stream<Duration?> get durationStream => player.durationStream;
  Stream<bool> get playingStream => player.playingStream;
  Stream<PlayerState> get playerStateStream => player.playerStateStream;

  Duration get position => player.position;
  Duration? get duration => player.duration;
  bool get playing => player.playing;

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await AudioService.androidForceEnableMediaButtons();
      } catch (e) {
        debugPrint('Could not force-enable Android media buttons: $e');
      }
    }

    playbackState.add(playbackState.value.copyWith(
      controls: _controlsFor(false),
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.idle,
    ));

    player.playbackEventStream.listen(_broadcastState);
    player.processingStateStream.listen((state) {
      if (state != ProcessingState.completed) {
        _completionReported = false;
        return;
      }
      if (_completionReported) return;
      _completionReported = true;
      unawaited(onCompleted?.call());
    });
    player.durationStream.listen((duration) {
      final current = mediaItem.valueOrNull;
      if (current == null || duration == null || current.duration == duration) {
        return;
      }
      mediaItem.add(current.copyWith(duration: duration));
    });
    player.positionStream.listen((_) => _updateWindowsTimeline());
    player.bufferedPositionStream.listen((_) => _updateWindowsTimeline());
    mediaItem.whereType<MediaItem>().listen((item) {
      _recentSubject.add([item]);
      unawaited(_updateWindowsMetadata(item));
    });
    volume.listen((value) => unawaited(player.setVolume(value)));

    if (!kIsWeb && Platform.isWindows) {
      _windowsSmtc = smtc.SMTCWindows(
        enabled: false,
        config: const smtc.SMTCConfig(
          playEnabled: true,
          pauseEnabled: true,
          nextEnabled: true,
          prevEnabled: true,
          stopEnabled: false,
          fastForwardEnabled: false,
          rewindEnabled: false,
        ),
      );
      _windowsButtonsSub = _windowsSmtc!.buttonPressStream.listen((button) {
        switch (button) {
          case smtc.PressedButton.play:
            unawaited(click(MediaButton.media));
            break;
          case smtc.PressedButton.pause:
            unawaited(click(MediaButton.media));
            break;
          case smtc.PressedButton.next:
            unawaited(skipToNext());
            break;
          case smtc.PressedButton.previous:
            unawaited(skipToPrevious());
            break;
          case smtc.PressedButton.stop:
            unawaited(stop());
            break;
          default:
            break;
        }
      });
      _windowsTimelineTimer = Timer.periodic(
          const Duration(seconds: 1), (_) => _updateWindowsTimeline());
    }
  }

  Future<void> openTrack(Music track, {Duration? initialPosition}) async {
    final item = _mediaItemFor(track);
    mediaItem.add(item);
    playbackState.add(playbackState.value.copyWith(queueIndex: 0));

    try {
      await player.setAudioSource(AudioSource.uri(_audioUri(track.filePath)));
    } catch (_) {
      playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.error,
        playing: false,
      ));
      rethrow;
    }
    if (initialPosition != null && initialPosition > Duration.zero) {
      await player.seek(initialPosition);
    }
    _broadcastState(player.playbackEvent);
    await _windowsSmtc?.enableSmtc();
  }

  Future<void> updateNowPlayingOnly(Music track) async {
    final current = mediaItem.valueOrNull;
    await updateNowPlaying(
      track,
      playing: playbackState.value.playing,
      position: playbackState.value.updatePosition,
      duration: track.duration ??
          (current?.id == track.id ? current?.duration : null),
    );
  }

  Future<void> updateNowPlaying(
    Music track, {
    required bool playing,
    required Duration position,
    Duration? duration,
    AudioProcessingState processingState = AudioProcessingState.ready,
  }) async {
    final item = _mediaItemFor(track, duration: duration);
    final current = mediaItem.valueOrNull;
    if (current == null ||
        current.id != item.id ||
        current.title != item.title ||
        current.artist != item.artist ||
        current.album != item.album ||
        current.duration != item.duration ||
        current.artUri != item.artUri) {
      mediaItem.add(item);
    }

    playbackState.add(playbackState.value.copyWith(
      controls: _controlsFor(playing),
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: processingState,
      playing: playing,
      updatePosition: position,
      bufferedPosition: position,
      speed: 1.0,
      queueIndex: 0,
    ));
    await _windowsSmtc?.enableSmtc();
  }

  void setExternalPlaybackState({
    required bool playing,
    required Duration position,
    required Duration duration,
  }) {
    final current = mediaItem.valueOrNull;
    if (current != null &&
        duration > Duration.zero &&
        current.duration != duration) {
      mediaItem.add(current.copyWith(duration: duration));
    }
    playbackState.add(playbackState.value.copyWith(
      controls: _controlsFor(playing),
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.ready,
      playing: playing,
      updatePosition: position,
      bufferedPosition: position,
      queueIndex: 0,
    ));
  }

  Future<void> playFromService() => player.play();

  Future<void> pauseFromService() => player.pause();

  Future<void> seekFromService(Duration position) => player.seek(position);

  Future<void> setVolumeFromService(double value) async {
    volume.add(value.clamp(0.0, 1.0));
  }

  @override
  Future<void> play() async {
    final command = onPlayCommand;
    if (command != null) {
      await command();
      return;
    }
    await playFromService();
  }

  @override
  Future<void> pause() async {
    final command = onPauseCommand;
    if (command != null) {
      await command();
      return;
    }
    await pauseFromService();
  }

  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    switch (button) {
      case MediaButton.media:
        await _togglePlayPauseNow();
        break;
      case MediaButton.next:
        await skipToNext();
        break;
      case MediaButton.previous:
        await skipToPrevious();
        break;
    }
  }

  Future<void> _togglePlayPauseNow() async {
    final now = DateTime.now();
    if (now.difference(_lastPlayPauseToggle).inMilliseconds < 450) {
      return;
    }
    _lastPlayPauseToggle = now;
    final toggleCommand = onTogglePlayPauseCommand;
    if (toggleCommand != null) {
      await toggleCommand();
      return;
    }
    if (playbackState.value.playing) {
      await pause();
    } else {
      await play();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    final command = onSeekCommand;
    if (command != null) {
      await command(position);
      return;
    }
    await seekFromService(position);
  }

  @override
  Future<void> skipToNext() async {
    final command = onNextCommand;
    if (command != null) {
      await command();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    final command = onPreviousCommand;
    if (command != null) {
      await command();
    }
  }

  @override
  Future<void> stop() async {
    await player.stop();
    await _windowsSmtc?.disableSmtc();
    playbackState.add(playbackState.value.copyWith(
      controls: _controlsFor(false),
      processingState: AudioProcessingState.idle,
      playing: false,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
    ));
  }

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId,
      [Map<String, dynamic>? options]) async {
    if (parentMediaId == AudioService.recentRootId) {
      return _recentSubject.value;
    }
    return const [];
  }

  @override
  ValueStream<Map<String, dynamic>> subscribeToChildren(String parentMediaId) {
    return _recentSubject.map((_) => <String, dynamic>{}).shareValueSeeded({});
  }

  List<MediaControl> _controlsFor(bool playing) => [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ];

  void _broadcastState(PlaybackEvent event) {
    final isPlaying = player.playing;
    final processingState = {
      ProcessingState.idle: AudioProcessingState.idle,
      ProcessingState.loading: AudioProcessingState.loading,
      ProcessingState.buffering: AudioProcessingState.buffering,
      ProcessingState.ready: AudioProcessingState.ready,
      ProcessingState.completed: AudioProcessingState.completed,
    }[player.processingState]!;

    playbackState.add(playbackState.value.copyWith(
      controls: _controlsFor(isPlaying),
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: processingState,
      playing: isPlaying,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
      queueIndex: 0,
    ));

    if (!kIsWeb && Platform.isWindows && !_windowsSmtcDisabled) {
      final status = isPlaying
          ? smtc.PlaybackStatus.playing
          : player.processingState == ProcessingState.completed
              ? smtc.PlaybackStatus.stopped
              : smtc.PlaybackStatus.paused;
      unawaited(_guardWindowsSmtc(
          () async => _windowsSmtc?.setPlaybackStatus(status)));
      _updateWindowsTimeline();
    }
  }

  MediaItem _mediaItemFor(Music track, {Duration? duration}) {
    final artUri = _artUri(track.coverPath);
    return MediaItem(
      id: track.id,
      title: _metadataTitle(track),
      artist: _metadataArtist(track),
      album: track.album.isEmpty ? null : track.album,
      duration: duration ?? track.duration,
      artUri: artUri,
      playable: true,
      extras: {'uri': track.filePath},
    );
  }

  Uri _audioUri(String path) {
    final parsed = Uri.tryParse(path);
    if (parsed != null && parsed.hasScheme && !_isWindowsDriveUri(parsed)) {
      return parsed;
    }
    return Uri.file(path);
  }

  Uri? _artUri(String path) {
    final value = path.trim();
    if (value.isEmpty) return null;
    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.hasScheme && !_isWindowsDriveUri(parsed)) {
      return parsed;
    }
    return Uri.file(value);
  }

  bool _isWindowsDriveUri(Uri uri) =>
      uri.scheme.length == 1 && RegExp(r'^[a-zA-Z]$').hasMatch(uri.scheme);

  String _metadataTitle(Music track) {
    final title = track.title.trim();
    if (title.isNotEmpty) return title;
    final uri = Uri.tryParse(track.filePath);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      return Uri.decodeComponent(uri.pathSegments.last);
    }
    return 'Unknown track';
  }

  String _metadataArtist(Music track) {
    final artist = track.artist.trim();
    return artist.isEmpty ? 'PlayerVf' : artist;
  }

  Future<void> _updateWindowsMetadata(MediaItem item) async {
    final controls = _windowsSmtc;
    if (controls == null || _windowsSmtcDisabled) return;
    await _guardWindowsSmtc(() async {
      await controls.updateMetadata(smtc.MusicMetadata(
        title: _safeSmtcText(item.title, 'PlayerVf'),
        artist: _safeSmtcText(item.artist, 'PlayerVf'),
        album: _safeSmtcText(item.album, ''),
        albumArtist: _safeSmtcText(item.artist, 'PlayerVf'),
        thumbnail: _safeSmtcThumbnail(item.artUri),
      ));
      _updateWindowsTimeline();
    });
  }

  void _updateWindowsTimeline() {
    final controls = _windowsSmtc;
    if (controls == null || _windowsSmtcDisabled) return;
    final total = player.duration ?? mediaItem.valueOrNull?.duration;
    final endMs = total?.inMilliseconds ?? 0;
    if (endMs <= 0) return;
    unawaited(_guardWindowsSmtc(() async {
      await controls.updateTimeline(smtc.PlaybackTimeline(
        startTimeMs: 0,
        endTimeMs: endMs,
        positionMs: player.position.inMilliseconds.clamp(0, endMs),
        minSeekTimeMs: 0,
        maxSeekTimeMs: endMs,
      ));
    }));
  }

  Future<void> _guardWindowsSmtc(Future<void>? Function() action) async {
    if (_windowsSmtcDisabled) return;
    try {
      await action();
    } catch (error, stackTrace) {
      _windowsSmtcDisabled = true;
      _windowsTimelineTimer?.cancel();
      debugPrint('Windows SMTC disabled after native error: $error');
      if (kDebugMode) {
        debugPrintStack(stackTrace: stackTrace);
      }
      try {
        await _windowsSmtc?.dispose();
      } catch (_) {}
      _windowsSmtc = null;
    }
  }

  String _safeSmtcText(String? value, String fallback) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  String _safeSmtcThumbnail(Uri? uri) {
    if (uri == null) return '';
    if (uri.scheme == 'file') {
      final file = File(uri.toFilePath());
      return file.existsSync() ? uri.toString() : '';
    }
    return uri.toString();
  }

  Future<void> disposeHandler() async {
    _windowsTimelineTimer?.cancel();
    await _windowsButtonsSub?.cancel();
    await _windowsSmtc?.dispose();
    await player.dispose();
    await volume.close();
    await _recentSubject.close();
  }
}
