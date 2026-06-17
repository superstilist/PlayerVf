import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/settings_model.dart';

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
    this.blur = 0.0,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final intensity = context.select<SettingsModel, double>(
      (settings) => settings.glassEffect.clamp(0.0, 1.0),
    );
    final fallbackColor = _surfaceColor(theme, intensity);
    final borderColor = theme.colorScheme.outlineVariant.withOpacity(
      theme.brightness == Brightness.dark
          ? 0.40 + (0.10 * intensity)
          : 0.54 + (0.10 * intensity),
    );
    final effectiveColor = color == null
        ? fallbackColor
        : Color.alphaBlend(color!.withOpacity(0.18), fallbackColor);

    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: effectiveColor,
        borderRadius: borderRadius,
        border: border ??
            Border.all(
              color: borderColor,
              width: 1,
            ),
      ),
      child: child,
    );
  }

  Color _surfaceColor(ThemeData theme, double intensity) {
    final base = theme.brightness == Brightness.dark
        ? theme.colorScheme.surfaceContainerHigh
        : theme.colorScheme.surfaceContainerLowest;

    final opacity = theme.brightness == Brightness.dark
        ? 0.94 - (0.10 * intensity)
        : 0.98 - (0.08 * intensity);

    return base.withOpacity(opacity.clamp(0.84, 0.99));
  }
}
