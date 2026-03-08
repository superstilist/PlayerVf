import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path/path.dart' as p;
import '../models/music_model.dart';
import 'id3_parser.dart';

class _ScanTask {
  final List<String> roots;
  final SendPort sendPort;
  _ScanTask(this.roots, this.sendPort);
}

class MusicScannerService {
  static final OnAudioQuery _audioQuery = OnAudioQuery();

  /// Comprehensive permission check
  static Future<bool> checkPermissions() async {
    if (kIsWeb) return true;
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        final status = await Permission.audio.request();
        return status.isGranted;
      } else {
        final status = await Permission.storage.request();
        return status.isGranted;
      }
    }
    return true;
  }

  /// FULL REWORK: Isolate-based scanning to prevent UI freezing
  static Future<void> startScanning({
    required Function(List<Music>) onBatchUpdate,
    List<String>? customPaths,
  }) async {
    final Set<String> seenPaths = {};

    // 1. Android MediaStore Scan (Near-instant)
    if (Platform.isAndroid && (customPaths == null || customPaths.isEmpty)) {
      try {
        final songs = await _audioQuery.querySongs(
          uriType: UriType.EXTERNAL,
          ignoreCase: true,
        );
        
        final List<Music> systemBatch = [];
        for (var song in songs) {
          if ((song.duration ?? 0) < 5000) continue;
          seenPaths.add(song.data);
          systemBatch.add(Music(
            id: song.id.toString(),
            title: song.title,
            artist: song.artist ?? 'Unknown Artist',
            album: song.album ?? 'Unknown Album',
            genre: song.genre ?? 'Unknown',
            filePath: song.data,
            coverPath: '', // NO CACHING
            duration: song.duration != null ? Duration(milliseconds: song.duration!) : null,
            dateAdded: song.dateAdded != null 
                ? DateTime.fromMillisecondsSinceEpoch(song.dateAdded! * 1000) 
                : DateTime.now(),
          ));
          
          if (systemBatch.length >= 50) {
            onBatchUpdate(List.from(systemBatch));
            systemBatch.clear();
          }
        }
        if (systemBatch.isNotEmpty) onBatchUpdate(systemBatch);
      } catch (e) {
        debugPrint('MediaStore Scan Error: $e');
      }
    }

    // 2. Custom Folders / Desktop (Background Isolate)
    final roots = <String>[];
    if (customPaths != null && customPaths.isNotEmpty) {
      roots.addAll(customPaths);
    } else if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null) roots.add(p.join(userProfile, 'Music'));
    }

    if (roots.isNotEmpty) {
      final receivePort = ReceivePort();
      await Isolate.spawn(_isolateScanner, _ScanTask(roots, receivePort.sendPort));

      await for (final message in receivePort) {
        if (message is List<Music>) {
          final filteredBatch = message.where((m) => !seenPaths.contains(m.filePath)).toList();
          for (var m in filteredBatch) seenPaths.add(m.filePath);
          if (filteredBatch.isNotEmpty) onBatchUpdate(filteredBatch);
        } else if (message == "DONE") {
          receivePort.close();
          break;
        }
      }
    }
  }

  /// The Isolate entry point
  static void _isolateScanner(_ScanTask task) async {
    final List<String> audioExts = ['.mp3', '.m4a', '.wav', '.flac', '.ogg', '.aac', '.opus'];
    final parser = ID3Parser();
    final List<Music> batch = [];

    for (final root in task.roots) {
      final dir = Directory(root);
      if (!dir.existsSync()) continue;

      try {
        final entities = dir.listSync(recursive: true, followLinks: true);
        for (final entity in entities) {
          if (entity is File) {
            final ext = p.extension(entity.path).toLowerCase();
            if (audioExts.contains(ext)) {
              try {
                // We use a simplified parser here if needed or full one
                // Since we are in isolate, we can do heavy work
                final tags = await parser.parseTagsFromFile(entity.path);
                final music = parser.createMusicFromTags(entity.path, tags);
                
                batch.add(music);
                if (batch.length >= 20) {
                  task.sendPort.send(List<Music>.from(batch));
                  batch.clear();
                }
              } catch (e) {
                // Skip files with errors
              }
            }
          }
        }
      } catch (e) {
        // Skip inaccessible directories
      }
    }

    if (batch.isNotEmpty) task.sendPort.send(batch);
    task.sendPort.send("DONE");
  }

  static Future<void> cleanupCache() async {
    // No-op as we moved to native display
  }

  static Future<void> cacheMusic(Music music, File file) async {
    // Manual trigger - could be used to force metadata refresh
  }
}
