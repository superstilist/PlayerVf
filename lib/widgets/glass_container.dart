import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/settings_model.dart';
import '../services/performance_policy.dart';

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final BorderRadiusGeometry borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final double blur;
  final Border? border;

  const GlassContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.padding,
    this.margin,
    this.color,
    this.blur = 0.0, // Default to 0 for flat aesthetic
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final policy = PerformancePolicy.of(context);
    final intensity = context.select<SettingsModel, double>(
      (settings) => settings.glassEffect.clamp(0.0, 1.0),
    );
    final fallbackColor = _surfaceColor(theme, intensity);
    final borderColor = theme.colorScheme.outlineVariant.withOpacity(
      theme.brightness == Brightness.dark
          ? 0.18 + (0.22 * intensity)
          : 0.24 + (0.22 * intensity),
    );
    final guiBlur = policy.allowBackdropBlur
        ? (blur * intensity).clamp(0.0, policy.maxGlassBlur)
        : 0.0;
    final effectiveColor = color == null
        ? fallbackColor
        : Color.lerp(fallbackColor, color!, 0.15 + (0.60 * intensity)) ??
            fallbackColor;

    final innerContainer = Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: effectiveColor,
        borderRadius: borderRadius,
        border: border ??
            Border.all(
              color: borderColor,
              width: 0.7,
            ),
      ),
      child: child,
    );

    return Container(
      width: width,
      height: height,
      margin: margin,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: guiBlur > 0
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: guiBlur, sigmaY: guiBlur),
                child: innerContainer,
              )
            : innerContainer,
      ),
    );
  }

  Color _surfaceColor(ThemeData theme, double intensity) {
    final base = theme.brightness == Brightness.dark
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.surfaceContainerLow;

    // 0 = flat/readable solid surface. 100 = glassy but still visible.
    final opacity = theme.brightness == Brightness.dark
        ? 0.90 - (0.36 * intensity)
        : 0.96 - (0.28 * intensity);

    return base.withOpacity(opacity.clamp(0.54, 0.96));
  }
}
