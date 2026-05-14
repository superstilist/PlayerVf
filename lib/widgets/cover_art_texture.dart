import 'dart:io' as io;

import 'package:flutter/material.dart';

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
          child: _NetworkCoverArt(
            url: coverArtPath,
            width: width,
            height: height,
            fallback: _buildDefaultCover(),
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
            gaplessPlayback: true,
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

class _NetworkCoverArt extends StatefulWidget {
  final String url;
  final double width;
  final double height;
  final Widget fallback;

  const _NetworkCoverArt({
    required this.url,
    required this.width,
    required this.height,
    required this.fallback,
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
        gaplessPlayback: true,
        filterQuality: FilterQuality.high,
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
