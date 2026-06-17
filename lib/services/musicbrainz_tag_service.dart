import 'dart:convert';
import 'dart:io';

import '../models/music_model.dart';

class MusicBrainzTagService {
  static const String _host = 'musicbrainz.org';
  static const String _userAgent =
      'PlayerVf/1.0 (https://github.com/player-vf/player-vf)';

  Future<MusicBrainzTag?> findBestTagForMusic(Music music) async {
    return findBestTag(
      title: music.title,
      artist: music.artist,
      album: music.album,
      duration: music.duration,
    );
  }

  Future<MusicBrainzTag?> findBestTag({
    required String title,
    required String artist,
    String? album,
    Duration? duration,
  }) async {
    final results = await searchTags(
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      limit: 8,
    );
    return results.isEmpty ? null : results.first;
  }

  Future<List<MusicBrainzTag>> searchTags({
    required String title,
    required String artist,
    String? album,
    Duration? duration,
    int limit = 8,
  }) async {
    final cleanedTitle = _cleanSearchText(title);
    final cleanedArtist = _cleanSearchText(artist);
    final cleanedAlbum = _cleanSearchText(album ?? '');
    if (cleanedTitle.isEmpty) return const [];

    final queryLimit = limit.clamp(1, 25);
    final queries = _recordingQueries(
      title: cleanedTitle,
      artist: cleanedArtist,
      album: cleanedAlbum,
    );

    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      final byId = <String, MusicBrainzTag>{};
      for (final query in queries) {
        final fetched = await _fetchRecordingSearch(
          client,
          query: query,
          limit: queryLimit,
        );
        for (final tag in fetched) {
          if (tag.id.isEmpty) continue;
          byId.putIfAbsent(tag.id, () => tag);
        }
        if (byId.length >= queryLimit) break;
      }

      final tags = byId.values.toList();

      tags.sort((a, b) {
        final score = _scoreTag(
              b,
              title: cleanedTitle,
              artist: cleanedArtist,
              album: cleanedAlbum,
              duration: duration,
            ) -
            _scoreTag(
              a,
              title: cleanedTitle,
              artist: cleanedArtist,
              album: cleanedAlbum,
              duration: duration,
            );
        if (score != 0) return score;
        return b.musicBrainzScore.compareTo(a.musicBrainzScore);
      });

      return tags;
    } catch (_) {
      return const [];
    } finally {
      client?.close(force: true);
    }
  }

  Future<List<MusicBrainzTag>> _fetchRecordingSearch(
    HttpClient client, {
    required String query,
    required int limit,
  }) async {
    final uri = Uri.https(_host, '/ws/2/recording', {
      'query': query,
      'fmt': 'json',
      'limit': limit.toString(),
    });

    final request = await client.getUrl(uri).timeout(
          const Duration(seconds: 8),
        );
    request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(
          const Duration(seconds: 10),
        );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const [];
    }

    final raw = await utf8.decoder.bind(response).join();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const [];

    final recordings = decoded['recordings'];
    if (recordings is! List) return const [];

    return recordings
        .whereType<Map>()
        .map((item) => MusicBrainzTag.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .where((tag) => tag.title.trim().isNotEmpty)
        .toList();
  }

  List<String> _recordingQueries({
    required String title,
    required String artist,
    required String album,
  }) {
    final usableArtist = artist.isNotEmpty && artist != 'Unknown Artist';
    final usableAlbum = album.isNotEmpty && album != 'Unknown Album';
    return [
      [
        'recording:"${_lucenePhrase(title)}"',
        if (usableArtist) 'artist:"${_lucenePhrase(artist)}"',
        if (usableAlbum) 'release:"${_lucenePhrase(album)}"',
      ].join(' AND '),
      [
        'recording:"${_lucenePhrase(title)}"',
        if (usableArtist) 'artist:"${_lucenePhrase(artist)}"',
      ].join(' AND '),
      [
        'recording:${_luceneTerm(title)}',
        if (usableArtist) 'artist:${_luceneTerm(artist)}',
      ].join(' AND '),
      [
        title,
        if (usableArtist) artist,
        if (usableAlbum) album,
      ].join(' '),
    ].where((query) => query.trim().isNotEmpty).toSet().toList();
  }

  int _scoreTag(
    MusicBrainzTag tag, {
    required String title,
    required String artist,
    required String album,
    required Duration? duration,
  }) {
    var score = tag.musicBrainzScore;
    if (_sameToken(tag.title, title)) score += 100;
    if (artist.isNotEmpty && _sameToken(tag.artist, artist)) score += 70;
    if (album.isNotEmpty && _sameToken(tag.album, album)) score += 20;
    if (duration != null && tag.duration != null) {
      final delta = (duration.inSeconds - tag.duration!.inSeconds).abs();
      if (delta <= 2) {
        score += 20;
      } else if (delta <= 8) {
        score += 10;
      }
    }
    return score;
  }

  bool _sameToken(String left, String right) {
    return _normalizeToken(left) == _normalizeToken(right);
  }

  String _normalizeToken(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }

  String _cleanSearchText(String value) {
    return value
        .replaceAll(
          RegExp(r'\.(mp3|m4a|flac|wav|ogg|aac|wma)$', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _lucenePhrase(String value) {
    return value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  }

  String _luceneTerm(String value) {
    return value
        .split(RegExp(r'\s+'))
        .map(_lucenePhrase)
        .where((part) => part.isNotEmpty)
        .join(' ');
  }
}

class MusicBrainzTag {
  final String id;
  final String title;
  final String artist;
  final String album;
  final Duration? duration;
  final int musicBrainzScore;

  const MusicBrainzTag({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.musicBrainzScore,
  });

  factory MusicBrainzTag.fromJson(Map<String, dynamic> json) {
    final artistCredit = json['artist-credit'];
    final artist = artistCredit is List
        ? artistCredit
            .whereType<Map>()
            .map((credit) {
              final name = credit['name']?.toString().trim() ?? '';
              if (name.isEmpty) return '';
              final joinPhrase = credit['joinphrase']?.toString() ?? '';
              return '$name$joinPhrase';
            })
            .join()
            .trim()
        : '';
    final releases = json['releases'];
    Map? release;
    if (releases is List) {
      for (final item in releases) {
        if (item is Map) {
          release = item;
          break;
        }
      }
    }
    final length = (json['length'] as num?)?.toInt();

    return MusicBrainzTag(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString().trim() ?? '',
      artist: artist.isEmpty ? 'Unknown Artist' : artist,
      album: release?['title']?.toString().trim().isNotEmpty == true
          ? release!['title'].toString().trim()
          : 'Unknown Album',
      duration:
          length == null || length <= 0 ? null : Duration(milliseconds: length),
      musicBrainzScore: int.tryParse(json['score']?.toString() ?? '') ?? 0,
    );
  }
}
