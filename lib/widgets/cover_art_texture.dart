import 'dart:io' as io;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../models/settings_model.dart';
import '../services/performance_policy.dart';

class CoverArtTexture extends StatelessWidget {
  final String coverArtPath;
  final double width;
  final double height;
  final BorderRadius? borderRadius;
  final FilterQuality? filterQuality;
  final double? cacheScale;
  final CoverArtDisplayMode coverArtDisplayMode;

  const CoverArtTexture({
    super.key,
    required this.coverArtPath,
    this.width = 200,
    this.height = 200,
    this.borderRadius,
    this.filterQuality,
    this.cacheScale,
    this.coverArtDisplayMode = CoverArtDisplayMode.fit,
  });

  @override
  Widget build(BuildContext context) {
    final policy = PerformancePolicy.of(context);
    final resolvedFilterQuality = policy.resolveFilterQuality(filterQuality);
    final resolvedCacheScale = cacheScale == null
        ? policy.coverCacheScale
        : cacheScale!.clamp(0.35, policy.coverCacheScale);

    final resolvedWidth = _sanitizeDimension(width, 200);
    final resolvedHeight = _sanitizeDimension(height, 200);
    final radius = borderRadius ?? BorderRadius.zero;

    final Widget child;
    if (coverArtPath.isNotEmpty) {
      if (_isBrowserImage(coverArtPath)) {
        child = _NetworkCoverArt(
          url: coverArtPath,
          width: resolvedWidth,
          height: resolvedHeight,
          fallback: _buildDefaultCover(
            width: resolvedWidth,
            height: resolvedHeight,
            borderRadius: radius,
          ),
          filterQuality: resolvedFilterQuality,
          cacheScale: resolvedCacheScale,
        );
      } else if (kIsWeb) {
        child = _buildDefaultCover(
          width: resolvedWidth,
          height: resolvedHeight,
          borderRadius: radius,
        );
      } else {
        child = _buildCoverArtImage(
          context,
          width: resolvedWidth,
          height: resolvedHeight,
          path: coverArtPath,
          filterQuality: resolvedFilterQuality,
          cacheScale: resolvedCacheScale,
        );
      }
    } else {
      child = _buildDefaultCover(
        width: resolvedWidth,
        height: resolvedHeight,
        borderRadius: radius,
      );
    }

    return SizedBox(
      width: resolvedWidth,
      height: resolvedHeight,
      child: ClipRRect(
        borderRadius: radius,
        child: child,
      ),
    );
  }

  Widget _buildCoverArtImage(
      BuildContext context, {
        required double width,
        required double height,
        required String path,
        required FilterQuality filterQuality,
        required double cacheScale,
      }) {
    switch (coverArtDisplayMode) {
      case CoverArtDisplayMode.fit:
        return Image.file(
          io.File(path),
          width: width,
          height: height,
          cacheWidth: _cacheExtent(width, cacheScale),
          cacheHeight: _cacheExtent(height, cacheScale),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: filterQuality,
          isAntiAlias: true,
          errorBuilder: (context, error, stackTrace) {
            return _buildDefaultCover(
              width: width,
              height: height,
              borderRadius: borderRadius ?? BorderRadius.zero,
            );
          },
        );

      case CoverArtDisplayMode.crop:
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              io.File(path),
              cacheWidth: _cacheExtent(width, cacheScale),
              cacheHeight: _cacheExtent(height, cacheScale),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: filterQuality,
              isAntiAlias: true,
              errorBuilder: (context, error, stackTrace) {
                return _buildDefaultCover(
                  width: width,
                  height: height,
                  borderRadius: borderRadius ?? BorderRadius.zero,
                );
              },
            ),
            Container(
              color: Colors.black.withOpacity(0.3),
            ),
          ],
        );

      case CoverArtDisplayMode.square:
        final side = width < height ? width : height;

        return Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              io.File(path),
              cacheWidth: _cacheExtent(width, cacheScale),
              cacheHeight: _cacheExtent(height, cacheScale),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: filterQuality,
              isAntiAlias: true,
              errorBuilder: (context, error, stackTrace) {
                return _buildDefaultCover(
                  width: width,
                  height: height,
                  borderRadius: borderRadius ?? BorderRadius.zero,
                );
              },
            ),
            Container(
              color: Colors.black.withOpacity(0.3),
            ),
            Center(
              child: Container(
                width: side,
                height: side,
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
        return Image.file(
          io.File(path),
          width: width,
          height: height,
          cacheWidth: _cacheExtent(width, cacheScale),
          cacheHeight: _cacheExtent(height, cacheScale),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: filterQuality,
          isAntiAlias: true,
          errorBuilder: (context, error, stackTrace) {
            return _buildDefaultCover(
              width: width,
              height: height,
              borderRadius: borderRadius ?? BorderRadius.zero,
            );
          },
        );
    }
  }

  bool _isBrowserImage(String path) {
    return path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith('blob:') ||
        path.startsWith('data:image/');
  }

  int? _cacheExtent(double value, double multiplier) {
    if (!value.isFinite || value <= 0) return null;
    return (value * multiplier).clamp(64, 1024).round();
  }

  double _sanitizeDimension(double value, double fallback) {
    if (!value.isFinite || value <= 0) return fallback;
    return value;
  }

  Widget _buildDefaultCover({
    required double width,
    required double height,
    required BorderRadius borderRadius,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: const Color(0xFF1A1A1A),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.maxWidth.isFinite
              ? constraints.maxWidth * 0.4
              : 60.0;
          return Icon(
            Icons.music_note,
            color: Colors.white24,
            size: size,
          );
        },
      ),
    );
  }
}

