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
    if (coverArtPath.isNotEmpty) {
      if (coverArtPath.startsWith('http://') ||
          coverArtPath.startsWith('https://')) {
        return ClipRRect(
          borderRadius: borderRadius ?? BorderRadius.zero,
          child: Image.network(
            coverArtPath,
            width: width,
            height: height,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            isAntiAlias: true,
            errorBuilder: (context, error, stackTrace) => _buildDefaultCover(),
          ),
        );
      }

      final file = io.File(coverArtPath);
      // We still check if file exists to avoid showing errorBuilder immediately
      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: borderRadius ?? BorderRadius.zero,
          child: Image.file(
            file,
            width: width,
            height: height,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            isAntiAlias: true,
            errorBuilder: (context, error, stackTrace) {
              return _buildDefaultCover();
            },
          ),
        );
      }
    }

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
      child: LayoutBuilder(builder: (context, constraints) {
        final size =
            constraints.maxWidth.isFinite ? constraints.maxWidth * 0.4 : 60.0;
        return Icon(
          Icons.music_note,
          color: Colors.white54,
          size: size,
        );
      }),
    );
  }
}
