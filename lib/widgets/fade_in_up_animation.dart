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

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 280),
      vsync: this,
    );

    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(curve);
    _translateAnimation =
        Tween<double>(begin: widget.distance, end: 0.0).animate(curve);

    // Start animation with delay
    Future.delayed(Duration(milliseconds: (widget.delay * 1000).toInt()), () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: Transform.translate(
            offset: Offset(0, _translateAnimation.value),
            child: widget.child,
          ),
        );
      },
    );
  }
}
