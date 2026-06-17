import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

class CoverArtPalette {
  final Color dominant;
  final Color accent;
  final Color text;
  final Color subduedText;
  final Color backgroundStart;
  final Color backgroundMid;
  final Color vibrant;
  final Color muted;
  final Color darkVibrant;
  final Color lightVibrant;
  final List<Color> orbColors;

  const CoverArtPalette({
    required this.dominant,
    required this.accent,
    required this.text,
    required this.subduedText,
    required this.backgroundStart,
    required this.backgroundMid,
    this.vibrant = Colors.teal,
    this.muted = Colors.teal,
    this.darkVibrant = Colors.teal,
    this.lightVibrant = Colors.teal,
    this.orbColors = const [],
  });
}

class CoverColorService {
  static final Map<String, Future<CoverArtPalette>> _cache = {};
  static const CoverArtPalette fallbackPalette = CoverArtPalette(
    dominant: Color(0xFF00BCD4),
    accent: Color(0xFF5FE0C4),
    text: Colors.white,
    subduedText: Color(0xB3FFFFFF),
    backgroundStart: Color(0xFF0E1718),
    backgroundMid: Color(0xFF143333),
    vibrant: Color(0xFF00E5FF),
    muted: Color(0xFF80DEEA),
    darkVibrant: Color(0xFF00838F),
    lightVibrant: Color(0xFF84FFFF),
    orbColors: [
      Color(0xFF00BCD4),
      Color(0xFF5FE0C4),
      Color(0xFF00E5FF),
      Color(0xFF00838F),
      Color(0xFF84FFFF),
    ],
  );

  static Future<CoverArtPalette> fromPath(String? path, {int paletteSize = 4}) {
    final key = '${path?.trim() ?? ''}:::$paletteSize';
    return _cache.putIfAbsent(key, () => _loadPalette(path?.trim() ?? '', paletteSize));
  }

  static Future<CoverArtPalette> _loadPalette(String path, int paletteSize) async {
    final clampedSize = paletteSize.clamp(2, 5);
    if (path.isEmpty) return _buildDefaultPalette(clampedSize);

    PaletteGenerator palette;
    if (_isNetworkPalettePath(path)) {
      try {
        palette = await PaletteGenerator.fromImageProvider(
          NetworkImage(path),
          maximumColorCount: 32,
          size: const Size(160, 160),
        );
      } catch (_) {
        return _buildDefaultPalette(clampedSize);
      }
    } else if (!kIsWeb) {
      final file = File(path);
      if (!file.existsSync()) return _buildDefaultPalette(clampedSize);
      try {
        palette = await PaletteGenerator.fromImageProvider(
          FileImage(file),
          maximumColorCount: 32,
          size: const Size(160, 160),
        );
      } catch (_) {
        return _buildDefaultPalette(clampedSize);
      }
    } else {
      return _buildDefaultPalette(clampedSize);
    }

    final dominant = palette.dominantColor?.color ??
        palette.vibrantColor?.color ??
        palette.mutedColor?.color ??
        Colors.teal;
    final accent = palette.vibrantColor?.color ??
        palette.lightVibrantColor?.color ??
        _shiftLightness(dominant, 0.18);
    final vibrant = palette.vibrantColor?.color ?? dominant;
    final muted = palette.mutedColor?.color ?? _desaturate(dominant, 0.3);
    final darkVibrant = palette.darkVibrantColor?.color ?? _shiftLightness(dominant, -0.15);
    final lightVibrant = palette.lightVibrantColor?.color ?? _shiftLightness(dominant, 0.25);

    final List<Color> candidateColors = [];
    candidateColors.add(_saturate(dominant, 0.2));
    if (vibrant != dominant) candidateColors.add(_saturate(vibrant, 0.35));
    if (accent != dominant && accent != vibrant) candidateColors.add(_saturate(accent, 0.35));
    if (darkVibrant != dominant) candidateColors.add(_saturate(darkVibrant, 0.35));
    if (lightVibrant != dominant) candidateColors.add(_saturate(lightVibrant, 0.35));
    if (muted != dominant && muted != vibrant) candidateColors.add(_saturate(muted, 0.15));

    for (final color in palette.colors) {
      if (candidateColors.length < clampedSize * 4) {
        final saturated = _saturate(color, 0.25);
        bool isDuplicate = false;
        for (final existing in candidateColors) {
          if (_colorDistance(saturated, existing) < 0.12) {
            isDuplicate = true;
            break;
          }
        }
        if (!isDuplicate) candidateColors.add(saturated);
      }
    }

    final orbColors = _extractDominantPalette(candidateColors, clampedSize);

    return _fromColor(
      dominant,
      accent: accent,
      vibrant: vibrant,
      muted: muted,
      darkVibrant: darkVibrant,
      lightVibrant: lightVibrant,
      orbColors: orbColors,
    );
  }

