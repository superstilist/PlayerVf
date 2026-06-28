import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/artist_info.dart';
import 'artist_image_service.dart';

class MusicBrainzService {
  MusicBrainzService._();
  static final MusicBrainzService instance = MusicBrainzService._();

  static const _baseUrl = 'https://musicbrainz.org/ws/2';
  static const _coverArtUrl = 'https://coverartarchive.org';
  static const _wikidataUrl = 'https://www.wikidata.org/wiki/Special:EntityData';
  static const _cacheDuration = Duration(hours: 6);

  final Map<String, _CacheEntry<ArtistInfo>> _artistCache = {};
  final Map<String, _CacheEntry<String>> _coverCache = {};
  final Map<String, _CacheEntry<String>> _wikidataImageCache = {};

  Future<ArtistInfo> lookupArtist(String mbid) async {
    final cached = _artistCache[mbid];
    if (cached != null && !cached.isExpired) return cached.data;

    try {
      final response = await http
          .get(
            Uri.parse(
                '$_baseUrl/artist/$mbid?fmt=json&inc=url-rels+tags+genres+areas+aliases'),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return ArtistInfo.empty();

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final artist = _parseArtist(json);
      _artistCache[mbid] = _CacheEntry(artist);
      return artist;
    } catch (_) {
      return ArtistInfo.empty();
    }
  }

  Future<ArtistInfo?> createArtistWithProfileImage(String mbid) async {
    try {
      final response = await http
          .get(
            Uri.parse(
                '$_baseUrl/artist/$mbid?fmt=json&inc=url-rels+tags+genres+areas+aliases'),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return _parseArtist(json);
    } catch (_) {
      return null;
    }
  }

  Future<String?> enrichArtistWithProfileImage(ArtistInfo artist) async {
    try {
      if (artist.wikidataId != null && artist.wikidataId!.isNotEmpty) {
        print('[MusicBrainzService] Enriching artist with profile image');
        final profileImageUrl =
            await ArtistImageService.instance.fetchWikidataImageUrl(
                artist.wikidataId!);

        if (profileImageUrl != null) {
          print('[MusicBrainzService] Found profile image: $profileImageUrl');
          return profileImageUrl;
        }
      }

      print('[MusicBrainzService] No profile image for ${artist.name}');
      return null;
    } catch (e) {
      print('[MusicBrainzService] Error enriching: $e');
      return null;
    }
  }

  Future<ArtistInfo> searchArtist(String name) async {
    final key = 'search:$name';
    final cached = _artistCache[key];
    if (cached != null && !cached.isExpired) return cached.data;

    try {
      final query = Uri.encodeComponent('artist:"$name"');
      final response = await http
          .get(
            Uri.parse('$_baseUrl/artist/?query=$query&fmt=json&limit=1'),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return ArtistInfo.empty();

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final artists = json['artists'] as List<dynamic>?;
      if (artists == null || artists.isEmpty) return ArtistInfo.empty();

      final artistJson = artists.first as Map<String, dynamic>;
      final mbid = artistJson['id']?.toString() ?? '';
      if (mbid.isEmpty) return ArtistInfo.empty();

      final artist = _parseArtist(artistJson);
      _artistCache[key] = _CacheEntry(artist);

      if (artist.mbid.isNotEmpty) {
        unawaited(_enrichArtist(artist));
      }

      return artist;
    } catch (_) {
      return ArtistInfo.empty();
    }
  }

  Future<void> _enrichArtist(ArtistInfo artist) async {
    if (artist.mbid.isEmpty) return;
    try {
      final enriched = await lookupArtist(artist.mbid);
      if (enriched.isNotEmpty && enriched.name == artist.name) {
        _artistCache[artist.mbid] = _CacheEntry(enriched);
      }
    } catch (_) {}
  }

  Future<String> fetchCoverArt(String mbid) async {
    if (mbid.isEmpty) return '';
    final cached = _coverCache[mbid];
    if (cached != null && !cached.isExpired) return cached.data;

    try {
      final response = await http
          .get(Uri.parse('$_coverArtUrl/artist/$mbid'))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        _coverCache[mbid] = _CacheEntry('');
        return '';
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final images = json['images'] as List<dynamic>?;
      if (images == null || images.isEmpty) {
        _coverCache[mbid] = _CacheEntry('');
        return '';
      }

      final front = images.firstWhere(
        (img) => img['front'] == true,
        orElse: () => images.first,
      );
      final url = front['image']?.toString() ?? '';
      _coverCache[mbid] = _CacheEntry(url);
      return url;
    } catch (_) {
      _coverCache[mbid] = _CacheEntry('');
      return '';
    }
  }

  Future<String> fetchWikidataImage(String wikidataId) async {
    if (wikidataId.isEmpty) return '';
    final cached = _wikidataImageCache[wikidataId];
    if (cached != null && !cached.isExpired) return cached.data;

    try {
      final response = await http
          .get(Uri.parse('$_wikidataUrl/$wikidataId.json'))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        _wikidataImageCache[wikidataId] = _CacheEntry('');
        return '';
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final entities = json['entities'] as Map<String, dynamic>?;
      if (entities == null || entities.isEmpty) {
        _wikidataImageCache[wikidataId] = _CacheEntry('');
        return '';
      }

      final entity = entities[wikidataId] as Map<String, dynamic>?;
      if (entity == null) {
        _wikidataImageCache[wikidataId] = _CacheEntry('');
        return '';
      }

      final claims = entity['claims'] as Map<String, dynamic>?;
      if (claims == null) {
        _wikidataImageCache[wikidataId] = _CacheEntry('');
        return '';
      }

      final imageClaims = claims['P18'] as List<dynamic>?;
      if (imageClaims == null || imageClaims.isEmpty) {
        _wikidataImageCache[wikidataId] = _CacheEntry('');
        return '';
      }

      final mainsnak = imageClaims.first['mainsnak'] as Map<String, dynamic>?;
      if (mainsnak == null) {
        _wikidataImageCache[wikidataId] = _CacheEntry('');
        return '';
      }

      final datavalue = mainsnak['datavalue'] as Map<String, dynamic>?;
      if (datavalue == null) {
        _wikidataImageCache[wikidataId] = _CacheEntry('');
        return '';
      }

      final imageName = datavalue['value']?.toString() ?? '';
      if (imageName.isEmpty) {
        _wikidataImageCache[wikidataId] = _CacheEntry('');
        return '';
      }

      final encodedName = Uri.encodeComponent(imageName.replaceAll(' ', '_'));
      final imageUrl = 'https://commons.wikimedia.org/wiki/Special:FilePath/$encodedName';

      _wikidataImageCache[wikidataId] = _CacheEntry(imageUrl);
      return imageUrl;
    } catch (_) {
      _wikidataImageCache[wikidataId] = _CacheEntry('');
      return '';
    }
  }

  Future<List<ArtistInfo>> fetchRelatedArtists(String mbid) async {
    if (mbid.isEmpty) return [];
    try {
      final response = await http
          .get(Uri.parse(
              '$_baseUrl/artist/$mbid?fmt=json&inc=artist-rels'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return [];

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final relations = json['relations'] as List<dynamic>? ?? [];

      final artists = <ArtistInfo>[];
      for (final rel in relations) {
        if (rel['target-type'] == 'artist') {
          final target = rel['artist'] as Map<String, dynamic>?;
          if (target != null) {
            artists.add(ArtistInfo(
              mbid: target['id']?.toString() ?? '',
              name: target['name']?.toString() ?? '',
              sortName: target['sort-name']?.toString() ?? '',
              country: target['country']?.toString() ?? '',
            ));
          }
        }
        if (artists.length >= 12) break;
      }
      return artists;
    } catch (_) {
      return [];
    }
  }

  ArtistInfo _parseArtist(Map<String, dynamic> json) {
    final lifeSpan = json['life-span'] as Map<String, dynamic>?;
    final begin = lifeSpan?['begin']?.toString();
    final end = lifeSpan?['end']?.toString();
    final ended = lifeSpan?['ended'] == true;

    int? beginYear;
    int? endYear;
    if (begin != null && begin.length >= 4) {
      beginYear = int.tryParse(begin.substring(0, 4));
    }
    if (end != null && end.length >= 4) {
      endYear = int.tryParse(end.substring(0, 4));
    }

    final tags = <String>[];
    final tagList = json['tags'] as List<dynamic>?;
    if (tagList != null) {
      for (final t in tagList) {
        final name = t['name']?.toString();
        if (name != null && name.isNotEmpty) tags.add(name);
      }
    }

    final genres = <String>[];
    final genreList = json['genres'] as List<dynamic>?;
    if (genreList != null) {
      for (final g in genreList) {
        final name = g['name']?.toString();
        if (name != null && name.isNotEmpty) genres.add(name);
      }
    }

    final relations = <ArtistRelation>[];
    final relList = json['relations'] as List<dynamic>?;
    if (relList != null) {
      for (final r in relList) {
        relations.add(ArtistRelation(
          type: r['type']?.toString() ?? '',
          target: r['url']?['resource']?.toString() ?? '',
          targetType: r['url']?['resource-type']?.toString(),
        ));
      }
    }

    String? imageUrl;
    final relations2 = json['relations'] as List<dynamic>?;
    if (relations2 != null) {
      for (final r in relations2) {
        if (r['type'] == 'image' || r['type'] == 'wiki cover') {
          final url = r['url']?['resource']?.toString();
          if (url != null && url.isNotEmpty) {
            imageUrl = url;
            break;
          }
        }
      }
    }

    final area = json['area'] as Map<String, dynamic>?;
    final country = area?['country']?.toString() ?? '';

    String? lastFmUrl;
    String? wikidataId;
    String? mbUrl;
    for (final r in relations) {
      if (r.type == 'last.fm' || r.target.contains('last.fm')) {
        lastFmUrl = r.target;
      }
      if (r.target.contains('wikidata.org')) {
        final parts = r.target.split('/');
        wikidataId = parts.isNotEmpty ? parts.last : null;
      }
      if (r.target.contains('musicbrainz.org')) {
        mbUrl = r.target;
      }
    }

    return ArtistInfo(
      mbid: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      sortName: json['sort-name']?.toString() ?? '',
      disambiguation: json['disambiguation']?.toString() ?? '',
      country: country,
      beginYear: beginYear,
      endYear: ended ? endYear : null,
      type: json['type']?.toString(),
      tags: tags,
      genres: genres,
      imageUrl: imageUrl,
      lastFmUrl: lastFmUrl,
      wikidataId: wikidataId,
      musicBrainzUrl:
          mbUrl ?? (json['id'] != null ? 'https://musicbrainz.org/artist/${json['id']}' : null),
      relations: relations,
    );
  }

  void clearCache() {
    _artistCache.clear();
    _coverCache.clear();
  }
}

class _CacheEntry<T> {
  final T data;
  final DateTime timestamp;
  _CacheEntry(this.data) : timestamp = DateTime.now();
  bool get isExpired =>
      DateTime.now().difference(timestamp) >
      MusicBrainzService._cacheDuration;
}
