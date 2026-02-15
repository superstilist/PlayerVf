import 'dart:typed_data';
import 'dart:core';

class Music {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String filePath;
  final String coverPath;
  Duration? duration;

  Music({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.filePath,
    required this.coverPath,
    this.duration,
  });
}