  static List<Color> _extractDominantPalette(List<Color> candidates, int targetCount) {
    if (candidates.isEmpty) return _defaultOrbPalette(targetCount);
    if (candidates.length <= targetCount) {
      return candidates.map((c) => _boostVibrancy(c)).toList();
    }

    final rgbPixels = candidates.map((c) => [
      c.red.toDouble(),
      c.green.toDouble(),
      c.blue.toDouble(),
    ]).toList();

    final clusters = _kMeans(rgbPixels, targetCount, maxIterations: 15);

    final List<Color> dominantColors = clusters.map((centroid) {
      return _boostVibrancy(Color.fromARGB(
        255,
        centroid[0].round().clamp(0, 255),
        centroid[1].round().clamp(0, 255),
        centroid[2].round().clamp(0, 255),
      ));
    }).toList();

    final balanced = _enforceMinColorDistance(dominantColors, 0.18);
    if (balanced.length < targetCount) {
      while (balanced.length < targetCount) {
        final base = balanced[balanced.length % max(1, balanced.length - 1)];
        final hsl = HSLColor.fromColor(base);
        final shifted = hsl.withHue((hsl.hue + 40) % 360).toColor();
        if (_minDistanceFromList(shifted, balanced) > 0.15) {
          balanced.add(shifted);
        } else {
          final alt = hsl.withSaturation((hsl.saturation + 0.2).clamp(0.0, 1.0)).toColor();
          balanced.add(alt);
        }
      }
    }

    return balanced.take(targetCount).toList();
  }

  static List<List<double>> _kMeans(List<List<double>> pixels, int k, {int maxIterations = 15}) {
    if (pixels.length <= k) return List<List<double>>.from(pixels.map((p) => List<double>.from(p)));

    final rng = Random(42);
    final centroids = <List<double>>[];
    final usedIndices = <int>{};

    for (int i = 0; i < k; i++) {
      int idx;
      do {
        idx = rng.nextInt(pixels.length);
      } while (usedIndices.contains(idx));
      usedIndices.add(idx);
      centroids.add(List<double>.from(pixels[idx]));
    }

    List<int> assignments = List.filled(pixels.length, 0);

    for (int iter = 0; iter < maxIterations; iter++) {
      bool changed = false;

      for (int i = 0; i < pixels.length; i++) {
        int bestCluster = 0;
        double bestDist = double.infinity;
        for (int c = 0; c < k; c++) {
          final dist = _euclideanDist(pixels[i], centroids[c]);
          if (dist < bestDist) {
            bestDist = dist;
            bestCluster = c;
          }
        }
        if (assignments[i] != bestCluster) {
          assignments[i] = bestCluster;
          changed = true;
        }
      }

      if (!changed) break;

      for (int c = 0; c < k; c++) {
        final assignedPixels = <List<double>>[];
        for (int i = 0; i < pixels.length; i++) {
          if (assignments[i] == c) assignedPixels.add(pixels[i]);
        }
        if (assignedPixels.isNotEmpty) {
          centroids[c] = _meanVector(assignedPixels);
        }
      }
    }

    return centroids;
  }

  static double _euclideanDist(List<double> a, List<double> b) {
    double sum = 0;
    for (int i = 0; i < min(a.length, b.length); i++) {
      final diff = a[i] - b[i];
      sum += diff * diff;
    }
    return sqrt(sum);
  }

  static List<double> _meanVector(List<List<double>> vectors) {
    final dim = vectors.first.length;
    final sums = List<double>.filled(dim, 0.0);
    for (final v in vectors) {
      for (int i = 0; i < min(dim, v.length); i++) {
        sums[i] += v[i];
      }
    }
    return sums.map((s) => s / vectors.length).toList();
  }

