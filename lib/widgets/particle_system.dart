import 'dart:math';
import 'package:flutter/material.dart';
import '../models/settings_model.dart';

class ParticleSystem extends StatefulWidget {
  final ParticleEffect effect;
  const ParticleSystem({super.key, required this.effect});

  @override
  State<ParticleSystem> createState() => _ParticleSystemState();
}

class _ParticleSystemState extends State<ParticleSystem> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<Particle> _particles = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _initParticles();
  }

  void _initParticles() {
    _particles.clear();
    int count = _getParticleCount();
    for (int i = 0; i < count; i++) {
      _particles.add(Particle(_random, widget.effect));
    }
  }

  int _getParticleCount() {
    switch (widget.effect) {
      case ParticleEffect.sakura: return 15;
      case ParticleEffect.snow: return 25;
      case ParticleEffect.stars: return 40;
      case ParticleEffect.bubbles: return 15;
      case ParticleEffect.rain: return 40;
      default: return 0;
    }
  }

  @override
  void didUpdateWidget(ParticleSystem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.effect != widget.effect) {
      _initParticles();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.effect == ParticleEffect.none) return const SizedBox.shrink();
    
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        for (var particle in _particles) {
          particle.update();
        }
        return CustomPaint(
          painter: ParticlePainter(_particles, widget.effect),
          size: Size.infinite,
        );
      },
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

  void reset() {
    x = random.nextDouble() * 1920; 
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
        x = random.nextDouble() * 1920;
        y = random.nextDouble() * 1080;
        speedX = 0;
        speedY = 0;
        size = random.nextDouble() * 2 + 1;
        break;
      case ParticleEffect.bubbles:
        y = 1100; // Rise from bottom
        speedX = (random.nextDouble() - 0.5) * 0.5;
        speedY = -(random.nextDouble() * 2 + 1);
        size = random.nextDouble() * 15 + 5;
        break;
      case ParticleEffect.rain:
        speedX = -1;
        speedY = random.nextDouble() * 10 + 15;
        size = 2;
        break;
      default:
        speedX = 0;
        speedY = 0;
    }
  }

  void update() {
    if (effect == ParticleEffect.stars) {
      opacity = (sin(DateTime.now().millisecondsSinceEpoch / 1000 + x) + 1) / 2 * 0.5 + 0.1;
      return;
    }

    x += speedX;
    y += speedY;
    rotation += rotationSpeed;

    if (y > 1100 || x < -100 || x > 2000 || (effect == ParticleEffect.bubbles && y < -50)) {
      reset();
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

    for (var p in particles) {
      final baseColor = _getParticleColor(1.0);
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
          final originalColor = paint.color;
          paint.color = originalColor.withOpacity(p.opacity * 0.3);
          canvas.drawCircle(Offset.zero, p.size * 0.3, paint);
          paint.color = originalColor;
          break;
        case ParticleEffect.rain:
          canvas.drawRect(const Rect.fromLTWH(0, 0, 1, 15), paint);
          break;
        default:
          canvas.drawCircle(Offset.zero, p.size, paint);
      }
      canvas.restore();
    }
  }

  Color _getParticleColor(double opacity) {
    switch (effect) {
      case ParticleEffect.sakura: return const Color(0xFFFFB7C5).withOpacity(opacity);
      case ParticleEffect.snow: return Colors.white.withOpacity(opacity);
      case ParticleEffect.stars: return Colors.white.withOpacity(opacity);
      case ParticleEffect.bubbles: return Colors.white.withOpacity(opacity);
      case ParticleEffect.rain: return Colors.blue.withOpacity(opacity);
      default: return Colors.white.withOpacity(opacity);
    }
  }

  void _drawSakura(Canvas canvas, double size, Paint paint) {
    final path = Path();
    path.moveTo(0, -size);
    path.quadraticBezierTo(size * 0.5, -size * 0.5, 0, 0);
    path.quadraticBezierTo(-size * 0.5, -size * 0.5, 0, -size);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
