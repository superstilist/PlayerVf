import 'dart:typed_data';
import 'dart:io' as io;
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as path;

import '../models/cover_model.dart';
import '../services/id3_parser.dart';

class CoverExtractor {
  final ID3Parser _id3Parser = ID3Parser();

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
        debugPrint('No cover art found for $filePath');
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
      debugPrint('Error extracting cover: $e');
      return null;
    }
  }

  Future<Cover?> getCoverFromAssets(String musicFilePath) async {
    if (kIsWeb) {
      return null;
    }

    try {
      final tempDir = await io.Directory.systemTemp.createTemp('fluttersp');
      final tempFile =
          io.File('${tempDir.path}/${path.basename(musicFilePath)}');

      final ByteData byteData = await rootBundle.load(musicFilePath);
      await tempFile.writeAsBytes(byteData.buffer.asUint8List());

      final tags = await _id3Parser.parseTagsFromFile(tempFile.path);
      final Uint8List? coverData = _id3Parser.extractCover(tags);

      await tempFile.delete();
      await tempDir.delete();

      if (coverData == null || coverData.isEmpty) {
        debugPrint('No cover art found in asset: $musicFilePath');
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
      debugPrint('Error extracting cover from asset: $e');
      return null;
    }
  }
}
