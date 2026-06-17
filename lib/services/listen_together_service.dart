import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/music_model.dart';
import '../services/local_share_service.dart';
import '../services/music_service.dart';

class ListenTogetherService extends ChangeNotifier {
  final LocalShareService _partyShareService = LocalShareService();

  bool _isPartyHosting = false;
  bool _isPartyJoined = false;
  bool _isPartyBusy = false;
  bool _isApplyingPartyState = false;
  String? _partyStatus;
  String? _partyHostUrl;
  String? _partyTrackUrl;
  String? _partyTrackId;
  String? _partyQueueSignature;
  List<DiscoveredShareDevice> _partyDevices = const [];

  Timer? _partyHostTimer;
  Timer? _partyGuestTimer;

  // Getters
  LocalShareService get partyShareService => _partyShareService;
  bool get isPartyHosting => _isPartyHosting;
  bool get isPartyJoined => _isPartyJoined;
  bool get isPartyBusy => _isPartyBusy;
  String? get partyStatus => _partyStatus;
  String? get partyHostUrl => _partyHostUrl;
  String? get partyTrackUrl => _partyTrackUrl;
  List<DiscoveredShareDevice> get partyDevices => _partyDevices;

  @override
  void dispose() {
    stop(silent: true);
    super.dispose();
  }

  void stop({bool silent = false}) {
    _partyHostTimer?.cancel();
    _partyGuestTimer?.cancel();
    _partyHostTimer = null;
    _partyGuestTimer = null;
    unawaited(_partyShareService.stopSharing());

    _isPartyHosting = false;
    _isPartyJoined = false;
    _isPartyBusy = false;
    _isApplyingPartyState = false;
    _partyHostUrl = null;
    _partyTrackUrl = null;
    _partyTrackId = null;
    _partyQueueSignature = null;
    _partyDevices = const [];
    _partyStatus = silent ? null : 'Party stopped';
    notifyListeners();
  }

  Future<void> startHost(MusicService musicService) async {
    final current = musicService.currentMusic;
    if (current == null) return;
    final queue = _partyShareQueue(musicService, current);

    _isPartyBusy = true;
    _partyStatus = 'Starting party...';
    notifyListeners();

    try {
      final info = await _partyShareService.startSharing(
        library: musicService.musicList,
        currentTrack: current,
        selectedTracks: queue,
        scope: ShareScope.selectedSongs,
        onRemoteCommand: (command) =>
            _handlePartyRemoteCommand(command, musicService),
      );
      _partyShareService.updatePlaybackState(
        currentTrack: current,
        isPlaying: musicService.isPlaying,
        position: musicService.position,
      );
      await _publishPartyLyrics(musicService, current);
      _partyHostTimer?.cancel();
      _partyTrackId = current.id;
      _partyHostTimer =
          Timer.periodic(const Duration(milliseconds: 350), (_) async {
        await _publishPartyHostState(musicService);
      });

      _isPartyHosting = true;
      _isPartyJoined = false;
      _partyHostUrl = info.urls.isNotEmpty ? info.urls.first : null;
      _partyStatus = 'Hosting ${current.title}';
    } catch (error) {
      _partyStatus = 'Party failed: $error';
    } finally {
      _isPartyBusy = false;
      notifyListeners();
    }
  }

  Future<void> _publishPartyHostState(MusicService musicService) async {
    if (!_isPartyHosting || _isPartyBusy) return;
    final current = musicService.currentMusic;
    if (current == null) return;
    final queue = _partyShareQueue(musicService, current);
    if (_partyTrackId != current.id) {
      _partyTrackId = current.id;
      try {
        _partyShareService.updateSharedTracks(
          library: musicService.musicList,
          currentTrack: current,
          selectedTracks: queue,
          scope: ShareScope.selectedSongs,
        );
        await _publishPartyLyrics(musicService, current);
      } catch (_) {}
    } else {
      _partyShareService.updateSharedTracks(
        library: musicService.musicList,
        currentTrack: current,
        selectedTracks: queue,
        scope: ShareScope.selectedSongs,
      );
    }
    _partyShareService.updatePlaybackState(
      currentTrack: current,
      isPlaying: musicService.isPlaying,
      position: musicService.position,
    );
    final peers = _partyShareService.connectedPeerLabels;
    _partyStatus = peers.isEmpty
        ? 'Hosting ${current.title}'
        : 'Hosting ${current.title} with ${peers.length} connected';
    notifyListeners();
  }

