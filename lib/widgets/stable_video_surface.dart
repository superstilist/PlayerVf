import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

class StableVideoSurface extends StatefulWidget {
  final VideoController controller;
  final String surfaceKey;
  final BoxFit fit;
  final Widget? placeholder;

  const StableVideoSurface({
    super.key,
    required this.controller,
    required this.surfaceKey,
    this.fit = BoxFit.contain,
    this.placeholder,
  });

  @override
  State<StableVideoSurface> createState() => _StableVideoSurfaceState();
}

class _StableVideoSurfaceState extends State<StableVideoSurface> {
  Timer? _resizeTimer;
  Size? _lastLogicalSize;

  @override
  void dispose() {
    _resizeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final video = RepaintBoundary(
      child: Video(
        key: ValueKey('media-kit-video-${widget.surfaceKey}'),
        controller: widget.controller,
        fit: widget.fit,
        controls: NoVideoControls,
      ),
    );

    if (defaultTargetPlatform != TargetPlatform.windows) {
      return video;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        if (!width.isFinite || !height.isFinite || width <= 1 || height <= 1) {
          return widget.placeholder ?? const SizedBox.shrink();
        }
        _scheduleWindowsTextureResize(context, Size(width, height));
        return SizedBox(
          width: width,
          height: height,
          child: ClipRect(child: video),
        );
      },
    );
  }

  void _scheduleWindowsTextureResize(BuildContext context, Size logicalSize) {
    final previous = _lastLogicalSize;
    if (previous != null &&
        (previous.width - logicalSize.width).abs() < 8 &&
        (previous.height - logicalSize.height).abs() < 8) {
      return;
    }
    _lastLogicalSize = logicalSize;
    _resizeTimer?.cancel();
    _resizeTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final width =
          math.max(2, math.min(1920, logicalSize.width * dpr)).round();
      final height =
          math.max(2, math.min(1080, logicalSize.height * dpr)).round();
      unawaited(widget.controller.setSize(width: width, height: height));
    });
  }
}
