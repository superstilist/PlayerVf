import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/music_model.dart';
import 'app_directories.dart';

enum ShareScope { currentSong, selectedSongs, fullLibrary }

class ShareServerInfo {
  final int port;
  final List<String> urls;
  final ShareScope scope;
  final int trackCount;

  const ShareServerInfo({
    required this.port,
    required this.urls,
    required this.scope,
    required this.trackCount,
  });
}

class DiscoveredShareDevice {
  final String deviceName;
  final String url;
  final ShareScope scope;
  final int trackCount;

  const DiscoveredShareDevice({
    required this.deviceName,
    required this.url,
    required this.scope,
    required this.trackCount,
  });

  factory DiscoveredShareDevice.fromJson(Map<String, dynamic> json) {
    final scopeName = json['scope']?.toString();
    return DiscoveredShareDevice(
      deviceName: json['deviceName']?.toString() ?? 'PlayerVF device',
      url: json['url']?.toString() ?? '',
      scope: _shareScopeFromName(scopeName),
      trackCount: (json['trackCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class RemoteShareManifest {
  final String deviceName;
  final ShareScope scope;
  final String? currentTrackId;
  final bool isPlaying;
  final int positionMs;
  final int updatedAtMs;
  final List<String> connectedPeers;
  final List<RemoteShareTrack> tracks;

  const RemoteShareManifest({
    required this.deviceName,
    required this.scope,
    required this.currentTrackId,
    required this.isPlaying,
    required this.positionMs,
    required this.updatedAtMs,
    required this.connectedPeers,
    required this.tracks,
  });

  factory RemoteShareManifest.fromJson(Map<String, dynamic> json) {
    final scopeName = json['scope']?.toString();
    final tracks = (json['tracks'] as List? ?? [])
        .whereType<Map>()
        .map((item) => RemoteShareTrack.fromJson(
            Map<String, dynamic>.from(item.cast<String, dynamic>())))
        .toList();

    return RemoteShareManifest(
      deviceName: json['deviceName']?.toString() ?? 'PlayerVF device',
      scope: _shareScopeFromName(scopeName),
      currentTrackId: json['currentTrackId']?.toString(),
      isPlaying: json['isPlaying'] == true,
      positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
      updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ?? 0,
      connectedPeers: (json['connectedPeers'] as List? ?? [])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(growable: false),
      tracks: tracks,
    );
  }

  RemoteShareTrack? get currentTrack {
    final id = currentTrackId;
    if (id == null || id.isEmpty) return null;
    for (final track in tracks) {
      if (track.id == id) return track;
    }
    return null;
  }
}

class RemoteShareTrack {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String genre;
  final String year;
  final String fileName;
  final int sizeBytes;
  final int? durationMs;
  final String downloadPath;
  final String coverDownloadPath;
  final String lyricsText;

  const RemoteShareTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.genre,
    required this.year,
    required this.fileName,
    required this.sizeBytes,
    required this.durationMs,
    required this.downloadPath,
    required this.coverDownloadPath,
    required this.lyricsText,
  });

  factory RemoteShareTrack.fromJson(Map<String, dynamic> json) {
    return RemoteShareTrack(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Unknown title',
      artist: json['artist']?.toString() ?? 'Unknown Artist',
      album: json['album']?.toString() ?? 'Unknown Album',
      genre: json['genre']?.toString() ?? 'Unknown',
      year: json['year']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? 'track',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      durationMs: (json['durationMs'] as num?)?.toInt(),
      downloadPath: json['downloadPath']?.toString() ?? '',
      coverDownloadPath: json['coverDownloadPath']?.toString() ?? '',
      lyricsText: json['lyricsText']?.toString() ?? '',
    );
  }
}

class ShareTransferProgress {
  final int completedFiles;
  final int totalFiles;
  final int receivedBytes;
  final int totalBytes;
  final String currentFileName;
  final double bytesPerSecond;

  const ShareTransferProgress({
    required this.completedFiles,
    required this.totalFiles,
    required this.receivedBytes,
    required this.totalBytes,
    required this.currentFileName,
    required this.bytesPerSecond,
  });

  double get fraction {
    if (totalBytes <= 0) return 0;
    return (receivedBytes / totalBytes).clamp(0.0, 1.0);
  }
}

class LocalShareService {
  static const int _defaultPort = 45780;
  static const int _discoveryPort = 45781;
  static const String _discoveryMagic = 'player-vf-share-discovery-v1';
  static const String _manifestPath = '/player-vf/manifest';
  static const String _controlPath = '/player-vf/control';
  static const String _filePrefix = '/player-vf/file/';
  static const String _coverPrefix = '/player-vf/cover/';

  HttpServer? _server;
  RawDatagramSocket? _discoverySocket;
  ShareServerInfo? _serverInfo;
  List<Music> _sharedTracks = [];
  Music? _currentTrack;
  ShareScope _scope = ShareScope.currentSong;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  DateTime _playbackUpdatedAt = DateTime.now();
  final Map<String, String> _sharedLyrics = {};
  final Map<String, DateTime> _connectedPeerSeenAt = {};
  final Map<String, String> _connectedPeerNames = {};
  Future<void> Function(String command)? _remoteControlHandler;
  bool _cancelTransfer = false;
  bool _pauseTransfer = false;

  bool get isSharing => _server != null;
  List<String> get connectedPeerLabels {
    _removeExpiredPeers();
    return _connectedPeerSeenAt.keys
        .map((key) => _connectedPeerNames[key] ?? key)
        .toList(growable: false)
      ..sort();
  }

  Future<ShareServerInfo> startSharing({
    required List<Music> library,
    Music? currentTrack,
    List<Music>? selectedTracks,
    ShareScope scope = ShareScope.currentSong,
    Future<void> Function(String command)? onRemoteCommand,
  }) async {
    await stopSharing();
    _scope = scope;
    _currentTrack = currentTrack;
    _remoteControlHandler = onRemoteCommand;
    _sharedTracks = _shareableTracksForScope(
      library: library,
      currentTrack: currentTrack,
      selectedTracks: selectedTracks,
      scope: scope,
    );

    if (_sharedTracks.isEmpty) {
      throw const FileSystemException(
          'No local audio files available to share');
    }

    _server = await HttpServer.bind(InternetAddress.anyIPv4, _defaultPort,
        shared: true);
    _server!.listen(_handleRequest);

    final info = ShareServerInfo(
      port: _server!.port,
      urls: await _localUrls(_server!.port),
      scope: scope,
      trackCount: _sharedTracks.length,
    );
    _serverInfo = info;
    await _startDiscoveryResponder(info);
    return info;
  }

  void updateSharedTracks({
    required List<Music> library,
    Music? currentTrack,
    List<Music>? selectedTracks,
    ShareScope? scope,
  }) {
    final nextScope = scope ?? _scope;
    final nextTracks = _shareableTracksForScope(
      library: library,
      currentTrack: currentTrack,
      selectedTracks: selectedTracks,
      scope: nextScope,
    );
    if (nextTracks.isEmpty) return;

    _scope = nextScope;
    _currentTrack = currentTrack ?? _currentTrack;
    _sharedTracks = nextTracks;
    final info = _serverInfo;
    if (info != null) {
      _serverInfo = ShareServerInfo(
        port: info.port,
        urls: info.urls,
        scope: _scope,
        trackCount: _sharedTracks.length,
      );
    }
    _sharedLyrics.removeWhere(
      (key, _) => !_sharedTracks.any((music) => music.id == key),
    );
  }

  Future<void> stopSharing() async {
    final server = _server;
    final discoverySocket = _discoverySocket;
    _server = null;
    _discoverySocket = null;
    _serverInfo = null;
    _sharedTracks = [];
    _currentTrack = null;
    _isPlaying = false;
    _position = Duration.zero;
    _playbackUpdatedAt = DateTime.now();
    _remoteControlHandler = null;
    _sharedLyrics.removeWhere(
      (key, _) => !_sharedTracks.any((music) => music.id == key),
    );
    _connectedPeerSeenAt.clear();
    _connectedPeerNames.clear();
    discoverySocket?.close();
    if (server != null) {
      await server.close(force: true);
    }
  }

  void updatePlaybackState({
    Music? currentTrack,
    required bool isPlaying,
    required Duration position,
  }) {
    _currentTrack = currentTrack ?? _currentTrack;
    _isPlaying = isPlaying;
    _position = position < Duration.zero ? Duration.zero : position;
    _playbackUpdatedAt = DateTime.now();
  }

  void setSharedLyrics(Music music, String? rawLyrics) {
    final lyrics = rawLyrics?.trim();
    if (lyrics == null || lyrics.isEmpty) {
      _sharedLyrics.remove(music.id);
      return;
    }
    _sharedLyrics[music.id] = lyrics;
  }

  Future<List<DiscoveredShareDevice>> discoverDevices({
    Duration timeout = const Duration(milliseconds: 1800),
  }) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final found = <String, DiscoveredShareDevice>{};
    final completer = Completer<List<DiscoveredShareDevice>>();
    Timer? timer;

    try {
      socket.broadcastEnabled = true;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;

        try {
          final decoded = jsonDecode(utf8.decode(datagram.data));
          if (decoded is! Map) return;
          final json = Map<String, dynamic>.from(decoded);
          if (json['app'] != 'PlayerVF' ||
              json['magic'] != _discoveryMagic ||
              json['type'] != 'announce') {
            return;
          }

          final urls = (json['urls'] as List? ?? [])
              .map((item) => item.toString())
              .where((url) => url.isNotEmpty)
              .toList();
          final directUrl = json['url']?.toString();
          final usableUrl = directUrl != null && directUrl.isNotEmpty
              ? directUrl
              : _bestUrlForAddress(urls, datagram.address.address);
          if (usableUrl == null || usableUrl.isEmpty) return;

          found[usableUrl] = DiscoveredShareDevice.fromJson({
            ...json,
            'url': usableUrl,
          });
        } catch (_) {}
      });

      final payload = utf8.encode(jsonEncode({
        'app': 'PlayerVF',
        'magic': _discoveryMagic,
        'type': 'discover',
      }));

      socket.send(payload, InternetAddress('255.255.255.255'), _discoveryPort);
      for (final address in await _subnetBroadcastAddresses()) {
        socket.send(payload, address, _discoveryPort);
      }

      timer = Timer(timeout, () {
        if (!completer.isCompleted) {
          completer.complete(found.values.toList());
        }
      });

      await completer.future;
      await _probeShareServers(found);
      final devices = found.values.toList()
        ..sort((a, b) => a.deviceName.compareTo(b.deviceName));
      return devices;
    } finally {
      timer?.cancel();
      socket.close();
    }
  }

  Future<RemoteShareManifest> fetchManifest(
    String address, {
    String? guestName,
  }) async {
    final base = _normalizeBaseAddress(address);
    final client = HttpClient();
    client.connectionTimeout = const Duration(milliseconds: 900);
    try {
      final query = <String, String>{};
      final cleanGuestName = guestName?.trim();
      if (cleanGuestName != null && cleanGuestName.isNotEmpty) {
        query['guestName'] = cleanGuestName;
      }
      final request = await client.getUrl(base.replace(
        path: _manifestPath,
        queryParameters: query.isEmpty ? null : query,
      ));
      final response =
          await request.close().timeout(const Duration(seconds: 2));
      final body =
          await utf8.decodeStream(response).timeout(const Duration(seconds: 2));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Share server returned ${response.statusCode}');
      }
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      return RemoteShareManifest.fromJson(decoded);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> sendControlCommand(
    String address,
    String command, {
    String? guestName,
  }) async {
    final base = _normalizeBaseAddress(address);
    final client = HttpClient();
    client.connectionTimeout = const Duration(milliseconds: 450);
    try {
      final query = <String, String>{};
      final cleanGuestName = guestName?.trim();
      if (cleanGuestName != null && cleanGuestName.isNotEmpty) {
        query['guestName'] = cleanGuestName;
      }
      final request = await client
          .postUrl(base.replace(
            path: _controlPath,
            queryParameters: query.isEmpty ? null : query,
          ))
          .timeout(const Duration(milliseconds: 550));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'command': command}));
      final response =
          await request.close().timeout(const Duration(milliseconds: 700));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Control failed with ${response.statusCode}');
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _probeShareServers(
    Map<String, DiscoveredShareDevice> found,
  ) async {
    final urls = await _candidateProbeUrls();
    const batchSize = 32;
    for (var offset = 0; offset < urls.length; offset += batchSize) {
      final batch = urls.skip(offset).take(batchSize).toList();
      final results = await Future.wait(
        batch.map(_probeShareServer),
      );
      for (final device in results.whereType<DiscoveredShareDevice>()) {
        found[device.url] = device;
      }
    }
  }

  Future<List<String>> _candidateProbeUrls() async {
    final hosts = <String>{'127.0.0.1', 'localhost'};
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final parts = address.address.split('.');
        if (parts.length != 4) continue;
        hosts.add(address.address);
        for (var host = 1; host <= 254; host++) {
          hosts.add('${parts[0]}.${parts[1]}.${parts[2]}.$host');
        }
      }
    }
    return hosts.map((host) => 'http://$host:$_defaultPort').toList();
  }

  Future<DiscoveredShareDevice?> _probeShareServer(String url) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(milliseconds: 220);
    try {
      final base = _normalizeBaseAddress(url);
      final request = await client
          .getUrl(base.replace(path: _manifestPath))
          .timeout(const Duration(milliseconds: 280));
      final response =
          await request.close().timeout(const Duration(milliseconds: 550));
      if (response.statusCode != HttpStatus.ok) return null;

      final body = await utf8
          .decodeStream(response)
          .timeout(const Duration(milliseconds: 550));
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final manifest =
          RemoteShareManifest.fromJson(Map<String, dynamic>.from(decoded));
      return DiscoveredShareDevice(
        deviceName: manifest.deviceName,
        url: url,
        scope: manifest.scope,
        trackCount: manifest.tracks.length,
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<List<String>> downloadTracks({
    required String address,
    required Iterable<RemoteShareTrack> tracks,
    void Function(ShareTransferProgress progress)? onProgress,
    Future<void> Function(String path)? onFileComplete,
  }) async {
    final base = _normalizeBaseAddress(address);
    final selectedTracks = tracks.toList();
    if (selectedTracks.isEmpty) return [];

    final targetDir = await _syncDirectory();
    final totalBytes = selectedTracks.fold<int>(
      0,
      (sum, track) => sum + track.sizeBytes,
    );
    var completedFiles = 0;
    var receivedBytes = 0;
    final startedAt = DateTime.now();
    final downloadedPaths = <String>[];
    final client = HttpClient();
    _cancelTransfer = false;
    _pauseTransfer = false;

    try {
      for (final track in selectedTracks) {
        if (_cancelTransfer) break;
        final existingPath = await _existingSyncedPath(targetDir, track);
        if (existingPath != null) {
          receivedBytes += track.sizeBytes;
          completedFiles++;
          downloadedPaths.add(existingPath);
          await onFileComplete?.call(existingPath);
          onProgress?.call(
            ShareTransferProgress(
              completedFiles: completedFiles,
              totalFiles: selectedTracks.length,
              receivedBytes: receivedBytes,
              totalBytes: totalBytes,
              currentFileName: track.fileName,
              bytesPerSecond: _transferSpeed(receivedBytes, startedAt),
            ),
          );
          continue;
        }

        final filePath = await _uniqueTargetPath(targetDir, track.fileName);
        final file = File(filePath);
        final sink = file.openWrite();
        var fileReceived = 0;

        try {
          final path = track.downloadPath.isNotEmpty
              ? track.downloadPath
              : '$_filePrefix${Uri.encodeComponent(track.id)}';
          final response = await _openDownloadResponse(client, base, path);
          if (response.statusCode != HttpStatus.ok) {
            throw HttpException(
              'Download failed for ${track.title}: ${response.statusCode}',
            );
          }

          await for (final chunk in response) {
            while (_pauseTransfer && !_cancelTransfer) {
              await Future<void>.delayed(const Duration(milliseconds: 180));
            }
            if (_cancelTransfer) {
              throw const HttpException('Transfer cancelled');
            }
            fileReceived += chunk.length;
            receivedBytes += chunk.length;
            sink.add(chunk);
            onProgress?.call(
              ShareTransferProgress(
                completedFiles: completedFiles,
                totalFiles: selectedTracks.length,
                receivedBytes: receivedBytes,
                totalBytes: totalBytes,
                currentFileName: track.fileName,
                bytesPerSecond: _transferSpeed(receivedBytes, startedAt),
              ),
            );
          }
        } finally {
          await sink.close();
        }

        if (fileReceived == 0) {
          await file.delete().catchError((_) => file);
        } else {
          downloadedPaths.add(filePath);
          await onFileComplete?.call(filePath);
        }

        completedFiles++;
        onProgress?.call(
          ShareTransferProgress(
            completedFiles: completedFiles,
            totalFiles: selectedTracks.length,
            receivedBytes: receivedBytes,
            totalBytes: totalBytes,
            currentFileName: track.fileName,
            bytesPerSecond: _transferSpeed(receivedBytes, startedAt),
          ),
        );
      }
    } finally {
      client.close(force: true);
    }

    return downloadedPaths;
  }

  Future<HttpClientResponse> _openDownloadResponse(
    HttpClient client,
    Uri base,
    String path,
  ) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final request = await client
            .getUrl(base.replace(path: path))
            .timeout(const Duration(seconds: 3));
        return await request.close().timeout(const Duration(seconds: 6));
      } catch (error) {
        lastError = error;
        if (attempt < 2) {
          await Future<void>.delayed(
              Duration(milliseconds: 220 * (attempt + 1)));
        }
      }
    }
    throw lastError ?? const HttpException('Unable to open transfer');
  }

  void cancelTransfer() {
    _cancelTransfer = true;
    _pauseTransfer = false;
  }

  void pauseTransfer() {
    _pauseTransfer = true;
  }

  void resumeTransfer() {
    _pauseTransfer = false;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (path == _manifestPath) {
        _rememberPeer(request);
        await _writeManifest(request.response);
        return;
      }

      if (path == _controlPath) {
        _rememberPeer(request);
        await _handleControl(request);
        return;
      }

      if (path.startsWith(_filePrefix)) {
        _rememberPeer(request);
        await _writeFile(request, path.substring(_filePrefix.length));
        return;
      }

      if (path.startsWith(_coverPrefix)) {
        _rememberPeer(request);
        await _writeCover(request, path.substring(_coverPrefix.length));
        return;
      }

      request.response
        ..statusCode = HttpStatus.notFound
        ..write('PlayerVF share endpoint not found');
    } catch (error) {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write(error.toString());
    } finally {
      await request.response.close();
    }
  }

  Future<void> _handleControl(HttpRequest request) async {
    if (request.method != 'POST') {
      request.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..write('POST required');
      return;
    }
    final body = await utf8.decodeStream(request);
    final decoded = jsonDecode(body);
    final command = decoded is Map ? decoded['command']?.toString() : null;
    if (command == null || command.trim().isEmpty) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('Missing command');
      return;
    }
    final handler = _remoteControlHandler;
    if (handler == null) {
      request.response
        ..statusCode = HttpStatus.conflict
        ..write('Remote control unavailable');
      return;
    }
    await handler(command.trim());
    request.response
      ..statusCode = HttpStatus.ok
      ..write('ok');
  }

  Future<void> _startDiscoveryResponder(ShareServerInfo info) async {
    _discoverySocket?.close();
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      _discoveryPort,
      reuseAddress: true,
      reusePort: true,
    );
    _discoverySocket = socket;

    socket.listen((event) async {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null) return;

      try {
        final decoded = jsonDecode(utf8.decode(datagram.data));
        if (decoded is! Map) return;
        final json = Map<String, dynamic>.from(decoded);
        if (json['app'] != 'PlayerVF' ||
            json['magic'] != _discoveryMagic ||
            json['type'] != 'discover') {
          return;
        }

        final currentInfo = _serverInfo ?? info;
        final urls = currentInfo.urls;
        final response = utf8.encode(jsonEncode({
          'app': 'PlayerVF',
          'magic': _discoveryMagic,
          'type': 'announce',
          'deviceName': await _deviceName(),
          'scope': currentInfo.scope.name,
          'trackCount': currentInfo.trackCount,
          'url': _bestUrlForAddress(urls, datagram.address.address) ??
              (urls.isNotEmpty ? urls.first : null),
          'urls': urls,
        }));
        socket.send(response, datagram.address, datagram.port);
      } catch (_) {}
    });
  }

  Future<void> _writeManifest(HttpResponse response) async {
    final deviceName = await _deviceName();
    final now = DateTime.now();
    final elapsed =
        _isPlaying ? now.difference(_playbackUpdatedAt) : Duration.zero;
    final effectivePosition = _position + elapsed;
    final manifest = {
      'app': 'PlayerVF',
      'version': 1,
      'deviceName': deviceName,
      'scope': _scope.name,
      'currentTrackId': _currentTrack?.id,
      'isPlaying': _isPlaying,
      'positionMs': effectivePosition.inMilliseconds,
      'updatedAtMs': now.millisecondsSinceEpoch,
      'connectedPeers': connectedPeerLabels,
      'tracks': [
        for (final music in _sharedTracks) await _trackJson(music),
      ],
    };

    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(manifest));
  }

  Future<void> _writeFile(HttpRequest request, String encodedId) async {
    final token = Uri.decodeComponent(encodedId);
    final music = _musicForTransferToken(token);
    if (music == null) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Track not shared');
      return;
    }

    final file = File(music.filePath);
    if (!await file.exists()) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Track file missing');
      return;
    }

    final length = await file.length();
    request.response.headers
      ..contentType = ContentType.binary
      ..set(HttpHeaders.contentLengthHeader, length)
      ..set(
        'content-disposition',
        'attachment; filename="${_asciiDownloadFileName(music.filePath)}"',
      );
    await request.response.addStream(file.openRead());
  }

  Future<void> _writeCover(HttpRequest request, String encodedId) async {
    final token = Uri.decodeComponent(encodedId);
    final music = _musicForTransferToken(token);
    if (music == null || music.coverPath.trim().isEmpty) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Cover art not shared');
      return;
    }

    final file = File(music.coverPath);
    if (!await file.exists()) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Cover art missing');
      return;
    }

    final length = await file.length();
    request.response.headers
      ..contentType = ContentType.parse(_contentTypeForPath(music.coverPath))
      ..set(HttpHeaders.contentLengthHeader, length)
      ..set(
        'content-disposition',
        'inline; filename="${_asciiDownloadFileName(music.coverPath)}"',
      );
    await request.response.addStream(file.openRead());
  }

  Future<Map<String, dynamic>> _trackJson(Music music) async {
    final file = File(music.filePath);
    final fileName = p.basename(music.filePath);
    final token = _transferTokenForIndex(_sharedTracks.indexOf(music));
    return {
      'id': music.id,
      'title': music.title,
      'artist': music.artist,
      'album': music.album,
      'genre': music.genre,
      'year': music.year,
      'fileName': fileName,
      'sizeBytes': await file.length().catchError((_) => 0),
      'durationMs': music.duration?.inMilliseconds,
      'downloadPath': '$_filePrefix$token',
      if (await _canShareCover(music.coverPath))
        'coverDownloadPath': '$_coverPrefix$token',
      if ((_sharedLyrics[music.id] ?? '').trim().isNotEmpty)
        'lyricsText': _sharedLyrics[music.id],
    };
  }

  void _rememberPeer(HttpRequest request) {
    final remoteAddress = request.connectionInfo?.remoteAddress.address;
    if (remoteAddress == null ||
        remoteAddress == '127.0.0.1' ||
        remoteAddress == '::1') {
      return;
    }
    final guestName = request.uri.queryParameters['guestName']?.trim();
    final label = guestName == null || guestName.isEmpty
        ? remoteAddress
        : '$guestName ($remoteAddress)';
    _connectedPeerSeenAt[remoteAddress] = DateTime.now();
    _connectedPeerNames[remoteAddress] = label;
    _removeExpiredPeers();
  }

  void _removeExpiredPeers() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 18));
    final expired = _connectedPeerSeenAt.entries
        .where((entry) => entry.value.isBefore(cutoff))
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final key in expired) {
      _connectedPeerSeenAt.remove(key);
      _connectedPeerNames.remove(key);
    }
  }

  Music? _musicForTransferToken(String token) {
    if (!token.startsWith('t')) return null;
    final index = int.tryParse(token.substring(1), radix: 36);
    if (index == null || index < 0 || index >= _sharedTracks.length) {
      return null;
    }
    return _sharedTracks[index];
  }

  String _transferTokenForIndex(int index) {
    final safeIndex = index < 0 ? 0 : index;
    return 't${safeIndex.toRadixString(36)}';
  }

  List<Music> _tracksForScope(
    List<Music> library,
    Music? currentTrack,
    List<Music>? selectedTracks,
    ShareScope scope,
  ) {
    if (scope == ShareScope.fullLibrary) return library;
    if (scope == ShareScope.selectedSongs) return selectedTracks ?? const [];
    if (currentTrack == null) return [];
    return [currentTrack];
  }

  List<Music> _shareableTracksForScope({
    required List<Music> library,
    required Music? currentTrack,
    required List<Music>? selectedTracks,
    required ShareScope scope,
  }) {
    final seen = <String>{};
    return _tracksForScope(library, currentTrack, selectedTracks, scope)
        .where((music) => _canShareFile(music.filePath))
        .where((music) => seen.add(music.id))
        .toList();
  }

  bool _canShareFile(String path) {
    if (path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith('blob:')) {
      return false;
    }
    return File(path).existsSync();
  }

  Future<bool> _canShareCover(String path) async {
    if (path.trim().isEmpty || !_canShareFile(path)) return false;
    return File(path).exists();
  }

  String _contentTypeForPath(String path) {
    final extension = p.extension(path).toLowerCase();
    return switch (extension) {
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      '.gif' => 'image/gif',
      _ => 'application/octet-stream',
    };
  }

  Uri _normalizeBaseAddress(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) throw const FormatException('Enter a device URL');
    final withScheme =
        trimmed.startsWith('http://') || trimmed.startsWith('https://')
            ? trimmed
            : 'http://$trimmed';
    final uri = Uri.parse(withScheme);
    if (uri.host.isEmpty) throw const FormatException('Invalid device URL');
    return uri;
  }

  Future<List<String>> _localUrls(int port) async {
    final addresses = <String>[];
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        addresses.add('http://${address.address}:$port');
      }
    }
    if (addresses.isEmpty) addresses.add('http://127.0.0.1:$port');
    return addresses;
  }

  Future<List<InternetAddress>> _subnetBroadcastAddresses() async {
    final broadcasts = <InternetAddress>[];
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final parts = address.address.split('.');
        if (parts.length != 4) continue;
        broadcasts.add(
          InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'),
        );
      }
    }
    return broadcasts;
  }

  String? _bestUrlForAddress(List<String> urls, String remoteAddress) {
    if (urls.isEmpty) return null;
    final remoteParts = remoteAddress.split('.');
    if (remoteParts.length == 4) {
      final remotePrefix =
          '${remoteParts[0]}.${remoteParts[1]}.${remoteParts[2]}.';
      for (final url in urls) {
        final uri = Uri.tryParse(url);
        if (uri != null && uri.host.startsWith(remotePrefix)) return url;
      }
    }
    return urls.first;
  }

  double _transferSpeed(int bytes, DateTime startedAt) {
    final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
    if (elapsedMs <= 0) return 0;
    return bytes / (elapsedMs / 1000);
  }

  Future<Directory> _syncDirectory() async {
    final dir = Directory(await _syncDirectoryPath());
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String> _syncDirectoryPath() async {
    final documents = await getPlayerVfDocumentsDirectory();
    return p.join(documents.path, 'PlayerVF Sync');
  }

  Future<String?> _existingSyncedPath(
    Directory dir,
    RemoteShareTrack track,
  ) async {
    final safeName = _safeFileName(track.fileName);
    final direct = File(p.join(dir.path, safeName));
    if (await _matchesExpectedFile(direct, track.sizeBytes)) {
      return direct.path;
    }

    final matchedByName = await _findSyncedPathBySimilarName(dir, track);
    if (matchedByName != null) return matchedByName;

    final extension = p.extension(safeName);
    final stem = p.basenameWithoutExtension(safeName);
    for (var counter = 1; counter < 1000; counter++) {
      final candidate = File(p.join(dir.path, '$stem ($counter)$extension'));
      if (!await candidate.exists()) {
        break;
      }
      if (await _matchesExpectedFile(candidate, track.sizeBytes)) {
        return candidate.path;
      }
    }
    return null;
  }

  Future<String?> _findSyncedPathBySimilarName(
    Directory dir,
    RemoteShareTrack track,
  ) async {
    if (!await dir.exists()) return null;

    final expectedFileName = _normalizedSongName(track.fileName);
    final expectedTitle = _normalizedSongName(track.title);
    if (expectedFileName.isEmpty && expectedTitle.isEmpty) return null;

    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      if (!_isAudioFilePath(entity.path)) continue;

      final candidateName =
          _normalizedSongName(p.basenameWithoutExtension(entity.path));
      if (candidateName.isEmpty) continue;

      final sameFileName = _songNamesMatch(candidateName, expectedFileName);
      final sameTitle = _songNamesMatch(candidateName, expectedTitle);
      if (!sameFileName && !sameTitle) continue;

      if (track.sizeBytes > 0) {
        final length = await entity.length();
        final closeSize =
            (length - track.sizeBytes).abs() <= (track.sizeBytes * 0.02);
        if (!closeSize && !sameTitle) continue;
      }

      return entity.path;
    }

    return null;
  }

  bool _isAudioFilePath(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.mp3':
      case '.m4a':
      case '.flac':
      case '.wav':
      case '.ogg':
      case '.aac':
      case '.wma':
        return true;
      default:
        return false;
    }
  }

  bool _songNamesMatch(String candidate, String expected) {
    if (candidate.isEmpty || expected.isEmpty) return false;
    if (candidate == expected) return true;

    final shorter = candidate.length < expected.length ? candidate : expected;
    final longer = candidate.length < expected.length ? expected : candidate;
    if (shorter.length < 8) return false;
    if (longer.contains(shorter) && shorter.length / longer.length >= 0.82) {
      return true;
    }

    final candidateTokens = candidate.split(' ').where((t) => t.length > 1);
    final expectedTokens = expected.split(' ').where((t) => t.length > 1);
    final expectedSet = expectedTokens.toSet();
    if (expectedSet.isEmpty) return false;
    final shared = candidateTokens.where(expectedSet.contains).length;
    return shared >= 3 && shared / expectedSet.length >= 0.75;
  }

  String _normalizedSongName(String value) {
    var text = value.toLowerCase();
    final extension = p.extension(text);
    if (extension.isNotEmpty) {
      text = p.basenameWithoutExtension(text);
    }
    text = text
        .replaceAll(RegExp(r'\(\d+\)$'), '')
        .replaceAll(RegExp(r'''[_\-.,;:!?"'`~]+'''), ' ')
        .replaceAll(RegExp(r'[\[\]{}()]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return text;
  }

  Future<bool> _matchesExpectedFile(File file, int expectedBytes) async {
    if (!await file.exists()) return false;
    if (expectedBytes <= 0) return true;
    return await file.length() == expectedBytes;
  }

  Future<String> _uniqueTargetPath(Directory dir, String fileName) async {
    final safeName = _safeFileName(fileName);
    final extension = p.extension(safeName);
    final stem = p.basenameWithoutExtension(safeName);
    var candidate = p.join(dir.path, safeName);
    var counter = 1;
    while (await File(candidate).exists()) {
      candidate = p.join(dir.path, '$stem ($counter)$extension');
      counter++;
    }
    return candidate;
  }

  String _safeFileName(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? 'PlayerVF track' : cleaned;
  }

  String _asciiDownloadFileName(String path) {
    final extension =
        p.extension(path).replaceAll(RegExp(r'[^A-Za-z0-9.]'), '');
    final safeExtension = extension.isEmpty ? '.bin' : extension;
    return 'player-vf-track$safeExtension';
  }

  Future<String> _deviceName() async {
    try {
      return Platform.localHostname.isEmpty
          ? 'PlayerVF device'
          : Platform.localHostname;
    } catch (_) {
      return 'PlayerVF device';
    }
  }
}

ShareScope _shareScopeFromName(String? name) {
  if (name == ShareScope.fullLibrary.name) return ShareScope.fullLibrary;
  if (name == ShareScope.selectedSongs.name) return ShareScope.selectedSongs;
  return ShareScope.currentSong;
}
