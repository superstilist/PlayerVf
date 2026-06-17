import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/music_model.dart';
import 'app_directories.dart';

class UserFeedbackStore {
  static Database? _db;
  static Future<Database>? _opening;

  static Future<Database> _database() async {
    final existing = _db;
    if (existing != null) return existing;

    final opening = _opening;
    if (opening != null) return opening;

    _opening = () async {
      final dir = await getPlayerVfDocumentsDirectory();
      final db = await openDatabase(
        p.join(dir.path, 'user_feedback.db'),
        version: 2,
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE user_likes (
              track_id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              artist TEXT NOT NULL,
              album TEXT NOT NULL,
              genre TEXT NOT NULL,
              file_path TEXT NOT NULL,
              liked INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          await database.execute(
            'CREATE INDEX idx_liked ON user_likes(liked)',
          );
        },
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await database.execute(
              'CREATE INDEX IF NOT EXISTS idx_liked ON user_likes(liked)',
            );
          }
        },
      );
      _db = db;
      return db;
    }();

    return _opening!;
  }

  static Future<Set<String>> likedTrackIds() async {
    final db = await _database();
    final rows = await db.query(
      'user_likes',
      columns: ['track_id'],
      where: 'liked = ?',
      whereArgs: [1],
    );
    return rows.map((row) => row['track_id'].toString()).toSet();
  }

  static Future<void> saveLike(Music music, bool liked) async {
    final db = await _database();
    await db.insert(
      'user_likes',
      {
        'track_id': music.id,
        'title': music.title,
        'artist': music.artist,
        'album': music.album,
        'genre': music.genre,
        'file_path': music.filePath,
        'liked': liked ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> saveLikes(Iterable<Music> music, bool liked) async {
    final db = await _database();
    final batch = db.batch();
    final updatedAt = DateTime.now().millisecondsSinceEpoch;
    for (final track in music) {
      batch.insert(
        'user_likes',
        {
          'track_id': track.id,
          'title': track.title,
          'artist': track.artist,
          'album': track.album,
          'genre': track.genre,
          'file_path': track.filePath,
          'liked': liked ? 1 : 0,
          'updated_at': updatedAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }
}
