import 'package:flutter/material.dart';
import 'dart:io' as io;
import 'package:on_audio_query/on_audio_query.dart';
import 'package:flutter/foundation.dart';

class CoverArtTexture extends StatefulWidget {
  final String coverArtPath;
  final String? musicId;
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const CoverArtTexture({
    super.key,
    required this.coverArtPath,
    this.musicId,
    this.width = 200,
    this.height = 200,
    this.borderRadius,
  });

  @override
  State<CoverArtTexture> createState() => _CoverArtTextureState();
}

class _CoverArtTextureState extends State<CoverArtTexture> {
  String? _lastMusicId;
  
  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius ?? BorderRadius.zero,
        color: Colors.black,
      ),
      child: ClipRRect(
        borderRadius: widget.borderRadius ?? BorderRadius.zero,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth.isFinite ? constraints.maxWidth : widget.width;
            final h = constraints.maxHeight.isFinite ? constraints.maxHeight : widget.height;
            return _buildImageContent(context, w, h);
          },
        ),
      ),
    );
  }

  Widget _buildImageContent(BuildContext context, double w, double h) {
    // 1. Android Native Query - Use maximum native resolution for best quality
    if (!kIsWeb && io.Platform.isAndroid && widget.musicId != null) {
      final id = int.tryParse(widget.musicId!);
      if (id != null) {
        // Only rebuild if music ID changed
        if (_lastMusicId != widget.musicId) {
          _lastMusicId = widget.musicId;
        }
        
        return QueryArtworkWidget(
          key: ValueKey('artwork_$id'),
          id: id,
          type: ArtworkType.AUDIO,
          // Use balanced resolution for quality without freezing (500x500 is good balance)
          artworkWidth: 500,
          artworkHeight: 500,
          artworkFit: BoxFit.cover,
          artworkBorder: BorderRadius.zero,
          format: ArtworkFormat.JPEG,
          quality: 100,
          size: 500, // Balanced size for performance
          nullArtworkWidget: _buildFileFallback(context, w, h),
          errorBuilder: (context, error, stackTrace) => _buildFileFallback(context, w, h),
        );
      }
    }

    return _buildFileFallback(context, w, h);
  }

  Widget _buildFileFallback(BuildContext context, double w, double h) {
    if (widget.coverArtPath.isNotEmpty) {
      final file = io.File(widget.coverArtPath);
      if (file.existsSync()) {
        // Use balanced quality settings - limit to reasonable size to prevent freezes
        final double devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
        final int targetWidth = (w * devicePixelRatio).toInt().clamp(1, 800);
        final int targetHeight = (h * devicePixelRatio).toInt().clamp(1, 800);
        return Image.file(
          file,
          width: w,
          height: h,
          fit: BoxFit.cover,
          cacheWidth: targetWidth,
          cacheHeight: targetHeight,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stackTrace) => _buildDefaultCover(w, h),
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
              child: child,
            );
          },
        );
      }
    }
    return _buildDefaultCover(w, h);
  }

  Widget _buildDefaultCover(double w, double h) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.teal.shade900,
            Colors.black,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          color: Colors.white10,
          size: w * 0.45,
        ),
      ),
    );
  }
}
