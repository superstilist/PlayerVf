import '../models/music_model.dart';

String? lyricsOwnerKey(Music? music) {
  return music == null ? null : '${music.id}\n${music.filePath}';
}