  static List<Color> _enforceMinColorDistance(List<Color> colors, double minDist) {
    final result = <Color>[];
    for (final c in colors) {
      if (result.isEmpty || _minDistanceFromList(c, result) >= minDist) {
        result.add(c);
      }
    }
    return result;
  }

  static double _minDistanceFromList(Color color, List<Color> others) {
    double minDist = double.infinity;
    for (final other in others) {
      final d = _colorDistance(color, other);
      if (d < minDist) minDist = d;
    }
    return minDist;
  }

  static Color _boostVibrancy(Color color) {
    final hsl = HSLColor.fromColor(color);
    final boostedSat = (hsl.saturation * 1.2).clamp(0.0, 1.0);
    final boostedLight = (hsl.lightness + 0.05).clamp(0.1, 0.85);
    return hsl.withSaturation(boostedSat).withLightness(boostedLight).toColor();
  }

  static List<Color> _defaultOrbPalette(int count) {
    const defaults = [
      Color(0xFF00BCD4),
      Color(0xFF5FE0C4),
      Color(0xFF00E5FF),
      Color(0xFF00838F),
      Color(0xFF84FFFF),
    ];
    return defaults.take(count.clamp(2, 5)).toList();
  }

  static CoverArtPalette _buildDefaultPalette(int size) {
    return CoverArtPalette(
      dominant: fallbackPalette.dominant,
      accent: fallbackPalette.accent,
      text: fallbackPalette.text,
      subduedText: fallbackPalette.subduedText,
      backgroundStart: fallbackPalette.backgroundStart,
      backgroundMid: fallbackPalette.backgroundMid,
      vibrant: fallbackPalette.vibrant,
      muted: fallbackPalette.muted,
      darkVibrant: fallbackPalette.darkVibrant,
      lightVibrant: fallbackPalette.lightVibrant,
      orbColors: _defaultOrbPalette(size),
    );
  }

  static bool _isNetworkPalettePath(String path) {
    return path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith('blob:') ||
        path.startsWith('data:image/');
  }

  static CoverArtPalette _fromColor(
    Color dominant, {
    Color? accent,
    Color? vibrant,
    Color? muted,
    Color? darkVibrant,
    Color? lightVibrant,
    List<Color> orbColors = const [],
  }) {
    final base = _saturate(dominant, 0.18);
    final action = accent ?? _shiftLightness(base, 0.16);
    final luminance = base.computeLuminance();
    final text = luminance > 0.45 ? Colors.black : Colors.white;
    final subduedText = text.withOpacity(0.68);
    final backgroundStart = _mix(base, const Color(0xFF081012), 0.82);
    final backgroundMid = _mix(action, const Color(0xFF10181B), 0.60);
    return CoverArtPalette(
      dominant: base,
      accent: action,
      text: text,
      subduedText: subduedText,
      backgroundStart: backgroundStart,
      backgroundMid: backgroundMid,
      vibrant: _saturate(vibrant ?? base, 0.35),
      muted: muted ?? _desaturate(base, 0.3),
      darkVibrant: _saturate(darkVibrant ?? _shiftLightness(base, -0.15), 0.35),
      lightVibrant: _saturate(lightVibrant ?? _shiftLightness(base, 0.25), 0.35),
      orbColors: orbColors,
    );
  }

  static Color _mix(Color a, Color b, double amount) {
    return Color.lerp(a, b, amount) ?? a;
  }

  static Color _shiftLightness(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    final next = (hsl.lightness + amount).clamp(0.0, 1.0);
    return hsl.withLightness(next).toColor();
  }

  static Color _saturate(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    final next = (hsl.saturation + amount).clamp(0.0, 1.0);
    return hsl.withSaturation(next).toColor();
  }

  static Color _desaturate(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    final next = (hsl.saturation - amount).clamp(0.0, 1.0);
    return hsl.withSaturation(next).toColor();
  }

  static double _colorDistance(Color a, Color b) {
    final dr = (a.r - b.r) / 255.0;
    final dg = (a.g - b.g) / 255.0;
    final db = (a.b - b.b) / 255.0;
    return sqrt(dr * dr + dg * dg + db * db);
  }
}
