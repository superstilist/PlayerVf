import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import '../models/settings_model.dart';
import '../services/orb_controller.dart';
import '../services/performance_policy.dart';

class _OrbRepaintNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// Standalone orb rendering widget — completely separate from ParticleSystem.
/// Uses [OrbController] for state, owns its own [Ticker] for animation,
/// and is always wrapped in [IgnorePointer] + [ClipRect] to avoid
/// accessibility tree issues.
class OrbSystem extends StatefulWidget {
  final bool paused;
  final double intensity;

  const OrbSystem({
    super.key,
    this.paused = false,
    this.intensity = 1.0,
  });

  @override
  State<OrbSystem> createState() => _OrbSystemState();
}

class _OrbSystemState extends State<OrbSystem>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _OrbRepaintNotifier _repaintNotifier = _OrbRepaintNotifier();
  Duration _prevElapsed = Duration.zero;
  Duration _lastPainted = Duration.zero;
  Size _canvasSize = const Size(800, 600);

  bool _allowParticles = true;
  Duration _frameInterval = const Duration(milliseconds: 16);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final policy = PerformancePolicy.of(context);
    _allowParticles = policy.allowParticles;
    _frameInterval = policy.particleFrameInterval;
    final settings = context.read<SettingsModel>();
    final orbCtrl = OrbController.instance;
    orbCtrl.setSizeMultiplier(settings.orbSize);
    orbCtrl.setSpeedMultiplier(settings.orbSpeed);
    _syncTickerState();
  }

  void _syncTickerState() {
    final shouldRun = _allowParticles && !widget.paused;
    if (shouldRun && !_ticker.isActive) {
      _prevElapsed = Duration.zero;
      _ticker.start();
    } else if (!shouldRun && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void didUpdateWidget(OrbSystem old) {
    super.didUpdateWidget(old);
    _syncTickerState();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaintNotifier.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    final dt = (elapsed - _prevElapsed).inMicroseconds / 1e6;
    _prevElapsed = elapsed;
    final dtClamped = dt.clamp(0.0, 0.05);
    if (elapsed - _lastPainted < _frameInterval) return;
    _lastPainted = elapsed;

    if (!widget.paused) {
      final orbCtrl = OrbController.instance;
      orbCtrl.updateBounds(_canvasSize);
      orbCtrl.setIntensity(widget.intensity);
      orbCtrl.tick(dtClamped);
    }
    _repaintNotifier.notify();
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowParticles) return const SizedBox.shrink();

    final orbCtrl = context.read<OrbController>();

    return RepaintBoundary(
      child: ClipRect(
        child: LayoutBuilder(builder: (context, constraints) {
          final s = Size(constraints.maxWidth, constraints.maxHeight);
          if (s != _canvasSize) _canvasSize = s;
          return ListenableBuilder(
            listenable: orbCtrl,
            builder: (context, _) {
              return CustomPaint(
                painter: _OrbPainter(
                  orbs: orbCtrl.orbs,
                  repaint: _repaintNotifier,
                ),
                size: Size.infinite,
              );
            },
          );
        }),
      ),
    );
  }
}

// ─── Painter ──────────────────────────────────────────────────────────────────

class _OrbPainter extends CustomPainter {
  final List<OrbData> orbs;

  // Pre-allocated gradient color arrays — reused across all orbs and frames.
  final List<Color> _outerColors = List<Color>.filled(3, const Color(0x00000000));
  final List<Color> _midColors = List<Color>.filled(3, const Color(0x00000000));
  final List<Color> _coreColors = List<Color>.filled(3, const Color(0x00000000));

  static const List<double> _stops3 = [0.0, 0.45, 1.0];
  static const List<double> _stopsHalf = [0.0, 0.5, 1.0];
  static const List<double> _stopsCore = [0.0, 0.55, 1.0];

  _OrbPainter({
    required this.orbs,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    const baseColor = Colors.teal;

    for (final o in orbs) {
      final col = o.currentColor ?? baseColor;
      canvas.save();
      canvas.translate(o.x, o.y);
      canvas.rotate(o.rotation);
      paint.color = col.withValues(alpha: o.opacity.clamp(0.0, 1.0));
      _drawBlob(canvas, o.size, o.scale, o.aspectRatio, paint, size);
      canvas.restore();
    }
  }

  /// Multi-layered orb: outer halo + mid glow + bright core.
  /// Reuses pre-allocated color arrays to avoid per-frame allocation.
  void _drawBlob(Canvas c, double orbSize, double orbScale,
      double orbAspectRatio, Paint paint, Size screenSize) {
    final blobR = screenSize.shortestSide * (orbSize / 100.0) * orbScale;
    final baseColor = paint.color;
    final aspect = orbAspectRatio;
    final a = baseColor.a;

    _outerColors[0] = baseColor.withValues(alpha: (a * 0.22).clamp(0.0, 1.0));
    _outerColors[1] = baseColor.withValues(alpha: (a * 0.06).clamp(0.0, 1.0));
    _outerColors[2] = const Color(0x00000000);

    _midColors[0] = baseColor.withValues(alpha: (a * 0.50).clamp(0.0, 1.0));
    _midColors[1] = baseColor.withValues(alpha: (a * 0.15).clamp(0.0, 1.0));
    _midColors[2] = const Color(0x00000000);

    _coreColors[0] = baseColor.withValues(alpha: (a * 0.80).clamp(0.0, 1.0));
    _coreColors[1] = baseColor.withValues(alpha: (a * 0.25).clamp(0.0, 1.0));
    _coreColors[2] = const Color(0x00000000);

    paint.style = PaintingStyle.fill;

    // Layer 1: Outer halo — 1.8× radius
    final outerW = blobR * 1.8;
    final outerH = outerW * aspect;
    final outerRect = Rect.fromCenter(center: Offset.zero, width: outerW, height: outerH);
    paint.shader = RadialGradient(colors: _outerColors, stops: _stops3).createShader(outerRect);
    c.drawOval(outerRect, paint);

    // Layer 2: Mid glow — 1.3× radius
    final midW = blobR * 1.3;
    final midH = midW * aspect;
    final midRect = Rect.fromCenter(center: Offset.zero, width: midW, height: midH);
    paint.shader = RadialGradient(colors: _midColors, stops: _stopsHalf).createShader(midRect);
    c.drawOval(midRect, paint);

    // Layer 3: Bright inner core — 0.8× radius
    final coreW = blobR * 0.8;
    final coreH = coreW * (aspect * 0.85 + 0.15);
    final coreRect = Rect.fromCenter(center: Offset.zero, width: coreW, height: coreH);
    paint.shader = RadialGradient(colors: _coreColors, stops: _stopsCore).createShader(coreRect);
    c.drawOval(coreRect, paint);
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) => false;
}
