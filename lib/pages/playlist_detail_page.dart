import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';

import '../models/music_model.dart';
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
        final currentMusic = musicService.currentMusic;
        final bgPath = currentMusic?.coverPath ?? (musicList.isNotEmpty ? musicList.first.coverPath : '');

        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: Stack(
            children: [
              // ── Background Blur (Current Song) ──
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 1000),
                  child: Stack(
                    key: ValueKey(bgPath),
                    children: [
                      CoverArtTexture(coverArtPath: bgPath, width: double.infinity, height: double.infinity),
                      BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
                        child: Container(color: Colors.black.withOpacity(0.75)),
                      ),
                    ],
                  ),
                ),
              ),

              CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // ── Header Section ──
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(24.w, 100.h, 24.w, 32.h),
                      child: Column(
                        children: [
                          // Center Playlist Artwork
                          Center(
                            child: Hero(
                              tag: 'playlist-art-${playlist.id}',
                              child: Container(
                                width: 220.s,
                                height: 220.s,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(32.s),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.5),
                                      blurRadius: 30.s,
                                      offset: Offset(0, 15.h),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(32.s),
                                  child: _buildPlaylistCollage(musicList),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: 32.h),
                          
                          // Playlist Info
                          Text(
                            playlist.name,
                            style: TextStyle(fontSize: 36.sp, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1.5),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 8.h),
                          Text(
                            '${musicList.length} Tracks • curated for you',
                            style: TextStyle(fontSize: 14.sp, color: Colors.white54, fontWeight: FontWeight.w500),
                            textAlign: TextAlign.center,
                          ),
                          
                          SizedBox(height: 24.h),
                          
                          // Buttons Row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton.icon(
                                onPressed: () => musicService.playPlaylist(playlist.id),
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: const Text('Play All'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: settings.accentColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                  elevation: 8,
                                ),
                              ),
                              const SizedBox(width: 12),
                              IconButton(
                                icon: GlassContainer(
                                  padding: const EdgeInsets.all(12),
                                  borderRadius: BorderRadius.circular(16),
                                  color: Colors.white.withOpacity(0.08),
                                  child: const Icon(Icons.edit_note_rounded, color: Colors.white, size: 24),
                                ),
                                onPressed: () => _showEditPlaylistDialog(context, musicService),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Tracks List/Grid ──
                  if (musicList.isEmpty)
                    const SliverFillRemaining(
                      child: Center(
                        child: Text('Empty Playlist', style: TextStyle(color: Colors.white24)),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: 16.w),
                      sliver: settings.viewMode == ViewMode.card
                          ? SliverGrid(
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: _calculateCrossAxisCount(Responsive.screenWidth),
                                crossAxisSpacing: 16.w,
                                mainAxisSpacing: 16.h,
                                childAspectRatio: 1.0,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final music = musicList[index];
                                  return FadeInUpAnimation(
                                    delay: index * 0.03,
                                    child: MusicCard(
                                      music: music,
                                      viewMode: ViewMode.card,
                                      heroPrefix: 'playlist-detail',
                                      onTap: () => musicService.playMusicFromQueue(musicList, music, playlistId: playlist.id),
                                      onDelete: () => musicService.removeMusicFromPlaylist(playlist.id, music.id),
                                    ),
                                  );
                                },
                                childCount: musicList.length,
                              ),
                            )
                          : SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final music = musicList[index];
                                  return FadeInUpAnimation(
                                    delay: index * 0.03,
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

  Widget _buildPlaylistCollage(List<Music> musicList) {
    if (musicList.isEmpty) {
      return Container(
        color: Colors.white.withOpacity(0.05),
        child: const Icon(Icons.playlist_play_rounded, size: 100, color: Colors.white10),
      );
    }

    if (musicList.length < 4) {
      return CoverArtTexture(coverArtPath: musicList[0].coverPath, width: double.infinity, height: double.infinity);
    }

    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: CoverArtTexture(coverArtPath: musicList[0].coverPath, width: double.infinity, height: double.infinity)),
              Expanded(child: CoverArtTexture(coverArtPath: musicList[1].coverPath, width: double.infinity, height: double.infinity)),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(child: CoverArtTexture(coverArtPath: musicList[2].coverPath, width: double.infinity, height: double.infinity)),
              Expanded(child: CoverArtTexture(coverArtPath: musicList[3].coverPath, width: double.infinity, height: double.infinity)),
            ],
          ),
        ),
      ],
    );
  }

  int _calculateCrossAxisCount(double width) {
    if (width < 600) return 2;
    if (width < 900) return 3;
    return 4;
  }

  void _showEditPlaylistDialog(BuildContext context, MusicService musicService) {
    final controller = TextEditingController(text: playlist.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: GlassContainer(
          padding: const EdgeInsets.all(24),
          borderRadius: BorderRadius.circular(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Edit Playlist', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
                child: TextField(
                  controller: controller,
                  style: const TextStyle(fontSize: 16),
                  decoration: const InputDecoration(border: InputBorder.none, hintText: 'Playlist Name'),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () {
                      if (controller.text.isNotEmpty) {
                        musicService.renamePlaylist(playlist.id, controller.text);
                        Navigator.pop(context);
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                    child: const Text('Rename'),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}
