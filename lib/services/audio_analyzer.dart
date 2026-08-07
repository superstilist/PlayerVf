import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

class AudioTransientEvent {
  final Duration position;
  final double intensity;

  AudioTransientEvent({required this.position, required this.intensity});
}

class AudioAnalyzer extends ChangeNotifier {
  final AudioPlayer audioPlayer;
  
  // Stream to broadcast detected transient beats/phoneme changes
  final _transientController = StreamController<AudioTransientEvent>.broadcast();
  Stream<AudioTransientEvent> get transientStream => _transientController.stream;

  StreamSubscription<Duration>? _positionSub;
  Duration _lastPosition = Duration.zero;

  AudioAnalyzer({required this.audioPlayer}) {
    _initAnalysis();
  }

  void _initAnalysis() {
    _positionSub = audioPlayer.positionStream.listen((position) {
      final delta = (position - _lastPosition).inMilliseconds.abs();
      _lastPosition = position;

      // Detect position jumps that could indicate audio glitches or seek events.
      // A sudden jump > 50ms in a single position update suggests the player
      // skipped or buffered, which is a meaningful sync event.
      if (delta > 50 && delta < 2000) {
        _transientController.add(AudioTransientEvent(
          position: position,
          intensity: (delta / 500).clamp(0.3, 1.0),
        ));
      }
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _transientController.close();
    super.dispose();
  }
}
