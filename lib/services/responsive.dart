import 'package:flutter/widgets.dart';
import 'dart:math' as math;

class Responsive {
  static late MediaQueryData _mediaQueryData;
  static late double screenWidth;
  static late double screenHeight;
  static late double pixelRatio;
  static late double textScaleFactor;

  // Reference design size (using a standard 375x812 as base)
  static const double refWidth = 375;
  static const double refHeight = 812;

  static void init(BuildContext context) {
    _mediaQueryData = MediaQuery.of(context);
    screenWidth = _mediaQueryData.size.width;
    screenHeight = _mediaQueryData.size.height;
    pixelRatio = _mediaQueryData.devicePixelRatio;
    textScaleFactor = _mediaQueryData.textScaleFactor;
  }

  /// The ratio between current screen and design screen (smaller side)
  static double get scale => screenWidth < screenHeight 
      ? screenWidth / refWidth 
      : screenHeight / refHeight;

  /// Width scale
  static double get scaleW => screenWidth / refWidth;
  
  /// Height scale
  static double get scaleH => screenHeight / refHeight;

  /// On desktop/large screens, we don't want things to get too huge
  static double get _cappedScaleW => math.min(scaleW, 1.5);
  static double get _cappedScaleH => math.min(scaleH, 1.5);
  static double get _cappedScale => math.min(scale, 1.5);

  /// Scales width based on screen width
  static double w(double width) => width * _cappedScaleW;

  /// Scales height based on screen height
  static double h(double height) => height * _cappedScaleH;

  /// Scales font size based on width to maintain readability
  static double sp(double fontSize) => fontSize * _cappedScale;

  /// Scales based on the smaller dimension (shortest side) - useful for icons/images
  static double s(double size) => size * _cappedScale;

  /// Returns a percentage of screen width
  static double wp(double percent) => screenWidth * (percent / 100);

  /// Returns a percentage of screen height
  static double hp(double percent) => screenHeight * (percent / 100);

  static bool get isTablet => screenWidth > 600;
  static bool get isDesktop => screenWidth > 900;
  static bool get isLandscape => _mediaQueryData.orientation == Orientation.landscape;
}

extension ResponsiveExtension on num {
  double get w => Responsive.w(toDouble());
  double get h => Responsive.h(toDouble());
  double get sp => Responsive.sp(toDouble());
  double get s => Responsive.s(toDouble());
  double get wp => Responsive.wp(toDouble());
  double get hp => Responsive.hp(toDouble());
}
