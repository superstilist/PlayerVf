import 'dart:io' as io;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/performance_policy.dart';

class CoverArtTexture extends StatelessWidget {
  final String coverArtPath;
  final double width;
  final double height;
  final BorderRadius? borderRadius;
  final FilterQuality? filterQuality;
  final double? cacheScale;

  const CoverArtTexture({
    super.key,
    required this.coverArtPath,
    this.width = 200,
    this.height = 200,
    this.borderRadius,
    this.filterQuality,
    this.cacheScale,
  });

  @override
  Widget build(BuildContext context) {
    final policy = PerformancePolicy.of(context);
    final resolvedFilterQuality = policy.resolveFilterQuality(filterQuality);
    final resolvedCacheScale = cacheScale == null
        ? policy.coverCacheScale
        : cacheScale!.clamp(0.75, policy.coverCacheScale);

    if (coverArtPath.isNotEmpty) {
      if (_isBrowserImage(coverArtPath)) {
        return ClipRRect(
          borderRadius: borderRadius ?? BorderRadius.zero,
          child: _NetworkCoverArt(
            url: coverArtPath,
            width: width,
            height: height,
            fallback: _buildDefaultCover(),
            filterQuality: resolvedFilterQuality,
            cacheScale: resolvedCacheScale,
          ),
        );
      }

      if (kIsWeb) {
        return _buildDefaultCover();
      }

      return RepaintBoundary(
        child: ClipRRect(
          borderRadius: borderRadius ?? BorderRadius.zero,
          child: Image.file(
            io.File(coverArtPath),
            width: width,
            height: height,
            cacheWidth: _cacheExtent(width, resolvedCacheScale),
            cacheHeight: _cacheExtent(height, resolvedCacheScale),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: resolvedFilterQuality,
            isAntiAlias: true,
            errorBuilder: (context, error, stackTrace) {
              return _buildDefaultCover();
            },
          ),
        ),
      );
    }

    return _buildDefaultCover();
  }

  bool _isBrowserImage(String path) {
    return path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith('blob:') ||
        path.startsWith('data:image/');
  }

  int? _cacheExtent(double value, double multiplier) {
    if (!value.isFinite || value <= 0) return null;
    return (value * multiplier).clamp(96, 900).round();
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
    return (value * multiplier).clamp(96, 900).round();
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

    final clean = url.split('?').first;
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

    add(url);
    add(clean);
    return urls;
  }
}
