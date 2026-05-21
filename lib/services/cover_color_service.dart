import 'dart:io';

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

  const CoverArtPalette({
    required this.dominant,
    required this.accent,
    required this.text,
    required this.subduedText,
    required this.backgroundStart,
    required this.backgroundMid,
  });
}

class CoverColorService {
  static final Map<String, Future<CoverArtPalette>> _cache = {};
  static const CoverArtPalette fallbackPalette = CoverArtPalette(
    dominant: Colors.teal,
    accent: Color(0xFF5FE0C4),
    text: Colors.white,
    subduedText: Color(0xB3FFFFFF),
    backgroundStart: Color(0xFF0E1718),
    backgroundMid: Color(0xFF143333),
  );

  static Future<CoverArtPalette> fromPath(String? path) {
    final key = path?.trim() ?? '';
    return _cache.putIfAbsent(key, () => _loadPalette(key));
  }

  static Future<CoverArtPalette> _loadPalette(String path) async {
    const fallback = fallbackPalette;
    if (path.isEmpty) {
      return fallback;
    }

    if (_isNetworkPalettePath(path)) {
      try {
        final palette = await PaletteGenerator.fromImageProvider(
          NetworkImage(path),
          maximumColorCount: 12,
          size: const Size(160, 160),
        );
        final dominant = palette.dominantColor?.color ??
            palette.vibrantColor?.color ??
            palette.mutedColor?.color ??
            Colors.teal;
        final accent = palette.vibrantColor?.color ??
            palette.lightVibrantColor?.color ??
            _shiftLightness(dominant, 0.18);
        return _fromColor(dominant, accent: accent);
      } catch (_) {
        return fallback;
      }
    }

    if (kIsWeb) {
      return fallback;
    }

    final file = File(path);
    if (!file.existsSync()) {
      return fallback;
    }

    try {
      final palette = await PaletteGenerator.fromImageProvider(
        FileImage(file),
        maximumColorCount: 12,
        size: const Size(160, 160),
      );

      final dominant = palette.dominantColor?.color ??
          palette.vibrantColor?.color ??
          palette.mutedColor?.color ??
          Colors.teal;
      final accent = palette.vibrantColor?.color ??
          palette.lightVibrantColor?.color ??
          _shiftLightness(dominant, 0.18);

      return _fromColor(dominant, accent: accent);
    } catch (_) {
      return fallback;
    }
  }

  static bool _isNetworkPalettePath(String path) {
    return path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith('blob:') ||
        path.startsWith('data:image/');
  }

  static CoverArtPalette _fromColor(Color dominant, {Color? accent}) {
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
}
