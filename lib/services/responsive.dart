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

  static double get scale {
    final base = isLandscape ? screenHeight / refWidth : screenWidth / refWidth;
    return _clampScale(base, min: 0.82, max: _maxScale);
  }

  static double get scaleW {
    final usableWidth = isDesktop ? math.min(screenWidth, 760.0) : screenWidth;
    final raw = usableWidth / refWidth;
    return _clampScale((raw * 0.72) + (scale * 0.28),
        min: 0.84, max: _maxScale);
  }

  static double get scaleH {
    final usableHeight =
        isDesktop ? math.min(screenHeight, 920.0) : screenHeight;
    final raw = usableHeight / refHeight;
    return _clampScale((raw * 0.55) + (scale * 0.45),
        min: 0.78, max: _maxScale);
  }

  static double get _maxScale => isDesktop
      ? 1.28
      : isTablet
          ? 1.18
          : 1.10;
  static double _clampScale(double value,
          {required double min, required double max}) =>
      value.clamp(min, max).toDouble();

  static double w(double width) => width * scaleW;

  static double h(double height) => height * scaleH;

  static double sp(double fontSize) => fontSize * scale * globalFontSizeFactor;

  static double s(double size) => size * scale;

  static double wp(double percent) => screenWidth * (percent / 100);

  static double hp(double percent) => screenHeight * (percent / 100);

  static double get listArtSize {
    final base = isDesktop ? 64.0 : 56.0;
    final scaled = base * scale;
    return scaled.clamp(52.0, 68.0).toDouble();
  }

  static double get listArtRadius => (listArtSize * 0.22).clamp(8.0, 14.0);

  static bool get isTablet => shortestSide >= 600;
  static bool get isPhone => !isTablet;
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
  double get listArt => Responsive.listArtSize;
  double get listArtR => Responsive.listArtRadius;
}
