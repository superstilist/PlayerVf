import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/settings_model.dart';
import '../services/music_service.dart';
import '../services/responsive.dart';
import '../widgets/music_card.dart';

class FavoritePage extends StatelessWidget {
  final String searchQuery;

  const FavoritePage({super.key, this.searchQuery = ''});

  @override
  Widget build(BuildContext context) {
    return Consumer2<MusicService, SettingsModel>(
      builder: (context, musicService, settings, child) {
        final crossAxisCount = _calculateAdaptiveCrossAxisCount(Responsive.screenWidth);
        final padding = settings.viewMode == ViewMode.list ? 0.0 : 16.w;

        if (musicService.isLoadingSystemMusic) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(color: Colors.teal),
                SizedBox(height: 16.h),
                Text(
                  'Scanning music... ${musicService.systemMusicCount} files',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14.sp),
                ),
              ],
            ),
          );
        }

        final favoriteMusicList = musicService.favoriteMusicList.where((music) {
          return music.title.toLowerCase().contains(searchQuery.toLowerCase()) ||
              music.artist.toLowerCase().contains(searchQuery.toLowerCase());
        }).toList();

        final isSearching = searchQuery.isNotEmpty;

        if (favoriteMusicList.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isSearching ? Icons.search_off_rounded : Icons.favorite_border,
                  size: 80.s,
                  color: Colors.grey[600],
                ),
                SizedBox(height: 16.h),
                Text(
                  isSearching ? 'No favorite songs found' : 'No favorite songs',
                  style: TextStyle(color: Colors.grey[600], fontSize: 18.sp),
                ),
                SizedBox(height: 8.h),
                if (!isSearching)
                  Text(
                    'Tap the heart icon on songs to add them to favorites',
                    style: TextStyle(color: Colors.grey[700], fontSize: 14.sp),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          );
        }

        if (settings.viewMode == ViewMode.list) {
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(0, 60, 0, 100),
            itemCount: favoriteMusicList.length,
            itemBuilder: (context, index) {
              final music = favoriteMusicList[index];
              return MusicCard(
                music: music,
                viewMode: settings.viewMode,
                heroPrefix: 'fav',
                onTap: () => musicService.playMusicFromQueue(favoriteMusicList, music, playlistId: 'favorites'),
              );
            },
          );
        }

        return GridView.builder(
          padding: EdgeInsets.fromLTRB(padding, 60, padding, padding),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16.w,
            mainAxisSpacing: 16.h,
            childAspectRatio: 1.0,
          ),
          itemCount: favoriteMusicList.length,
          itemBuilder: (context, index) {
            final music = favoriteMusicList[index];
            return MusicCard(
              music: music,
              viewMode: settings.viewMode,
              onTap: () => musicService.playMusicFromQueue(favoriteMusicList, music, playlistId: 'favorites'),
            );
          },
        );
      },
    );
  }

  int _calculateAdaptiveCrossAxisCount(double screenWidth) {
    if (screenWidth < 600) return 2;
    if (screenWidth < 900) return 3;
    if (screenWidth < 1200) return 4;
    return 6;
  }
}
