import 'dart:typed_data';
import 'dart:io' as io;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:id3/id3.dart';
import 'dart:convert';

import '../models/music_model.dart';

class ID3Parser {
  /// Parses ID3 tags from a file path
  Future<Map<String, dynamic>> parseTagsFromFile(String filePath) async {
    if (kIsWeb) {
      return {};
    }

    try {
      final file = io.File(filePath);
      if (!await file.exists()) {
        return {};
      }

      final bytes = await file.readAsBytes();
      return _parseTags(bytes);
    } catch (e) {
      print('Error parsing ID3 tags from file $filePath: $e');
      return {};
    }
  }

  /// Parses ID3 tags from assets file
  Future<Map<String, dynamic>> parseTagsFromAsset(String assetPath) async {
    if (kIsWeb) {
      return {};
    }

    try {
      // For Windows, we need to handle asset files differently
      final tempDir = await io.Directory.systemTemp.createTemp('fluttersp');
      final tempFile = io.File('${tempDir.path}/${path.basename(assetPath)}');
      
      // Copy asset to temp file
      final ByteData byteData = await rootBundle.load(assetPath);
      await tempFile.writeAsBytes(byteData.buffer.asUint8List());
      
      // Parse tags from temp file
      final bytes = await tempFile.readAsBytes();
      final tags = _parseTags(bytes);

      // Cleanup temp file
      await tempFile.delete();
      await tempDir.delete();

      return tags;
    } catch (e) {
      print('Error parsing ID3 tags from asset $assetPath: $e');
      return {};
    }
  }

  /// Parse ID3 tags using the id3 package
  Map<String, dynamic> _parseTags(Uint8List bytes) {
    final result = <String, dynamic>{};

    try {
      final mp3 = MP3Instance(bytes);
      final success = mp3.parseTagsSync();
      
      if (success) {
        final tags = mp3.getMetaTags();
        
        if (tags != null) {
          // Title
          if (tags.containsKey('Title') && tags['Title'] != null && tags['Title'].toString().isNotEmpty) {
            result['title'] = tags['Title'];
          }
          
          // Artist
          if (tags.containsKey('Artist') && tags['Artist'] != null && tags['Artist'].toString().isNotEmpty) {
            result['artist'] = tags['Artist'];
          }
          
          // Album
          if (tags.containsKey('Album') && tags['Album'] != null && tags['Album'].toString().isNotEmpty) {
            result['album'] = tags['Album'];
          }
          
          // Track
          if (tags.containsKey('Track') && tags['Track'] != null && tags['Track'].toString().isNotEmpty) {
            result['track'] = tags['Track'];
          }
          
          // Year
          if (tags.containsKey('Year') && tags['Year'] != null && tags['Year'].toString().isNotEmpty) {
            result['year'] = tags['Year'];
          }
          
          // Genre
          if (tags.containsKey('Genre') && tags['Genre'] != null && tags['Genre'].toString().isNotEmpty) {
            result['genre'] = tags['Genre'];
          }
          
          // Cover art
          if (tags.containsKey('APIC') && tags['APIC'] != null) {
            final apic = tags['APIC'] as Map<String, dynamic>;
            if (apic.containsKey('base64') && apic['base64'] != null) {
              result['cover'] = base64.decode(apic['base64']);
            }
          }
        }
      }
    } catch (e) {
      print('Error parsing tags with id3 package: $e');
    }

    return result;
  }

  /// Extract cover art from parsed tags
  Uint8List? extractCover(Map<String, dynamic> tags) {
    if (tags.containsKey('cover')) {
      final cover = tags['cover'];
      if (cover is Uint8List) {
        return cover;
      }
      if (cover is List<int>) {
        return Uint8List.fromList(cover);
      }
    }
    return null;
  }

  /// Create Music object from parsed tags
  Music createMusicFromTags(String filePath, Map<String, dynamic> tags) {
    final fileName = path.basenameWithoutExtension(filePath);
    
    return Music(
      id: fileName,
      title: tags['title']?.toString() ?? fileName,
      artist: tags['artist']?.toString() ?? 'Unknown Artist',
      album: tags['album']?.toString() ?? 'Unknown Album',
      filePath: filePath,
      coverPath: tags.containsKey('cover') ? filePath : '',
    );
  }
}
