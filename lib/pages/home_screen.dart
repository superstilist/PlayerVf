import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/music_model.dart';
import '../models/playlist_model.dart';
import '../models/settings_model.dart';
import '../services/music_service.dart';
import '../services/responsive.dart';
import '../widgets/cover_art_texture.dart';
import '../widgets/music_card.dart';
import '../widgets/glass_container.dart';
import 'playlist_detail_page.dart';

class HomeScreen extends StatelessWidget {
  final String searchQuery;

  const HomeScreen({super.key, this.searchQuery = ''});

  @override
  Widget build(BuildContext context) {
    return Consumer2<MusicService, SettingsModel>(
      builder: (context, musicService, settings, child) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: _buildResponsiveLayout(context, musicService, settings),
        );
      },
    );
  }

  Widget _buildResponsiveLayout(BuildContext context, MusicService musicService, SettingsModel settings) {
    final theme = Theme.of(context);
    int crossAxisCount;
    if (settings.useAutoCardCount) {
      crossAxisCount = _calculateAutoCrossAxisCount(Responsive.screenWidth, settings.cardSize, settings.cardMargins);
    } else {
      crossAxisCount = settings.cardCount;
    }
    if (crossAxisCount < 1) crossAxisCount = 1;

    if (musicService.isLoadingSystemMusic) {
      return const Center(child: CircularProgressIndicator(color: Colors.teal));
    }

    final filteredMusic = musicService.musicList.where((music) {
      return music.title.toLowerCase().contains(searchQuery.toLowerCase()) ||
          music.artist.toLowerCase().contains(searchQuery.toLowerCase());
    }).toList();

    final isSearching = searchQuery.isNotEmpty;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: isSearching ? 40 : 60)),
        if (!isSearching) ...[
          SliverToBoxAdapter(
            child: SizedBox(
              height: 230.h,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                children: [
                  _buildSquarePlaylistCard(context, musicService, musicService.systemPlaylists[3], Icons.auto_awesome_rounded, Colors.tealAccent),
                  _buildSquarePlaylistCard(context, musicService, musicService.systemPlaylists[1], Icons.trending_up_rounded, Colors.purpleAccent),
                  _buildSquarePlaylistCard(context, musicService, musicService.systemPlaylists[2], Icons.access_time_rounded, Colors.blueAccent),
                  _buildSquarePlaylistCard(context, musicService, musicService.systemPlaylists[0], Icons.favorite_rounded, Colors.redAccent),
                  _buildAddPlaylistSquare(context, musicService),
                  ...musicService.playlists.map(
                    (playlist) => _buildSquarePlaylistCard(
                      context,
                      musicService,
                      playlist,
                      Icons.playlist_play_rounded,
                      theme.colorScheme.onSurface.withOpacity(0.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16.w, 32.h, 16.w, 12.h),
              child: Text(
                'Your Library',
                style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
        SliverPadding(
          padding: EdgeInsets.symmetric(
            horizontal: settings.viewMode == ViewMode.list ? 0 : settings.cardMargins.w,
            vertical: settings.cardMargins.h,
          ),
          sliver: filteredMusic.isEmpty
              ? SliverToBoxAdapter(child: _buildEmptyState(context, musicService, isSearching))
              : settings.viewMode == ViewMode.card
                  ? SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: settings.cardMargins.w,
                        mainAxisSpacing: settings.cardMargins.h,
                        childAspectRatio: 1.0,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final music = filteredMusic[index];
                          final actualIndex = musicService.musicList.indexWhere((item) => item.id == music.id);
                          return MusicCard(
                            music: music,
                            viewMode: settings.viewMode,
                            heroPrefix: 'home-${settings.viewMode}',
                            onTap: () => musicService.playMusicFromQueue(filteredMusic, music),
                            onDelete: actualIndex == -1 ? null : () => musicService.deleteMusic(actualIndex),
                          );
                        },
                        childCount: filteredMusic.length,
                      ),
                    )
                  : SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final music = filteredMusic[index];
                          final actualIndex = musicService.musicList.indexWhere((item) => item.id == music.id);
                          return MusicCard(
                            music: music,
                            viewMode: settings.viewMode,
                            heroPrefix: 'home-${settings.viewMode}',
                            onTap: () => musicService.playMusicFromQueue(filteredMusic, music),
                            onDelete: actualIndex == -1 ? null : () => musicService.deleteMusic(actualIndex),
                          );
                        },
                        childCount: filteredMusic.length,
                      ),
                    ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 100.h)),
      ],
    );
  }

  Widget _buildSquarePlaylistCard(BuildContext context, MusicService musicService, Playlist playlist, IconData icon, Color color) {
    final musicList = musicService.getMusicListForPlaylist(playlist.id);
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => PlaylistDetailPage(playlist: playlist))),
      child: Container(
        width: 180.s,
        margin: EdgeInsets.only(right: 16.w),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final artworkSize = (constraints.maxHeight - 42.h).clamp(110.0, 180.s.toDouble());
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GlassContainer(
                  width: artworkSize,
                  height: artworkSize,
                  color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(28.s),
                  blur: 0.0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28.s),
                    child: _buildPlaylistCollage(musicList, icon, color),
                  ),
                ),
                SizedBox(height: 10.h),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.w),
                  child: Text(
                    playlist.name,
                    style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPlaylistCollage(List<Music> musicList, IconData icon, Color color) {
    final musicWithCovers = musicList.where((music) => music.coverPath.isNotEmpty).toList();

    if (musicWithCovers.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withOpacity(0.2), Colors.black12],
          ),
        ),
        child: Center(child: Icon(icon, color: color.withOpacity(0.5), size: 60.s)),
      );
    }

    if (musicWithCovers.length < 4) {
      return CoverArtTexture(
        coverArtPath: musicWithCovers[0].coverPath,
        width: double.infinity,
        height: double.infinity,
      );
    }

    // High-quality 2x2 grid collage with no gaps
    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Image.file(
                      io.File(musicWithCovers[0].coverPath),
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, __, ___) => CoverArtTexture(coverArtPath: musicWithCovers[0].coverPath, width: double.infinity, height: double.infinity),
                    ),
                  ),
                  Expanded(
                    child: Image.file(
                      io.File(musicWithCovers[1].coverPath),
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, __, ___) => CoverArtTexture(coverArtPath: musicWithCovers[1].coverPath, width: double.infinity, height: double.infinity),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Image.file(
                      io.File(musicWithCovers[2].coverPath),
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, __, ___) => CoverArtTexture(coverArtPath: musicWithCovers[2].coverPath, width: double.infinity, height: double.infinity),
                    ),
                  ),
                  Expanded(
                    child: Image.file(
                      io.File(musicWithCovers[3].coverPath),
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, __, ___) => CoverArtTexture(coverArtPath: musicWithCovers[3].coverPath, width: double.infinity, height: double.infinity),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        // Subtle gradient overlay for a polished look
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black.withOpacity(0.15)],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddPlaylistSquare(BuildContext context, MusicService musicService) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => _showCreatePlaylistDialog(context, musicService),
      child: Container(
        width: 180.s,
        margin: EdgeInsets.only(right: 16.w),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final artworkSize = (constraints.maxHeight - 42.h).clamp(110.0, 180.s.toDouble());
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GlassContainer(
                  width: artworkSize,
                  height: artworkSize,
                  color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(28.s),
                  blur: 0.0,
                  child: Center(child: Icon(Icons.add_rounded, color: Colors.teal, size: 60.s)),
                ),
                SizedBox(height: 10.h),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.w),
                  child: Text(
                    'New List',
                    style: TextStyle(color: Colors.teal, fontSize: 14.sp, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showCreatePlaylistDialog(BuildContext context, MusicService musicService) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Name...',
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.teal)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                musicService.createPlaylist(controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text('Create', style: TextStyle(color: Colors.teal)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, MusicService musicService, bool isSearching) {
    final theme = Theme.of(context);
    if (isSearching) {
      return Center(
        child: Padding(
          padding: EdgeInsets.only(top: 50.h),
          child: Column(
            children: [
              Icon(Icons.search_off_rounded, color: theme.colorScheme.onSurface.withOpacity(0.2), size: 64.s),
              SizedBox(height: 16.h),
              Text('No songs found', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.2), fontSize: 16.sp)),
            ],
          ),
        ),
      );
    }
    return Center(
      child: ElevatedButton(onPressed: musicService.loadSystemMusic, child: const Text('Scan Music')),
    );
  }

  int _calculateAutoCrossAxisCount(double screenWidth, double cardSize, double margin) {
    final availableWidth = screenWidth - (margin * 2);
    final count = (availableWidth / (cardSize + margin)).floor();
    return count < 1 ? 1 : count;
  }
}
