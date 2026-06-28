import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/artist_info.dart';

class ArtistImageService {
  ArtistImageService._();
  static final ArtistImageService instance = ArtistImageService._();

  static const _wikidataUrl =
      'https://www.wikidata.org/wiki/Special:EntityData';
  static const _commonsBaseUrl =
      'https://commons.wikimedia.org/wiki/Special:FilePath';

  final Map<String, _CacheEntry<String>> _imageCache = {};
  static const _cacheDuration = Duration(hours: 6);

  Future<String?> getArtistImageUrlFromMusicBrainz({
    required Map<String, dynamic> musicBrainzResponse,
  }) async {
    try {
      final wikidataId = _extractWikidataId(musicBrainzResponse);
      if (wikidataId == null) {
        print('[ArtistImageService] No Wikidata link found in relations');
        return null;
      }
      print('[ArtistImageService] Found Wikidata ID: $wikidataId');
      return fetchWikidataImageUrl(wikidataId);
    } catch (e) {
      print('[ArtistImageService] Error: $e');
      return null;
    }
  }

  Future<String?> fetchArtistImageUrl(
    String artistName, {
    String? mbid,
    Map<String, dynamic>? mbJson,
  }) async {
    try {
      if (mbJson != null) {
        return getArtistImageUrlFromMusicBrainz(
            musicBrainzResponse: mbJson);
      }
      if (mbid != null) {
        return _fetchArtistFromMbId(mbid);
      }
      return _fetchArtistFromName(artistName);
    } catch (e) {
      print('[ArtistImageService] Error: $e');
      return null;
    }
  }

  Future<ArtistInfo> enrichArtistWithProfileImage(ArtistInfo artist) async {
    try {
      if (artist.wikidataId != null && artist.wikidataId!.isNotEmpty) {
        print('[ArtistImageService] Enriching "${artist.name}" with profile image');
        final url = await fetchWikidataImageUrl(artist.wikidataId!);
        if (url != null) {
          print('[ArtistImageService] Found profile image: $url');
          return artist.copyWith(profileImageUrl: url);
        }
      }
      print('[ArtistImageService] No profile image for "${artist.name}"');
      return artist;
    } catch (e) {
      print('[ArtistImageService] Error enriching: $e');
      return artist;
    }
  }

  String? _extractWikidataId(Map<String, dynamic> mbJson) {
    final relations = mbJson['relations'] as List<dynamic>? ?? [];
    for (final rel in relations) {
      final urlInfo = rel['url'] as Map<String, dynamic>?;
      if (urlInfo == null) continue;
      final resource = urlInfo['resource']?.toString() ?? '';
      if (resource.contains('wikidata.org')) {
        final match = RegExp(r'/(Q\d+)').firstMatch(resource);
        if (match != null) return match.group(1);
      }
    }
    return null;
  }

  Future<String?> fetchWikidataImageUrl(String wikidataId) async {
    if (wikidataId.isEmpty) return null;

    try {
      final key = 'wikidata:$wikidataId';
      final cached = _imageCache[key];
      if (cached != null && !cached.isExpired) {
        print('[ArtistImageService] Cached image for $wikidataId');
        return cached.data;
      }

      print('[ArtistImageService] Fetching Wikidata: $wikidataId');
      final response = await http
          .get(Uri.parse('$_wikidataUrl/$wikidataId.json'))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        print('[ArtistImageService] Wikidata HTTP ${response.statusCode}');
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final entities = json['entities'] as Map<String, dynamic>?;
      if (entities == null || entities.isEmpty) return null;

      final entity = entities[wikidataId] as Map<String, dynamic>?;
      if (entity == null) return null;

      final claims = entity['claims'] as Map<String, dynamic>?;
      if (claims == null) return null;

      final imageClaims = claims['P18'] as List<dynamic>?;
      if (imageClaims == null || imageClaims.isEmpty) {
        print('[ArtistImageService] No P18 image for $wikidataId');
        return null;
      }

      final mainSnak = imageClaims.first['mainsnak'] as Map<String, dynamic>?;
      if (mainSnak == null) return null;

      final datavalue = mainSnak['datavalue'] as Map<String, dynamic>?;
      if (datavalue == null) return null;

      final imageName = datavalue['value']?.toString() ?? '';
      if (imageName.isEmpty) return null;

      final encoded = Uri.encodeComponent(imageName.replaceAll(' ', '_'));
      final imageUrl = '$_commonsBaseUrl/$encoded';

      _imageCache[key] = _CacheEntry(imageUrl);
      print('[ArtistImageService] Image URL: $imageUrl');
      return imageUrl;
    } catch (e) {
      print('[ArtistImageService] Error fetching Wikidata: $e');
      return null;
    }
  }

  Future<String?> _fetchArtistFromMbId(String mbid) async {
    try {
      final response = await http
          .get(Uri.parse(
              'https://musicbrainz.org/ws/2/artist/$mbid?fmt=json&inc=url-rels+tags+genres+areas+aliases'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return getArtistImageUrlFromMusicBrainz(musicBrainzResponse: json);
    } catch (e) {
      print('[ArtistImageService] Error by MBID: $e');
      return null;
    }
  }

  Future<String?> _fetchArtistFromName(String artistName) async {
    try {
      final query = Uri.encodeComponent('artist:"$artistName"');
      final searchResponse = await http
          .get(Uri.parse(
              'https://musicbrainz.org/ws/2/artist/?query=$query&fmt=json&limit=1'))
          .timeout(const Duration(seconds: 10));

      if (searchResponse.statusCode != 200) return null;

      final searchJson =
          jsonDecode(searchResponse.body) as Map<String, dynamic>;
      final artists = searchJson['artists'] as List<dynamic>? ?? [];
      if (artists.isEmpty) return null;

      final artistJson = artists.first as Map<String, dynamic>;
      final mbid = artistJson['id']?.toString() ?? '';
      if (mbid.isEmpty) return null;

      return _fetchArtistFromMbId(mbid);
    } catch (e) {
      print('[ArtistImageService] Error by name: $e');
      return null;
    }
  }

  void clearCache() {
    print('[ArtistImageService] Clearing cache');
    _imageCache.clear();
  }
}

class _CacheEntry<T> {
  final T data;
  final DateTime timestamp;
  _CacheEntry(this.data) : timestamp = DateTime.now();
  bool get isExpired =>
      DateTime.now().difference(timestamp) >
      ArtistImageService._cacheDuration;
}
