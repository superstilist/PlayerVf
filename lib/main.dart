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
    const FavoritePage(),
    const PlaylistPage(),
    const SettingsScreen(),
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
      body: Column(
        children: [
          // Top navigation bar area
          Container(
            height: 60.h,
            padding: EdgeInsets.symmetric(horizontal: 8.w),
            child: Row(
              children: [
                Expanded(
                  child: NavigationBar(
                    height: 60.h,
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: _onDestinationSelected,
                    destinations: const [
                      NavigationDestination(icon: Icon(Icons.home), label: ''),
                      NavigationDestination(icon: Icon(Icons.favorite), label: ''),
                      NavigationDestination(icon: Icon(Icons.playlist_play), label: ''),
                      NavigationDestination(icon: Icon(Icons.settings), label: ''),
                    ],
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                  ),
                ),
                _buildAnimatedSearchBar(),
              ],
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

  Widget _buildAnimatedSearchBar() {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: _isSearchOpen ? Responsive.screenWidth * 0.4 : 40.s,
      height: 40.s,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(_isSearchOpen ? 12.s : 10.s),
        border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.1), width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_isSearchOpen ? 12.s : 10.s),
        child: Row(
          children: [
            if (_isSearchOpen)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: 12.w),
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    style: TextStyle(fontSize: 14.sp),
                    decoration: const InputDecoration(
                      hintText: 'Search...',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value.toLowerCase();
                      });
                    },
                  ),
                ),
              ),
            GestureDetector(
              onTap: () {
                setState(() {
                  _isSearchOpen = !_isSearchOpen;
                  if (!_isSearchOpen) {
                    _searchController.clear();
                    _searchQuery = '';
                  }
                });
              },
              child: Container(
                width: 38.s, // Smaller than 40.s to account for border
                height: 38.s,
                alignment: Alignment.center,
                child: Icon(
                  _isSearchOpen ? Icons.close_rounded : Icons.search_rounded,
                  size: 20.s,
                ),
              ),
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
