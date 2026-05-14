import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:ui' show ImageFilter, PointerDeviceKind;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:media_kit/media_kit.dart';

import 'pages/home_screen.dart';
import 'pages/favorite_page.dart';
import 'pages/playlist_page.dart';
import 'pages/player_page.dart';
import 'pages/video_page.dart';
import 'pages/youtube_music_page.dart';
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
        ChangeNotifierProvider<MusicService>(
            create: (_) => MusicService()..loadSystemMusic()),
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
          theme: _buildAppTheme(settings.accentColor, Brightness.light),
          darkTheme: _buildAppTheme(settings.accentColor, Brightness.dark),
          scrollBehavior: const _SmoothScrollBehavior(),
          home: const MainNavigationScreen(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }

  ThemeData _buildAppTheme(Color seed, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      surface: brightness == Brightness.dark
          ? const Color(0xFF101112)
          : const Color(0xFFF8FAF9),
    );
    final radius = BorderRadius.circular(14);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          hoverColor: scheme.primary.withOpacity(0.08),
          highlightColor: scheme.primary.withOpacity(0.10),
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 44),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size(48, 44),
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 44),
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: radius),
        iconColor: scheme.primary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHighest,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withOpacity(0.12),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.outline,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHighest,
        ),
      ),
    );
  }
}

class _SmoothScrollBehavior extends MaterialScrollBehavior {
  const _SmoothScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    final platform = getPlatform(context);
    if (platform == TargetPlatform.android || platform == TargetPlatform.iOS) {
      return const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      );
    }
    return const ClampingScrollPhysics();
  }

  @override
  Set<PointerDeviceKind> get dragDevices => {
        ...super.dragDevices,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
      };
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen>
    with SingleTickerProviderStateMixin {
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
      duration: const Duration(milliseconds: 360),
    );
    _playerSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _playerAnimationController,
      curve: Curves.easeOutCubic,
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
        YoutubeMusicPage(onOpenPlayer: _togglePlayer),
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
    final bool isVerticalNav = settings.navPosition == NavPosition.left ||
        settings.navPosition == NavPosition.right;

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

    final double uiOpacity =
        (1.0 - _playerAnimationController.value).clamp(0.0, 1.0);

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
            _buildMicaBackground(musicService, theme),
            Scaffold(
              key: _scaffoldKey,
              backgroundColor: Colors.transparent,
              endDrawer: const SettingsDrawer(),
              body: Stack(
                children: [
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
                      bottom: settings.navPosition == NavPosition.bottom
                          ? 110.h
                          : 24.h,
                      child: Opacity(
                        opacity: uiOpacity,
                        child: _buildMiniPlayer(musicService),
                      ),
                    ),

                  SlideTransition(
                    position: _playerSlideAnimation,
                    child: Visibility(
                      visible: _isPlayerVisible ||
                          _playerAnimationController.isAnimating,
                      maintainState: true,
                      child: musicService.isCurrentMediaVideo
                          ? VideoPage(onClose: _closePlayer)
                          : PlayerPage(onClose: _closePlayer),
                    ),
                  ),

                  // Particle System at the very top so it shows everywhere
                  IgnorePointer(
                    child: ParticleSystem(effect: settings.particleEffect),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMicaBackground(MusicService musicService, ThemeData theme) {
    final coverPath = musicService.currentMusic?.coverPath;
    return Positioned.fill(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        child: coverPath == null || coverPath.isEmpty
            ? Container(
                key: const ValueKey('bg-empty'),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.surface,
                      theme.colorScheme.surfaceContainerHighest
                          .withOpacity(0.72),
                    ],
                  ),
                ),
              )
            : Stack(
                key: ValueKey(coverPath),
                fit: StackFit.expand,
                children: [
                  Container(color: theme.colorScheme.surface),
                  Transform.scale(
                    scale: 1.08,
                    child: CoverArtTexture(
                        coverArtPath: coverPath,
                        width: double.infinity,
                        height: double.infinity),
                  ),
                  BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 84, sigmaY: 84),
                      child: Container(
                          color: theme.colorScheme.surface.withOpacity(
                              theme.brightness == Brightness.dark
                                  ? 0.78
                                  : 0.84))),
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
          Text('PlayerVf',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface)),
          Row(
            children: [
              IconButton(
                icon: Icon(
                    _isSearchOpen ? Icons.close_rounded : Icons.search_rounded),
                onPressed: () => setState(() {
                  _isSearchOpen = !_isSearchOpen;
                  if (!_isSearchOpen) {
                    _searchController.clear();
                    _searchQuery = '';
                  }
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
    final isVertical = settings.navPosition == NavPosition.left ||
        settings.navPosition == NavPosition.right;

    return Padding(
      padding: EdgeInsets.all(12.s),
      child: GlassContainer(
        width: isVertical ? 72.w : double.infinity,
        height: isVertical ? double.infinity : 72.h,
        borderRadius: BorderRadius.circular(24.s),
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.54),
        blur: 22,
        child: Flex(
          direction: isVertical ? Axis.vertical : Axis.horizontal,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildNavItem(0, Icons.home_rounded),
            _buildNavItem(1, Icons.favorite_rounded),
            _buildNavItem(2, Icons.playlist_play_rounded),
            _buildNavItem(3, Icons.library_music_rounded),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon) {
    final isSelected = _selectedIndex == index;
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => _onDestinationSelected(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(horizontal: 12.s, vertical: 8.s),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primaryContainer.withOpacity(0.72)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16.s),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurfaceVariant,
              size: 24.s,
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
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: _isSearchOpen ? 64.h : 0,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _isSearchOpen ? _buildSearchBar(theme) : null,
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeOutCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(opacity: animation, child: child);
            },
            child: IndexedStack(index: _selectedIndex, children: _screens),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return GlassContainer(
      borderRadius: BorderRadius.circular(18.s),
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.56),
      blur: 18,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          controller: _searchController,
          decoration: const InputDecoration(
              hintText: 'Search your library...',
              border: InputBorder.none,
              icon: Icon(Icons.search_rounded)),
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
          blur: 22,
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.62),
          border: Border.all(
              color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Row(
              children: [
                Hero(
                    tag: 'mini-player-art',
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(18.s),
                        child: CoverArtTexture(
                            coverArtPath: currentMusic.coverPath,
                            width: 56.s,
                            height: 56.s))),
                SizedBox(width: 16.w),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: Column(
                        key: ValueKey(currentMusic.id),
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(currentMusic.title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(currentMusic.artist,
                              style: TextStyle(
                                  fontSize: 12.sp,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.5)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ]),
                  ),
                ),
                IconButton(
                  icon: ValueListenableBuilder<bool>(
                      valueListenable: musicService.playingNotifier,
                      builder: (_, isPlaying, __) => Icon(
                          isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: settings.accentColor)),
                  onPressed: musicService.togglePlayPause,
                ),
                IconButton(
                    icon: const Icon(Icons.skip_next_rounded),
                    onPressed: musicService.next),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
