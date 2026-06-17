import 'dart:ui' show ImageFilter, TileMode;

import 'package:flutter/material.dart';

import '../services/performance_policy.dart';
import 'cover_art_texture.dart';

class BlurredCoverBackground extends StatelessWidget {
  final String coverArtPath;
  final Color surfaceColor;
  final Color overlayColor;
  final double blur;
  final double scale;
  final Widget? fallback;

  const BlurredCoverBackground({
    super.key,
    required this.coverArtPath,
    required this.surfaceColor,
    required this.overlayColor,
    required this.blur,
    this.scale = 1.08,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final policy = PerformancePolicy.of(context);
    final double effectiveBlur =
        policy.isAndroid ? blur.clamp(0.0, 4.0) : blur;
    // Skip the blur pass entirely when it's imperceptibly small — saves a GPU
    // compositing layer on battery saver / max-performance modes.
    final useBlur = effectiveBlur > 0.5;
    final effectiveOverlay = overlayColor;

    return ColoredBox(
      color: surfaceColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (coverArtPath.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) {
                final mediaSize = MediaQuery.sizeOf(context);
                final width = constraints.maxWidth.isFinite
                    ? constraints.maxWidth
                    : mediaSize.width;
                final height = constraints.maxHeight.isFinite
                    ? constraints.maxHeight
                    : mediaSize.height;
                final coverWidget = Transform.scale(
                  scale: scale,
                  child: CoverArtTexture(
                    coverArtPath: coverArtPath,
                    width: width,
                    height: height,
                    filterQuality: FilterQuality.low,
                    cacheScale: policy.backgroundCoverCacheScale,
                  ),
                );

                // RepaintBoundary wraps only the blurred content so that
                // overlay/theme changes don't trigger a re-rasterization of
                // the blurred cover image.
                return ClipRect(
                  child: useBlur
                      ? RepaintBoundary(
                          child: ImageFiltered(
                            imageFilter: ImageFilter.blur(
                              sigmaX: effectiveBlur,
                              sigmaY: effectiveBlur,
                              tileMode: TileMode.decal,
                            ),
                            child: coverWidget,
                          ),
                        )
                      : RepaintBoundary(child: coverWidget),
                );
              },
            )
          else if (fallback != null)
            fallback!,
          ColoredBox(color: effectiveOverlay),
        ],
      ),
    );
  }
}
