import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../models/settings_model.dart';
import '../services/performance_policy.dart';

class _RepaintNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

class ParticleSystem extends StatefulWidget {
  final ParticleEffect effect;
  final String customPack;
  final bool paused;
  final List<Color>? overrideColors;
  final double intensity;

  const ParticleSystem({
    super.key,
    required this.effect,
    this.customPack = '* + .',
    this.paused = false,
    this.overrideColors,
    this.intensity = 1.0,
  });

  @override
  State<ParticleSystem> createState() => _ParticleSystemState();
}

class _ParticleSystemState extends State<ParticleSystem>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  final _RepaintNotifier _repaintNotifier = _RepaintNotifier();
  final List<Particle> _particles = [];
  final Random _random = Random();

  double _timeSec = 0;
  Duration _prevElapsed = Duration.zero;
  Duration _lastPainted = Duration.zero;
  Size _canvasSize = const Size(800, 600);

  bool _allowParticles = true;
  Duration _particleFrameInterval = const Duration(milliseconds: 16);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _initParticles();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final policy = PerformancePolicy.of(context);
    _allowParticles = policy.allowParticles;
    _particleFrameInterval = policy.particleFrameInterval;
    _syncTickerState();
  }

  @override
  void didUpdateWidget(ParticleSystem old) {
    super.didUpdateWidget(old);
    if (old.effect != widget.effect) {
      _initParticles();
    }
    if (old.overrideColors != widget.overrideColors &&
        widget.overrideColors != null) {
      _reassignColors();
    }
    _syncTickerState();
  }

  void _syncTickerState() {
    final shouldRun = _allowParticles &&
        widget.effect != ParticleEffect.none &&
        !widget.paused;
    if (shouldRun && !_ticker.isActive) {
      _prevElapsed = Duration.zero;
      _ticker.start();
    } else if (!shouldRun && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaintNotifier.dispose();
    super.dispose();
  }

  void _initParticles() {
    _particles.clear();
    final count = _particleCount();
    for (int i = 0; i < count; i++) {
      _particles.add(
        Particle(_random, widget.effect)
          ..init(_canvasSize, widget.customPack, widget.overrideColors,
              spreadAcrossScreen: true, index: i, total: count),
      );
    }
  }

  void _reassignColors() {
    final colors = widget.overrideColors;
    if (colors == null || colors.isEmpty) return;
    for (final p in _particles) {
      p.targetColor = colors[_random.nextInt(colors.length)];
    }
  }

  int _particleCount() {
    switch (widget.effect) {
      case ParticleEffect.sakura:         return 10;
      case ParticleEffect.snow:           return 15;
      case ParticleEffect.stars:          return 20;
      case ParticleEffect.bubbles:        return 10;
      case ParticleEffect.rain:           return 20;
      case ParticleEffect.hearts:         return 12;
      case ParticleEffect.fireflies:      return 16;
      case ParticleEffect.confetti:       return 18;
      case ParticleEffect.custom:         return 16;
      default:                            return 0;
    }
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    final dt = (elapsed - _prevElapsed).inMicroseconds / 1e6;
    _prevElapsed = elapsed;
    final dtClamped = dt.clamp(0.0, 0.05);
    if (elapsed - _lastPainted < _particleFrameInterval) return;
    _lastPainted = elapsed;

    if (!widget.paused) {
      _timeSec += dtClamped;
      final lerpFactor = dtClamped * 0.5;
      for (final p in _particles) {
        p.update(_canvasSize, _timeSec, dtClamped,
            widget.customPack, widget.overrideColors, widget.intensity, lerpFactor);
      }
    }
    _repaintNotifier.notify();
  }

  @override
  Widget build(BuildContext context) {
    final policy = PerformancePolicy.of(context);
    if (widget.effect == ParticleEffect.none) return const SizedBox.shrink();
    if (!policy.allowParticles) return const SizedBox.shrink();

    final baseCount = _particleCount();
    final desired = max(4, (baseCount * policy.particleCountScale).round());
    if (_particles.length != desired) {
      if (_particles.length < desired) {
        for (int i = _particles.length; i < desired; i++) {
          _particles.add(
            Particle(_random, widget.effect)
              ..init(_canvasSize, widget.customPack, widget.overrideColors,
                  spreadAcrossScreen: true, index: i, total: desired),
          );
        }
      } else {
        _particles.removeRange(desired, _particles.length);
      }
    }

    return RepaintBoundary(
      child: LayoutBuilder(builder: (context, constraints) {
        final s = Size(constraints.maxWidth, constraints.maxHeight);
        if (s != _canvasSize) {
          final isFirstLayout = _canvasSize == const Size(800, 600);
          _canvasSize = s;
          if (isFirstLayout) {
            for (int i = 0; i < _particles.length; i++) {
              _particles[i].init(_canvasSize, widget.customPack, widget.overrideColors,
                  spreadAcrossScreen: true, index: i, total: _particles.length);
            }
          }
        }
        return CustomPaint(
          painter: _ParticlePainter(
            particles: _particles,
            effect: widget.effect,
            repaint: _repaintNotifier,
          ),
          size: Size.infinite,
          isComplex: true,
        );
      }),
    );
  }
}