  Future<void> _publishPartyLyrics(
    MusicService musicService,
    Music current,
  ) async {
    try {
      final document =
          await musicService.loadLyricsDocumentForCurrent(searchOnline: false);
      if (musicService.currentMusic?.id != current.id) return;
      _partyShareService.setSharedLyrics(current, document?.rawText);
    } catch (_) {
      _partyShareService.setSharedLyrics(current, null);
    }
  }

  Future<void> join(MusicService musicService) async {
    _isPartyBusy = true;
    _partyStatus = 'Searching for parties...';
    notifyListeners();

    try {
      final devices = await _partyShareService.discoverDevices(
        timeout: const Duration(milliseconds: 2200),
      );
      final available =
          devices.where((item) => item.trackCount > 0).toList(growable: false);
      _partyDevices = available;
      if (available.length > 1) {
        _partyStatus = 'Choose a device to join.';
        _isPartyBusy = false;
        notifyListeners();
        return;
      }
      final device = devices.firstWhere(
        (item) => item.trackCount > 0,
        orElse: () => throw StateError('No PlayerVF party found nearby.'),
      );
      await connect(musicService, device);
    } catch (error) {
      _partyStatus = error.toString();
      _isPartyBusy = false;
      notifyListeners();
    }
  }

  Future<void> connect(
    MusicService musicService,
    DiscoveredShareDevice device,
  ) async {
    _isPartyBusy = true;
    _partyStatus = 'Joining ${device.deviceName}...';
    notifyListeners();

    try {
      final manifest = await _partyShareService.fetchManifest(
        device.url,
        guestName: _localPartyDeviceName(),
      );
      await _applyPartyManifest(
        musicService: musicService,
        baseUrl: device.url,
        manifest: manifest,
        forceTrackOpen: true,
      );
      _partyGuestTimer?.cancel();
      _partyGuestTimer =
          Timer.periodic(const Duration(milliseconds: 250), (_) async {
        await _syncPartyGuest(musicService);
      });

      _isPartyJoined = true;
      _isPartyHosting = false;
      _isPartyBusy = false;
      _partyHostUrl = device.url;
      _partyStatus = 'Listening with ${manifest.deviceName}';
    } catch (error) {
      _isPartyBusy = false;
      _partyStatus = 'Could not join ${device.deviceName}: $error';
    } finally {
      notifyListeners();
    }
  }

  Future<void> _syncPartyGuest(MusicService musicService) async {
    final hostUrl = _partyHostUrl;
    if (!_isPartyJoined || hostUrl == null || _isApplyingPartyState) return;
    try {
      final manifest = await _partyShareService.fetchManifest(
        hostUrl,
        guestName: _localPartyDeviceName(),
      );
      await _applyPartyManifest(
        musicService: musicService,
        baseUrl: hostUrl,
        manifest: manifest,
      );
    } catch (error) {
      _partyStatus = 'Party sync paused: $error';
      notifyListeners();
    }
  }

  Future<void> _applyPartyManifest({
    required MusicService musicService,
    required String baseUrl,
    required RemoteShareManifest manifest,
    bool forceTrackOpen = false,
  }) async {
    final track = manifest.currentTrack ??
        (manifest.tracks.isNotEmpty ? manifest.tracks.first : null);
    if (track == null) return;
    _isApplyingPartyState = true;
    try {
      final streamUrl = _partyStreamUrl(baseUrl, track);
      final targetPosition = Duration(
        milliseconds: math.max(0, manifest.positionMs),
      );
      final current = musicService.currentMusic;
      final shouldOpen = forceTrackOpen ||
          current == null ||
          current.filePath != streamUrl ||
          _partyTrackUrl != streamUrl;
      final queueSignature =
          manifest.tracks.map((track) => track.id).join('\n');
      final shouldSyncQueue = _partyQueueSignature != queueSignature;
      if (shouldOpen) {
        _partyTrackUrl = streamUrl;
        _partyTrackId = track.id;
        _partyQueueSignature = queueSignature;
        await musicService.replaceStreamingQueue(
          _partyStreamingQueue(baseUrl, manifest.tracks),
          _partyStreamingMusic(baseUrl, track),
          startPosition: targetPosition,
          shouldPlay: manifest.isPlaying,
        );
        if (track.lyricsText.trim().isNotEmpty) {
          await musicService.saveLyricsForCurrent(track.lyricsText);
        }
        return;
      }

      if (shouldSyncQueue) {
        _partyQueueSignature = queueSignature;
        await musicService.replaceStreamingQueue(
          _partyStreamingQueue(baseUrl, manifest.tracks),
          _partyStreamingMusic(baseUrl, track),
        );
      }

      final drift =
          (musicService.position - targetPosition).inMilliseconds.abs();
      if (drift > 700) {
        musicService.seekTo(targetPosition);
      }
      if (manifest.isPlaying != musicService.isPlaying) {
        musicService.togglePlayPause();
      }
    } finally {
      _isApplyingPartyState = false;
    }
  }

