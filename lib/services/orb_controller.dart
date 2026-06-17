import 'dart:math';

import 'package:flutter/material.dart';

class OrbController extends ChangeNotifier {
  static final OrbController instance = OrbController._();
  OrbController._();

  static const double _twoPi = pi * 2;
  // lerp factor per second: dt * 0.5 → 95% in ~3s, 99% in ~7s
  static const double _colorLerpPerSec = 0.5;

  final List<OrbData> _orbs = [];
  double _timeSec = 0;
  Size _bounds = Size.zero;
  bool _initialized = false;
  double _shortestSide = 0;

  double _sizeMultiplier = 1.5;
  double _speedMultiplier = 1.0;

  List<Color> _targetColors = [Colors.teal];
  List<Color> _currentColors = [Colors.teal];

  List<OrbData> get orbs => _orbs;
  double get timeSec => _timeSec;

  void setColors(List<Color> colors) {
    if (colors.isEmpty) return;
    _targetColors = colors;
    if (_currentColors.length != _targetColors.length) {
      _currentColors = List<Color>.from(_targetColors);
    }
    _assignOrbColors();
  }

  void setSizeMultiplier(double multiplier) {
    final clamped = multiplier.clamp(0.5, 3.0);
    if ((_sizeMultiplier - clamped).abs() > 0.01) {
      _sizeMultiplier = clamped;
      if (_initialized) _applySizeMultiplier();
      notifyListeners();
    }
  }

  void setSpeedMultiplier(double multiplier) {
    final clamped = multiplier.clamp(0.2, 3.0);
    if ((_speedMultiplier - clamped).abs() > 0.01) {
      _speedMultiplier = clamped;
      if (_initialized) _applySpeedMultiplier();
      notifyListeners();
    }
  }

  void _applySizeMultiplier() {
    final rng = Random();
    for (final o in _orbs) {
      o.size = (rng.nextDouble() * 30 + 45) * _sizeMultiplier;
    }
  }

  void _applySpeedMultiplier() {
    final minSpd = _shortestSide * 0.03 * _speedMultiplier;
    final maxSpd = _shortestSide * 0.07 * _speedMultiplier;
    final rng = Random();
    for (final o in _orbs) {
      final speed = (rng.nextDouble() * (maxSpd - minSpd) + minSpd);
      o.speedX = speed * (o.speedX >= 0 ? 1 : -1);
      o.speedY = speed * (o.speedY >= 0 ? 1 : -1);
    }
  }

  void tick(double dt) {
    if (_orbs.isEmpty) return;
    _timeSec += dt;

    final lerpFactor = dt * _colorLerpPerSec;
    for (int i = 0; i < _currentColors.length && i < _targetColors.length; i++) {
      _currentColors[i] = Color.lerp(_currentColors[i], _targetColors[i], lerpFactor) ?? _targetColors[i];
    }

    final margin = _shortestSide * 0.15;
    final wobbleAmp = _shortestSide * 0.018;

    for (final o in _orbs) {
      o.x += (o.speedX + sin(_timeSec * o.freqX * _twoPi + o.phaseX) * wobbleAmp) * dt;
      o.y += (o.speedY + cos(_timeSec * o.freqY * _twoPi + o.phaseY) * wobbleAmp) * dt;
      o.rotation += o.rotationSpeed * dt;

      final breath = sin(_timeSec * (o.freqX * 0.2) * _twoPi + o.phaseX);
      o.scale = 1.0 + breath * 0.12;
      o.opacity = ((0.50 + breath * 0.08) * o.intensity).clamp(0.0, 1.0);

      o.currentColor = Color.lerp(o.currentColor, o.targetColor, lerpFactor) ?? o.targetColor;

      if (o.x < -margin) {
        o.x = -margin;
        o.speedX = o.speedX.abs();
      } else if (o.x > _bounds.width + margin) {
        o.x = _bounds.width + margin;
        o.speedX = -o.speedX.abs();
      }
      if (o.y < -margin) {
        o.y = -margin;
        o.speedY = o.speedY.abs();
      } else if (o.y > _bounds.height + margin) {
        o.y = _bounds.height + margin;
        o.speedY = -o.speedY.abs();
      }
    }
    notifyListeners();
  }

  Color orbColor(int index) {
    if (_currentColors.isEmpty) return Colors.teal;
    return _currentColors[index % _currentColors.length];
  }

  void updateBounds(Size bounds) {
    if (bounds == _bounds || bounds.shortestSide == 0) return;
    _bounds = bounds;
    _shortestSide = bounds.shortestSide;
    if (!_initialized) _initOrbs();
  }

  void setIntensity(double intensity) {
    for (final o in _orbs) {
      o.intensity = intensity;
    }
  }

  void _assignOrbColors() {
    if (_orbs.isEmpty || _targetColors.isEmpty) return;
    final colorCount = _targetColors.length;
    for (int i = 0; i < _orbs.length; i++) {
      final colorIdx = i % colorCount;
      _orbs[i].targetColor = _targetColors[colorIdx];
      _orbs[i].currentColor ??= _targetColors[colorIdx];
    }
  }

  void _initOrbs() {
    _initialized = true;
    _orbs.clear();
    final rng = Random();
    final count = _bounds.width < 600 ? 6 : 7;
    final minSpd = _shortestSide * 0.03 * _speedMultiplier;
    final maxSpd = _shortestSide * 0.07 * _speedMultiplier;
    for (int i = 0; i < count; i++) {
      _orbs.add(OrbData()
        ..x = rng.nextDouble() * _bounds.width
        ..y = rng.nextDouble() * _bounds.height
        ..speedX = (rng.nextDouble() * (maxSpd - minSpd) + minSpd) * (rng.nextBool() ? 1 : -1)
        ..speedY = (rng.nextDouble() * (maxSpd - minSpd) + minSpd) * (rng.nextBool() ? 1 : -1)
        ..phaseX = rng.nextDouble() * _twoPi
        ..phaseY = rng.nextDouble() * _twoPi
        ..freqX = rng.nextDouble() * 0.06 + 0.02
        ..freqY = rng.nextDouble() * 0.06 + 0.02
        ..size = (rng.nextDouble() * 30 + 45) * _sizeMultiplier
        ..opacity = rng.nextDouble() * 0.40 + 0.30
        ..rotation = rng.nextDouble() * _twoPi
        ..rotationSpeed = (rng.nextDouble() - 0.5) * 0.03
        ..aspectRatio = rng.nextDouble() * 0.30 + 0.70
        ..intensity = 1.0);
    }
    _assignOrbColors();
  }
}

class OrbData {
  double x = 0, y = 0, size = 5;
  double speedX = 0, speedY = 0;
  double opacity = 0.3, rotation = 0, rotationSpeed = 0, scale = 1.0, intensity = 1.0;
  double phaseX = 0, phaseY = 0, freqX = 0.15, freqY = 0.12;
  double aspectRatio = 0.8;
  Color? currentColor;
  Color? targetColor;
}
