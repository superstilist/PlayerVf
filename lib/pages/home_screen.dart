import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../widgets/music_card.dart';
import '../services/music_service.dart';
import '../models/settings_model.dart';
import '../models/playlist_model.dart';
import '../models/cover_model.dart';
import 'playlist_detail_page.dart';

import '../services/responsive.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<MusicService, SettingsModel>(
      builder: (context, musicService, settings, child) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: _buildResponsiveLayout(context, musicService, settings),
        );
      },
    );
  }

  Widget _buildResponsiveLayout(BuildContext context, MusicService musicService, SettingsModel settings) {
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

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: 50.h)),

        // Even Larger Square Playlist Section with Collages
        SliverToBoxAdapter(
          child: SizedBox(
            height: 230.h, // Scaled for bigger cards
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              children: [
                _buildSquarePlaylistCard(context, musicService, musicService.systemPlaylists[3], Icons.auto_awesome_rounded, Colors.tealAccent), // Daily Mix
                _buildSquarePlaylistCard(context, musicService, musicService.systemPlaylists[1], Icons.trending_up_rounded, Colors.purpleAccent), // Most Listened
                _buildSquarePlaylistCard(context, musicService, musicService.systemPlaylists[2], Icons.access_time_rounded, Colors.blueAccent), // Early Listened
                _buildSquarePlaylistCard(context, musicService, musicService.systemPlaylists[0], Icons.favorite_rounded, Colors.redAccent), // Favorites
                
                // Add Playlist
                _buildAddPlaylistSquare(context, musicService),

                // User Playlists
                ...musicService.playlists.map((pl) => _buildSquarePlaylistCard(context, musicService, pl, Icons.playlist_play_rounded, Colors.white38)),
              ],
            ),
          ),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16.w, 32.h, 16.w, 12.h),
            child: Text(
              'Your Library',
              style: TextStyle(color: Colors.white, fontSize: 20.sp, fontWeight: FontWeight.bold),
            ),
          ),
        ),

        // Music Grid
        SliverPadding(
          padding: EdgeInsets.all(settings.cardMargins.w),
          sliver: musicService.musicList.isEmpty
              ? SliverToBoxAdapter(child: _buildEmptyState(musicService))
              : SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: settings.cardMargins.w,
                    mainAxisSpacing: settings.cardMargins.h,
                    childAspectRatio: 1.0,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final music = musicService.musicList[index];
                      final cover = index < musicService.coverList.length ? musicService.coverList[index] : null;
                      return MusicCard(
                        music: music,
                        cover: cover,
                        onTap: () {
                          musicService.currentIndex = index;
                          musicService.play();
                        },
                        onDelete: () => musicService.deleteMusic(index),
                      );
                    },
                    childCount: musicService.musicList.length,
                  ),
                ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 100.h)),
      ],
    );
  }

  Widget _buildSquarePlaylistCard(BuildContext context, MusicService musicService, Playlist playlist, IconData icon, Color color) {
    final covers = musicService.getCoverListForPlaylist(playlist.id);
    
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
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(28.s),
                border: Border.all(color: Colors.white.withOpacity(0.05), width: 1),
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
                child: _buildPlaylistCollage(covers, icon, color),
              ),
            ),
            SizedBox(height: 10.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.w),
              child: Text(
                playlist.name,
                style: TextStyle(color: Colors.white, fontSize: 14.sp, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistCollage(List<Cover> covers, IconData icon, Color color) {
    final validCovers = covers.where((c) => c.imageData != null).toList();

    if (validCovers.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withOpacity(0.2), Colors.black],
          ),
        ),
        child: Center(child: Icon(icon, color: color.withOpacity(0.5), size: 60.s)),
      );
    }

    if (validCovers.length < 4) {
      return Image.memory(validCovers[0].imageData!, fit: BoxFit.cover);
    }

    // 2x2 Grid Collage
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: Image.memory(validCovers[0].imageData!, fit: BoxFit.cover)),
              Expanded(child: Image.memory(validCovers[1].imageData!, fit: BoxFit.cover)),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(child: Image.memory(validCovers[2].imageData!, fit: BoxFit.cover)),
              Expanded(child: Image.memory(validCovers[3].imageData!, fit: BoxFit.cover)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAddPlaylistSquare(BuildContext context, MusicService musicService) {
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
                color: Colors.grey[900],
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
        backgroundColor: Colors.grey[900],
        title: const Text('New Playlist', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Name...',
            hintStyle: TextStyle(color: Colors.white24),
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

  Widget _buildEmptyState(MusicService ms) {
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
