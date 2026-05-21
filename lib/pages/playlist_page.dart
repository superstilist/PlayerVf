import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/settings_model.dart';
import '../widgets/playlist_card.dart';
import '../services/music_service.dart';
import '../widgets/fade_in_up_animation.dart';
import '../widgets/glass_container.dart';
import 'playlist_detail_page.dart';

import '../services/responsive.dart';

class PlaylistPage extends StatelessWidget {
  final String searchQuery;
  final VoidCallback? onOpenPlayer;

  const PlaylistPage({
    super.key,
    this.searchQuery = '',
    this.onOpenPlayer,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer2<MusicService, SettingsModel>(
      builder: (context, musicService, settings, child) {
        var playlists = musicService.allPlaylists;

        if (searchQuery.isNotEmpty) {
          playlists = playlists
              .where((pl) =>
                  pl.name.toLowerCase().contains(searchQuery.toLowerCase()))
              .toList();
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── Mica Header ──
              SliverToBoxAdapter(
                child: Container(
                  padding: EdgeInsets.fromLTRB(24.w, 60.h, 24.w, 20.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Your Collection',
                                style: TextStyle(
                                    fontSize: 32.sp,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface),
                              ),
                              Text(
                                '${playlists.length} Playlists curated for you',
                                style: TextStyle(
                                    fontSize: 14.sp,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withOpacity(0.54)),
                              ),
                            ],
                          ),
                          GestureDetector(
                            onTap: () => _showCreatePlaylistDialog(
                                context, musicService),
                            child: GlassContainer(
                              padding: const EdgeInsets.all(12),
                              borderRadius: BorderRadius.circular(16),
                              color: settings.accentColor.withOpacity(0.15),
                              blur: 10,
                              child: Icon(Icons.add_rounded,
                                  color: settings.accentColor, size: 28.s),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              if (playlists.isEmpty)
                SliverFillRemaining(
                    child: _buildEmptyState(context, musicService))
              else
                SliverPadding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: _calculateAdaptiveCrossAxisCount(
                          Responsive.screenWidth),
                      crossAxisSpacing: 20.w,
                      mainAxisSpacing: 20.h,
                      childAspectRatio: 0.82,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final playlist = playlists[index];
                        final isSystem = [
                          'favorites',
                          'most_listened',
                          'early_listened',
                          'daily_mix'
                        ].contains(playlist.id);

                        return FadeInUpAnimation(
                          delay: 0.05 * index,
                          child: PlaylistCard(
                            playlist: playlist,
                            onTap: () {
                              Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => PlaylistDetailPage(
                                            playlist: playlist,
                                            onOpenPlayer: onOpenPlayer,
                                          )));
                            },
                            onDelete: isSystem
                                ? null
                                : () =>
                                    musicService.deletePlaylist(playlist.id),
                          ),
                        );
                      },
                      childCount: playlists.length,
                    ),
                  ),
                ),
              SliverToBoxAdapter(child: SizedBox(height: 120.h)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, MusicService musicService) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome_motion_rounded,
              size: 80.s, color: Colors.white10),
          SizedBox(height: 24.h),
          const Text('Your library is empty',
              style: TextStyle(color: Colors.white54, fontSize: 16)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => _showCreatePlaylistDialog(context, musicService),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('Create Playlist'),
          ),
        ],
      ),
    );
  }

  int _calculateAdaptiveCrossAxisCount(double screenWidth) {
    if (screenWidth < 600) return 2;
    if (screenWidth < 1000) return 3;
    if (screenWidth < 1400) return 4;
    return 5;
  }

  void _showCreatePlaylistDialog(
      BuildContext context, MusicService musicService) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: GlassContainer(
          padding: const EdgeInsets.all(32),
          borderRadius: BorderRadius.circular(24),
          blur: 18,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Create Playlist',
                  style: TextStyle(
                      fontSize: 22.sp,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0)),
              const SizedBox(height: 24),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16)),
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  style: const TextStyle(fontSize: 16),
                  decoration: const InputDecoration(
                      hintText: 'Playlist Name',
                      border: InputBorder.none,
                      hintStyle: TextStyle(color: Colors.white24)),
                ),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel',
                          style: TextStyle(color: Colors.white54)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (controller.text.isNotEmpty) {
                          musicService.createPlaylist(controller.text);
                          Navigator.pop(context);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Create'),
                    ),
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
