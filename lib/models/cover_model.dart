import 'dart:typed_data';

class Cover {
  final String id;
  final String filePath;
  final Uint8List? imageData;
  final String? mimeType;

  Cover({
    this.id = '',
    this.filePath = '',
    this.imageData,
    this.mimeType,
  });
}
