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

            return Column(
              children: [
                TweenAnimationBuilder<double>(
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
                    return SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 6.h,
                        thumbShape:
                            RoundSliderThumbShape(enabledThumbRadius: 6.s),
                        activeTrackColor: widget.activeColor,
                        inactiveTrackColor: widget.inactiveColor,
                        thumbColor: widget.activeColor,
                        overlayColor: widget.activeColor.withOpacity(0.14),
                        tickMarkShape: SliderTickMarkShape.noTickMark,
                      ),
                      child: Slider(
                        value: animatedProgress.clamp(0.0, 1.0).toDouble(),
                        min: 0,
                        max: 1,
                        onChangeStart: duration.inMilliseconds <= 0
                            ? null
                            : (value) {
                                _pendingSeekTimer?.cancel();
                                setState(() {
                                  _pendingSeekProgress = null;
                                  _dragProgress = value;
                                });
                              },
                        onChanged: duration.inMilliseconds <= 0
                            ? null
                            : (value) {
                                _pendingSeekTimer?.cancel();
                                setState(() {
                                  _pendingSeekProgress = null;
                                  _dragProgress = value;
                                });
                              },
                        onChangeEnd: duration.inMilliseconds <= 0
                            ? null
                            : (value) {
                                final target = value.clamp(0.0, 1.0);
                                widget.musicService.seekTo(
                                    _positionFor(target.toDouble(), duration));
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
                                  _pendingSeekProgress = target.toDouble();
                                });
                              },
                      ),
                    );
                  },
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.w),
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
}
