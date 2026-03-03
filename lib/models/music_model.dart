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
  }) : this.dateAdded = dateAdded ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'playCount': playCount,
    'lastPlayed': lastPlayed?.millisecondsSinceEpoch,
  };

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
