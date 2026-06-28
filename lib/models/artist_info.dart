class ArtistInfo {
  final String mbid;
  final String name;
  final String sortName;
  final String disambiguation;
  final String country;
  final String? beginArea;
  final String? endArea;
  final int? beginYear;
  final int? endYear;
  final String? type;
  final String? score;
  final List<String> tags;
  final List<String> genres;
  final String? biography;
  final String? imageUrl;
  final String? profileImageUrl;
  final int? albumCount;
  final int? rating;
  final String? wikidataId;
  final String? lastFmUrl;
  final String? musicBrainzUrl;
  final List<ArtistRelation> relations;
  final List<ArtistRelation> relatedArtists;
  final bool isTopArtist;

  const ArtistInfo({
    this.mbid = '',
    this.name = '',
    this.sortName = '',
    this.disambiguation = '',
    this.country = '',
    this.beginArea,
    this.endArea,
    this.beginYear,
    this.endYear,
    this.type,
    this.score,
    this.tags = const [],
    this.genres = const [],
    this.biography,
    this.imageUrl,
    this.profileImageUrl,
    this.albumCount,
    this.rating,
    this.wikidataId,
    this.lastFmUrl,
    this.musicBrainzUrl,
    this.relations = const [],
    this.relatedArtists = const [],
    this.isTopArtist = false,
  });

  String get activeYears {
    if (beginYear == null) return '';
    if (endYear == null) return '$beginYear – present';
    return '$beginYear – $endYear';
  }

  String get displayCountry {
    if (country.isEmpty) return '';
    return country;
  }

  String? get dominantColorHex {
    if (profileImageUrl == null || profileImageUrl!.isEmpty) return null;
    return 'dominant_color_placeholder';
  }

  ArtistInfo copyWith({
    String? mbid,
    String? name,
    String? sortName,
    String? disambiguation,
    String? country,
    String? beginArea,
    String? endArea,
    int? beginYear,
    int? endYear,
    String? type,
    String? score,
    List<String>? tags,
    List<String>? genres,
    String? biography,
    String? imageUrl,
    String? profileImageUrl,
    int? albumCount,
    int? rating,
    String? wikidataId,
    String? lastFmUrl,
    String? musicBrainzUrl,
    List<ArtistRelation>? relations,
    List<ArtistRelation>? relatedArtists,
    bool? isTopArtist,
  }) {
    return ArtistInfo(
      mbid: mbid ?? this.mbid,
      name: name ?? this.name,
      sortName: sortName ?? this.sortName,
      disambiguation: disambiguation ?? this.disambiguation,
      country: country ?? this.country,
      beginArea: beginArea ?? this.beginArea,
      endArea: endArea ?? this.endArea,
      beginYear: beginYear ?? this.beginYear,
      endYear: endYear ?? this.endYear,
      type: type ?? this.type,
      score: score ?? this.score,
      tags: tags ?? this.tags,
      genres: genres ?? this.genres,
      biography: biography ?? this.biography,
      imageUrl: imageUrl ?? this.imageUrl,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      albumCount: albumCount ?? this.albumCount,
      rating: rating ?? this.rating,
      wikidataId: wikidataId ?? this.wikidataId,
      lastFmUrl: lastFmUrl ?? this.lastFmUrl,
      musicBrainzUrl: musicBrainzUrl ?? this.musicBrainzUrl,
      relations: relations ?? this.relations,
      relatedArtists: relatedArtists ?? this.relatedArtists,
      isTopArtist: isTopArtist ?? this.isTopArtist,
    );
  }

  factory ArtistInfo.empty() => const ArtistInfo();

  bool get isEmpty => mbid.isEmpty && name.isEmpty;
  bool get isNotEmpty => !isEmpty;

  bool get hasProfileImage => profileImageUrl != null && profileImageUrl!.isNotEmpty;
}

class ArtistRelation {
  final String type;
  final String target;
  final String? targetType;
  final String? direction;
  final String? beginYear;
  final String? endYear;

  const ArtistRelation({
    this.type = '',
    this.target = '',
    this.targetType,
    this.direction,
    this.beginYear,
    this.endYear,
  });
}