// ─── Particle ─────────────────────────────────────────────────────────────────

class Particle {
  static const double _twoPi = pi * 2;

  final Random rng;
  final ParticleEffect effect;

  double x = 0, y = 0, size = 5;
  double speedX = 0, speedY = 0;
  double opacity = 0.3, rotation = 0, rotationSpeed = 0, scale = 1.0;
  Color? currentColor;
  Color? targetColor;

  String? symbol;
  TextPainter? cachedTextPainter;
  String? cachedSymbol;

  Particle(this.rng, this.effect);

  void init(
    Size bounds,
    String customPack,
    List<Color>? colors, {
    bool spreadAcrossScreen = false,
    int index = 0,
    int total = 1,
  }) {
    rotation = rng.nextDouble() * _twoPi;
    rotationSpeed = (rng.nextDouble() - 0.5) * 0.03;
    opacity = rng.nextDouble() * 0.4 + 0.15;
    size = rng.nextDouble() * 8 + 4;

    if (colors != null && colors.isNotEmpty) {
      targetColor = colors[rng.nextInt(colors.length)];
      currentColor = targetColor;
    }

    switch (effect) {
      case ParticleEffect.sakura:
        x = rng.nextDouble() * bounds.width;
        y = spreadAcrossScreen ? rng.nextDouble() * bounds.height : -50;
        speedX = (rng.nextDouble() - 0.2) * 2;
        speedY = rng.nextDouble() * 2 + 1;
        size = rng.nextDouble() * 8 + 4;
        break;
      case ParticleEffect.snow:
        x = rng.nextDouble() * bounds.width;
        y = spreadAcrossScreen ? rng.nextDouble() * bounds.height : -50;
        speedX = (rng.nextDouble() - 0.5);
        speedY = rng.nextDouble() * 1.5 + 0.5;
        size = rng.nextDouble() * 4 + 2;
        break;
      case ParticleEffect.stars:
        x = rng.nextDouble() * bounds.width;
        y = rng.nextDouble() * bounds.height;
        speedX = 0; speedY = 0;
        size = rng.nextDouble() * 2 + 1;
        break;
      case ParticleEffect.bubbles:
        x = rng.nextDouble() * bounds.width;
        y = spreadAcrossScreen ? rng.nextDouble() * bounds.height : bounds.height + 20;
        speedX = (rng.nextDouble() - 0.5) * 0.5;
        speedY = -(rng.nextDouble() * 2 + 1);
        size = rng.nextDouble() * 15 + 5;
        break;
      case ParticleEffect.rain:
        x = rng.nextDouble() * bounds.width;
        y = spreadAcrossScreen ? rng.nextDouble() * bounds.height : -50;
        speedX = -(rng.nextDouble() * 2.8 + 1.4);
        speedY = rng.nextDouble() * 12 + 14;
        size = rng.nextDouble() * 16 + 14;
        opacity = rng.nextDouble() * 0.3 + 0.18;
        rotation = -0.22; rotationSpeed = 0;
        break;
      case ParticleEffect.hearts:
        x = rng.nextDouble() * bounds.width;
        y = spreadAcrossScreen ? rng.nextDouble() * bounds.height : bounds.height + 30;
        speedX = (rng.nextDouble() - 0.5) * 1.2;
        speedY = -(rng.nextDouble() * 1.7 + 0.7);
        size = rng.nextDouble() * 9 + 8;
        opacity = rng.nextDouble() * 0.42 + 0.30;
        break;
      case ParticleEffect.fireflies:
        x = rng.nextDouble() * bounds.width;
        y = rng.nextDouble() * bounds.height;
        speedX = (rng.nextDouble() - 0.5) * 0.9;
        speedY = (rng.nextDouble() - 0.5) * 0.9;
        size = rng.nextDouble() * 3 + 2;
        opacity = rng.nextDouble() * 0.5 + 0.2;
        break;
      case ParticleEffect.confetti:
        x = rng.nextDouble() * bounds.width;
        y = spreadAcrossScreen ? rng.nextDouble() * bounds.height : -50;
        speedX = (rng.nextDouble() - 0.5) * 3.4;
        speedY = rng.nextDouble() * 4.5 + 2.2;
        size = rng.nextDouble() * 8 + 4;
        opacity = rng.nextDouble() * 0.52 + 0.36;
        rotationSpeed = (rng.nextDouble() - 0.5) * 0.16;
        break;
      case ParticleEffect.custom:
        x = rng.nextDouble() * bounds.width;
        y = spreadAcrossScreen ? rng.nextDouble() * bounds.height : -50;
        speedX = (rng.nextDouble() - 0.5) * 1.8;
        speedY = rng.nextDouble() * 2.2 + 0.8;
        size = rng.nextDouble() * 12 + 10;
        opacity = rng.nextDouble() * 0.48 + 0.26;
        symbol = _pickSymbol(customPack);
        cachedTextPainter = null;
        break;
      default:
        x = rng.nextDouble() * bounds.width;
        y = -50;
        speedX = 0; speedY = 0;
    }
  }

