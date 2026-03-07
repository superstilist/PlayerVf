import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import '../models/music_model.dart';
import 'id3_parser.dart';

class MusicScannerService {
  static final ID3Parser _parser = ID3Parser();

  /// Scans system music folders using background processing.
  static Future<void> startScanning({
    required Function(List<Music>) onBatchUpdate,
  }) async {
    final List<Directory> scanDirs = [];
    
    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null) {
        final musicDir = Directory('$userProfile\\Music');
        if (await musicDir.exists()) scanDirs.add(musicDir);
      }
    } else if (Platform.isAndroid) {
      final musicDir = Directory('/storage/emulated/0/Music');
      if (await musicDir.exists()) scanDirs.add(musicDir);
    }

    final List<Music> batch = [];
    const int batchSize = 10;

    for (final dir in scanDirs) {
      try {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File && _isAudioFile(entity.path)) {
            try {
              // Offload to background isolate
              final music = await _parseMetadata(entity.path);
              if (music != null) {
                batch.add(music);
                if (batch.length >= batchSize) {
                  onBatchUpdate(List.from(batch));
                  batch.clear();
                }
              }
            } catch (e) {
              debugPrint('Error parsing ${entity.path}: $e');
            }
          }
        }
      } catch (e) {
        debugPrint('Error listing directory ${dir.path}: $e');
      }
    }
    
    if (batch.isNotEmpty) onBatchUpdate(batch);
  }

  static bool _isAudioFile(String path) {
    final ext = path.toLowerCase();
    return ext.endsWith('.mp3') || ext.endsWith('.m4a') || ext.endsWith('.wav') || ext.endsWith('.flac');
  }

  static Future<Music?> _parseMetadata(String filePath) async {
    try {
      final tags = await _parser.parseTagsFromFile(filePath);
      final cacheDir = await getTemporaryDirectory();
      return _parser.createMusicFromTags(filePath, tags, coverDirectory: cacheDir.path);
    } catch (e) {
      debugPrint('Metadata parse error: $e');
      return null;
    }
  }

  /// Clears the local metadata cache.
  static Future<void> cleanupCache() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      if (await cacheDir.exists()) {
        await for (final entity in cacheDir.list()) {
          if (entity is File && entity.path.contains('_cover.jpg')) {
            await entity.delete();
          }
        }
      }
    } catch (e) {
      debugPrint('Cleanup error: $e');
    }
  }

  /// Manually caches/updates music metadata.
  static Future<void> cacheMusic(Music music, File file) async {
    // This could update a local DB if implemented. 
    // For now, it just ensures the cover is extracted.
    await _parseMetadata(file.path);
  }
}
