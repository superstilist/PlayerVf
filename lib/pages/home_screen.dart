import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/music_card.dart';
import '../services/music_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<void> _loadMusicFuture;

  @override
  void initState() {
    super.initState();
    _loadMusicFuture = context.read<MusicService>().loadMusic();
  }

  @override
  Widget build(BuildContext context) {
    final musicService = Provider.of<MusicService>(context);
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    
    if (isPortrait) {
      return _buildPortraitLayout(context, musicService);
    } else {
      return _buildLandscapeLayout(context, musicService);
    }
  }

  Widget _buildPortraitLayout(BuildContext context, MusicService musicService) {
    final size = MediaQuery.of(context).size;
    final crossAxisCount = _getCrossAxisCount(size.width);

    return FutureBuilder(
      future: _loadMusicFuture,
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
                Icon(Icons.music_off, size: 80, color: Colors.grey[600]),
                const SizedBox(height: 16),
                Text('No music files found', style: TextStyle(color: Colors.grey[600], fontSize: 18)),
              ],
            ),
          );
        }
        
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
      },
    );
  }

  Widget _buildLandscapeLayout(BuildContext context, MusicService musicService) {
    final size = MediaQuery.of(context).size;
    final crossAxisCount = _getCrossAxisCount(size.width);
    final adjustedCrossAxisCount = crossAxisCount + 2;

    return FutureBuilder(
      future: _loadMusicFuture,
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
                Icon(Icons.music_off, size: 80, color: Colors.grey[600]),
                const SizedBox(height: 16),
                Text('No music files found', style: TextStyle(color: Colors.grey[600], fontSize: 18)),
              ],
            ),
          );
        }
        
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: adjustedCrossAxisCount,
            crossAxisSpacing: 12.0,
            mainAxisSpacing: 12.0,
            childAspectRatio: 0.8,
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
      },
    );
  }

  int _getCrossAxisCount(double width) {
    if (width < 300) return 1;
    if (width < 500) return 2;
    if (width < 700) return 3;
    if (width < 900) return 4;
    if (width < 1100) return 5;
    return 6;
  }
}
