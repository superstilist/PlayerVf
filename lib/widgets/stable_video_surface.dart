import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Stable video surface for Windows media_kit playback.
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
  static const double _fallbackAspectRatio = 16 / 9;
  static const double _maxTextureWidth = 1920;
  static const double _maxTextureHeight = 1080;

  int? _lastRequestedWidth;
  int? _lastRequestedHeight;

  @override
  void didUpdateWidget(covariant StableVideoSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller) ||
        oldWidget.surfaceKey != widget.surfaceKey ||
        oldWidget.fit != widget.fit) {
      _lastRequestedWidth = null;
      _lastRequestedHeight = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        if (!width.isFinite || !height.isFinite || width <= 1 || height <= 1) {
          return widget.placeholder ?? const SizedBox.shrink();
        }

        final size = _targetTextureSize(width, height, widget.fit);
        _scheduleControllerResize(size);

        return SizedBox(
          width: width,
          height: height,
          child: ExcludeSemantics(
            child: Video(
              key: ValueKey('stable-video-${widget.surfaceKey}'),
              controller: widget.controller,
              fit: widget.fit,
              controls: NoVideoControls,
            ),
          ),
        );
      },
    );
  }

  _SurfaceSize _targetTextureSize(
    double containerWidth,
    double containerHeight,
    BoxFit fit,
  ) {
    final containerAspect = containerWidth / containerHeight;
    var width = containerWidth;
    var height = containerHeight;

    if (fit == BoxFit.cover) {
      if (containerAspect > _fallbackAspectRatio) {
        width = containerWidth;
        height = width / _fallbackAspectRatio;
      } else {
        height = containerHeight;
        width = height * _fallbackAspectRatio;
      }
    } else if (fit != BoxFit.fill) {
      if (containerAspect > _fallbackAspectRatio) {
        height = containerHeight;
        width = height * _fallbackAspectRatio;
      } else {
        width = containerWidth;
        height = width / _fallbackAspectRatio;
      }
    }

    final scale = min(
      1.0,
      min(_maxTextureWidth / width, _maxTextureHeight / height),
    );
    return _SurfaceSize(
      max(2, (width * scale).round()),
      max(2, (height * scale).round()),
    );
  }

  void _scheduleControllerResize(_SurfaceSize size) {
    if (_lastRequestedWidth == size.width &&
        _lastRequestedHeight == size.height) {
      return;
    }

    _lastRequestedWidth = size.width;
    _lastRequestedHeight = size.height;
    final controller = widget.controller;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(controller, widget.controller)) return;
      unawaited(
        controller
            .setSize(width: size.width, height: size.height)
            .timeout(const Duration(seconds: 2))
            .catchError((Object error) {
          debugPrint('StableVideoSurface resize failed: $error');
        }),
      );
    });
  }
}

class _SurfaceSize {
  final int width;
  final int height;

  const _SurfaceSize(this.width, this.height);
}
