import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../models/settings_model.dart';
import '../core/size_aware_cache.dart';

/// A cover art widget that resamples the source image with the
/// `image` package's bicubic interpolation (the highest quality method
/// it exposes) and encodes the result as a high-quality JPEG at the
/// target DPR-matched size, so list-mode cover art is rendered at the
/// maximum attainable sharpness for the device.
///
/// The widget first paints the source via [Image.file] with a DPR-aware
/// `cacheWidth`/`cacheHeight` and `FilterQuality.high` so the user
/// always sees the artwork instantly. In the background, the decode +
/// bicubic resize + JPEG re-encode runs inside an isolate via
/// [compute]; when it completes the widget swaps in the higher-quality
/// version. Results are cached in a bounded LRU so repeated list
/// scrolls are instant.
class LanczosCoverArt extends StatefulWidget {
  final String coverArtPath;
  final double width;
  final double height;
  final BorderRadius? borderRadius;
  final BoxFit fit;
  final Widget? placeholder;
  final int maxTargetSize;
  final int jpegQuality;
  final CoverArtDisplayMode coverArtDisplayMode;

  const LanczosCoverArt({
    super.key,
    required this.coverArtPath,
    required this.width,
    required this.height,
    this.borderRadius,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.maxTargetSize = 1280,
    this.jpegQuality = 96,
    this.coverArtDisplayMode = CoverArtDisplayMode.fit,
  });

  @override
  State<LanczosCoverArt> createState() => _LanczosCoverArtState();
}

class _LanczosCoverArtState extends State<LanczosCoverArt> {
  static final LruCache<String, Uint8List> _cache = LruCache(maxEntries: 48);
  static const int _maxDecodeDimension = 1024;

  Uint8List? _imageBytes;
  int _requestId = 0;
  String? _lastKey;
  double? _dpr;

  String get _cacheKey {
    final w = widget.width.toInt();
    final h = widget.height.toInt();
    return '${widget.coverArtPath}|$w|$h|${widget.maxTargetSize}';
  }

  int _cacheExtent(double value, double dpr) {
    final raw = (value * dpr).round();
    return raw.clamp(48, _maxDecodeDimension);
  }

  @override
  void initState() {
    super.initState();
    _lastKey = _cacheKey;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dpr = MediaQuery.of(context).devicePixelRatio;
    _load();
  }

  @override
  void didUpdateWidget(covariant LanczosCoverArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    final key = _cacheKey;
    if (_lastKey != key) {
      _lastKey = key;
      _imageBytes = null;
      _load();
    }
  }

  Future<void> _load() async {
    if (widget.coverArtPath.isEmpty) return;
    if (_dpr == null) return;

    final key = _cacheKey;
    final cached = _cache.get(key);
    if (cached != null) {
      if (mounted) setState(() => _imageBytes = cached);
      return;
    }

    final requestId = ++_requestId;
    final dpr = _dpr!;
    final targetW = _cacheExtent(widget.width, dpr);
    final targetH = _cacheExtent(widget.height, dpr);

    try {
      final file = io.File(widget.coverArtPath);
      if (!await file.exists()) return;

      final bytes = await file.readAsBytes();
      if (requestId != _requestId || !mounted) return;

      final resized = await compute(
        _highQualityResizeIsolate,
        _ResizeRequest(bytes, targetW, targetH, widget.jpegQuality),
      );

      if (requestId != _requestId || !mounted) return;

      _putCache(key, resized);
      setState(() => _imageBytes = resized);
    } catch (_) {
      // Keep showing the fast fallback; do not blank the artwork.
    }
  }