  String _partyStreamUrl(String baseUrl, RemoteShareTrack track) {
    return _partyAssetUrl(baseUrl, track.downloadPath) ??
        Uri.parse(baseUrl)
            .replace(path: '/player-vf/file/${Uri.encodeComponent(track.id)}')
            .toString();
  }

  List<Music> _partyShareQueue(MusicService musicService, Music current) {
    final seen = <String>{};
    final tracks = <Music>[];
    for (final music in musicService.queueMusicList) {
      if (seen.add(music.id)) tracks.add(music);
    }
    if (seen.add(current.id)) {
      tracks.insert(0, current);
    }
    return tracks;
  }

  List<Music> _partyStreamingQueue(
    String baseUrl,
    List<RemoteShareTrack> tracks,
  ) {
    return [
      for (final track in tracks) _partyStreamingMusic(baseUrl, track),
    ];
  }

  Music _partyStreamingMusic(String baseUrl, RemoteShareTrack track) {
    final coverUrl = _partyAssetUrl(baseUrl, track.coverDownloadPath);
    return Music(
      id: 'party-${track.id}',
      title: track.title,
      artist: track.artist,
      album: track.album,
      filePath: _partyStreamUrl(baseUrl, track),
      coverPath: coverUrl ?? '',
      genre: track.genre,
      year: track.year,
      duration: track.durationMs == null
          ? null
          : Duration(milliseconds: track.durationMs!),
    );
  }

  void runPartyPlaybackCommand(String command, MusicService musicService) {
    if (!_isPartyJoined || _partyHostUrl == null) {
      _applyLocalPartyCommand(command, musicService);
      return;
    }
    unawaited(_sendPartyPlaybackCommand(command, musicService));
  }

  Future<void> _sendPartyPlaybackCommand(
    String command,
    MusicService musicService,
  ) async {
    final hostUrl = _partyHostUrl;
    if (hostUrl == null) return;
    try {
      await _partyShareService.sendControlCommand(
        hostUrl,
        command,
        guestName: _localPartyDeviceName(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 90));
      await _syncPartyGuest(musicService);
    } catch (error) {
      _partyStatus = 'Party control failed: $error';
      notifyListeners();
    }
  }

  Future<void> _handlePartyRemoteCommand(
    String command,
    MusicService musicService,
  ) async {
    _applyLocalPartyCommand(command, musicService);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    _partyShareService.updatePlaybackState(
      currentTrack: musicService.currentMusic,
      isPlaying: musicService.isPlaying,
      position: musicService.position,
    );
  }

  void _applyLocalPartyCommand(String command, MusicService musicService) {
    switch (command) {
      case 'toggle':
      case 'playPause':
        musicService.togglePlayPause();
        break;
      case 'next':
        musicService.next();
        break;
      case 'previous':
      case 'back':
        musicService.previousTrack();
        break;
    }
  }

  String? _partyAssetUrl(String baseUrl, String path) {
    if (path.isEmpty) return null;
    final base = Uri.parse(baseUrl);
    return base.replace(path: path).toString();
  }

  String _localPartyDeviceName() {
    try {
      final host = Platform.localHostname.trim();
      if (host.isNotEmpty) return host;
    } catch (_) {}
    return 'PlayerVF device';
  }
}
