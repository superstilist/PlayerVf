import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'pages/home_screen.dart';
import 'pages/favorite_page.dart';
import 'pages/playlist_page.dart';
import 'pages/settings_screen.dart';
import 'pages/player_page.dart';
import 'services/music_service.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<MusicService>(create: (_) => MusicService()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Material 3 Music Player',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const MainNavigationScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;
  bool _isPlayerVisible = false;

  final List<Widget> _screens = const [
    HomeScreen(),
    FavoritePage(),
    PlaylistPage(),
    SettingsScreen(),
  ];

  void _onDestinationSelected(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _togglePlayer() {
    setState(() {
      _isPlayerVisible = !_isPlayerVisible;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Main content with Consumer for auto-refresh
          IndexedStack(
            index: _selectedIndex,
            children: _screens,
          ),
          
          // Full-screen player overlay
          if (_isPlayerVisible)
            Positioned.fill(
              child: Consumer<MusicService>(
                builder: (context, musicService, child) {
                  return PlayerPage(
                    onClose: _togglePlayer,
                  );
                },
              ),
            ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mini player control panel with Consumer for auto-refresh
          Consumer<MusicService>(
            builder: (context, musicService, child) {
              final currentMusic = musicService.currentMusic;
              if (currentMusic != null && !_isPlayerVisible) {
                return _buildMiniPlayer(musicService);
              }
              return const SizedBox.shrink();
            },
          ),
          // Navigation bar
          NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _onDestinationSelected,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
              NavigationDestination(icon: Icon(Icons.favorite), label: 'Favorites'),
              NavigationDestination(icon: Icon(Icons.playlist_play), label: 'Playlists'),
              NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniPlayer(MusicService musicService) {
    final currentMusic = musicService.currentMusic;
    final currentCover = musicService.currentCover;

    return GestureDetector(
      onTap: _togglePlayer,
      child: Container(
        height: 68,
        decoration: BoxDecoration(
          color: Colors.grey[900],
          border: Border(
            top: BorderSide(
              color: Colors.grey[800]!,
              width: 0.5,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              // Cover art with rounded corners
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: currentCover != null && currentCover.imageData != null
                      ? Image.memory(
                          currentCover.imageData!,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.teal.shade700, Colors.teal.shade900],
                            ),
                          ),
                          child: const Icon(
                            Icons.music_note,
                            color: Colors.white54,
                            size: 24,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),

              // Song info
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentMusic?.title ?? 'No music playing',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      currentMusic?.artist ?? '',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: musicService.duration.inMilliseconds > 0
                            ? musicService.position.inMilliseconds /
                                musicService.duration.inMilliseconds
                            : 0,
                        backgroundColor: Colors.grey[700],
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.teal),
                        minHeight: 3,
                      ),
                    ),
                  ],
                ),
              ),

              // Play/Pause button
              IconButton(
                icon: Icon(
                  musicService.isPlaying ? Icons.pause : Icons.play_arrow,
                ),
                onPressed: () => musicService.togglePlayPause(),
                color: Colors.white,
                iconSize: 32,
              ),

              // Next button
              IconButton(
                icon: const Icon(Icons.skip_next),
                onPressed: () => musicService.next(),
                color: Colors.white,
                iconSize: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
