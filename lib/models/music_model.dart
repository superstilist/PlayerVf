import 'dart:core';

class Music {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String filePath;
  final String coverPath;
  final Map<String, String> httpHeaders;
  final String genre;
  final String year;
  Duration? duration;
  bool isFavorite;
  int playCount;
  DateTime? lastPlayed;
  String? spotifyUrl;
  final DateTime dateAdded;
  final Set<String> userEditedFields;
  late final String searchText = [
    title,
    artist,
    album,
    genre,
    year,
  ].join('\u0000').toLowerCase();

  Music({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.filePath,
    required this.coverPath,
    this.httpHeaders = const {},
    this.genre = 'Unknown',
    this.year = '',
    this.duration,
    this.isFavorite = false,
    this.playCount = 0,
    this.lastPlayed,
    this.spotifyUrl,
    DateTime? dateAdded,
    Set<String>? userEditedFields,
  })  : dateAdded = dateAdded ?? DateTime.now(),
        userEditedFields = userEditedFields ?? {};

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'filePath': filePath,
        'coverPath': coverPath,
        'httpHeaders': httpHeaders,
        'genre': genre,
        'year': year,
        'durationMs': duration?.inMilliseconds,
        'isFavorite': isFavorite,
        'playCount': playCount,
        'lastPlayed': lastPlayed?.millisecondsSinceEpoch,
        'spotifyUrl': spotifyUrl,
        'dateAdded': dateAdded.millisecondsSinceEpoch,
        'userEditedFields': userEditedFields.toList(),
      };

  factory Music.fromJson(Map<String, dynamic> json) {
    final durationMs = (json['durationMs'] as num?)?.toInt();
    final rawEdited = json['userEditedFields'];
    final editedFields = rawEdited is List
        ? rawEdited.map((e) => e.toString()).toSet()
        : <String>{};
    return Music(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Unknown title',
      artist: json['artist']?.toString() ?? 'Unknown Artist',
      album: json['album']?.toString() ?? 'Unknown Album',
      filePath: json['filePath']?.toString() ?? '',
      coverPath: json['coverPath']?.toString() ?? '',
      httpHeaders: _stringMapFromJson(json['httpHeaders']),
      genre: json['genre']?.toString() ?? 'Unknown',
      year: json['year']?.toString() ?? '',
      duration: durationMs == null || durationMs <= 0
          ? null
          : Duration(milliseconds: durationMs),
      isFavorite: json['isFavorite'] == true,
      playCount: (json['playCount'] as num?)?.toInt() ?? 0,
      lastPlayed: (json['lastPlayed'] as num?) == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              (json['lastPlayed'] as num).toInt()),
      spotifyUrl: json['spotifyUrl']?.toString(),
      dateAdded: (json['dateAdded'] as num?) == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              (json['dateAdded'] as num).toInt()),
      userEditedFields: editedFields,
    );
  }

  factory Music.fromBase(Music base, int playCount, DateTime? lastPlayed) {
    return Music(
      id: base.id,
      title: base.title,
      artist: base.artist,
      album: base.album,
      filePath: base.filePath,
      coverPath: base.coverPath,
      httpHeaders: base.httpHeaders,
      genre: base.genre,
      year: base.year,
      duration: base.duration,
      isFavorite: base.isFavorite,
      playCount: playCount,
      lastPlayed: lastPlayed,
      spotifyUrl: base.spotifyUrl,
      dateAdded: base.dateAdded,
      userEditedFields: base.userEditedFields,
    );
  }
}

Map<String, String> _stringMapFromJson(Object? value) {
  if (value is! Map) return const {};
  final result = <String, String>{};
  for (final entry in value.entries) {
    final key = entry.key?.toString().trim() ?? '';
    final itemValue = entry.value?.toString() ?? '';
    if (key.isNotEmpty && itemValue.isNotEmpty) {
      result[key] = itemValue;
    }
  }
  return result;
}
