import 'dart:async';

import 'package:flutter/material.dart';

class FadeInUpAnimation extends StatefulWidget {
  final Widget child;
  final double delay;
  final double distance;

  const FadeInUpAnimation({
    super.key,
    required this.child,
    this.delay = 0.0,
    this.distance = 30.0,
  });

  @override
  State<FadeInUpAnimation> createState() => _FadeInUpAnimationState();
}

class _FadeInUpAnimationState extends State<FadeInUpAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;
  late Animation<double> _translateAnimation;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 360),
      vsync: this,
    );

    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutQuart,
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(curve);
    _translateAnimation =
        Tween<double>(begin: widget.distance, end: 0.0).animate(curve);

    final delayMs = (widget.delay * 1000).toInt();
    if (delayMs > 0) {
      _delayTimer = Timer(Duration(milliseconds: delayMs), () {
        if (mounted) _controller.forward();
      });
    } else {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(FadeInUpAnimation old) {
    super.didUpdateWidget(old);
    if (old.delay != widget.delay && !_controller.isAnimating) {
      _delayTimer?.cancel();
      _controller.reset();
      final delayMs = (widget.delay * 1000).toInt();
      if (delayMs > 0) {
        _delayTimer = Timer(Duration(milliseconds: delayMs), () {
          if (mounted) _controller.forward();
        });
      } else {
        _controller.forward();
      }
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final animatedChild = Transform.translate(
          offset: Offset(0, _translateAnimation.value),
          child: child,
        );
        if (_opacityAnimation.value >= 0.999) return animatedChild;
        return Opacity(
          opacity: _opacityAnimation.value,
          child: animatedChild,
        );
      },
    );
  }
}
