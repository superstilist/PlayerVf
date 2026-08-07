class LibraryMiniStat {
  final String label;
  final String value;
  final double ratio;
  const LibraryMiniStat(this.label, this.value, this.ratio);
}

class StatsSlice {
  final String label;
  final int value;
  const StatsSlice(this.label, this.value);
}

class StatsRankItem {
  final String label;
  final int count;
  final double ratio;
  final String subtitle;
  const StatsRankItem(this.label, this.count, this.ratio, {this.subtitle = ''});

  int get value => count;
}

class RecommendationSignalStat {
  final String label;
  final int count;
  final double ratio;
  const RecommendationSignalStat(this.label, this.count, this.ratio);

  int get value => count;
}

class LibraryStatsDashboard {
  final int totalRecords;
  final int musicRecords;
  final int videoRecords;
  final int likedRecords;
  final int playedRecords;
  final int playlistCount;
  final int totalPlays;
  final Duration totalDuration;
  final int genreCount;
  final int artistCount;
  final int albumCount;
  final int yearCount;
  final int aiCandidates;
  final StatsRankItem topGenre;
  final StatsRankItem topArtist;
  final List<StatsSlice> mediaSlices;
  final List<StatsSlice> likedSlices;
  final List<StatsSlice> playedSlices;
  final List<StatsRankItem> genreRanks;
  final List<StatsRankItem> artistRanks;
  final List<StatsRankItem> albumRanks;
  final List<StatsRankItem> yearRanks;
  final List<StatsRankItem> playlistRanks;
  final List<StatsRankItem> topPlayedTracks;
  final List<StatsRankItem> recentlyPlayed;
  final List<StatsRankItem> earlyListened;
  final List<RecommendationSignalStat> recommendationSignals;

  const LibraryStatsDashboard({
    required this.totalRecords,
    required this.musicRecords,
    required this.videoRecords,
    required this.likedRecords,
    required this.playedRecords,
    required this.playlistCount,
    required this.totalPlays,
    required this.totalDuration,
    required this.genreCount,
    required this.artistCount,
    required this.albumCount,
    required this.yearCount,
    required this.aiCandidates,
    required this.topGenre,
    required this.topArtist,
    required this.mediaSlices,
    required this.likedSlices,
    required this.playedSlices,
    required this.genreRanks,
    required this.artistRanks,
    required this.albumRanks,
    required this.yearRanks,
    required this.playlistRanks,
    required this.topPlayedTracks,
    required this.recentlyPlayed,
    required this.earlyListened,
    required this.recommendationSignals,
  });
}

class RankItem {
  final String label;
  final int count;
  final double ratio;
  const RankItem(this.label, this.count, this.ratio);
}

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