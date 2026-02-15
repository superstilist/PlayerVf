import 'dart:typed_data';
import 'dart:io' as io;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/cover_model.dart';
import '../services/id3_parser.dart';

class CoverExtractor {
  final ID3Parser _id3Parser = ID3Parser();

  /// Extracts cover art from a given file path.
  /// Returns a [Cover] object or null if no cover found.
  Future<Cover?> extractCover(String filePath) async {
    if (kIsWeb) {
      return null;
    }
    
    try {
      final file = io.File(filePath);
      if (!await file.exists()) {
        return null;
      }

      final tags = await _id3Parser.parseTagsFromFile(filePath);
      final Uint8List? coverData = _id3Parser.extractCover(tags);

      if (coverData == null || coverData.isEmpty) {
        print('No cover art found for $filePath');
        return null;
      }

      final fileName = path.basenameWithoutExtension(filePath);
      final coverId = 'cover_$fileName';

      return Cover(
        id: coverId,
        filePath: filePath,
        imageData: coverData,
      );
    } catch (e) {
      print('Error extracting cover: $e');
      return null;
    }
  }

  /// Extracts cover art from a music file located in assets.
  /// Returns a [Cover] object or null if no cover found.
  Future<Cover?> getCoverFromAssets(String musicFilePath) async {
    if (kIsWeb) {
      return null;
    }
    
    try {
      // For Windows, we need to handle asset files differently
      // First, try to get the actual file path from asset
      final tempDir = await io.Directory.systemTemp.createTemp('fluttersp');
      final tempFile = io.File('${tempDir.path}/${path.basename(musicFilePath)}');
      
      // Copy asset to temp file
      final ByteData byteData = await rootBundle.load(musicFilePath);
      await tempFile.writeAsBytes(byteData.buffer.asUint8List());
      
      // Extract metadata from temp file
      final tags = await _id3Parser.parseTagsFromFile(tempFile.path);
      final Uint8List? coverData = _id3Parser.extractCover(tags);

      // Cleanup temp file
      await tempFile.delete();
      await tempDir.delete();

      if (coverData == null || coverData.isEmpty) {
        print('No cover art found in asset: $musicFilePath');
        return null;
      }

      final fileName = path.basenameWithoutExtension(musicFilePath);
      final coverId = 'cover_$fileName';

      return Cover(
        id: coverId,
        filePath: musicFilePath,
        imageData: coverData,
      );
    } catch (e) {
      print('Error extracting cover from asset: $e');
      return null;
    }
  }
}
