import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../widgets/music_card.dart';
import '../services/music_service.dart';

import '../services/responsive.dart';

class FavoritePage extends StatelessWidget {
  const FavoritePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicService>(
      builder: (context, musicService, child) {
        final crossAxisCount = _calculateAdaptiveCrossAxisCount(Responsive.screenWidth);
        final padding = 16.w;
        
        // Show loading if still scanning
        if (musicService.isLoadingSystemMusic) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(color: Colors.teal),
                SizedBox(height: 16.h),
                Text('Scanning music... ${musicService.systemMusicCount} files',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14.sp)),
              ],
            ),
          );
        }
        
        final favoriteMusicList = musicService.favoriteMusicList;
        final favoriteCoverList = musicService.favoriteCoverList;
        
        if (favoriteMusicList.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.favorite_border, size: 80.s, color: Colors.grey[600]),
                SizedBox(height: 16.h),
                Text('No favorite songs', style: TextStyle(color: Colors.grey[600], fontSize: 18.sp)),
                SizedBox(height: 8.h),
                Text('Tap the heart icon on songs to add them to favorites', 
                  style: TextStyle(color: Colors.grey[700], fontSize: 14.sp),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
        
        return GridView.builder(
          padding: EdgeInsets.all(padding),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16.w,
            mainAxisSpacing: 16.h,
            childAspectRatio: 1.0,
          ),
          itemCount: favoriteMusicList.length,
          itemBuilder: (context, index) {
            final music = favoriteMusicList[index];
            final cover = index < favoriteCoverList.length ? favoriteCoverList[index] : null;
            final originalIndex = musicService.musicList.indexWhere((m) => m.id == music.id);
            return MusicCard(
              music: music,
              cover: cover,
              onTap: () {
                musicService.currentIndex = originalIndex;
                musicService.play();
              },
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

