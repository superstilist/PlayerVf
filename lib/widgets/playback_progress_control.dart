import 'dart:async';

import 'package:flutter/material.dart';

import '../services/music_service.dart';
import '../services/responsive.dart';
import '../utils/duration_format.dart';

class PlaybackProgressControl extends StatefulWidget {
  final MusicService musicService;
  final Color activeColor;
  final Color inactiveColor;
  final TextStyle timeStyle;

  const PlaybackProgressControl({
    super.key,
    required this.musicService,
    required this.activeColor,
    required this.inactiveColor,
    required this.timeStyle,
  });

  @override
  State<PlaybackProgressControl> createState() =>
      _PlaybackProgressControlState();
}

class _PlaybackProgressControlState extends State<PlaybackProgressControl> {
  double? _dragProgress;
  double? _pendingSeekProgress;
  String? _lastTrackId;
  Timer? _trackResetTimer;
  Timer? _pendingSeekTimer;
  bool _isResettingForTrackChange = false;

  @override
  void didUpdateWidget(covariant PlaybackProgressControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.musicService.currentMusic?.id !=
        widget.musicService.currentMusic?.id) {
      _dragProgress = null;
      _pendingSeekProgress = null;
    }
  }

  @override
  void dispose() {
    _trackResetTimer?.cancel();
    _pendingSeekTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: widget.musicService.durationNotifier,
      builder: (context, duration, child) {
        return ValueListenableBuilder<Duration>(
          valueListenable: widget.musicService.positionNotifier,
          builder: (context, position, child) {
            final currentTrackId = widget.musicService.currentMusic?.id;
            final isNewTrack = currentTrackId != _lastTrackId;
            if (isNewTrack) {
              _lastTrackId = currentTrackId;
              _dragProgress = null;
              _pendingSeekProgress = null;
              _pendingSeekTimer?.cancel();
              _isResettingForTrackChange = true;
              _trackResetTimer?.cancel();
              _trackResetTimer = Timer(
                const Duration(milliseconds: 420),
                () {
                  if (mounted) {
                    setState(() => _isResettingForTrackChange = false);
                  }
                },
              );
            }

            final boundedPosition = _boundedPosition(position, duration);
            final liveProgress = _progressFor(boundedPosition, duration);
            if (_pendingSeekProgress != null &&
                (liveProgress - _pendingSeekProgress!).abs() < 0.004) {
              _pendingSeekProgress = null;
              _pendingSeekTimer?.cancel();
              _pendingSeekTimer = null;
            }

            final targetProgress = (_dragProgress ??
                    _pendingSeekProgress ??
                    (_isResettingForTrackChange ? 0.0 : liveProgress))
                .clamp(0.0, 1.0)
                .toDouble();
            final previewPosition =
                (_dragProgress != null || _pendingSeekProgress != null)
                    ? _positionFor(targetProgress, duration)
                    : (_isResettingForTrackChange
                        ? Duration.zero
                        : boundedPosition);
            final reduceMotion =
                MediaQuery.maybeOf(context)?.disableAnimations == true;
            final progressString = '${(targetProgress * 100).round()}%';

            return ExcludeSemantics(
              excluding: true,
              child: Semantics(
                label: 'Playback progress',
                value: progressString,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2.w),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: targetProgress),
                    duration: reduceMotion
                        ? Duration.zero
                        : _dragProgress != null
                            ? const Duration(milliseconds: 90)
                            : _isResettingForTrackChange
                                ? const Duration(milliseconds: 240)
                                : const Duration(milliseconds: 110),
                    curve: _isResettingForTrackChange
                        ? Curves.easeInOutCubic
                        : Curves.easeOutCubic,
                    builder: (context, animatedProgress, child) {
                      return _ProgressScrubber(
                        progress: animatedProgress.clamp(0.0, 1.0).toDouble(),
                        enabled: duration.inMilliseconds > 0,
                        activeColor: widget.activeColor,
                        inactiveColor: widget.inactiveColor,
                        onChangeStart: _beginDrag,
                        onChanged: _updateDrag,
                        onChangeEnd: (value) => _finishDrag(value, duration),
                      );
                    },
                  ),
                ),
                SizedBox(height: 2.h),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12.s),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 54.w,
                        child: Text(
                          formatPlaybackDuration(previewPosition),
                          style: widget.timeStyle,
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: 54.w,
                        child: Text(
                          formatPlaybackDuration(duration),
                          style: widget.timeStyle,
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            ),
            );
          },
        );
      },
    );
  }

  Duration _boundedPosition(Duration position, Duration duration) {
    if (duration <= Duration.zero) {
      return position < Duration.zero ? Duration.zero : position;
    }
    if (position < Duration.zero) return Duration.zero;
    if (position > duration) return duration;
    return position;
  }

  double _progressFor(Duration position, Duration duration) {
    if (duration.inMilliseconds <= 0) return 0;
    return position.inMilliseconds / duration.inMilliseconds;
  }

  Duration _positionFor(double progress, Duration duration) {
    return Duration(
      milliseconds: (progress.clamp(0, 1) * duration.inMilliseconds).round(),
    );
  }

  void _beginDrag(double value) {
    _pendingSeekTimer?.cancel();
    setState(() {
      _pendingSeekProgress = null;
      _dragProgress = value;
    });
  }

  void _updateDrag(double value) {
    _pendingSeekTimer?.cancel();
    setState(() {
      _pendingSeekProgress = null;
      _dragProgress = value;
    });
  }

  void _finishDrag(double value, Duration duration) {
    final target = value.clamp(0.0, 1.0).toDouble();
    widget.musicService.seekTo(_positionFor(target, duration));
    _pendingSeekTimer?.cancel();
    _pendingSeekTimer = Timer(
      const Duration(milliseconds: 900),
      () {
        if (mounted) {
          setState(() {
            _pendingSeekProgress = null;
          });
        }
      },
    );
    setState(() {
      _dragProgress = null;
      _pendingSeekProgress = target;
    });
  }
}

