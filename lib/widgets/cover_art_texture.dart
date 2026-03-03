import 'package:flutter/material.dart';
import 'dart:io' as io;

class CoverArtTexture extends StatelessWidget {
  final String coverArtPath;
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const CoverArtTexture({
    super.key,
    required this.coverArtPath,
    this.width = 200,
    this.height = 200,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    try {
      final file = io.File(coverArtPath);
      if (file.existsSync()) {
        final bytes = file.readAsBytesSync();
        return ClipRRect(
          borderRadius: borderRadius ?? BorderRadius.zero,
          child: Image.memory(
            bytes,
            width: width,
            height: height,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return _buildDefaultCover();
            },
          ),
        );
      }
    } catch (_) {}
    
    return _buildDefaultCover();
  }

  Widget _buildDefaultCover() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.teal.shade700,
            Colors.teal.shade900,
            Colors.black87,
          ],
        ),
      ),
      child: Icon(
        Icons.music_note,
        color: Colors.white54,
        size: width * 0.4,
      ),
    );
  }
}
