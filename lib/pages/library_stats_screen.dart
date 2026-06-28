import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/settings_model.dart';
import '../services/music_service.dart';
import '../widgets/glass_container.dart';

class LibraryStatsScreen extends StatelessWidget {
  const LibraryStatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final musicService = context.watch<MusicService>();
    final settings = context.watch<SettingsModel>();
    final stats = musicService.libraryStatsDashboard;

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          title: const Text(
            'Mini Stats',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Theme.of(context).colorScheme.surface,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => Navigator.pop(context),
          ),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Library'),
              Tab(text: 'Metadata'),
              Tab(text: 'Listening'),
              Tab(text: 'AI Signals'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _OverviewTab(stats: stats, accent: settings.accentColor),
            _LibraryTab(stats: stats, accent: settings.accentColor),
            _MetadataTab(stats: stats, accent: settings.accentColor),
            _ListeningTab(stats: stats, accent: settings.accentColor),
            _AiSignalsTab(stats: stats, accent: settings.accentColor),
          ],
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  final LibraryStatsDashboard stats;
  final Color accent;

  const _OverviewTab({required this.stats, required this.accent});

  @override
  Widget build(BuildContext context) {
    return _StatsList(
      children: [
        const _SummaryCard(),
        _MetricGrid(
          items: [
            _MetricData('Records', '${stats.totalRecords}',
                Icons.library_music_rounded),
            _MetricData(
                'Liked', '${stats.likedRecords}', Icons.favorite_rounded),
            _MetricData(
                'Played', '${stats.playedRecords}', Icons.play_circle_rounded),
            _MetricData(
                'Videos', '${stats.videoRecords}', Icons.videocam_rounded),
            _MetricData('Playlists', '${stats.playlistCount}',
                Icons.playlist_play_rounded),
            _MetricData('Duration', _formatDuration(stats.totalDuration),
                Icons.timer_rounded),
            _MetricData('Plays', '${stats.totalPlays}', Icons.repeat_rounded),
            _MetricData('AI picks', '${stats.aiCandidates}',
                Icons.auto_awesome_rounded),
          ],
          accent: accent,
        ),
        _RankSection(
          title: 'Playlist sizes',
          emptyText: 'No playlists yet',
          items: stats.playlistRanks,
          accent: accent,
        ),
      ],
    );
  }
}

class _LibraryTab extends StatelessWidget {
  final LibraryStatsDashboard stats;
  final Color accent;

  const _LibraryTab({required this.stats, required this.accent});

  @override
  Widget build(BuildContext context) {
    return _StatsList(
      children: [
        _DonutCard(
          title: 'Media type',
          emptyText: 'No media data yet',
          slices: stats.mediaSlices,
          accent: accent,
        ),
        _DonutCard(
          title: 'Likes',
          emptyText: 'No like data yet',
          slices: stats.likedSlices,
          accent: accent,
        ),
        _DonutCard(
          title: 'Play history',
          emptyText: 'No play data yet',
          slices: stats.playedSlices,
          accent: accent,
        ),
      ],
    );
  }
}

class _MetadataTab extends StatelessWidget {
  final LibraryStatsDashboard stats;
  final Color accent;

  const _MetadataTab({required this.stats, required this.accent});

  @override
  Widget build(BuildContext context) {
    return _StatsList(
      children: [
        _RankSection(
          title: 'Genres',
          emptyText: 'No genre data yet',
          items: stats.genreRanks,
          accent: accent,
        ),
        _RankSection(
          title: 'Artists',
          emptyText: 'No artist data yet',
          items: stats.artistRanks,
          accent: accent,
        ),
        _RankSection(
          title: 'Albums',
          emptyText: 'No album data yet',
          items: stats.albumRanks,
          accent: accent,
        ),
        _RankSection(
          title: 'Years',
          emptyText: 'No year data yet',
          items: stats.yearRanks,
          accent: accent,
        ),
      ],
    );
  }
}

class _ListeningTab extends StatelessWidget {
  final LibraryStatsDashboard stats;
  final Color accent;

  const _ListeningTab({required this.stats, required this.accent});

  @override
  Widget build(BuildContext context) {
    return _StatsList(
      children: [
        _RankSection(
          title: 'Top played tracks',
          emptyText: 'No plays yet',
          items: stats.topPlayedTracks,
          accent: accent,
        ),
        _RankSection(
          title: 'Recently played',
          emptyText: 'No recently played tracks yet',
          items: stats.recentlyPlayed,
          accent: accent,
        ),
        _RankSection(
          title: 'Early listened',
          emptyText: 'No early listened tracks yet',
          items: stats.earlyListened,
          accent: accent,
        ),
      ],
    );
  }
}

class _AiSignalsTab extends StatelessWidget {
  final LibraryStatsDashboard stats;
  final Color accent;

  const _AiSignalsTab({required this.stats, required this.accent});

  @override
  Widget build(BuildContext context) {
    return _StatsList(
      children: [
        const _SummaryCard(),
        _SignalSection(
          signals: stats.recommendationSignals,
          accent: accent,
        ),
        _RankSection(
          title: 'Top genre signal',
          emptyText: 'No genre signal yet',
          items: [stats.topGenre],
          accent: accent,
        ),
        _RankSection(
          title: 'Top artist signal',
          emptyText: 'No artist signal yet',
          items: [stats.topArtist],
          accent: accent,
        ),
      ],
    );
  }
}