  String _pickSymbol(String pack) {
    final list = pack.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    return list.isEmpty ? '*' : list[rng.nextInt(list.length)];
  }

  void update(
    Size bounds,
    double timeSec,
    double dt,
    String customPack,
    List<Color>? colors,
    double intensity,
    double lerpFactor,
  ) {
    if (currentColor != null && targetColor != null && currentColor != targetColor) {
      currentColor = Color.lerp(currentColor, targetColor, lerpFactor);
    }
    switch (effect) {
      case ParticleEffect.stars:
        opacity = ((sin(timeSec * 0.8 + x / 200) + 1) / 2 * 0.5) + 0.05;
        return;

      case ParticleEffect.fireflies:
        opacity = ((sin(timeSec * 1.3 + x / 80) + 1) / 2 * 0.45) + 0.08;
        x += speedX * dt * 60;
        y += speedY * dt * 60;
        if (x < 0) x = bounds.width;
        else if (x > bounds.width) x = 0;
        if (y < 0) y = bounds.height;
        else if (y > bounds.height) y = 0;
        return;

      default:
        x += speedX;
        y += speedY;
        rotation += rotationSpeed;
        final goesUp = effect == ParticleEffect.bubbles || effect == ParticleEffect.hearts;
        if (y > bounds.height + 60 ||
            x < -100 ||
            x > bounds.width + 100 ||
            (goesUp && y < -50)) {
          init(bounds, customPack, colors);
        }
    }
  }
}

// ─── Painter ──────────────────────────────────────────────────────────────────

class _ParticlePainter extends CustomPainter {
  final List<Particle> particles;
  final ParticleEffect effect;

  late final Color _baseColor;

