import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../widgets/music_card.dart';
import '../widgets/cover_art_texture.dart';
import '../services/music_service.dart';
import '../models/settings_model.dart';
import '../models/playlist_model.dart';
import '../models/music_model.dart';
import '../models/cover_model.dart';
import 'playlist_detail_page.dart';

import '../services/responsive.dart';

class HomeScreen extends StatelessWidget {
  final String searchQuery;
  const HomeScreen({super.key, this.searchQuery = ''});

  @override
  Widget build(BuildContext context) {
    return Consumer2<MusicService, SettingsModel>(
      builder: (context, musicService, settings, child) {
        return Scaffold(
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

    final filteredMusic = musicService.musicList.where((m) {
      return m.title.toLowerCase().contains(searchQuery.toLowerCase()) ||
             m.artist.toLowerCase().contains(searchQuery.toLowerCase());
    }).toList();

    final isSearching = searchQuery.isNotEmpty;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: isSearching ? 40 : 60)),

        if (!isSearching) ...[
          // Even Larger Square Playlist Section with Collages
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
                  ...musicService.playlists.map((pl) => _buildSquarePlaylistCard(context, musicService, pl, Icons.playlist_play_rounded, theme.colorScheme.onSurface.withOpacity(0.4))),
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

        // Music Grid
        SliverPadding(
          padding: EdgeInsets.all(settings.cardMargins.w),
          sliver: filteredMusic.isEmpty
              ? SliverToBoxAdapter(child: _buildEmptyState(context, musicService, isSearching))
              : SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: settings.cardMargins.w,
                    mainAxisSpacing: settings.cardMargins.h,
                    childAspectRatio: 1.0,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final music = filteredMusic[index];
                      // Find actual index in musicService.musicList
                      final actualIndex = musicService.musicList.indexWhere((m) => m.id == music.id);
                      return MusicCard(
                        music: music,
                        onTap: () {
                          if (actualIndex != -1) {
                            musicService.currentIndex = actualIndex;
                            musicService.play();
                          }
                        },
                        onDelete: () => musicService.deleteMusic(actualIndex),
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
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => PlaylistDetailPage(playlist: playlist)));
      },
      child: Container(
        width: 180.s,
        margin: EdgeInsets.only(right: 16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 180.s,
              height: 180.s,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                borderRadius: BorderRadius.circular(28.s),
                border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.05), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.1),
                    blurRadius: 20.s,
                    spreadRadius: -5.s,
                  )
                ],
              ),
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
        ),
      ),
    );
  }

  Widget _buildPlaylistCollage(List<Music> musicList, IconData icon, Color color) {
    final musicWithCovers = musicList.where((m) => m.coverPath.isNotEmpty).toList();

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

    // 2x2 Grid Collage
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: CoverArtTexture(coverArtPath: musicWithCovers[0].coverPath, width: double.infinity, height: double.infinity)),
              Expanded(child: CoverArtTexture(coverArtPath: musicWithCovers[1].coverPath, width: double.infinity, height: double.infinity)),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(child: CoverArtTexture(coverArtPath: musicWithCovers[2].coverPath, width: double.infinity, height: double.infinity)),
              Expanded(child: CoverArtTexture(coverArtPath: musicWithCovers[3].coverPath, width: double.infinity, height: double.infinity)),
            ],
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 180.s,
              height: 180.s,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                borderRadius: BorderRadius.circular(28.s),
                border: Border.all(color: Colors.teal.withOpacity(0.2), width: 1),
              ),
              child: Center(
                child: Icon(Icons.add_rounded, color: Colors.teal, size: 60.s),
              ),
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

  Widget _buildEmptyState(BuildContext context, MusicService ms, bool isSearching) {
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
      child: ElevatedButton(onPressed: ms.loadSystemMusic, child: const Text('Scan Music')),
    );
  }

  int _calculateAutoCrossAxisCount(double screenWidth, double cardSize, double margin) {
    double availableWidth = screenWidth - (margin * 2);
    int count = (availableWidth / (cardSize + margin)).floor();
    return count < 1 ? 1 : count;
  }
}
