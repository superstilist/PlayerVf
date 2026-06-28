import 'dart:ui' show ImageFilter;

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
    final effectiveBlur = (blur * (0.38 + 0.22 * intensity)).clamp(0.0, 18.0);
    final effectiveBorder = border ??
        Border.all(
          color: borderColor,
          width: 1,
        );

    final decoration = BoxDecoration(
      color: effectiveColor,
      borderRadius: borderRadius,
      border: effectiveBorder,
      boxShadow: effectiveBlur > 0
          ? [
              BoxShadow(
                color: borderColor.withValues(alpha: 0.18 + 0.10 * intensity),
                blurRadius: effectiveBlur * 1.55,
                spreadRadius: -effectiveBlur * 0.32,
              ),
              BoxShadow(
                color: theme.colorScheme.shadow.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.18 : 0.08),
                blurRadius: effectiveBlur * 0.9,
                spreadRadius: -effectiveBlur * 0.55,
                offset: const Offset(0, 4),
              ),
            ]
          : null,
    );

    final content = Container(
      padding: padding,
      decoration: decoration,
      child: child,
    );

    if (effectiveBlur <= 0) {
      return Container(
        width: width,
        height: height,
        margin: margin,
        child: content,
      );
    }

    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: borderColor.withValues(alpha: 0.16 + 0.12 * intensity),
            blurRadius: effectiveBlur * 1.7,
            spreadRadius: -effectiveBlur * 0.35,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: effectiveBlur,
            sigmaY: effectiveBlur,
          ),
          child: content,
        ),
      ),
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
