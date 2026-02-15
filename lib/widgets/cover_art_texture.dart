import 'package:flutter/material.dart';

/// A widget to display cover art with proper error handling and loading states.
class CoverArtTexture extends StatelessWidget {
  /// The path to the cover art image.
  final String? coverArtPath;

  /// The width of the cover art.
  final double width;

  /// The height of the cover art.
  final double height;

  /// The border radius of the cover art.
  final BorderRadius? borderRadius;

  /// The placeholder widget to display while the cover art is loading.
  final Widget? placeholder;

  /// The error widget to display if the cover art fails to load.
  final Widget? errorWidget;

  /// Creates a [CoverArtTexture] widget.
  ///
  /// The [coverArtPath] is the path to the cover art image. If null, the [errorWidget] is displayed.
  /// The [width] and [height] define the dimensions of the cover art.
  /// The [borderRadius] defines the border radius of the cover art (default: 16px rounded corners).
  /// The [placeholder] is displayed while the cover art is loading.
  /// The [errorWidget] is displayed if the cover art fails to load.
  const CoverArtTexture({
    Key? key,
    required this.coverArtPath,
    required this.width,
    required this.height,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (coverArtPath == null || coverArtPath!.isEmpty) {
      return _buildErrorWidget();
    }

    // Default border radius of 16px for rounded corners
    final defaultRadius = BorderRadius.circular(16);

    return ClipRRect(
      borderRadius: borderRadius ?? defaultRadius,
      child: Image.asset(
        coverArtPath!,
        width: width,
        height: height,
        fit: BoxFit.cover,
        cacheWidth: (width * 2).toInt(), // Cache higher resolution for better quality
        cacheHeight: (height * 2).toInt(),
        errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
          return errorWidget ?? _buildErrorWidget();
        },
      ),
    );
  }

  /// Builds the default placeholder widget.
  Widget _buildDefaultPlaceholder() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: borderRadius ?? BorderRadius.circular(16),
      ),
      child: const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.teal),
        ),
      ),
    );
  }

  /// Builds the default error widget.
  Widget _buildErrorWidget() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.teal.shade700,
            Colors.teal.shade900,
          ],
        ),
        borderRadius: borderRadius ?? BorderRadius.circular(16),
      ),
      child: const Center(
        child: Icon(
          Icons.music_note,
          color: Colors.white54,
          size: 40,
        ),
      ),
    );
  }
}