class _ProgressScrubber extends StatefulWidget {
  final double progress;
  final bool enabled;
  final Color activeColor;
  final Color inactiveColor;
  final ValueChanged<double> onChangeStart;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _ProgressScrubber({
    required this.progress,
    required this.enabled,
    required this.activeColor,
    required this.inactiveColor,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  State<_ProgressScrubber> createState() => _ProgressScrubberState();
}

class _ProgressScrubberState extends State<_ProgressScrubber> {
  double? _gestureProgress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalInset = 12.s;

        double valueFromDx(double dx) {
          final trackWidth = (constraints.maxWidth - (horizontalInset * 2))
              .clamp(1.0, double.infinity);
          return ((dx - horizontalInset) / trackWidth)
              .clamp(0.0, 1.0)
              .toDouble();
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
            onTapDown: widget.enabled
                ? (details) {
                    final value = valueFromDx(details.localPosition.dx);
                    widget.onChangeStart(value);
                    widget.onChangeEnd(value);
                  }
                : null,
            onHorizontalDragStart: widget.enabled
                ? (details) {
                    final value = valueFromDx(details.localPosition.dx);
                    _gestureProgress = value;
                    widget.onChangeStart(value);
                  }
                : null,
            onHorizontalDragUpdate: widget.enabled
                ? (details) {
                    final value = valueFromDx(details.localPosition.dx);
                    _gestureProgress = value;
                    widget.onChanged(value);
                  }
                : null,
            onHorizontalDragEnd: widget.enabled
                ? (_) {
                    widget.onChangeEnd(_gestureProgress ?? widget.progress);
                    _gestureProgress = null;
                  }
                : null,
            child: SizedBox(
              width: double.infinity,
              height: 32.h.clamp(28.0, 38.0).toDouble(),
              child: CustomPaint(
                painter: _ProgressBarPainter(
                  progress: widget.progress,
                  activeColor: widget.activeColor,
                  inactiveColor: widget.inactiveColor,
                  enabled: widget.enabled,
                  horizontalInset: horizontalInset,
                ),
                size: Size.infinite,
              ),
            ),
          );
      },
    );
  }
}

class _ProgressBarPainter extends CustomPainter {
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final bool enabled;
  final double horizontalInset;

  const _ProgressBarPainter({
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    required this.enabled,
    required this.horizontalInset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final trackHeight = size.height * 0.36;
    final radius = Radius.circular(4.s);
    final trackWidth =
        (size.width - (horizontalInset * 2)).clamp(0.0, size.width);
    final trackRect = Rect.fromLTWH(
      horizontalInset,
      centerY - trackHeight / 2,
      trackWidth,
      trackHeight,
    );
    final activeWidth = (trackWidth * progress).clamp(0.0, trackWidth);
    final activeRect = Rect.fromLTWH(
      trackRect.left,
      trackRect.top,
      activeWidth,
      trackHeight,
    );

    final bgPaint = Paint()
      ..color = inactiveColor.withOpacity(enabled ? 0.82 : 0.42)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(RRect.fromRectAndRadius(trackRect, radius), bgPaint);

    if (activeWidth > 0) {
      final activePaint = Paint()
        ..shader = LinearGradient(
          colors: [
            activeColor.withOpacity(enabled ? 0.78 : 0.40),
            activeColor,
          ],
        ).createShader(trackRect)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
          RRect.fromRectAndRadius(activeRect, radius), activePaint);
    }

    _drawMetroSegments(canvas, trackRect, activeWidth);

    final thumbX = (trackRect.left + activeWidth)
        .clamp(trackRect.left, trackRect.right)
        .toDouble();
    final haloPaint = Paint()
      ..color = activeColor.withOpacity(enabled ? 0.12 : 0.05)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(thumbX, centerY),
          width: 20.s,
          height: size.height * 0.78,
        ),
        Radius.circular(7.s),
      ),
      haloPaint,
    );

    final thumbPaint = Paint()
      ..color = enabled ? activeColor : activeColor.withOpacity(0.50)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(thumbX, centerY),
          width: 5.s,
          height: size.height * 0.70,
        ),
        Radius.circular(2.s),
      ),
      thumbPaint,
    );
  }

  void _drawMetroSegments(Canvas canvas, Rect trackRect, double activeWidth) {
    const segmentCount = 18;
    final gap = 3.s.clamp(2.0, 4.0).toDouble();
    final segmentWidth =
        ((trackRect.width - (gap * (segmentCount - 1))) / segmentCount)
            .clamp(4.0, 18.0)
            .toDouble();
    final segmentPaint = Paint()..style = PaintingStyle.fill;

    for (var i = 1; i < segmentCount; i++) {
      final x = trackRect.left + (i * (segmentWidth + gap)) - gap;
      final isActive = x - trackRect.left < activeWidth;
      segmentPaint.color = isActive
          ? Colors.white.withOpacity(enabled ? 0.22 : 0.10)
          : Colors.black.withOpacity(enabled ? 0.16 : 0.08);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            x,
            trackRect.top + 2,
            gap.clamp(1.0, 3.0).toDouble(),
            trackRect.height - 4,
          ),
          Radius.circular(1.s),
        ),
        segmentPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressBarPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.enabled != enabled ||
        oldDelegate.horizontalInset != horizontalInset;
  }
}