class _NetworkCoverArt extends StatefulWidget {
  final String url;
  final double width;
  final double height;
  final Widget fallback;
  final FilterQuality filterQuality;
  final double cacheScale;

  const _NetworkCoverArt({
    required this.url,
    required this.width,
    required this.height,
    required this.fallback,
    required this.filterQuality,
    required this.cacheScale,
  });

  @override
  State<_NetworkCoverArt> createState() => _NetworkCoverArtState();
}

class _NetworkCoverArtState extends State<_NetworkCoverArt> {
  late List<String> _candidates;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _candidates = _coverCandidates(widget.url);
  }

  @override
  void didUpdateWidget(covariant _NetworkCoverArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _candidates = _coverCandidates(widget.url);
      _index = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_candidates.isEmpty) return widget.fallback;

    return RepaintBoundary(
      child: Image.network(
        _candidates[_index],
        key: ValueKey(_candidates[_index]),
        width: widget.width,
        height: widget.height,
        fit: BoxFit.cover,
        cacheWidth: _cacheExtent(widget.width, widget.cacheScale),
        cacheHeight: _cacheExtent(widget.height, widget.cacheScale),
        gaplessPlayback: true,
        filterQuality: widget.filterQuality,
        isAntiAlias: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) return child;
          return widget.fallback;
        },
        errorBuilder: (context, error, stackTrace) {
          if (_index < _candidates.length - 1) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _index++);
            });
          }
          return widget.fallback;
        },
      ),
    );
  }

  static int? _cacheExtent(double value, double multiplier) {
    if (!value.isFinite || value <= 0) return null;
    return (value * multiplier).clamp(128, 1280).round();
  }

  static List<String> _coverCandidates(String rawUrl) {
    final urls = <String>[];

    void add(String value) {
      if (value.isNotEmpty && !urls.contains(value)) {
        urls.add(value);
      }
    }

    final url = rawUrl.trim();
    if (url.isEmpty) return urls;

    final uri = Uri.tryParse(url);
    final clean = uri?.hasQuery == true
        ? url.split('?').first
        : url;

    final googleSized = RegExp(r'=w\d+-h\d+[^?]*$');
    final googleSquare = RegExp(r'=s\d+[^?]*$');

    if (googleSized.hasMatch(clean)) {
      add(clean.replaceFirst(googleSized, '=w1200-h1200-l90-rj'));
      add(clean.replaceFirst(googleSized, '=w960-h960-l90-rj'));
      add(clean.replaceFirst(googleSized, '=w544-h544-l90-rj'));
    } else if (googleSquare.hasMatch(clean)) {
      add(clean.replaceFirst(googleSquare, '=s1200'));
      add(clean.replaceFirst(googleSquare, '=s960'));
      add(clean.replaceFirst(googleSquare, '=s544'));
    }

    final youtubeMatch =
        RegExp(r'(https?:\/\/[^\/]+\/(?:vi|vi_webp)\/([^\/]+)\/)')
            .firstMatch(clean);
    if (youtubeMatch != null) {
      final prefix = youtubeMatch.group(1)!.replaceAll('/vi_webp/', '/vi/');
      for (final name in const [
        'maxresdefault.jpg',
        'sddefault.jpg',
        'hq720.jpg',
        'hqdefault.jpg',
        'mqdefault.jpg',
      ]) {
        add('$prefix$name');
      }
    }

    final ggphtMatch =
        RegExp(r'(https?:\/\/yt3\.ggpht\.com\/[^=]+)')
            .firstMatch(url);
    if (ggphtMatch != null) {
      final base = ggphtMatch.group(1)!;
      add('$base=s544');
      add('$base=s720');
      add('$base=s1200');
    }

    final sizedInPath = RegExp(r'\/(w\d+)-h\d+\/').firstMatch(url);
    if (sizedInPath != null) {
      final upgraded = url.replaceFirst(
          RegExp(r'\/(w\d+)-h\d+\/'), '/w1200-h1200/');
      if (upgraded != url) add(upgraded);
    }

    add(url);
    if (uri?.hasQuery == true) {
      add(clean);
    }
    return urls;
  }
}