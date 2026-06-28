import 'dart:async';

import 'package:flutter/material.dart';

import '../services/responsive.dart';

class SongGapCountdownPill extends StatelessWidget {
  final Duration remaining;
  final Color foreground;
  final Color background;

  const SongGapCountdownPill({
    super.key,
    required this.remaining,
    required this.foreground,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    final seconds = (remaining.inMilliseconds / 1000).ceil().clamp(1, 99);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background.withOpacity(0.42),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: foreground.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                foreground.withOpacity(0.72),
              ),
            ),
          ),
          const SizedBox(width: 9),
          Text(
            'next track: $seconds sec',
            style: TextStyle(
              color: foreground.withOpacity(0.72),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class SmoothPlayPauseButton extends StatefulWidget {
  final bool isPlaying;
  final VoidCallback onPressed;
  final Size size;
  final double iconSize;

  const SmoothPlayPauseButton({
    super.key,
    required this.isPlaying,
    required this.onPressed,
    required this.size,
    required this.iconSize,
  });

  @override
  State<SmoothPlayPauseButton> createState() => _SmoothPlayPauseButtonState();
}

class _SmoothPlayPauseButtonState extends State<SmoothPlayPauseButton> {
  bool? _optimisticIsPlaying;
  Timer? _optimisticTimer;

  bool get _visualIsPlaying => _optimisticIsPlaying ?? widget.isPlaying;

  @override
  void didUpdateWidget(covariant SmoothPlayPauseButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_optimisticIsPlaying != null &&
        widget.isPlaying == _optimisticIsPlaying) {
      _clearOptimisticState();
    }
  }

  @override
  void dispose() {
    _optimisticTimer?.cancel();
    super.dispose();
  }

  void _clearOptimisticState() {
    _optimisticTimer?.cancel();
    _optimisticTimer = null;
    _optimisticIsPlaying = null;
  }

  void _handlePressed() {
    final nextVisualState = !_visualIsPlaying;
    _optimisticTimer?.cancel();
    setState(() => _optimisticIsPlaying = nextVisualState);
    _optimisticTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() => _optimisticIsPlaying = null);
      }
    });
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visualIsPlaying = _visualIsPlaying;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: visualIsPlaying ? 1 : 0),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.scale(
          scale: 0.98 + (value * 0.02),
          child: FilledButton(
            onPressed: _handlePressed,
            style: FilledButton.styleFrom(
              minimumSize: widget.size,
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20.s),
              ),
              backgroundColor: Color.lerp(
                theme.colorScheme.primaryContainer,
                theme.colorScheme.primary.withOpacity(0.24),
                value,
              ),
              foregroundColor: theme.colorScheme.onPrimaryContainer,
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final scale = Tween<double>(begin: 0.9, end: 1).animate(
                  CurvedAnimation(
                      parent: animation, curve: Curves.easeOutCubic),
                );
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: scale, child: child),
                );
              },
              child: Icon(
                visualIsPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                key: ValueKey(visualIsPlaying),
                size: widget.iconSize,
              ),
            ),
          ),
        );
      },
    );
  }
}
