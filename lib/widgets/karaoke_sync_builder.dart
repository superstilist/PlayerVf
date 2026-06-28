import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:player_vf/models/lyrics_model.dart';
import 'package:player_vf/services/karaoke_sync_calculator.dart';
import 'package:player_vf/services/music_service.dart';

class KaraokeSyncBuilder extends StatefulWidget {
  final MusicService musicService;
  final LyricsDocument lyrics;
  final int transitionGapMs;
  final Widget Function(BuildContext context, KaraokeSyncState syncState)
      builder;

  const KaraokeSyncBuilder({
    super.key,
    required this.musicService,
    required this.lyrics,
    this.transitionGapMs = 700,
    required this.builder,
  });

  @override
  State<KaraokeSyncBuilder> createState() => _KaraokeSyncBuilderState();
}

class _KaraokeSyncBuilderState extends State<KaraokeSyncBuilder>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late KaraokeSyncCalculator _calculator;

  KaraokeSyncState _currentState = KaraokeSyncState.empty;
  Duration _anchorAudioPosition = Duration.zero;
  Duration _anchorTickElapsed = Duration.zero;
  Duration _lastTickElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _calculator =
        KaraokeSyncCalculator(transitionGapMs: widget.transitionGapMs);
    _ticker = createTicker(_onTick);
    _anchorAudioPosition = widget.musicService.positionNotifier.value;
    _ticker.start();

    widget.musicService.positionNotifier.addListener(_onPositionChanged);
    widget.musicService.playingNotifier.addListener(_onPositionChanged);
    widget.musicService.addListener(_onPositionChanged);
  }

  @override
  void didUpdateWidget(KaraokeSyncBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transitionGapMs != widget.transitionGapMs) {
      _calculator =
          KaraokeSyncCalculator(transitionGapMs: widget.transitionGapMs);
    }
    if (!identical(oldWidget.lyrics, widget.lyrics)) {
      _currentState = KaraokeSyncState.empty;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    widget.musicService.positionNotifier.removeListener(_onPositionChanged);
    widget.musicService.playingNotifier.removeListener(_onPositionChanged);
    widget.musicService.removeListener(_onPositionChanged);
    super.dispose();
  }

  void _onPositionChanged() {
    _anchorAudioPosition = widget.musicService.positionNotifier.value;
    _anchorTickElapsed = _lastTickElapsed;
    _updateFromAudioPosition();
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    _lastTickElapsed = elapsed;
    _updateFromAudioPosition();
  }

  void _updateFromAudioPosition() {
    final position = _sampleAudioPosition();
    final activeIndex = widget.lyrics.activeIndexAt(position);
    final lineSync = _calculator.compute(
      lyrics: widget.lyrics,
      activeIndex: activeIndex,
      position: position,
    );
    _currentState = KaraokeSyncState(
      position: position,
      lineSync: lineSync,
      activeIndex: activeIndex,
    );
    if (mounted) setState(() {});
  }

  Duration _sampleAudioPosition() {
    final backendPosition = widget.musicService.positionNotifier.value;
    final drift = (backendPosition - _anchorAudioPosition).inMilliseconds.abs();
    if (drift > 180) {
      _anchorAudioPosition = backendPosition;
      _anchorTickElapsed = _lastTickElapsed;
    }

    if (!widget.musicService.playingNotifier.value) {
      return backendPosition;
    }

    final effectiveSpeed =
        widget.musicService.isEffectsEnabled ? widget.musicService.speed : 1.0;
    final elapsedMs =
        (_lastTickElapsed - _anchorTickElapsed).inMicroseconds / 1000.0;
    final interpolatedMs =
        _anchorAudioPosition.inMilliseconds + elapsedMs * effectiveSpeed;
    final duration = widget.musicService.durationNotifier.value;
    final clampedMs = duration > Duration.zero
        ? interpolatedMs.clamp(0.0, duration.inMilliseconds.toDouble())
        : interpolatedMs.clamp(0.0, double.infinity);
    return Duration(milliseconds: clampedMs.round());
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _currentState);
  }
}

class KaraokeSyncState {
  final Duration position;
  final KaraokeLineSync lineSync;
  final int activeIndex;

  const KaraokeSyncState({
    required this.position,
    required this.lineSync,
    required this.activeIndex,
  });

  static const empty = KaraokeSyncState(
    position: Duration.zero,
    lineSync: KaraokeLineSync.empty,
    activeIndex: -1,
  );
}
