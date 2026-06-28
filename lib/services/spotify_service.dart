import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/music_model.dart';

class TrackResult {
  final String title;
  final String artist;
  final String? spotifyUrl;

  TrackResult({
    required this.title,
    required this.artist,
    this.spotifyUrl,
  });
}

class SpotifyTrack {
  final String id;
  final String name;
  final String artist;
  final String album;
  final String uri;
  final String url;
  final String? previewUrl;
  final String? imageUrl;
  final int durationMs;

  const SpotifyTrack({
    required this.id,
    required this.name,
    required this.artist,
    required this.album,
    required this.uri,
    required this.url,
    this.previewUrl,
    this.imageUrl,
    this.durationMs = 0,
  });
}

class SpotifyService extends ChangeNotifier {
  static const _mbBaseUrl = 'https://musicbrainz.org/ws/2';
  static const _userAgent = 'PlayerVF/1.0 (music-player)';
  static const _cacheDuration = Duration(hours: 12);

  final Map<String, _CacheEntry<String>> _cache = {};
  DateTime _lastMbRequest = DateTime.fromMillisecondsSinceEpoch(0);

  String? _lastError;
  String? get lastError => _lastError;

  Future<void> init() async {}
  bool get isAuthenticated => false;
  bool get isAuthenticating => false;
  List<String> get pinnedTrackIds => [];
  Future<void> authenticate() async {}
  void logout() {}