  static void _putCache(String key, Uint8List bytes) {
    _cache.put(key, bytes);
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    Widget child;
    if (_imageBytes != null) {
      // High-quality bicubic-resized bitmap is ready.
      child = _buildCoverArtImage(
        context,
        imageBytes: _imageBytes,
        width: widget.width,
        height: widget.height,
        filterQuality: FilterQuality.high,
        cacheScale: dpr,
      );
    } else if (widget.coverArtPath.isNotEmpty) {
      // Fallback: paint the source directly with DPR-aware decode size
      // and the engine's highest filter quality. The user always sees
      // the cover art instantly while the background resize runs.
      child = _buildCoverArtImage(
        context,
        path: widget.coverArtPath,
        width: widget.width,
        height: widget.height,
        filterQuality: FilterQuality.high,
        cacheScale: dpr,
      );
    } else {
      child = widget.placeholder ??
          _DefaultPlaceholder(
            width: widget.width,
            height: widget.height,
          );
    }

    if (widget.borderRadius != null) {
      child = ClipRRect(
        borderRadius: widget.borderRadius!,
        child: child,
      );
    }

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: child,
    );
  }

  Widget _buildCoverArtImage(
    BuildContext context,
    {required double width,
    required double height,
    required FilterQuality filterQuality,
    required double cacheScale,
    Uint8List? imageBytes,
    String? path,
    }) {
    switch (widget.coverArtDisplayMode) {
      case CoverArtDisplayMode.fit:
        if (imageBytes != null) {
          return Image.memory(
            imageBytes,
            width: width,
            height: height,
            fit: widget.fit,
            filterQuality: filterQuality,
            gaplessPlayback: true,
            isAntiAlias: true,
          );
        } else {
          return Image.file(
            io.File(path!),
            width: width,
            height: height,
            fit: widget.fit,
            cacheWidth: _cacheExtent(width, cacheScale),
            cacheHeight: _cacheExtent(height, cacheScale),
            filterQuality: filterQuality,
            gaplessPlayback: true,
            isAntiAlias: true,
            errorBuilder: (_, __, ___) => widget.placeholder ??
                _DefaultPlaceholder(
                  width: width,
                  height: height,
                ),
          );
        }
      case CoverArtDisplayMode.crop:
        Widget image;
        if (imageBytes != null) {
          image = Image.memory(
            imageBytes,
            width: double.infinity,
            height: double.infinity,
            fit: widget.fit,
            filterQuality: filterQuality,
            gaplessPlayback: true,
            isAntiAlias: true,
          );
        } else {
          image = Image.file(
            io.File(path!),
            width: double.infinity,
            height: double.infinity,
            fit: widget.fit,
            cacheWidth: _cacheExtent(width, cacheScale),
            cacheHeight: _cacheExtent(height, cacheScale),
            filterQuality: filterQuality,
            gaplessPlayback: true,
            isAntiAlias: true,
          );
        }
        return Stack(
          children: [
            image,
            Container(
              color: Colors.black.withOpacity(0.3),
            ),
          ],
        );
      case CoverArtDisplayMode.square:
        Widget image;
        if (imageBytes != null) {
          image = Image.memory(
            imageBytes,
            width: double.infinity,
            height: double.infinity,
            fit: widget.fit,
            filterQuality: filterQuality,
            gaplessPlayback: true,
            isAntiAlias: true,
          );
        } else {
          image = Image.file(
            io.File(path!),
            width: double.infinity,
            height: double.infinity,
            fit: widget.fit,
            cacheWidth: _cacheExtent(width, cacheScale),
            cacheHeight: _cacheExtent(height, cacheScale),
            filterQuality: filterQuality,
            gaplessPlayback: true,
            isAntiAlias: true,
          );
        }
        return Stack(
          children: [
            image,
            Container(
              color: Colors.black.withOpacity(0.3),
            ),
            Center(
              child: Container(
                width: width.clamp(0, height),
                height: height.clamp(0, width),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 2,
                  ),
                ),
              ),
            ),
          ],
        );
      case CoverArtDisplayMode.custom:
        if (imageBytes != null) {
          return Image.memory(
            imageBytes,
            width: width,
            height: height,
            fit: widget.fit,
            filterQuality: filterQuality,
            gaplessPlayback: true,
            isAntiAlias: true,
          );
        } else {
          return Image.file(
            io.File(path!),
            width: width,
            height: height,
            fit: widget.fit,
            cacheWidth: _cacheExtent(width, cacheScale),
            cacheHeight: _cacheExtent(height, cacheScale),
            filterQuality: filterQuality,
            gaplessPlayback: true,
            isAntiAlias: true,
            errorBuilder: (_, __, ___) => widget.placeholder ??
                _DefaultPlaceholder(
                  width: width,
                  height: height,
                ),
          );
        }
    }
  }
}

class _ResizeRequest {
  final Uint8List bytes;
  final int targetWidth;
  final int targetHeight;
  final int quality;

  const _ResizeRequest(this.bytes, this.targetWidth, this.targetHeight, this.quality);
}

Uint8List _highQualityResizeIsolate(_ResizeRequest request) {
  final src = img.decodeImage(request.bytes);
  if (src == null) {
    throw Exception('Failed to decode image');
  }

  final w = request.targetWidth;
  final h = request.targetHeight;

  final img.Image resized;
  if (src.width == w && src.height == h) {
    resized = src;
  } else if (src.width >= w && src.height >= h) {
    // Downscale: single cubic pass preserves the maximum detail.
    resized = img.copyResize(
      src,
      width: w,
      height: h,
      interpolation: img.Interpolation.cubic,
    );
  } else {
    // Upscale: two-step cubic pass for fewer ringing artifacts.
    final stepW = (src.width * 2).clamp(1, w);
    final stepH = (src.height * 2).clamp(1, h);
    final intermediate = img.copyResize(
      src,
      width: stepW,
      height: stepH,
      interpolation: img.Interpolation.cubic,
    );
    resized = img.copyResize(
      intermediate,
      width: w,
      height: h,
      interpolation: img.Interpolation.cubic,
    );
  }

  return Uint8List.fromList(img.encodeJpg(resized, quality: request.quality));
}

class _DefaultPlaceholder extends StatelessWidget {
  final double width;
  final double height;

  const _DefaultPlaceholder({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: const BoxDecoration(color: Color(0xFF1A1A1A)),
      child: LayoutBuilder(builder: (context, constraints) {
        final size = constraints.maxWidth.isFinite
            ? constraints.maxWidth * 0.4
            : 24.0;
        return Icon(
          Icons.music_note,
          color: Colors.white24,
          size: size,
        );
      }),
    );
  }
}
