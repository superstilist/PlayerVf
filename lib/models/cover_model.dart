import 'dart:typed_data';

class Cover {
  final String id;
  final String filePath;
  final Uint8List? imageData;

  Cover({
    required this.id,
    required this.filePath,
    this.imageData,
  });
}