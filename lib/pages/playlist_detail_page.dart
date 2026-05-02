import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';

import '../models/playlist_model.dart';
import '../models/settings_model.dart';
import '../services/music_service.dart';
import '../services/responsive.dart';
import '../widgets/music_card.dart';
import '../widgets/cover_art_texture.dart';
import '../widgets/glass_container.dart';
import '../widgets/fade_in_up_animation.dart';

class PlaylistDetailPage extends StatelessWidget {
  final Playlist playlist;

  const PlaylistDetailPage({super.key, required this.playlist});

  @override
  Widget build(BuildContext context) {
    return Consumer2<MusicService, SettingsModel>(
      builder: (context, musicService, settings, child) {
        final musicList = musicService.getMusicListForPlaylist(playlist.id);
        final firstMusic = musicList.isNotEmpty ? musicList.first : null;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              // ── Background Blur layer ──
              if (firstMusic != null)
                Positioned.fill(
                  child: Stack(
                    children: [
                      CoverArtTexture(coverArtPath: firstMusic.coverPath, width: double.infinity, height: double.infinity),
                      BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                        child: Container(color: Colors.black.withOpacity(0.7)),
                      ),
                    ],
                  ),
                ),

              CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverAppBar(
                    expandedHeight: 300.h,
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                    pinned: true,
                    flexibleSpace: FlexibleSpaceBar(
                      background: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (firstMusic != null)
                            CoverArtTexture(coverArtPath: firstMusic.coverPath, width: double.infinity, height: double.infinity),
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black.withOpacity(0.9)],
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 20,
                            left: 20,
                            right: 20,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  playlist.name,
                                  style: TextStyle(fontSize: 32.sp, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${musicList.length} Tracks • Created ${playlist.createdAt.day}/${playlist.createdAt.month}/${playlist.createdAt.year}',
                                  style: TextStyle(fontSize: 14.sp, color: Colors.white60),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SliverPadding(
                    padding: EdgeInsets.all(20.w),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => musicService.playPlaylist(playlist.id),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Play All'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: settings.accentColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            icon: GlassContainer(
                              padding: const EdgeInsets.all(10),
                              borderRadius: BorderRadius.circular(12),
                              child: const Icon(Icons.shuffle_rounded, size: 20),
                            ),
                            onPressed: () {
                              musicService.toggleShuffle();
                              musicService.playPlaylist(playlist.id);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (musicList.isEmpty)
                    const SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.music_note_rounded, size: 64, color: Colors.white10),
                            SizedBox(height: 16),
                            Text('Playlist is empty', style: TextStyle(color: Colors.white30)),
                          ],
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: 10.w),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final music = musicList[index];
                            return FadeInUpAnimation(
                              delay: index * 0.05,
                              child: MusicCard(
                                music: music,
                                viewMode: ViewMode.list,
                                heroPrefix: 'playlist-detail',
                                onTap: () => musicService.playMusicFromQueue(musicList, music, playlistId: playlist.id),
                                onDelete: () => musicService.removeMusicFromPlaylist(playlist.id, music.id),
                              ),
                            );
                          },
                          childCount: musicList.length,
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(child: SizedBox(height: 120.h)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
