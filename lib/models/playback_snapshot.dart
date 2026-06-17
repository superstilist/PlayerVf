class PlaybackSnapshot {
  final Duration position;
  final Duration duration;
  final Duration songGapRemaining;
  final bool isPlaying;
  final double volume;

  const PlaybackSnapshot({
    required this.position,
    required this.duration,
    required this.songGapRemaining,
    required this.isPlaying,
    required this.volume,
  });

  static const PlaybackSnapshot empty = PlaybackSnapshot(
    position: Duration.zero,
    duration: Duration.zero,
    songGapRemaining: Duration.zero,
    isPlaying: false,
    volume: 100.0,
  );

  PlaybackSnapshot copyWith({
    Duration? position,
    Duration? duration,
    Duration? songGapRemaining,
    bool? isPlaying,
    double? volume,
  }) {
    return PlaybackSnapshot(
      position: position ?? this.position,
      duration: duration ?? this.duration,
      songGapRemaining: songGapRemaining ?? this.songGapRemaining,
      isPlaying: isPlaying ?? this.isPlaying,
      volume: volume ?? this.volume,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaybackSnapshot &&
          runtimeType == other.runtimeType &&
          position == other.position &&
          duration == other.duration &&
          songGapRemaining == other.songGapRemaining &&
          isPlaying == other.isPlaying &&
          volume == other.volume;

  @override
  int get hashCode => Object.hash(
        position,
        duration,
        songGapRemaining,
        isPlaying,
        volume,
      );
}