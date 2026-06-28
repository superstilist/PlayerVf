import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/music_model.dart';
import '../services/music_service.dart';
import '../services/responsive.dart';
import '../widgets/cover_art_texture.dart';
import 'artist_page.dart';

class AlbumDetailPage extends StatelessWidget {
  final String albumName;
  const AlbumDetailPage({super.key, required this.albumName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final musicService = context.read<MusicService>();
    final songs = musicService.musicList
        .where((m) => m.album.toLowerCase() == albumName.toLowerCase())
        .toList();
    final coverPath = songs.isNotEmpty ? songs.first.coverPath : '';
    final artist = songs.isNotEmpty ? songs.first.artist : '';

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: theme.colorScheme.surface,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              title: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    albumName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  if (artist.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          PageRouteBuilder(
                            transitionDuration: const Duration(milliseconds: 320),
                            reverseTransitionDuration: const Duration(milliseconds: 280),
                            pageBuilder: (_, __, ___) => ArtistPage(
                              artistName: artist,
                              localCoverPath: coverPath,
                            ),
                            transitionsBuilder: (_, anim, __, child) {
                              return FadeTransition(
                                opacity: CurvedAnimation(
                                  parent: anim,
                                  curve: Curves.easeOutCubic,
                                ),
                                child: child,
                              );
                            },
                          ),
                        );
                      },
                      child: Text(
                        artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.primary.withOpacity(0.8),
                        ),
                      ),
                    ),
                ],
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (coverPath.isNotEmpty)
                    CoverArtTexture(
                      coverArtPath: coverPath,
                      width: double.infinity,
                      height: double.infinity,
                      filterQuality: FilterQuality.medium,
                    ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          theme.colorScheme.surface,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 4.h),
              child: Text(
                '${songs.length} song${songs.length == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final music = songs[index];
                return _SongTile(music: music, songs: songs);
              },
              childCount: songs.length,
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
        ],
      ),
    );
  }
}

class _SongTile extends StatelessWidget {
  final Music music;
  final List<Music> songs;
  const _SongTile({required this.music, required this.songs});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final musicService = context.read<MusicService>();
    final currentMusic = context.select<MusicService, Music?>(
      (s) => s.currentMusic,
    );
    final isPlaying = currentMusic?.id == music.id;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 44,
          height: 44,
          child: music.coverPath.isNotEmpty
              ? CoverArtTexture(
                  coverArtPath: music.coverPath,
                  width: 44,
                  height: 44,
                )
              : Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(Icons.music_note_rounded,
                      color: theme.colorScheme.onSurface.withOpacity(0.4)),
                ),
        ),
      ),
      title: Text(
        music.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isPlaying ? FontWeight.w700 : FontWeight.w600,
          fontSize: 14,
          color: isPlaying ? theme.colorScheme.primary : null,
        ),
      ),
      subtitle: Text(
        music.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.onSurface.withOpacity(0.5),
        ),
      ),
      trailing: Text(
        _formatDuration(music.duration),
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.onSurface.withOpacity(0.4),
        ),
      ),
      onTap: () {
        musicService.playMusicFromQueue(songs, music);
      },
    );
  }

  String _formatDuration(Duration? d) {
    if (d == null) return '';
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
