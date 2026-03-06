import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'pages/home_screen.dart';
import 'pages/favorite_page.dart';
import 'pages/playlist_page.dart';
import 'pages/player_page.dart';
import 'pages/settings_screen.dart';
import 'services/music_service.dart';
import 'models/settings_model.dart';
import 'services/responsive.dart';
import 'widgets/cover_art_texture.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (Platform.isWindows || Platform.isLinux) {
    // Initialize FFI
    sqfliteFfiInit();
    // Change the default factory
    databaseFactory = databaseFactoryFfi;
  }

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
    return Consumer<SettingsModel>(
      builder: (context, settings, child) {
        return MaterialApp(
          title: 'Material 3 Music Player',
          themeMode: settings.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.teal,
              brightness: Brightness.light,
            ),
            navigationBarTheme: NavigationBarThemeData(
              height: 60,
              indicatorColor: Colors.teal.withOpacity(0.1),
              labelTextStyle: WidgetStateProperty.all(
                const TextStyle(fontSize: 0, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.teal,
              brightness: Brightness.dark,
              surface: Colors.black,
            ),
            scaffoldBackgroundColor: Colors.black,
            navigationBarTheme: NavigationBarThemeData(
              height: 60,
              indicatorColor: Colors.teal.withOpacity(0.2),
              labelTextStyle: WidgetStateProperty.all(
                const TextStyle(fontSize: 0, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          home: const MainNavigationScreen(),
          debugShowCheckedModeBanner: false,
        );
      }
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  int _previousIndex = 0;
  bool _isPlayerVisible = false;
  late AnimationController _playerAnimationController;
  late Animation<Offset> _playerSlideAnimation;

  final TextEditingController _searchController = TextEditingController();
  bool _isSearchOpen = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _playerAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _playerSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _playerAnimationController,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void dispose() {
    _playerAnimationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<Widget> get _screens => [
    HomeScreen(searchQuery: _searchQuery),
    FavoritePage(searchQuery: _searchQuery),
    PlaylistPage(searchQuery: _searchQuery),
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
      if (_isPlayerVisible) {
        _playerAnimationController.forward();
      } else {
        _playerAnimationController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Initialize Responsive helper
    Responsive.init(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Fixed top margin
            SizedBox(height: Provider.of<SettingsModel>(context).topMargin),
            // Top panel with app name on left and search/settings on right
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // App name
                  const Text(
                    'PlayerV',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                  // Search and settings buttons
                  Row(
                    children: [
                      // Search button
                      IconButton(
                        icon: Icon(_isSearchOpen ? Icons.close_rounded : Icons.search_rounded),
                        onPressed: () {
                          setState(() {
                            _isSearchOpen = !_isSearchOpen;
                            if (!_isSearchOpen) {
                              _searchController.clear();
                              _searchQuery = '';
                            }
                          });
                        },
                        padding: const EdgeInsets.all(8),
                        iconSize: 24,
                      ),
                      // Settings button
                      IconButton(
                        icon: const Icon(Icons.settings_rounded),
                        onPressed: () {
                          setState(() {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const SettingsScreen()),
                            );
                          });
                        },
                        padding: const EdgeInsets.all(8),
                        iconSize: 24,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Page navigation panel below app name and buttons
            const SizedBox(height: 24),
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: NavigationBar(
                  height: 40,
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _onDestinationSelected,
                  destinations: const [
                    NavigationDestination(icon: Icon(Icons.home), label: ''),
                    NavigationDestination(icon: Icon(Icons.favorite), label: ''),
                    NavigationDestination(icon: Icon(Icons.playlist_play), label: ''),
                  ],
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                ),
              ),
            ),
            // Search bar that expands below navigation
            // Horizontal separator line
            Container(
              height: 1.h,
              color: theme.colorScheme.onSurface.withOpacity(0.1),
            ),
            
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              height: _isSearchOpen ? 60.h : 0,
              child: _isSearchOpen ? _buildExpandedSearchBar(theme) : null,
            ),
            
            // Horizontal separator line between search and main content
            Container(
              height: 1.h,
              color: theme.colorScheme.onSurface.withOpacity(0.1),
            ),
            
            // Additional margin before main content
            SizedBox(height: 24.h),
            
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
                  SlideTransition(
                    position: _playerSlideAnimation,
                    child: Consumer<MusicService>(
                      builder: (context, musicService, child) {
                        return Visibility(
                          visible: _isPlayerVisible || _playerAnimationController.isAnimating,
                          maintainState: true,
                          child: PlayerPage(
                            onClose: _togglePlayer,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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

  Widget _buildExpandedSearchBar(ThemeData theme) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(16.s),
          border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.1), width: 1),
        ),
        child: Row(
          children: [
            SizedBox(width: 12.w),
            Icon(
              Icons.search_rounded,
              color: theme.colorScheme.onSurface.withOpacity(0.6),
              size: 20.s,
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(fontSize: 14.sp),
                decoration: InputDecoration(
                  hintText: 'Search songs, artists...',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  hintStyle: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.4),
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.toLowerCase();
                  });
                },
              ),
            ),
            SizedBox(width: 8.w),
            IconButton(
              icon: Icon(
                Icons.close_rounded,
                color: theme.colorScheme.onSurface.withOpacity(0.6),
                size: 20.s,
              ),
              onPressed: () {
                setState(() {
                  _isSearchOpen = false;
                  _searchController.clear();
                  _searchQuery = '';
                });
              },
              padding: EdgeInsets.all(8.s),
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniPlayer(MusicService musicService) {
    final currentMusic = musicService.currentMusic;
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: _togglePlayer,
      child: Container(
        height: 72.h,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.onSurface.withOpacity(0.1),
              width: 0.5,
            ),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
          child: Row(
            children: [
              // Cover art
              Container(
                width: 48.s,
                height: 48.s,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8.s),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 6.s,
                      offset: Offset(0, 2.h),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8.s),
                  child: CoverArtTexture(
                    coverArtPath: currentMusic?.coverPath ?? '',
                    width: 48.s,
                    height: 48.s,
                  ),
                ),
              ),
              SizedBox(width: 12.w),

              // Song info
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      currentMusic?.title ?? 'No music playing',
                      style: TextStyle(
                        fontSize: 13.sp, // Slightly smaller font
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 1.h),
                    Text(
                      currentMusic?.artist ?? '',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                        fontSize: 11.sp, // Slightly smaller font
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 4.h),
                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2.s),
                      child: LinearProgressIndicator(
                        value: musicService.duration.inMilliseconds > 0
                            ? musicService.position.inMilliseconds /
                                musicService.duration.inMilliseconds
                            : 0,
                        backgroundColor: theme.colorScheme.onSurface.withOpacity(0.1),
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.teal),
                        minHeight: 2.h,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8.w),

              // Play/Pause button
              IconButton(
                icon: Icon(
                  musicService.isPlaying ? Icons.pause : Icons.play_arrow,
                ),
                onPressed: () => musicService.togglePlayPause(),
                iconSize: 28.s, // Smaller icon
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              SizedBox(width: 8.w),

              // Next button
              IconButton(
                icon: const Icon(Icons.skip_next),
                onPressed: () => musicService.next(),
                iconSize: 24.s, // Smaller icon
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
