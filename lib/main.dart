import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter, PlatformDispatcher, PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, kIsWeb;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'pages/home_screen.dart';
import 'pages/favorite_page.dart';
import 'pages/playlist_page.dart';
import 'pages/player_page.dart';
import 'pages/video_page.dart';
import 'pages/youtube_music_page.dart';
import 'pages/share_page.dart';
import 'services/music_service.dart';
import 'services/performance_policy.dart';
import 'services/player_controller.dart';
import 'services/player_audio_handler.dart';
import 'models/settings_model.dart';
import 'services/responsive.dart';
import 'widgets/cover_art_texture.dart';
import 'widgets/glass_container.dart';
import 'widgets/settings_drawer.dart';
import 'widgets/particle_system.dart';

DateTime _lastKeyboardAssertionLog = DateTime.fromMillisecondsSinceEpoch(0);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installWindowsKeyboardAssertionGuard();
  MediaKit.ensureInitialized();
  playerAudioHandler = await initPlayerAudioHandler();

  if (_supportsDesktopFullscreen) {
    await windowManager.ensureInitialized();
  }

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsModel>(create: (_) => SettingsModel()),
        ChangeNotifierProvider<MusicService>(create: (_) => MusicService()),
      ],
      child: const MyApp(),
    ),
  );
}

bool get _supportsDesktopFullscreen =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

void _installWindowsKeyboardAssertionGuard() {
  if (kIsWeb || !Platform.isWindows) return;

  final previousFlutterError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (_isDuplicateWindowsKeyDownAssertion(details.exceptionAsString())) {
      _logKeyboardAssertionOnce();
      unawaited(HardwareKeyboard.instance.syncKeyboardState());
      return;
    }
    if (previousFlutterError != null) {
      previousFlutterError(details);
    } else {
      FlutterError.presentError(details);
    }
  };

  final previousPlatformError = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    if (_isDuplicateWindowsKeyDownAssertion(error.toString())) {
      _logKeyboardAssertionOnce();
      unawaited(HardwareKeyboard.instance.syncKeyboardState());
      return true;
    }
    return previousPlatformError?.call(error, stack) ?? false;
  };
}

bool _isDuplicateWindowsKeyDownAssertion(String message) {
  return message.contains('A KeyDownEvent is dispatched') &&
      message.contains('physical key is already pressed');
}

