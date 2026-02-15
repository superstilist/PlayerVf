import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/music_card.dart';
import '../services/music_service.dart';

class PlaylistPage extends StatelessWidget {
  const PlaylistPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicService>(
      builder: (context, musicService, child) {
        final size = MediaQuery.of(context).size;
        final crossAxisCount = _getCrossAxisCount(size.width);
        
        return Scaffold(
          body: FutureBuilder(
            future: musicService.loadMusic(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              } else if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              } else if (musicService.musicList.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.playlist_play, size: 80, color: Colors.grey[600]),
                      const SizedBox(height: 16),
                      Text('No playlists yet', style: TextStyle(color: Colors.grey[600], fontSize: 18)),
                    ],
                  ),
                );
              } else {
                return GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 10.0,
                    mainAxisSpacing: 10.0,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: musicService.musicList.length,
                  itemBuilder: (context, index) {
                    final music = musicService.musicList[index];
                    final cover = index < musicService.coverList.length ? musicService.coverList[index] : null;
                    return MusicCard(
                      music: music,
                      cover: cover,
                      onTap: () {
                        musicService.currentIndex = index;
                        musicService.play();
                      },
                    );
                  },
                );
              }
            },
          ),
        );
      },
    );
  }

  int _getCrossAxisCount(double width) {
    if (width < 400) return 2;
    if (width < 600) return 3;
    if (width < 900) return 4;
    if (width < 1200) return 5;
    return 6;
  }
}
