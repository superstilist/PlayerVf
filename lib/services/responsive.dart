import 'package:flutter/widgets.dart';
import 'dart:math' as math;

class Responsive {
  static late MediaQueryData _mediaQueryData;
  static late double screenWidth;
  static late double screenHeight;
  static late double pixelRatio;
  static late double shortestSide;
  static late double longestSide;
  static double globalFontSizeFactor = 1.0;

  // Reference design size (using a standard 375x812 as base)
  static const double refWidth = 375;
  static const double refHeight = 812;

  static void init(BuildContext context) {
    _mediaQueryData = MediaQuery.of(context);
    screenWidth = _mediaQueryData.size.width;
    screenHeight = _mediaQueryData.size.height;
    pixelRatio = _mediaQueryData.devicePixelRatio;
    shortestSide = math.min(screenWidth, screenHeight);
    longestSide = math.max(screenWidth, screenHeight);
  }

  /// The ratio between current screen and design screen (smaller side)
  static double get scale {
    final base = isLandscape ? screenHeight / refWidth : screenWidth / refWidth;
    return _clampScale(base, min: 0.82, max: _maxScale);
  }

  /// Width scale
  static double get scaleW {
    final usableWidth = isDesktop ? math.min(screenWidth, 760.0) : screenWidth;
    final raw = usableWidth / refWidth;
    return _clampScale((raw * 0.72) + (scale * 0.28),
        min: 0.84, max: _maxScale);
  }

  /// Height scale
  static double get scaleH {
    final usableHeight =
        isDesktop ? math.min(screenHeight, 920.0) : screenHeight;
    final raw = usableHeight / refHeight;
    return _clampScale((raw * 0.55) + (scale * 0.45),
        min: 0.78, max: _maxScale);
  }

  /// On desktop/large screens, keep UI comfortable instead of oversized.
  static double get _maxScale => isDesktop ? 1.28 : 1.18;
  static double _clampScale(double value,
          {required double min, required double max}) =>
      value.clamp(min, max).toDouble();

  /// Scales width based on screen width
  static double w(double width) => width * scaleW;

  /// Scales height based on screen height
  static double h(double height) => height * scaleH;

  /// Scales font size based on width to maintain readability
  static double sp(double fontSize) => fontSize * scale * globalFontSizeFactor;

  /// Scales based on the smaller dimension (shortest side) - useful for icons/images
  static double s(double size) => size * scale;

  /// Returns a percentage of screen width
  static double wp(double percent) => screenWidth * (percent / 100);

  /// Returns a percentage of screen height
  static double hp(double percent) => screenHeight * (percent / 100);

  static bool get isTablet => screenWidth > 600;
  static bool get isDesktop => screenWidth > 900;
  static bool get isLandscape =>
      _mediaQueryData.orientation == Orientation.landscape;
  static bool get isCompact => shortestSide < 360 || screenHeight < 560;
}

extension ResponsiveExtension on num {
  double get w => Responsive.w(toDouble());
  double get h => Responsive.h(toDouble());
  double get sp => Responsive.sp(toDouble());
  double get s => Responsive.s(toDouble());
  double get wp => Responsive.wp(toDouble());
  double get hp => Responsive.hp(toDouble());
}