void _logKeyboardAssertionOnce() {
  final now = DateTime.now();
  if (now.difference(_lastKeyboardAssertionLog).inSeconds < 5) return;
  _lastKeyboardAssertionLog = now;
  debugPrint('Recovered from duplicate Windows key-down state.');
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
          theme: _buildAppTheme(settings.accentColor, Brightness.light,
              settings.themePreset, settings.glassEffect),
          darkTheme: _buildAppTheme(settings.accentColor, Brightness.dark,
              settings.themePreset, settings.glassEffect),
          scrollBehavior: const _SmoothScrollBehavior(),
          home: const MainNavigationScreen(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }

  ThemeData _buildAppTheme(Color seed, Brightness brightness,
      ThemePreset preset, double glassEffect) {
    final surface = _surfaceForPreset(brightness, preset);
    final glass = glassEffect.clamp(0.0, 1.0);
    final controlFill = _controlFillOpacity(brightness, glass);
    final selectedFill = _selectedFillOpacity(brightness, glass);
    final outlineOpacity = _outlineOpacity(brightness, glass);
    final generatedScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      surface: surface,
    );
    final scheme = brightness == Brightness.light
        ? generatedScheme.copyWith(
            surface: surface,
            onSurface: const Color(0xFF111827),
            surfaceContainerLowest: Colors.white,
            surfaceContainerLow: const Color(0xFFF9FAFB),
            surfaceContainer: const Color(0xFFF3F4F6),
            surfaceContainerHigh: const Color(0xFFEFF2F6),
            surfaceContainerHighest: const Color(0xFFE7ECF2),
            outline: const Color(0xFF8A95A3),
            outlineVariant: const Color(0xFFC7CED8),
          )
        : generatedScheme.copyWith(surface: surface);
    final radius = BorderRadius.circular(20);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      cardColor: scheme.surfaceContainerLow,
      dialogBackgroundColor: scheme.surfaceContainerLow,
      splashFactory: InkRipple.splashFactory,
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
          backgroundColor:
              scheme.surfaceContainerHighest.withOpacity(controlFill),
          hoverColor: scheme.onSurface.withOpacity(0.06),
          highlightColor: scheme.onSurface.withOpacity(0.08),
          fixedSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 42),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size(48, 42),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          backgroundColor: scheme.surfaceContainerHighest.withOpacity(
            brightness == Brightness.dark
                ? (0.46 - (0.14 * glass))
                : (0.78 - (0.18 * glass)),
          ),
          foregroundColor: scheme.onSurface,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 42),
          padding: const EdgeInsets.symmetric(horizontal: 18),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        iconColor: scheme.primary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(
            color: scheme.outlineVariant.withOpacity(outlineOpacity)),
        backgroundColor: scheme.surfaceContainerHighest.withOpacity(
          controlFill,
        ),
        selectedColor: scheme.primaryContainer.withOpacity(selectedFill),
        labelStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHighest.withOpacity(
          brightness == Brightness.dark
              ? (0.68 - (0.20 * glass))
              : (0.88 - (0.18 * glass)),
        ),
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withOpacity(0.12),
        trackHeight: 6,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
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
              : scheme.surfaceContainerHighest.withOpacity(controlFill),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withOpacity(outlineOpacity),
        thickness: 0.8,
      ),
      dialogTheme: DialogTheme(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: scheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withOpacity(
          brightness == Brightness.dark ? 0.22 : 0.58,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withOpacity(outlineOpacity),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
    );
  }

  double _controlFillOpacity(Brightness brightness, double glass) {
    return brightness == Brightness.dark
        ? 0.34 - (0.14 * glass)
        : 0.82 - (0.14 * glass);
  }

  double _selectedFillOpacity(Brightness brightness, double glass) {
    return brightness == Brightness.dark
        ? 0.74 - (0.12 * glass)
        : 0.90 - (0.10 * glass);
  }

  double _outlineOpacity(Brightness brightness, double glass) {
    return brightness == Brightness.dark
        ? 0.34 + (0.18 * glass)
        : 0.62 + (0.12 * glass);
  }

  Color _surfaceForPreset(Brightness brightness, ThemePreset preset) {
    switch (preset) {
      case ThemePreset.material:
        return brightness == Brightness.dark
            ? const Color(0xFF1B1C1E)
            : const Color(0xFFF5F7FA);
      case ThemePreset.graphite:
        return brightness == Brightness.dark
            ? const Color(0xFF151719)
            : const Color(0xFFF3F5F7);
      case ThemePreset.classic:
        return brightness == Brightness.dark
            ? const Color(0xFF151616)
            : const Color(0xFFF7F8FA);
      case ThemePreset.azure:
        return brightness == Brightness.dark
            ? const Color(0xFF10171C)
            : const Color(0xFFF2F8FC);
      case ThemePreset.sunset:
        return brightness == Brightness.dark
            ? const Color(0xFF1C1715)
            : const Color(0xFFFAF7F5);
      default:
        return brightness == Brightness.dark
            ? const Color(0xFF111315)
            : const Color(0xFFF6F7F9);
    }
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

class _TogglePlayPauseIntent extends Intent {
  const _TogglePlayPauseIntent();
}

class _NextTrackIntent extends Intent {
  const _NextTrackIntent();
}

class _PreviousOrRestartIntent extends Intent {
  const _PreviousOrRestartIntent();
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
  DateTime _lastPlayPauseShortcut = DateTime.fromMillisecondsSinceEpoch(0);
  double _lastNonZeroVolume = 100.0;
  bool _isSearchOpen = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _shortcutsFocusNode.requestFocus();
    });
    _playerAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _playerSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _playerAnimationController,
      curve: Curves.easeOutQuart,
    ));
  }

  @override
  void dispose() {
    _playerAnimationController.dispose();
    _searchController.dispose();
    _shortcutsFocusNode.dispose();
    super.dispose();
  }

  List<Widget> get _screens => [
        HomeScreen(searchQuery: _searchQuery, onOpenPlayer: _openPlayer),
        FavoritePage(searchQuery: _searchQuery, onOpenPlayer: _openPlayer),
        PlaylistPage(searchQuery: _searchQuery, onOpenPlayer: _openPlayer),
        YoutubeMusicPage(onOpenPlayer: _togglePlayer),
        const SharePage(),
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

  void _openPlayer() {
    if (!_isPlayerVisible) _togglePlayer();
  }

  bool _allowPlayPauseShortcut() {
    final now = DateTime.now();
    if (now.difference(_lastPlayPauseShortcut).inMilliseconds < 120) {
      return false;
    }
    _lastPlayPauseShortcut = now;
    return true;
  }

  void _seekRelative(MusicService musicService, int direction, int seconds) {
    if (musicService.currentMusic == null) return;
    final delta = Duration(seconds: seconds * direction);
    final next = musicService.position + delta;
    final clamped = next < Duration.zero
        ? Duration.zero
        : musicService.duration > Duration.zero && next > musicService.duration
            ? musicService.duration
            : next;
    musicService.seekTo(clamped);
  }

  void _changeVolume(MusicService musicService, int direction) {
    final next = (musicService.volume + (direction * 5)).clamp(0.0, 100.0);
    if (next > 0) _lastNonZeroVolume = next;
    musicService.setVolume(next);
  }

  void _toggleMute(MusicService musicService) {
    if (musicService.volume > 0) {
      _lastNonZeroVolume = musicService.volume;
      musicService.setVolume(0);
      return;
    }
    musicService.setVolume(_lastNonZeroVolume.clamp(5.0, 100.0));
  }

  KeyEventResult _handleGlobalKeyEvent(
    KeyEvent event,
    MusicService musicService,
    SettingsModel settings,
  ) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.f11) {
      unawaited(_toggleDesktopFullscreen());
      return KeyEventResult.handled;
    }

    if (_isTypingInEditable()) {
      return KeyEventResult.ignored;
    }

    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      if (_allowPlayPauseShortcut()) {
        PlayerCommandController(musicService).handlePlayPauseShortcut();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyN ||
        key == LogicalKeyboardKey.mediaTrackNext) {
      PlayerCommandController(musicService).handleNextShortcut();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyB ||
        key == LogicalKeyboardKey.keyP ||
        key == LogicalKeyboardKey.mediaTrackPrevious) {
      PlayerCommandController(musicService).handlePreviousShortcut();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyR || key == LogicalKeyboardKey.home) {
      PlayerCommandController(musicService).handleRestartShortcut();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyJ) {
      _seekRelative(musicService, -1, settings.seekStepSeconds);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyL) {
      _seekRelative(musicService, 1, settings.seekStepSeconds);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.audioVolumeDown) {
      _changeVolume(musicService, -1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.audioVolumeUp) {
      _changeVolume(musicService, 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM ||
        key == LogicalKeyboardKey.audioVolumeMute) {
      _toggleMute(musicService);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter && musicService.currentMusic != null) {
      _openPlayer();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && _isPlayerVisible) {
      _closePlayer();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Future<void> _toggleDesktopFullscreen() async {
    if (!_supportsDesktopFullscreen) return;
    final isFullScreen = await windowManager.isFullScreen();
    await windowManager.setFullScreen(!isFullScreen);
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
      leftOffset = _navDockCrossExtent;
    } else if (settings.navPosition == NavPosition.right) {
      rightOffset = _navDockCrossExtent;
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

    final commandController = PlayerCommandController(musicService);

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.digit1): _TogglePlayPauseIntent(),
        SingleActivator(LogicalKeyboardKey.numpad1): _TogglePlayPauseIntent(),
        SingleActivator(LogicalKeyboardKey.digit2): _NextTrackIntent(),
        SingleActivator(LogicalKeyboardKey.numpad2): _NextTrackIntent(),
        SingleActivator(LogicalKeyboardKey.digit3): _PreviousOrRestartIntent(),
        SingleActivator(LogicalKeyboardKey.numpad3): _PreviousOrRestartIntent(),
      },
      child: Actions(
        actions: {
          _TogglePlayPauseIntent: CallbackAction<_TogglePlayPauseIntent>(
            onInvoke: (_) {
              if (_isTypingInEditable()) return null;
              if (_allowPlayPauseShortcut()) {
                commandController.handlePlayPauseShortcut();
              }
              return null;
            },
          ),
          _NextTrackIntent: CallbackAction<_NextTrackIntent>(
            onInvoke: (_) {
              if (_isTypingInEditable()) return null;
              commandController.handleNextShortcut();
              return null;
            },
          ),
          _PreviousOrRestartIntent: CallbackAction<_PreviousOrRestartIntent>(
            onInvoke: (_) {
              if (_isTypingInEditable()) return null;
              commandController.handlePreviousShortcut();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          focusNode: _shortcutsFocusNode,
          onKeyEvent: (_, event) =>
              _handleGlobalKeyEvent(event, musicService, settings),
          onFocusChange: (hasFocus) {
            if (!hasFocus && !_isTypingInEditable()) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_isTypingInEditable()) {
                  _shortcutsFocusNode.requestFocus();
                }
              });
            }
          },
          child: PopScope(
            canPop: !_isPlayerVisible,
            onPopInvoked: (didPop) {
              if (!didPop && _isPlayerVisible) _closePlayer();
            },
            child: AnimatedBuilder(
              animation: _playerAnimationController,
              builder: (context, child) {
                final uiOpacity =
                    (1.0 - _playerAnimationController.value).clamp(0.0, 1.0);

                return Stack(
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
                                    SizedBox(
                                        height: _effectiveTopMargin(settings)),
                                    _buildTopAppBar(theme),
                                    Expanded(child: mainLayout),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          if (musicService.currentMusic != null &&
                              uiOpacity > 0.05)
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
                            child:
                                ParticleSystem(effect: settings.particleEffect),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  bool _isTypingInEditable() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    if (focusContext is! Element || !focusContext.mounted) return false;
    return focusContext.widget is EditableText ||
        focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  Widget _buildMicaBackground(MusicService musicService, ThemeData theme) {
    final policy = PerformancePolicy.of(context);
    final blur = policy.backgroundBlur;
    final coverPath = musicService.currentMusic?.coverPath;
    return Positioned.fill(
      child: AnimatedSwitcher(
        duration: policy.animation(const Duration(milliseconds: 360)),
        child: coverPath == null || coverPath.isEmpty
            ? Container(
                key: const ValueKey('bg-empty'),
                color: theme.colorScheme.surface,
              )
            : Stack(
                key: ValueKey('bg-cover-$coverPath'),
                fit: StackFit.expand,
                children: [
                  Container(color: theme.colorScheme.surface),
                  Transform.scale(
                    scale: 1.08,
                    child: CoverArtTexture(
                      coverArtPath: coverPath,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                  if (blur > 0)
                    ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: blur,
                          sigmaY: blur,
                        ),
                        child: ColoredBox(
                          color: theme.colorScheme.surface.withOpacity(
                            theme.brightness == Brightness.dark ? 0.74 : 0.80,
                          ),
                        ),
                      ),
                    )
                  else
                    ColoredBox(
                      color: theme.colorScheme.surface.withOpacity(
                        theme.brightness == Brightness.dark ? 0.88 : 0.92,
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  double _effectiveTopMargin(SettingsModel settings) {
    final height = MediaQuery.sizeOf(context).height;
    final cap = height < 520
        ? 12.0
        : height < 700
            ? 32.0
            : 96.0;
    return settings.topMargin.clamp(0.0, cap).toDouble();
  }

  double get _navDockCrossExtent =>
      ((Responsive.isCompact ? 64.0 : 72.0).s + (24.0.s));

  Widget _buildTopAppBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Text('PlayerVf',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface)),
              ],
            ),
          ),
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
    final dockHeight = Responsive.isCompact ? 62.0 : 68.0;
    final dockWidth = Responsive.isCompact ? 64.0 : 72.0;

    return Padding(
      padding: EdgeInsets.all(12.s),
      child: GlassContainer(
        width: isVertical ? dockWidth.s : double.infinity,
        height: isVertical ? double.infinity : dockHeight.s,
        borderRadius: BorderRadius.circular(22.s),
        color: null,
        blur: 6,
        child: Flex(
          direction: isVertical ? Axis.vertical : Axis.horizontal,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildNavItem(0, Icons.home_rounded),
            _buildNavItem(1, Icons.favorite_rounded),
            _buildNavItem(2, Icons.playlist_play_rounded),
            _buildNavItem(3, Icons.library_music_rounded),
            _buildNavItem(4, Icons.ios_share_rounded),
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
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutQuart,
        padding: EdgeInsets.symmetric(horizontal: 12.s, vertical: 8.s),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primaryContainer.withOpacity(0.82)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(18.s),
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
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutQuart,
          height: _isSearchOpen ? 64.h : 0,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _isSearchOpen ? _buildSearchBar(theme) : null,
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final offset = Tween<Offset>(
                begin: const Offset(0.025, 0),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: offset, child: child),
              );
            },
            child: IndexedStack(
              key: ValueKey(_selectedIndex),
              index: _selectedIndex,
              children: _screens,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return GlassContainer(
      borderRadius: BorderRadius.circular(20.s),
      color: null,
      blur: 6,
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
    final height = Responsive.isCompact ? 66.0.s : 74.0.s;
    final coverSize = (height - 20.0.s).clamp(42.0, 56.0).toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: _togglePlayer,
        child: GlassContainer(
          height: height,
          borderRadius: BorderRadius.circular(22.s),
          blur: 8,
          color: null,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 9.h),
            child: Row(
              children: [
                Hero(
                    tag: 'mini-player-art',
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(16.s),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 360),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          child: CoverArtTexture(
                              key: ValueKey(currentMusic.coverPath),
                              coverArtPath: currentMusic.coverPath,
                              width: coverSize,
                              height: coverSize),
                        ))),
                SizedBox(width: 14.w),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      final offset = Tween<Offset>(
                        begin: const Offset(0, 0.12),
                        end: Offset.zero,
                      ).animate(animation);
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(position: offset, child: child),
                      );
                    },
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
                ValueListenableBuilder<bool>(
                  valueListenable: musicService.playingNotifier,
                  builder: (_, isPlaying, __) {
                    return _MiniPlayPauseButton(
                      isPlaying: isPlaying,
                      onPressed: musicService.togglePlayPause,
                    );
                  },
                ),
                SizedBox(width: 6.w),
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

class _MiniPlayPauseButton extends StatefulWidget {
  final bool isPlaying;
  final VoidCallback onPressed;

  const _MiniPlayPauseButton({
    required this.isPlaying,
    required this.onPressed,
  });

  @override
  State<_MiniPlayPauseButton> createState() => _MiniPlayPauseButtonState();
}

class _MiniPlayPauseButtonState extends State<_MiniPlayPauseButton> {
  bool? _optimisticIsPlaying;
  Timer? _optimisticTimer;

  bool get _visualIsPlaying => _optimisticIsPlaying ?? widget.isPlaying;

  @override
  void didUpdateWidget(covariant _MiniPlayPauseButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_optimisticIsPlaying != null &&
        widget.isPlaying == _optimisticIsPlaying) {
      _clearOptimisticState();
    }
  }

  @override
  void dispose() {
    _optimisticTimer?.cancel();
    super.dispose();
  }

  void _clearOptimisticState() {
    _optimisticTimer?.cancel();
    _optimisticTimer = null;
    _optimisticIsPlaying = null;
  }

  void _handlePressed() {
    final nextVisualState = !_visualIsPlaying;
    _optimisticTimer?.cancel();
    setState(() => _optimisticIsPlaying = nextVisualState);
    _optimisticTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() => _optimisticIsPlaying = null);
      }
    });
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visualIsPlaying = _visualIsPlaying;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: visualIsPlaying ? 1 : 0),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.scale(
          scale: 0.98 + (value * 0.02),
          child: IconButton(
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final scale = Tween<double>(begin: 0.9, end: 1).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                );
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: scale, child: child),
                );
              },
              child: Icon(
                visualIsPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                key: ValueKey(visualIsPlaying),
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            onPressed: _handlePressed,
            style: IconButton.styleFrom(
              backgroundColor: Color.lerp(
                theme.colorScheme.primaryContainer.withOpacity(0.86),
                theme.colorScheme.primary.withOpacity(0.34),
                value,
              ),
              foregroundColor: theme.colorScheme.onPrimaryContainer,
              fixedSize: Size(46.s, 46.s),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.s),
              ),
            ),
          ),
        );
      },
    );
  }
}
