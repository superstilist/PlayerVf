import 'dart:math';
import 'package:flutter/material.dart';
import '../models/settings_model.dart';
import '../services/performance_policy.dart';

class ParticleSystem extends StatefulWidget {
  final ParticleEffect effect;
  const ParticleSystem({super.key, required this.effect});

  @override
  State<ParticleSystem> createState() => _ParticleSystemState();
}

class _ParticleSystemState extends State<ParticleSystem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<Particle> _particles = [];
  final Random _random = Random();
  Duration _lastPaintTime = Duration.zero;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 6))
          ..repeat();
    _initParticles(1.0);
  }

  void _initParticles(double scale) {
    _particles.clear();
    int count = _getParticleCount(scale);
    for (int i = 0; i < count; i++) {
      _particles.add(Particle(_random, widget.effect));
    }
  }

  int _getParticleCount(double scale) {
    if (scale <= 0) return 0;
    int scaled(int value) => max(4, (value * scale).round());

    switch (widget.effect) {
      case ParticleEffect.sakura:
        return scaled(15);
      case ParticleEffect.snow:
        return scaled(25);
      case ParticleEffect.stars:
        return scaled(40);
      case ParticleEffect.bubbles:
        return scaled(15);
      case ParticleEffect.rain:
        return scaled(40);
      default:
        return 0;
    }
  }

  @override
  void didUpdateWidget(ParticleSystem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.effect != widget.effect) {
      _particles.clear();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final policy = PerformancePolicy.of(context);
    if (widget.effect == ParticleEffect.none) return const SizedBox.shrink();
    if (!policy.allowParticles || policy.particleCountScale <= 0) {
      if (_controller.isAnimating) _controller.stop();
      return const SizedBox.shrink();
    }
    if (!_controller.isAnimating) _controller.repeat();
    final targetCount = _getParticleCount(policy.particleCountScale);
    if (_particles.length != targetCount) {
      _initParticles(policy.particleCountScale);
    }

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final elapsed = _controller.lastElapsedDuration ?? Duration.zero;
          if (elapsed - _lastPaintTime < policy.particleFrameInterval) {
            return child ?? const SizedBox.expand();
          }
          _lastPaintTime = elapsed;
          final size = MediaQuery.sizeOf(context);
          final time = _controller.value * pi * 2;
          for (var particle in _particles) {
            particle.update(size, time);
          }
          return CustomPaint(
            painter: ParticlePainter(_particles, widget.effect),
            size: Size.infinite,
            isComplex: false,
            willChange: true,
          );
        },
      ),
    );
  }
}

class Particle {
  late double x, y, size, speedX, speedY, opacity, rotation, rotationSpeed;
  final Random random;
  final ParticleEffect effect;

  Particle(this.random, this.effect) {
    reset();
    y = random.nextDouble() * 800; // Random initial Y
  }

  void reset([Size bounds = const Size(1920, 1080)]) {
    x = random.nextDouble() * bounds.width;
    y = -50;
    size = random.nextDouble() * 10 + 5;
    opacity = random.nextDouble() * 0.5 + 0.2;
    rotation = random.nextDouble() * pi * 2;
    rotationSpeed = (random.nextDouble() - 0.5) * 0.05;

    switch (effect) {
      case ParticleEffect.sakura:
        speedX = (random.nextDouble() - 0.2) * 2;
        speedY = random.nextDouble() * 2 + 1;
        size = random.nextDouble() * 8 + 4;
        break;
      case ParticleEffect.snow:
        speedX = (random.nextDouble() - 0.5) * 1;
        speedY = random.nextDouble() * 1.5 + 0.5;
        size = random.nextDouble() * 4 + 2;
        break;
      case ParticleEffect.stars:
        x = random.nextDouble() * bounds.width;
        y = random.nextDouble() * bounds.height;
        speedX = 0;
        speedY = 0;
        size = random.nextDouble() * 2 + 1;
        break;
      case ParticleEffect.bubbles:
        y = bounds.height + 20; // Rise from bottom
        speedX = (random.nextDouble() - 0.5) * 0.5;
        speedY = -(random.nextDouble() * 2 + 1);
        size = random.nextDouble() * 15 + 5;
        break;
      case ParticleEffect.rain:
        speedX = -(random.nextDouble() * 2.8 + 1.4);
        speedY = random.nextDouble() * 12 + 14;
        size = random.nextDouble() * 16 + 14;
        opacity = random.nextDouble() * 0.30 + 0.18;
        rotation = -0.22;
        rotationSpeed = 0;
        break;
      default:
        speedX = 0;
        speedY = 0;
    }
  }

  void update(Size bounds, double time) {
    if (effect == ParticleEffect.stars) {
      opacity = ((sin(time + x) + 1) / 2 * 0.5) + 0.1;
      return;
    }

    x += speedX;
    y += speedY;
    rotation += rotationSpeed;

    if (y > bounds.height + 60 ||
        x < -100 ||
        x > bounds.width + 100 ||
        (effect == ParticleEffect.bubbles && y < -50)) {
      reset(bounds);
    }
  }
}

class ParticlePainter extends CustomPainter {
  final List<Particle> particles;
  final ParticleEffect effect;

  ParticlePainter(this.particles, this.effect);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final baseColor = _getParticleColor();

    for (var p in particles) {
      paint.color = baseColor.withOpacity(p.opacity);

      canvas.save();
      canvas.translate(p.x, p.y);
      canvas.rotate(p.rotation);

      switch (effect) {
        case ParticleEffect.sakura:
          _drawSakura(canvas, p.size, paint);
          break;
        case ParticleEffect.snow:
          canvas.drawCircle(Offset.zero, p.size, paint);
          break;
        case ParticleEffect.stars:
          canvas.drawCircle(Offset.zero, p.size, paint);
          break;
        case ParticleEffect.bubbles:
          paint.style = PaintingStyle.stroke;
          paint.strokeWidth = 1;
          canvas.drawCircle(Offset.zero, p.size, paint);
          paint.style = PaintingStyle.fill;
          paint.color = baseColor.withOpacity(p.opacity * 0.3);
          canvas.drawCircle(Offset.zero, p.size * 0.3, paint);
          break;
        case ParticleEffect.rain:
          _drawRain(canvas, p, paint);
          break;
        default:
          canvas.drawCircle(Offset.zero, p.size, paint);
      }
      canvas.restore();
    }
  }

  Color _getParticleColor() {
    switch (effect) {
      case ParticleEffect.sakura:
        return const Color(0xFFFFB7C5);
      case ParticleEffect.snow:
        return Colors.white;
      case ParticleEffect.stars:
        return Colors.white;
      case ParticleEffect.bubbles:
        return Colors.white;
      case ParticleEffect.rain:
        return const Color(0xFF8FD3FF);
      default:
        return Colors.white;
    }
  }

  void _drawSakura(Canvas canvas, double size, Paint paint) {
    final path = Path();
    path.moveTo(0, -size);
    path.quadraticBezierTo(size * 0.5, -size * 0.5, 0, 0);
    path.quadraticBezierTo(-size * 0.5, -size * 0.5, 0, -size);
    canvas.drawPath(path, paint);
  }

  void _drawRain(Canvas canvas, Particle p, Paint paint) {
    paint
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = (p.size / 18).clamp(0.8, 1.6);
    canvas.drawLine(
      Offset.zero,
      Offset(0, p.size),
      paint,
    );
    paint.style = PaintingStyle.fill;
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
