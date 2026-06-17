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
    final PerformanceMode effectiveMode;
    if (requestedMode == PerformanceMode.auto) {
      if (reduceMotion) {
        // System accessibility setting takes priority → battery saver
        effectiveMode = PerformanceMode.batterySaver;
      } else if (platform == TargetPlatform.android) {
        // Android defaults to balanced — smooth UI without desktop-level effects
        effectiveMode = PerformanceMode.balanced;
      } else if (platform == TargetPlatform.iOS) {
        // iOS is performant enough for balanced as well
        effectiveMode = PerformanceMode.balanced;
      } else {
        // Desktop: full balanced
        effectiveMode = PerformanceMode.balanced;
      }
    } else {
      effectiveMode = requestedMode;
    }
    return PerformancePolicy._(
      requestedMode: requestedMode,
      effectiveMode: effectiveMode,
      platform: platform,
      reduceMotion: reduceMotion,
      backgroundBlurScale: backgroundBlurScale.clamp(0.0, 2.5).toDouble(),
    );
  }

  bool get isAndroid => platform == TargetPlatform.android;
  bool get isIOS => platform == TargetPlatform.iOS;
  bool get isMobile => isAndroid || isIOS;

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
        return isAndroid ? 4.0 : (isMobile ? 8.0 : 22.0);
      case PerformanceMode.balanced:
        return isAndroid ? 3.0 : (isMobile ? 5.0 : 14.0);
      case PerformanceMode.batterySaver:
        return isAndroid ? 0.0 : (isMobile ? 3.0 : 8.0);
      case PerformanceMode.maxPerformance:
        return 0;
      case PerformanceMode.auto:
        return isAndroid ? 2.0 : (isMobile ? 5.0 : 14.0);
    }
  }

  double get backgroundBlur {
    if (!allowBackdropBlur) return 0;
    final baseBlur = switch (effectiveMode) {
      PerformanceMode.quality => isAndroid ? 8.0 : (isMobile ? 14.0 : 46.0),
      PerformanceMode.balanced => isAndroid ? 5.0 : (isMobile ? 9.0 : 28.0),
      PerformanceMode.batterySaver => isAndroid ? 2.0 : (isMobile ? 6.0 : 10.0),
      PerformanceMode.maxPerformance => 0.0,
      PerformanceMode.auto => isAndroid ? 4.0 : (isMobile ? 8.0 : 28.0),
    };
    final maxBlur = isAndroid ? 10.0 : (isMobile ? 18.0 : 72.0);
    return (baseBlur * backgroundBlurScale).clamp(0.0, maxBlur).toDouble();
  }

  double get particleCountScale {
    if (!allowParticles) return 0;
    switch (effectiveMode) {
      case PerformanceMode.quality:
        return isAndroid ? 0.15 : (isMobile ? 0.35 : 0.85);
      case PerformanceMode.balanced:
        return isAndroid ? 0.0 : (isMobile ? 0.18 : 0.50);
      case PerformanceMode.batterySaver:
      case PerformanceMode.maxPerformance:
        return 0;
      case PerformanceMode.auto:
        return isAndroid ? 0.0 : (isMobile ? 0.22 : 0.65);
    }
  }

  Duration get particleFrameInterval {
    switch (effectiveMode) {
      case PerformanceMode.quality:
        return isMobile
            ? const Duration(milliseconds: 33)
            : const Duration(milliseconds: 16);
      case PerformanceMode.balanced:
        return const Duration(milliseconds: 33);
      case PerformanceMode.batterySaver:
      case PerformanceMode.maxPerformance:
        return const Duration(milliseconds: 1000);
      case PerformanceMode.auto:
        return isMobile
            ? const Duration(milliseconds: 50)
            : const Duration(milliseconds: 33);
    }
  }

  double get coverCacheScale {
    if (kIsWeb) return 1.2;
    switch (effectiveMode) {
      case PerformanceMode.quality:
        return isAndroid ? 2.0 : (isMobile ? 1.7 : 2.6);
      case PerformanceMode.balanced:
        return isAndroid ? 1.7 : (isMobile ? 1.4 : 2.1);
      case PerformanceMode.batterySaver:
        return isAndroid ? 1.3 : (isMobile ? 1.1 : 1.6);
      case PerformanceMode.maxPerformance:
        return isAndroid ? 1.0 : (isMobile ? 0.9 : 1.2);
      case PerformanceMode.auto:
        return isAndroid ? 1.7 : (isMobile ? 1.3 : 2.1);
    }
  }

  double get backgroundCoverCacheScale {
    if (kIsWeb) return 0.6;
    if (isAndroid) return 0.05; // 5% cache scale for background blur on Android -> extremely fast to blur!
    switch (effectiveMode) {
      case PerformanceMode.quality:
        return isMobile ? 0.5 : 0.78;
      case PerformanceMode.balanced:
        return isMobile ? 0.42 : 0.62;
      case PerformanceMode.batterySaver:
        return isMobile ? 0.35 : 0.5;
      case PerformanceMode.maxPerformance:
        return isMobile ? 0.35 : 0.45;
      case PerformanceMode.auto:
        return isMobile ? 0.4 : 0.62;
    }
  }

  double get listCacheExtent {
    if (kIsWeb) {
      return effectiveMode == PerformanceMode.quality ? 360 : 180;
    }
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
        // Extra preload on mobile so fast flings don't show blank tiles
        return isMobile ? 400 : 560;
    }
  }

  FilterQuality resolveFilterQuality(FilterQuality? requested) {
    if (effectiveMode == PerformanceMode.quality) {
      return requested ?? FilterQuality.high;
    }
    if (effectiveMode == PerformanceMode.maxPerformance ||
        effectiveMode == PerformanceMode.batterySaver) {
      return FilterQuality.low;
    }
    if (isAndroid) {
      return requested ?? FilterQuality.high;
    }
    if (requested == FilterQuality.high && isMobile) {
      return FilterQuality.high;
    }
    return requested ?? (isMobile ? FilterQuality.medium : FilterQuality.high);
  }

  Duration animation(Duration base) {
    if (!allowDecorativeAnimations) return Duration.zero;
    final factor = switch (effectiveMode) {
      PerformanceMode.quality => isAndroid ? 0.7 : 1.0,
      PerformanceMode.balanced => isAndroid ? 0.55 : 0.82,
      PerformanceMode.batterySaver => isAndroid ? 0.35 : 0.55,
      PerformanceMode.maxPerformance => 0.0,
      PerformanceMode.auto => isAndroid ? 0.4 : (isMobile ? 0.55 : 0.82),
    };
    return Duration(milliseconds: (base.inMilliseconds * factor).round());
  }
}