class _StatsList extends StatelessWidget {
  final List<Widget> children;

  const _StatsList({required this.children});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      itemBuilder: (context, index) => children[index],
      separatorBuilder: (context, index) => const SizedBox(height: 14),
      itemCount: children.length,
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassContainer(
      padding: const EdgeInsets.all(18),
      borderRadius: BorderRadius.circular(18),
      blur: 14,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_graph_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Local stats and recommendation signals stay on this device.',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 6),
                Text(
                  'Mini AI reads your likes, genres, artists, years, plays, and recency to rank local tracks.',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.62),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  final List<_MetricData> items;
  final Color accent;

  const _MetricGrid({required this.items, required this.accent});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 700 ? 4 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: columns == 4 ? 2.6 : 2.1,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return GlassContainer(
              padding: const EdgeInsets.all(12),
              borderRadius: BorderRadius.circular(14),
              blur: 10,
              child: Row(
                children: [
                  Icon(item.icon, color: accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.58),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _DonutCard extends StatelessWidget {
  final String title;
  final String emptyText;
  final List<StatsSlice> slices;
  final Color accent;

  const _DonutCard({
    required this.title,
    required this.emptyText,
    required this.slices,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<int>(0, (sum, slice) => sum + slice.value);
    final visible = slices.where((slice) => slice.value > 0).toList();
    final colors = _chartColors(accent, visible.length);
    final theme = Theme.of(context);

    return GlassContainer(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(18),
      blur: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          if (total <= 0)
            Text(emptyText,
                style: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.58)))
          else
            Row(
              children: [
                SizedBox(
                  width: 132,
                  height: 132,
                  child: CustomPaint(
                    painter: _DonutPainter(slices: visible, colors: colors),
                    child: Center(
                      child: Text(
                        '$total',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    children: [
                      for (var i = 0; i < visible.length; i++)
                        _LegendRow(
                          color: colors[i],
                          label: visible[i].label,
                          value: visible[i].value,
                        ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _RankSection extends StatelessWidget {
  final String title;
  final String emptyText;
  final List<StatsRankItem> items;
  final Color accent;

  const _RankSection({
    required this.title,
    required this.emptyText,
    required this.items,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = items.where((item) => item.value > 0).take(8).toList();

    return GlassContainer(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(18),
      blur: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          if (visible.isEmpty)
            Text(emptyText,
                style: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.58)))
          else
            for (final item in visible) ...[
              _BarRow(
                label: item.label,
                value: item.value.toString(),
                ratio: item.ratio,
                subtitle: item.subtitle,
                accent: accent,
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _SignalSection extends StatelessWidget {
  final List<RecommendationSignalStat> signals;
  final Color accent;

  const _SignalSection({required this.signals, required this.accent});

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(18),
      blur: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recommendation score inputs',
              style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          if (signals.isEmpty)
            Text(
              'No recommendation signals yet',
              style: TextStyle(
                color:
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.58),
              ),
            )
          else
            for (final signal in signals) ...[
              _BarRow(
                label: signal.label,
                value: signal.value.toString(),
                ratio: signal.ratio,
                accent: accent,
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  final String label;
  final String value;
  final double ratio;
  final String? subtitle;
  final Color accent;

  const _BarRow({
    required this.label,
    required this.value,
    required this.ratio,
    required this.accent,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 10),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
        if (subtitle != null)
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.colorScheme.onSurface.withOpacity(0.52),
              fontSize: 12,
            ),
          ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: CustomPaint(
            painter: _BarPainter(
              ratio: ratio.clamp(0.0, 1.0).toDouble(),
              color: accent,
              background:
                  theme.colorScheme.surfaceContainerHighest.withOpacity(0.42),
            ),
            child: const SizedBox(height: 8, width: double.infinity),
          ),
        ),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final int value;

  const _LegendRow({
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text('$value', style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<StatsSlice> slices;
  final List<Color> colors;

  const _DonutPainter({required this.slices, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<int>(0, (sum, slice) => sum + slice.value);
    if (total <= 0) return;

    final rect = Offset.zero & size;
    final stroke = size.shortestSide * 0.18;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    var start = -math.pi / 2;
    for (var i = 0; i < slices.length; i++) {
      final sweep = (slices[i].value / total) * math.pi * 2;
      paint.color = colors[i];
      canvas.drawArc(rect.deflate(stroke / 2), start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.slices != slices || oldDelegate.colors != colors;
  }
}

class _BarPainter extends CustomPainter {
  final double ratio;
  final Color color;
  final Color background;

  const _BarPainter({
    required this.ratio,
    required this.color,
    required this.background,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    final backgroundPaint = Paint()..color = background;
    final foregroundPaint = Paint()..color = color;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius),
      backgroundPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width * ratio, size.height),
        radius,
      ),
      foregroundPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _BarPainter oldDelegate) {
    return oldDelegate.ratio != ratio ||
        oldDelegate.color != color ||
        oldDelegate.background != background;
  }
}

class _MetricData {
  final String label;
  final String value;
  final IconData icon;

  const _MetricData(this.label, this.value, this.icon);
}

List<Color> _chartColors(Color accent, int count) {
  return List<Color>.generate(count, (index) {
    final hue = (HSVColor.fromColor(accent).hue + (index * 47)) % 360;
    return HSVColor.fromAHSV(1, hue, 0.62, 0.88).toColor();
  });
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours <= 0) return '${minutes}m';
  return '${hours}h ${minutes}m';
}