  String _cleanText(String input) {
    return input
        .replaceAll(RegExp(r'\.(mp3|wav|flac|m4a|aac)$', caseSensitive: false), '')
        .replaceAll(RegExp(r'[_\-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _buildSearchUrl(String query) {
    return 'https://open.spotify.com/search/${Uri.encodeComponent(query)}/tracks';
  }

  Future<void> _throttleMusicBrainz() async {
    final now = DateTime.now();
    final elapsed = now.difference(_lastMbRequest);
    if (elapsed < const Duration(seconds: 1)) {
      await Future.delayed(const Duration(seconds: 1) - elapsed);
    }
    _lastMbRequest = DateTime.now();
  }

  Future<String?> _lookupRecordingSpotifyUrl(String mbid) async {
    await _throttleMusicBrainz();
    final url = Uri.parse('$_mbBaseUrl/recording/$mbid?fmt=json&inc=url-rels');
    final response = await http.get(url, headers: {
      'User-Agent': _userAgent,
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) return null;

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final relations = json['relations'] as List<dynamic>? ?? [];

    for (final rel in relations) {
      final urlObj = rel['url'] as Map<String, dynamic>?;
      final resource = urlObj?['resource']?.toString() ?? '';
      if (resource.contains('open.spotify.com/track/')) {
        return resource.split('?').first;
      }
    }
    return null;
  }

  Future<String?> _searchMusicBrainz(String title, String artist) async {
    final cleanTitle = _cleanText(title);
    final cleanArtist = _cleanText(artist);

    // Strategy 1: exact match with quotes
    final results = await _mbSearch(cleanTitle, cleanArtist, useQuotes: true);
    if (results != null) return results;

    // Strategy 2: without quotes (fuzzy)
    final results2 = await _mbSearch(cleanTitle, cleanArtist, useQuotes: false);
    if (results2 != null) return results2;

    // Strategy 3: title only
    if (cleanArtist.isNotEmpty) {
      final results3 = await _mbSearch(cleanTitle, '', useQuotes: true);
      if (results3 != null) return results3;
    }

    return null;
  }

  Future<String?> _mbSearch(String title, String artist, {required bool useQuotes}) async {
    final queryParts = <String>[];
    if (title.isNotEmpty) {
      queryParts.add(useQuotes ? 'recording:"$title"' : 'recording:$title');
    }
    if (artist.isNotEmpty) {
      // Split by comma and use first artist only for better matching
      final firstArtist = artist.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).first;
      queryParts.add(useQuotes ? 'artist:"$firstArtist"' : 'artist:$firstArtist');
    }
    if (queryParts.isEmpty) return null;

    await _throttleMusicBrainz();
    final query = Uri.encodeComponent(queryParts.join(' AND '));
    final url = Uri.parse('$_mbBaseUrl/recording/?query=$query&fmt=json&limit=5');

    final response = await http.get(url, headers: {
      'User-Agent': _userAgent,
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) return null;

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final recordings = json['recordings'] as List<dynamic>?;
    if (recordings == null || recordings.isEmpty) return null;

    // Try each recording, lookup url-rels
    for (final recording in recordings.take(3)) {
      final mbid = recording['id']?.toString() ?? '';
      if (mbid.isEmpty) continue;

      final spotifyUrl = await _lookupRecordingSpotifyUrl(mbid);
      if (spotifyUrl != null) return spotifyUrl;
    }
    return null;
  }

  Future<String?> _searchMusicBrainzForSpotify(String title, String artist) async {
    final cacheKey = 'mb:${artist.toLowerCase()}:${title.toLowerCase()}';
    final cached = _cache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.data.isEmpty ? null : cached.data;
    }

    try {
      final spotifyUrl = await _searchMusicBrainz(title, artist);
      _cache[cacheKey] = _CacheEntry(spotifyUrl ?? '');
      return spotifyUrl;
    } catch (e) {
      debugPrint('MusicBrainz Spotify search error: $e');
      return null;
    }
  }

  Future<SpotifyTrack> resolveSpotifyNoToken(String title, String artist) async {
    final cleanTitle = _cleanText(title);
    final cleanArtist = _cleanText(artist);

    debugPrint('--- Spotify Resolver (MusicBrainz) ---');
    debugPrint('Title: $title');
    debugPrint('Artist: $artist');

    final spotifyUrl = await _searchMusicBrainzForSpotify(cleanTitle, cleanArtist);
    if (spotifyUrl != null) {
      debugPrint('Found via MusicBrainz: $spotifyUrl');
      final idMatch = RegExp(r'open\.spotify\.com/track/([a-zA-Z0-9]{22})')
          .firstMatch(spotifyUrl);
      return SpotifyTrack(
        id: idMatch?.group(1) ?? '',
        name: cleanTitle,
        artist: cleanArtist.isNotEmpty ? cleanArtist : 'Unknown Artist',
        album: 'Unknown Album',
        uri: idMatch != null ? 'spotify:track:${idMatch.group(1)}' : '',
        url: spotifyUrl,
      );
    }

    debugPrint('Not found on MusicBrainz, using search fallback');
    final fallbackUrl = _buildSearchUrl(
      cleanArtist.isNotEmpty ? '$cleanTitle $cleanArtist' : cleanTitle,
    );
    return SpotifyTrack(
      id: '',
      name: cleanTitle,
      artist: cleanArtist.isNotEmpty ? cleanArtist : 'Unknown Artist',
      album: 'Unknown Album',
      uri: '',
      url: fallbackUrl,
    );
  }

  Future<List<SpotifyTrack>> searchTrack(Music music) async {
    final resolved = await resolveSpotifyNoToken(music.title, music.artist);
    return [resolved];
  }

  Future<SpotifyTrack?> searchTrackByQuery(String query) async {
    final cleanQuery = _cleanText(query);
    return resolveSpotifyNoToken(cleanQuery, '');
  }

  Future<String?> getTrackSpotifyUrl(Music music) async {
    final tracks = await searchTrack(music);
    if (tracks.isEmpty || tracks.first.id.isEmpty) {
      return null;
    }
    return tracks.first.url;
  }

  String getSearchFallbackUrl(Music music) {
    final query = _cleanText(music.artist.isNotEmpty
        ? '${music.title} ${music.artist}'
        : music.title);
    return _buildSearchUrl(query);
  }

  Future<TrackResult?> resolveTrack(String title, String artist) async {
    final track = await resolveSpotifyNoToken(title, artist);
    return TrackResult(
      title: track.name,
      artist: track.artist,
      spotifyUrl: track.url,
    );
  }

  void clearCache() {
    _cache.clear();
  }
}

class _CacheEntry<T> {
  final T data;
  final DateTime timestamp;
  _CacheEntry(this.data) : timestamp = DateTime.now();
  bool get isExpired =>
      DateTime.now().difference(timestamp) > SpotifyService._cacheDuration;
}
