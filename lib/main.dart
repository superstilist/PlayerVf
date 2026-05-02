import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:ui';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:media_kit/media_kit.dart';

import 'pages/home_screen.dart';
import 'pages/favorite_page.dart';
import 'pages/playlist_page.dart';
import 'pages/player_page.dart';
import 'services/music_service.dart';
import 'models/settings_model.dart';
import 'services/responsive.dart';
import 'widgets/cover_art_texture.dart';
import 'widgets/glass_container.dart';
import 'widgets/settings_drawer.dart';
import 'widgets/particle_system.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
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
          title: 'PlayerVf',
          themeMode: settings.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: settings.accentColor,
              brightness: Brightness.light,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: settings.accentColor,
              brightness: Brightness.dark,
              surface: Colors.black,
            ),
            scaffoldBackgroundColor: Colors.black,
          ),
          home: const MainNavigationScreen(),
          debugShowCheckedModeBanner: false,
        );
      },
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
  bool _isPlayerVisible = false;
  late AnimationController _playerAnimationController;
  late Animation<Offset> _playerSlideAnimation;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _shortcutsFocusNode = FocusNode(debugLabel: 'main-shortcuts');
  bool _isSearchOpen = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _playerAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _playerSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _playerAnimationController,
      curve: Curves.easeOutQuart,
    ));
    
    _playerAnimationController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _playerAnimationController.dispose();
    _searchController.dispose();
    _shortcutsFocusNode.dispose();
    super.dispose();
  }

  List<Widget> get _screens => [
    HomeScreen(searchQuery: _searchQuery),
    FavoritePage(searchQuery: _searchQuery),
    PlaylistPage(searchQuery: _searchQuery),
  ];

  void _onDestinationSelected(int index) {
    if (index == _selectedIndex) return;
    setState(() {
      _selectedIndex = index;
    });
  }

  void _togglePlayer() {
    if (_playerAnimationController.isAnimating) return;
    
    setState(() {
      _isPlayerVisible = !_isPlayerVisible;
      if (_isPlayerVisible) {
        _playerAnimationController.forward();
      } else {
        _playerAnimationController.reverse();
      }
    });
  }

  void _closePlayer() {
    if (_isPlayerVisible) _togglePlayer();
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    final settings = Provider.of<SettingsModel>(context);
    final theme = Theme.of(context);
    final musicService = Provider.of<MusicService>(context);

    double leftOffset = 0;
    double rightOffset = 0;
    final bool isVerticalNav = settings.navPosition == NavPosition.left || settings.navPosition == NavPosition.right;
    
    if (settings.navPosition == NavPosition.left) {
      leftOffset = 88.w; 
    } else if (settings.navPosition == NavPosition.right) {
      rightOffset = 88.w;
    }

    Widget mainLayout;
    final navDock = _buildNavigationDock(settings, theme);
    
    if (isVerticalNav) {
      mainLayout = Row(
        children: [
          if (settings.navPosition == NavPosition.left) navDock,
          Expanded(child: _buildMainContentArea(settings, theme)),
          if (settings.navPosition == NavPosition.right) navDock,
        ],
      );
    } else {
      mainLayout = Column(
        children: [
          if (settings.navPosition == NavPosition.top) navDock,
          Expanded(child: _buildMainContentArea(settings, theme)),
          if (settings.navPosition == NavPosition.bottom) navDock,
        ],
      );
    }

    final double uiOpacity = (1.0 - _playerAnimationController.value).clamp(0.0, 1.0);

    return Focus(
      autofocus: true,
      focusNode: _shortcutsFocusNode,
      child: PopScope(
        canPop: !_isPlayerVisible,
        onPopInvoked: (didPop) {
          if (!didPop && _isPlayerVisible) _closePlayer();
        },
        child: Stack(
          children: [
            _buildGlobalBackground(musicService, theme),
            Scaffold(
              key: _scaffoldKey,
              backgroundColor: Colors.transparent,
              endDrawer: const SettingsDrawer(),
              body: Stack(
                children: [
                  ParticleSystem(effect: settings.particleEffect),
                  Opacity(
                    opacity: uiOpacity,
                    child: IgnorePointer(
                      ignoring: _playerAnimationController.value > 0.5,
                      child: SafeArea(
                        bottom: false,
                        child: Column(
                          children: [
                            SizedBox(height: settings.topMargin),
                            _buildTopAppBar(settings, theme),
                            Expanded(child: mainLayout),
                          ],
                        ),
                      ),
                    ),
                  ),

                  if (musicService.currentMusic != null && uiOpacity > 0.05)
                    Positioned(
                      left: leftOffset,
                      right: rightOffset,
                      bottom: settings.navPosition == NavPosition.bottom ? 110.h : 24.h,
                      child: Opacity(
                        opacity: uiOpacity,
                        child: _buildMiniPlayer(musicService),
                      ),
                    ),

                  SlideTransition(
                    position: _playerSlideAnimation,
                    child: Visibility(
                      visible: _isPlayerVisible || _playerAnimationController.isAnimating,
                      maintainState: true,
                      child: PlayerPage(onClose: _closePlayer),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlobalBackground(MusicService musicService, ThemeData theme) {
    final coverPath = musicService.currentMusic?.coverPath;
    return Positioned.fill(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 1000),
        child: coverPath == null || coverPath.isEmpty
            ? Container(key: const ValueKey('bg-empty'), decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [theme.colorScheme.surface, theme.colorScheme.surfaceContainerHighest])))
            : Stack(
                key: ValueKey(coverPath),
                fit: StackFit.expand,
                children: [
                  CoverArtTexture(coverArtPath: coverPath, width: double.infinity, height: double.infinity),
                  BackdropFilter(filter: ImageFilter.blur(sigmaX: 70, sigmaY: 70), child: Container(color: theme.colorScheme.surface.withOpacity(0.65))),
                ],
              ),
      ),
    );
  }

  Widget _buildTopAppBar(SettingsModel settings, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('PlayerVf', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: settings.accentColor)),
          Row(
            children: [
              IconButton(
                icon: Icon(_isSearchOpen ? Icons.close_rounded : Icons.search_rounded),
                onPressed: () => setState(() {
                  _isSearchOpen = !_isSearchOpen;
                  if (!_isSearchOpen) { _searchController.clear(); _searchQuery = ''; }
                }),
              ),
              IconButton(
                icon: const Icon(Icons.settings_rounded), 
                onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationDock(SettingsModel settings, ThemeData theme) {
    final isVertical = settings.navPosition == NavPosition.left || settings.navPosition == NavPosition.right;
    
    return Padding(
      padding: EdgeInsets.all(12.s),
      child: GlassContainer(
        width: isVertical ? 72.w : double.infinity,
        height: isVertical ? double.infinity : 72.h,
        borderRadius: BorderRadius.circular(32.s),
        color: theme.colorScheme.onSurface.withOpacity(0.08),
        blur: 12,
        child: Flex(
          direction: isVertical ? Axis.vertical : Axis.horizontal,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildNavItem(0, Icons.home_rounded),
            _buildNavItem(1, Icons.favorite_rounded),
            _buildNavItem(2, Icons.playlist_play_rounded),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon) {
    final isSelected = _selectedIndex == index;
    final theme = Theme.of(context);
    final settings = Provider.of<SettingsModel>(context, listen: false);

    return GestureDetector(
      onTap: () => _onDestinationSelected(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        padding: EdgeInsets.symmetric(horizontal: 12.s, vertical: 8.s),
        decoration: BoxDecoration(
          color: isSelected ? settings.accentColor.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20.s),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? settings.accentColor : theme.colorScheme.onSurface.withOpacity(0.4),
              size: 26.s,
            ),
            if (isSelected)
              Container(
                margin: EdgeInsets.only(top: 4.h),
                width: 4.s,
                height: 4.s,
                decoration: BoxDecoration(shape: BoxShape.circle, color: settings.accentColor),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContentArea(SettingsModel settings, ThemeData theme) {
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: _isSearchOpen ? 64.h : 0,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _isSearchOpen ? _buildSearchBar(theme) : null,
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            transitionBuilder: (child, animation) {
              return FadeTransition(opacity: animation, child: child);
            },
            child: IndexedStack(key: ValueKey<int>(_selectedIndex), index: _selectedIndex, children: _screens),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return GlassContainer(
      borderRadius: BorderRadius.circular(16.s),
      color: theme.colorScheme.onSurface.withOpacity(0.05),
      blur: 8,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          controller: _searchController,
          decoration: const InputDecoration(hintText: 'Search your library...', border: InputBorder.none, icon: Icon(Icons.search_rounded)),
          onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
        ),
      ),
    );
  }

  Widget _buildMiniPlayer(MusicService musicService) {
    final currentMusic = musicService.currentMusic!;
    final theme = Theme.of(context);
    final settings = Provider.of<SettingsModel>(context, listen: false);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: _togglePlayer,
        child: GlassContainer(
          height: 76.h,
          borderRadius: BorderRadius.circular(28.s),
          blur: 15,
          color: settings.accentColor.withOpacity(0.12),
          border: Border.all(color: settings.accentColor.withOpacity(0.2)),
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Row(
              children: [
                Hero(tag: 'mini-player-art', child: ClipRRect(borderRadius: BorderRadius.circular(18.s), child: CoverArtTexture(coverArtPath: currentMusic.coverPath, width: 56.s, height: 56.s))),
                SizedBox(width: 16.w),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: Column(
                      key: ValueKey(currentMusic.id),
                      mainAxisAlignment: MainAxisAlignment.center, 
                      crossAxisAlignment: CrossAxisAlignment.start, 
                      children: [
                        Text(currentMusic.title, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(currentMusic.artist, style: TextStyle(fontSize: 12.sp, color: theme.colorScheme.onSurface.withOpacity(0.5)), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ]
                    ),
                  ),
                ),
                IconButton(
                  icon: ValueListenableBuilder<bool>(valueListenable: musicService.playingNotifier, builder: (_, isPlaying, __) => Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: settings.accentColor)),
                  onPressed: musicService.togglePlayPause,
                ),
                IconButton(icon: const Icon(Icons.skip_next_rounded), onPressed: musicService.next),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
