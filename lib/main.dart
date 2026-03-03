import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'pages/home_screen.dart';
import 'pages/favorite_page.dart';
import 'pages/playlist_page.dart';
import 'pages/player_page.dart';
import 'pages/settings_screen.dart';
import 'services/music_service.dart';
import 'models/settings_model.dart';
import 'services/responsive.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsModel>(create: (_) => SettingsModel()),
        ChangeNotifierProvider<MusicService>(create: (_) => MusicService()..loadSystemMusic()),
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
        navigationBarTheme: NavigationBarThemeData(
          height: 60, // Base height, will be scaled
          indicatorColor: Colors.teal.withOpacity(0.2),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
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
  int _previousIndex = 0;
  bool _isPlayerVisible = false;

  final List<Widget> _screens = const [
    HomeScreen(),
    FavoritePage(),
    PlaylistPage(),
    SettingsScreen(),
  ];

  void _onDestinationSelected(int index) {
    setState(() {
      _previousIndex = _selectedIndex;
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
    // Initialize Responsive helper
    Responsive.init(context);

    return Scaffold(
      body: Column(
        children: [
          // Top navigation bar - transparent
          Container(
            decoration: const BoxDecoration(
              color: Colors.transparent,
            ),
            child: NavigationBar(
              height: 60.h,
              selectedIndex: _selectedIndex,
              onDestinationSelected: _onDestinationSelected,
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
                NavigationDestination(icon: Icon(Icons.favorite), label: 'Favorites'),
                NavigationDestination(icon: Icon(Icons.playlist_play), label: 'Playlists'),
                NavigationDestination(icon: Icon(Icons.settings), label: ''),
              ],
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
          ),
          // Main content with fade-in animation
          Expanded(
            child: Stack(
              children: [
                // Main content with slide animation based on navigation direction
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  transitionBuilder: (child, animation) {
                    final direction = _selectedIndex > _previousIndex ? 1.0 : -1.0;
                    return SlideTransition(
                      position: Tween<Offset>(
                        begin: Offset(direction * 0.3, 0),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeInOut,
                        ),
                      ),
                      child: FadeTransition(
                        opacity: animation,
                        child: child,
                      ),
                    );
                  },
                  child: IndexedStack(
                    key: ValueKey<int>(_selectedIndex),
                    index: _selectedIndex,
                    children: _screens,
                  ),
                ),
                
                // Full-screen player overlay with slide animation
                if (_isPlayerVisible)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeInOut,
                    top: 0,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 1), // Start from bottom
                        end: Offset.zero, // End at normal position
                      ).animate(
                        CurvedAnimation(
                          parent: ModalRoute.of(context)!.animation!,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                      child: Consumer<MusicService>(
                        builder: (context, musicService, child) {
                          return PlayerPage(
                            onClose: _togglePlayer,
                          );
                        },
                      ),
                    ),
                  ),
              ],
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
        height: 68.h,
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
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
          child: Row(
            children: [
              // Cover art with rounded corners
              Container(
                width: 52.s,
                height: 52.s,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10.s),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8.s,
                      offset: Offset(0, 2.h),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10.s),
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
                          child: Icon(
                            Icons.music_note,
                            color: Colors.white54,
                            size: 24.s,
                          ),
                        ),
                ),
              ),
              SizedBox(width: 12.w),

              // Song info
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min, // Use min to let it fit
                  children: [
                    Text(
                      currentMusic?.title ?? 'No music playing',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 1.h), // Smaller height
                    Text(
                      currentMusic?.artist ?? '',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12.sp,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 2.h), // Smaller height
                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2.s),
                      child: LinearProgressIndicator(
                        value: musicService.duration.inMilliseconds > 0
                            ? musicService.position.inMilliseconds /
                                musicService.duration.inMilliseconds
                            : 0,
                        backgroundColor: Colors.grey[700],
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.teal),
                        minHeight: 2.h, // Smaller height
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
                iconSize: 32.s,
              ),

              // Next button
              IconButton(
                icon: const Icon(Icons.skip_next),
                onPressed: () => musicService.next(),
                color: Colors.white,
                iconSize: 28.s,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