  _ParticlePainter({
    required this.particles,
    required this.effect,
    required Listenable repaint,
  }) : super(repaint: repaint) {
    _baseColor = switch (effect) {
      ParticleEffect.sakura       => const Color(0xFFFFB7C5),
      ParticleEffect.rain         => const Color(0xFF8FD3FF),
      ParticleEffect.hearts       => const Color(0xFFFF7AAE),
      ParticleEffect.fireflies    => const Color(0xFFFDE68A),
      ParticleEffect.confetti     => const Color(0xFF67E8F9),
      _                           => Colors.white,
    };
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final base = _baseColor;

    for (final p in particles) {
      final col = p.currentColor ?? base;

      canvas.save();
      canvas.translate(p.x, p.y);
      canvas.rotate(p.rotation);
      paint.color = col.withValues(alpha: p.opacity.clamp(0.0, 1.0));

      switch (effect) {
        case ParticleEffect.sakura:
          _drawSakura(canvas, p.size, paint);
          break;
        case ParticleEffect.snow:
        case ParticleEffect.stars:
          canvas.drawCircle(Offset.zero, p.size, paint);
          break;
        case ParticleEffect.bubbles:
          paint.style = PaintingStyle.stroke;
          paint.strokeWidth = 1;
          canvas.drawCircle(Offset.zero, p.size, paint);
          paint.style = PaintingStyle.fill;
          paint.color = col.withValues(alpha: p.opacity * 0.3);
          canvas.drawCircle(Offset.zero, p.size * 0.3, paint);
          break;
        case ParticleEffect.rain:
          _drawRain(canvas, p, paint);
          break;
        case ParticleEffect.hearts:
          _drawHeart(canvas, p.size, paint);
          break;
        case ParticleEffect.fireflies:
          _drawFirefly(canvas, p, paint);
          break;
        case ParticleEffect.confetti:
          _drawConfetti(canvas, p, paint);
          break;
        case ParticleEffect.custom:
          _drawCustom(canvas, p, col.withValues(alpha: p.opacity));
          break;
        default:
          canvas.drawCircle(Offset.zero, p.size, paint);
      }

      canvas.restore();
    }
  }

  void _drawSakura(Canvas c, double s, Paint p) {
    final path = Path()
      ..moveTo(0, -s)
      ..quadraticBezierTo(s * 0.5, -s * 0.5, 0, 0)
      ..quadraticBezierTo(-s * 0.5, -s * 0.5, 0, -s);
    c.drawPath(path, p);
  }

  void _drawRain(Canvas c, Particle p, Paint paint) {
    paint
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = (p.size / 18).clamp(0.8, 1.6);
    c.drawLine(Offset.zero, Offset(0, p.size), paint);
    paint.style = PaintingStyle.fill;
  }

  void _drawHeart(Canvas c, double s, Paint p) {
    final path = Path()
      ..moveTo(0, -s * 0.35)
      ..cubicTo(-s*.45, -s*.8, -s*.95, -s*.45, -s*.95, s*.05)
      ..cubicTo(-s*.95, s*.5, -s*.5, s*.8, 0, s*1.05)
      ..cubicTo(s*.5, s*.8, s*.95, s*.5, s*.95, s*.05)
      ..cubicTo(s*.95, -s*.45, s*.45, -s*.8, 0, -s*0.35)
      ..close();
    c.drawPath(path, p);
  }

  void _drawFirefly(Canvas c, Particle p, Paint paint) {
    paint
      ..color = const Color(0xFFFDE68A).withValues(alpha: p.opacity)
      ..style = PaintingStyle.fill;
    c.drawCircle(Offset.zero, p.size, paint);
    paint
      ..color = const Color(0xFFFDE68A).withValues(alpha: p.opacity * 0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    c.drawCircle(Offset.zero, p.size * 2.5, paint);
    paint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    c.drawCircle(Offset.zero, p.size * 1.5, paint);
    paint.maskFilter = null;
  }

  void _drawConfetti(Canvas c, Particle p, Paint paint) {
    const colors = [
      Color(0xFFF87171), Color(0xFFFBBF24), Color(0xFF34D399),
      Color(0xFF60A5FA), Color(0xFFA78BFA),
    ];
    paint.color = colors[(p.x.toInt().abs() + p.y.toInt().abs()) % colors.length]
        .withValues(alpha: p.opacity);
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: p.size * 0.8, height: p.size * 1.8),
        const Radius.circular(2),
      ),
      paint,
    );
  }

  void _drawCustom(Canvas c, Particle p, Color color) {
    if (p.cachedTextPainter == null || p.cachedSymbol != p.symbol) {
      p.cachedSymbol = p.symbol;
      p.cachedTextPainter = TextPainter(
        text: TextSpan(
          text: p.symbol ?? '*',
          style: TextStyle(color: Colors.white, fontSize: p.size, fontWeight: FontWeight.w900),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    }
    final r = Rect.fromCircle(center: Offset.zero, radius: p.size * 1.2);
    c.saveLayer(r, Paint()..colorFilter = ColorFilter.mode(color, BlendMode.srcIn));
    p.cachedTextPainter!.paint(
        c, Offset(-p.cachedTextPainter!.width / 2, -p.cachedTextPainter!.height / 2));
    c.restore();
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter old) => false;
}
