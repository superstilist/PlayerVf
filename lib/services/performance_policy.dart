import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/settings_model.dart';

class PerformancePolicy {
  final PerformanceMode requestedMode;
  final PerformanceMode effectiveMode;
  final TargetPlatform platform;
  final bool reduceMotion;
  final double backgroundBlurScale;

  const PerformancePolicy._({
    required this.requestedMode,
    required this.effectiveMode,
    required this.platform,
    required this.reduceMotion,
    required this.backgroundBlurScale,
  });

  factory PerformancePolicy.of(BuildContext context) {
    final settings = Provider.of<SettingsModel>(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations == true;
    return PerformancePolicy.from(
      requestedMode: settings.performanceMode,
      platform: defaultTargetPlatform,
      reduceMotion: reduceMotion,
      backgroundBlurScale: settings.backgroundBlurScale,
    );
  }

  factory PerformancePolicy.from({
    required PerformanceMode requestedMode,
    required TargetPlatform platform,
    required bool reduceMotion,
    double backgroundBlurScale = 1.0,
  }) {
    final isAndroid = platform == TargetPlatform.android;
    final effectiveMode = requestedMode == PerformanceMode.auto
        ? reduceMotion || isAndroid
            ? PerformanceMode.batterySaver
            : PerformanceMode.balanced
        : requestedMode;
    return PerformancePolicy._(
      requestedMode: requestedMode,
      effectiveMode: effectiveMode,
      platform: platform,
      reduceMotion: reduceMotion,
      backgroundBlurScale: backgroundBlurScale.clamp(0.0, 2.5).toDouble(),
    );
  }

  bool get isAndroid => platform == TargetPlatform.android;

  bool get allowDecorativeAnimations =>
      !reduceMotion && effectiveMode != PerformanceMode.maxPerformance;

  bool get allowParticles =>
      allowDecorativeAnimations &&
      effectiveMode != PerformanceMode.maxPerformance &&
      effectiveMode != PerformanceMode.batterySaver;

  bool get allowBackdropBlur =>
      !reduceMotion && effectiveMode != PerformanceMode.maxPerformance;

  double get maxGlassBlur {
    if (!allowBackdropBlur) return 0;
    switch (effectiveMode) {
      case PerformanceMode.quality:
        return isAndroid ? 2.5 : 8.0;
      case PerformanceMode.balanced:
        return isAndroid ? 1.5 : 4.0;
      case PerformanceMode.batterySaver:
        return isAndroid ? 0.5 : 1.5;
      case PerformanceMode.maxPerformance:
        return 0;
      case PerformanceMode.auto:
        return isAndroid ? 1.5 : 4.0;
    }
  }

  double get backgroundBlur {
    if (!allowBackdropBlur) return 0;
    final baseBlur = switch (effectiveMode) {
      PerformanceMode.quality => isAndroid ? 10.0 : 38.0,
      PerformanceMode.balanced => isAndroid ? 6.0 : 20.0,
      PerformanceMode.batterySaver => isAndroid ? 1.5 : 6.0,
      PerformanceMode.maxPerformance => 0.0,
      PerformanceMode.auto => isAndroid ? 6.0 : 20.0,
    };
    final maxBlur = isAndroid ? 24.0 : 64.0;
    return (baseBlur * backgroundBlurScale).clamp(0.0, maxBlur).toDouble();
  }

  double get particleCountScale {
    if (!allowParticles) return 0;
    switch (effectiveMode) {
      case PerformanceMode.quality:
        return isAndroid ? 0.45 : 0.85;
      case PerformanceMode.balanced:
        return isAndroid ? 0.28 : 0.50;
      case PerformanceMode.batterySaver:
      case PerformanceMode.maxPerformance:
        return 0;
      case PerformanceMode.auto:
        return isAndroid ? 0.35 : 0.65;
    }
  }

  Duration get particleFrameInterval {
    switch (effectiveMode) {
      case PerformanceMode.quality:
        return isAndroid
            ? const Duration(milliseconds: 33)
            : const Duration(milliseconds: 16);
      case PerformanceMode.balanced:
        return const Duration(milliseconds: 33);
      case PerformanceMode.batterySaver:
      case PerformanceMode.maxPerformance:
        return const Duration(milliseconds: 1000);
      case PerformanceMode.auto:
        return isAndroid
            ? const Duration(milliseconds: 50)
            : const Duration(milliseconds: 33);
    }
  }

  double get coverCacheScale {
    switch (effectiveMode) {
      case PerformanceMode.quality:
        return isAndroid ? 1.55 : 2.2;
      case PerformanceMode.balanced:
        return isAndroid ? 1.25 : 1.7;
      case PerformanceMode.batterySaver:
        return isAndroid ? 1.0 : 1.25;
      case PerformanceMode.maxPerformance:
        return isAndroid ? 0.85 : 1.0;
      case PerformanceMode.auto:
        return isAndroid ? 1.0 : 1.7;
    }
  }

  double get listCacheExtent {
    switch (effectiveMode) {
      case PerformanceMode.quality:
        return 700;
      case PerformanceMode.balanced:
        return 560;
      case PerformanceMode.batterySaver:
        return 360;
      case PerformanceMode.maxPerformance:
        return 260;
      case PerformanceMode.auto:
        return isAndroid ? 360 : 560;
    }
  }

  FilterQuality resolveFilterQuality(FilterQuality? requested) {
    if (effectiveMode == PerformanceMode.quality) {
      return requested ??
          (isAndroid ? FilterQuality.medium : FilterQuality.high);
    }
    if (effectiveMode == PerformanceMode.maxPerformance ||
        effectiveMode == PerformanceMode.batterySaver) {
      return FilterQuality.low;
    }
    if (requested == FilterQuality.high && isAndroid) {
      return FilterQuality.medium;
    }
    return requested ?? (isAndroid ? FilterQuality.low : FilterQuality.medium);
  }

  Duration animation(Duration base) {
    if (!allowDecorativeAnimations) return Duration.zero;
    final factor = switch (effectiveMode) {
      PerformanceMode.quality => 1.0,
      PerformanceMode.balanced => 0.82,
      PerformanceMode.batterySaver => 0.55,
      PerformanceMode.maxPerformance => 0.0,
      PerformanceMode.auto => isAndroid ? 0.55 : 0.82,
    };
    return Duration(milliseconds: (base.inMilliseconds * factor).round());
  }
}
