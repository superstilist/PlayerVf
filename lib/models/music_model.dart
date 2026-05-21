import 'dart:core';

class Music {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String filePath;
  final String coverPath;
  final String genre;
  Duration? duration;
  bool isFavorite;
  int playCount;
  DateTime? lastPlayed;
  final DateTime dateAdded;

  Music({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.filePath,
    required this.coverPath,
    this.genre = 'Unknown',
    this.duration,
    this.isFavorite = false,
    this.playCount = 0,
    this.lastPlayed,
    DateTime? dateAdded,
  }) : dateAdded = dateAdded ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'filePath': filePath,
        'coverPath': coverPath,
        'genre': genre,
        'durationMs': duration?.inMilliseconds,
        'isFavorite': isFavorite,
        'playCount': playCount,
        'lastPlayed': lastPlayed?.millisecondsSinceEpoch,
        'dateAdded': dateAdded.millisecondsSinceEpoch,
      };

  factory Music.fromJson(Map<String, dynamic> json) {
    final durationMs = (json['durationMs'] as num?)?.toInt();
    return Music(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Unknown title',
      artist: json['artist']?.toString() ?? 'Unknown Artist',
      album: json['album']?.toString() ?? 'Unknown Album',
      filePath: json['filePath']?.toString() ?? '',
      coverPath: json['coverPath']?.toString() ?? '',
      genre: json['genre']?.toString() ?? 'Unknown',
      duration: durationMs == null || durationMs <= 0
          ? null
          : Duration(milliseconds: durationMs),
      isFavorite: json['isFavorite'] == true,
      playCount: (json['playCount'] as num?)?.toInt() ?? 0,
      lastPlayed: (json['lastPlayed'] as num?) == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              (json['lastPlayed'] as num).toInt()),
      dateAdded: (json['dateAdded'] as num?) == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              (json['dateAdded'] as num).toInt()),
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
      genre: base.genre,
      duration: base.duration,
      isFavorite: base.isFavorite,
      playCount: playCount,
      lastPlayed: lastPlayed,
      dateAdded: base.dateAdded,
    );
  }
}
