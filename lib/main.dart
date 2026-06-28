import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher, PointerDeviceKind;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, kIsWeb;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'pages/home_screen.dart';
import 'pages/favorite_page.dart';
import 'pages/playlist_page.dart';
import 'pages/records_page.dart';
import 'pages/player_page.dart';
import 'pages/youtube_music_page.dart';
import 'pages/share_page.dart';
import 'services/music_service.dart';
import 'services/listen_together_service.dart';
import 'services/orb_controller.dart';
import 'services/performance_policy.dart';
import 'services/player_audio_handler.dart';
import 'models/settings_model.dart';
import 'models/music_model.dart';
import 'services/responsive.dart';
import 'widgets/lanczos_cover_art.dart';
import 'widgets/cover_art_texture.dart';
import 'widgets/blurred_cover_background.dart';
import 'widgets/glass_container.dart';
import 'pages/artist_page.dart';
import 'pages/album_detail_page.dart';
import 'pages/settings_page.dart';
import 'widgets/fast_settings_menu.dart';
import 'widgets/particle_system.dart';
import 'widgets/orb_system.dart';
import 'widgets/listen_together_sheet.dart';
import 'services/debug_service.dart';
import 'services/cover_color_service.dart';
import 'services/spotify_service.dart';

DateTime _lastKeyboardAssertionLog = DateTime.fromMillisecondsSinceEpoch(0);
const List<String> _textFontFallback = [
  'NotoSans',
  'NotoSansJP',
  'NotoSansSC',
];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debug.init();
  _installWindowsKeyboardAssertionGuard();
  await _configureMobileSystemUi();
  _configureImageCache();
  MediaKit.ensureInitialized();
  playerAudioHandler = await initPlayerAudioHandler();
  debug.perf('Core initialization complete');

  if (_supportsDesktopFullscreen) {
    try {
      await windowManager.ensureInitialized();
    } on MissingPluginException catch (error) {
      debugPrint('Window manager plugin unavailable: $error');
    }
  }

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  final settings = SettingsModel();
  await settings.loadSettings();

  final spotifyService = SpotifyService();
  await spotifyService.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsModel>.value(value: settings),
        ChangeNotifierProvider<MusicService>(create: (_) => MusicService()),
        ChangeNotifierProvider<ListenTogetherService>(create: (_) => ListenTogetherService()),
        ChangeNotifierProvider<OrbController>.value(value: OrbController.instance),
        ChangeNotifierProvider<SpotifyService>.value(value: spotifyService),
      ],
      child: const MyApp(),
    ),
  );
}

Future<void> _configureMobileSystemUi() async {
  if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
}

bool get _supportsDesktopFullscreen =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

void _configureImageCache() {
  if (kIsWeb) {
    imageCache.maximumSize = 160;
    imageCache.maximumSizeBytes = 72 << 20;
    return;
  }

  final isMobile = Platform.isAndroid || Platform.isIOS;
  if (Platform.isAndroid) {
    // Generous cache for Android: largeHeap is enabled in AndroidManifest so
    // we can afford more entries without OOM pressure.
    imageCache.maximumSize = 240;
    imageCache.maximumSizeBytes = 96 << 20;
  } else {
    imageCache.maximumSize = isMobile ? 260 : 420;
    imageCache.maximumSizeBytes = (isMobile ? 112 : 192) << 20;
  }
  debug.perf(
    'Image cache: max=${imageCache.maximumSize} '
    'bytes=${imageCache.maximumSizeBytes >> 20}MB '
    'platform=${isMobile ? "mobile" : "desktop"}',
  );
}

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
          builder: (context, child) {
            final defaultStyle = DefaultTextStyle.of(context).style;
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarDividerColor: Colors.transparent,
                statusBarIconBrightness:
                    isDark ? Brightness.light : Brightness.dark,
                systemNavigationBarIconBrightness:
                    isDark ? Brightness.light : Brightness.dark,
              ),
              child: DefaultTextStyle(
                style: _withCjkFallback(defaultStyle) ?? defaultStyle,
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
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
            onSurface: const Color(0xFF1A1D23),
            surfaceContainerLowest: const Color(0xFFF0F1F4),
            surfaceContainerLow: const Color(0xFFE8EAEE),
            surfaceContainer: const Color(0xFFDEE1E6),
            surfaceContainerHigh: const Color(0xFFD4D8DE),
            surfaceContainerHighest: const Color(0xFFC8CDD5),
            outline: const Color(0xFF7A8594),
            outlineVariant: const Color(0xFFB8BFC9),
          )
        : generatedScheme.copyWith(surface: surface);
    final radius = BorderRadius.circular(20);

    final theme = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: 'NotoSans',
      fontFamilyFallback: _textFontFallback,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      cardColor: scheme.surfaceContainerLow,
      dialogBackgroundColor: scheme.surfaceContainerLow,
      splashFactory: InkRipple.splashFactory,
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          TargetPlatform.android: const ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: const CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: const FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: const FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: const CupertinoPageTransitionsBuilder(),
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
          fontSize: 19,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          backgroundColor: scheme.surfaceContainerHigh.withOpacity(controlFill),
          hoverColor: scheme.primary.withOpacity(0.08),
          highlightColor: scheme.primary.withOpacity(0.12),
          fixedSize: const Size(42, 42),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 42),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size(48, 42),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          backgroundColor: scheme.surfaceContainerHigh.withOpacity(
            brightness == Brightness.dark
                ? (0.74 - (0.10 * glass))
                : (0.92 - (0.08 * glass)),
          ),
          foregroundColor: scheme.onSurface,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 42),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        iconColor: scheme.primary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(
            color: scheme.outlineVariant.withOpacity(outlineOpacity)),
        backgroundColor: scheme.surfaceContainerHigh.withOpacity(
          controlFill,
        ),
        selectedColor: scheme.primaryContainer.withOpacity(selectedFill),
        labelStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHighest.withOpacity(
          brightness == Brightness.dark
              ? (0.78 - (0.10 * glass))
              : (0.90 - (0.08 * glass)),
        ),
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withOpacity(0.12),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
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
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
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
        fillColor: scheme.surfaceContainerHigh.withOpacity(
          brightness == Brightness.dark ? 0.54 : 0.82,
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
    return theme.copyWith(
      textTheme: _withCjkTextTheme(theme.textTheme),
      primaryTextTheme: _withCjkTextTheme(theme.primaryTextTheme),
      appBarTheme: theme.appBarTheme.copyWith(
        titleTextStyle: _withCjkFallback(theme.appBarTheme.titleTextStyle),
        toolbarTextStyle: _withCjkFallback(theme.appBarTheme.toolbarTextStyle),
      ),
    );
  }

  TextTheme _withCjkTextTheme(TextTheme textTheme) {
    return textTheme.copyWith(
      displayLarge: _withCjkFallback(textTheme.displayLarge),
      displayMedium: _withCjkFallback(textTheme.displayMedium),
      displaySmall: _withCjkFallback(textTheme.displaySmall),
      headlineLarge: _withCjkFallback(textTheme.headlineLarge),
      headlineMedium: _withCjkFallback(textTheme.headlineMedium),
      headlineSmall: _withCjkFallback(textTheme.headlineSmall),
      titleLarge: _withCjkFallback(textTheme.titleLarge),
      titleMedium: _withCjkFallback(textTheme.titleMedium),
      titleSmall: _withCjkFallback(textTheme.titleSmall),
      bodyLarge: _withCjkFallback(textTheme.bodyLarge),
      bodyMedium: _withCjkFallback(textTheme.bodyMedium),
      bodySmall: _withCjkFallback(textTheme.bodySmall),
      labelLarge: _withCjkFallback(textTheme.labelLarge),
      labelMedium: _withCjkFallback(textTheme.labelMedium),
      labelSmall: _withCjkFallback(textTheme.labelSmall),
    );
  }

  TextStyle? _withCjkFallback(TextStyle? style) {
    if (style == null) return null;
    final existing = style.fontFamilyFallback ?? const <String>[];
    final fallback = <String>[
      ...existing,
      for (final family in _textFontFallback)
        if (!existing.contains(family)) family,
    ];
    return style.copyWith(fontFamilyFallback: fallback);
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
            : const Color(0xFFE8EAEE);
      case ThemePreset.graphite:
        return brightness == Brightness.dark
            ? const Color(0xFF151719)
            : const Color(0xFFE4E6EA);
      case ThemePreset.classic:
        return brightness == Brightness.dark
            ? const Color(0xFF151616)
            : const Color(0xFFEAECEF);
      case ThemePreset.azure:
        return brightness == Brightness.dark
            ? const Color(0xFF10171C)
            : const Color(0xFFE5EAF0);
      case ThemePreset.sunset:
        return brightness == Brightness.dark
            ? const Color(0xFF1C1715)
            : const Color(0xFFEDE9E6);
      default:
        return brightness == Brightness.dark
            ? const Color(0xFF111315)
            : const Color(0xFFE6E8EC);
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
  bool _isPageTransitioning = false;
  late PageController _pageController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _shortcutsFocusNode = FocusNode(debugLabel: 'main-shortcuts');
  DateTime _lastPlayPauseShortcut = DateTime.fromMillisecondsSinceEpoch(0);
  double _lastNonZeroVolume = 100.0;
  bool _isSearchOpen = false;
  String _searchQuery = '';
  Timer? _searchDebounce;

  // Palette cache for coverArtShadowPoints — avoids FutureBuilder rebuild blink
  Future<CoverArtPalette>? _paletteFuture;
  String _paletteCoverPath = '';
  CoverArtPalette _paletteSnapshot = CoverColorService.fallbackPalette;

  void _syncPalette(String? coverPath, int paletteSize) {
    final path = coverPath ?? '';
    final key = '$path::$paletteSize';
    if (key == _paletteCoverPath) return;
    _paletteCoverPath = key;
    _paletteFuture = CoverColorService.fromPath(path, paletteSize: paletteSize);
    _paletteFuture!.then((p) {
      if (mounted) {
        setState(() => _paletteSnapshot = p);
        context.read<OrbController>().setColors(p.orbColors.isNotEmpty ? p.orbColors : [
          p.dominant,
          p.vibrant,
          p.accent,
          p.darkVibrant,
          p.lightVibrant,
        ]);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _shortcutsFocusNode.requestFocus();
    });
    _pageController = PageController(initialPage: 0);
    _pageController.addListener(_onPageTransition);
  }

  void _onPageTransition() {
    if (!_pageController.hasClients) return;
    final pixels = _pageController.page;
    if (pixels == null) return;
    final isAnimating = (pixels - _selectedIndex).abs() > 0.01;
    if (_isPageTransitioning != isAnimating) {
      _isPageTransitioning = isAnimating;
      // Defer setState to avoid frame drops during smooth page scrolling
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _shortcutsFocusNode.dispose();
    super.dispose();
  }

  List<Widget> _cachedScreens = const [];
  String _lastSearchQuery = '';

  List<Widget> get _screens {
    if (_cachedScreens.length == 6 && _searchQuery == _lastSearchQuery) {
      return _cachedScreens;
    }
    _lastSearchQuery = _searchQuery;
    _cachedScreens = [
      HomeScreen(searchQuery: _searchQuery, onOpenPlayer: _openPlayer),
      RecordsPage(searchQuery: _searchQuery, onOpenPlayer: _openPlayer),
      FavoritePage(searchQuery: _searchQuery, onOpenPlayer: _openPlayer),
      PlaylistPage(searchQuery: _searchQuery, onOpenPlayer: _openPlayer),
      YoutubeMusicPage(onOpenPlayer: _openPlayer),
      const SharePage(),
    ];
    return _cachedScreens;
  }

  void _onDestinationSelected(int index) {
    if (index == _selectedIndex) return;
    _selectedIndex = index;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _togglePlayer() {
    if (_isPlayerVisible) {
      _closePlayer();
    } else {
      _openPlayer();
    }
  }

  void _closePlayer() {
    if (_isPlayerVisible) {
      Navigator.of(context).pop();
    }
  }

  void _openPlayer() {
    if (_isPlayerVisible) return;
    _isPlayerVisible = true;
    
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 600),
        reverseTransitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (context, animation, secondaryAnimation) {
          return PlayerPage(
            onClose: () => Navigator.of(context).pop(),
            routeAnimation: animation,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return child; // Hero and Fade handled inside PlayerPage
        },
      ),
    ).then((_) {
      if (mounted) {
        setState(() {
          _isPlayerVisible = false;
        });
      }
    });
  }

  void _updateSearchQuery(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == _searchQuery) return;
    _searchDebounce?.cancel();
    _searchDebounce =
        Timer(const Duration(milliseconds: kIsWeb ? 320 : 180), () {
      if (!mounted) return;
      setState(() => _searchQuery = normalized);
    });
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
  KeyEventResult _handleGlobalKeyEvent(FocusNode focusNode, KeyEvent event) {
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

    final context = focusNode.context;
    if (context == null) return KeyEventResult.ignored;
    
    final musicService = context.read<MusicService>();
    final settings = context.read<SettingsModel>();

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      if (_allowPlayPauseShortcut()) {
        musicService.togglePlayPause();
      }

      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyN ||
        key == LogicalKeyboardKey.mediaTrackNext) {
      musicService.next();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyB ||
        key == LogicalKeyboardKey.keyP ||
        key == LogicalKeyboardKey.mediaTrackPrevious) {
      musicService.previous();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyR || key == LogicalKeyboardKey.home) {
      musicService.restartCurrentTrack();
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
    final theme = Theme.of(context);
    final policy = PerformancePolicy.of(context);
    final isPhone = !Responsive.isTablet;

    final navPosition = context.select<SettingsModel, NavPosition>((s) => s.navPosition);
    final topMargin = context.select<SettingsModel, double>((s) => s.topMargin);
    final backgroundMode = context.select<SettingsModel, BackgroundMode>((s) => s.backgroundMode);
    final isSolidColor = backgroundMode == BackgroundMode.solidColor;

    final particleEffect = isSolidColor
        ? ParticleEffect.coverArtShadowPoints
        : context.select<SettingsModel, ParticleEffect>((s) => s.particleEffect);
    final customParticlePack = context.select<SettingsModel, String>((s) => s.customParticlePack);
    final orbPaletteSize = context.select<SettingsModel, int>((s) => s.orbPaletteSize);
    final allowParticles = isSolidColor ? true : policy.allowParticles;

    final currentMusic = context.select<MusicService, Music?>((s) => s.currentMusic);
    // Sync palette whenever the track changes (no FutureBuilder, no blink)
    _syncPalette(currentMusic?.coverPath, orbPaletteSize);
    final paletteColors = [_paletteSnapshot.dominant, _paletteSnapshot.accent,
                           _paletteSnapshot.backgroundMid, _paletteSnapshot.backgroundStart];
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    final leftOffset = navPosition == NavPosition.left ? _navDockCrossExtent : 0.0;
    final rightOffset = navPosition == NavPosition.right ? _navDockCrossExtent : 0.0;
    final isVerticalNav = navPosition == NavPosition.left || navPosition == NavPosition.right;

    final navDock = _buildNavigationDock(navPosition, theme);
    final mainLayout = isVerticalNav
        ? Row(
            children: [
              if (navPosition == NavPosition.left) navDock,
              Expanded(child: _buildMainContentArea(theme)),
              if (navPosition == NavPosition.right) navDock,
            ],
          )
        : Column(
            children: [
              if (navPosition == NavPosition.top) navDock,
              Expanded(child: _buildMainContentArea(theme)),
              if (navPosition == NavPosition.bottom) navDock,
            ],
          );

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
                context.read<MusicService>().togglePlayPause();
              }
              return null;
            },
          ),
          _NextTrackIntent: CallbackAction<_NextTrackIntent>(
            onInvoke: (_) {
              if (_isTypingInEditable()) return null;
              context.read<MusicService>().next();
              return null;
            },
          ),
          _PreviousOrRestartIntent: CallbackAction<_PreviousOrRestartIntent>(
            onInvoke: (_) {
              if (_isTypingInEditable()) return null;
              context.read<MusicService>().previous();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          focusNode: _shortcutsFocusNode,
          onKeyEvent: (focusNode, event) => _handleGlobalKeyEvent(focusNode, event),
          onFocusChange: (hasFocus) {
            if (!hasFocus && !_isTypingInEditable()) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_isTypingInEditable()) {
                  _shortcutsFocusNode.requestFocus();
                }
              });
            }
          },
           child: Scaffold(
                 key: _scaffoldKey,
                 backgroundColor: Colors.transparent,
                 body: Stack(
                   children: [
                     _buildMicaBackground(currentMusic, theme),
                       if (allowParticles)
                          IgnorePointer(
                            child: Builder(
                              builder: (context) {
                                if (particleEffect == ParticleEffect.coverArtShadowPoints) {
                                  return const OrbSystem(
                                    paused: false,
                                    intensity: 1.0,
                                  );
                                }
                                return ValueListenableBuilder<bool>(
                                  valueListenable: context.read<MusicService>().playingNotifier,
                                  builder: (context, isPlaying, child) {
                                    final targetIntensity = isPlaying ? 1.0 : 0.0;
                                    return TweenAnimationBuilder<double>(
                                      tween: Tween<double>(begin: 0.0, end: targetIntensity),
                                      duration: const Duration(milliseconds: 800),
                                      curve: Curves.easeInOutCubic,
                                      builder: (context, intensity, child) {
                                        return isSolidColor
                                          ? ParticleSystem(
                                              effect: particleEffect,
                                              customPack: customParticlePack,
                                              paused: _isPageTransitioning || intensity == 0.0,
                                              overrideColors: paletteColors,
                                              intensity: intensity,
                                            )
                                          : ParticleSystem(
                                              effect: particleEffect,
                                              customPack: customParticlePack,
                                              paused: _isPageTransitioning || intensity == 0.0,
                                              intensity: intensity,
                                            );
                                      },
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                      _PlayerContentOverlay(
                        mainLayout: mainLayout,
                        appBar: _buildTopAppBar(theme),
                        topMargin: _effectiveTopMargin(topMargin),
                      ),
                      if (currentMusic != null)
                        _MiniPlayerOverlay(
                          leftOffset: leftOffset,
                          rightOffset: rightOffset,
                          bottomOffset: navPosition == NavPosition.bottom
                              ? (isPhone
                                  ? _mobileBottomNavMiniPlayerOffset(safeBottom)
                                  : 110.h)
                              : 24.h,
                          child: _buildMiniPlayer(currentMusic),
                        ),
                    ],
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


  Widget _buildMicaBackground(Music? currentMusic, ThemeData theme) {
    final policy = PerformancePolicy.of(context);
    final blur = policy.backgroundBlur;
    final coverPath = currentMusic?.coverPath;
    final backgroundMode = context.select<SettingsModel, BackgroundMode>((s) => s.backgroundMode);
    final customBackgroundImage = context.select<SettingsModel, String>((s) => s.customBackgroundImage);

    if (backgroundMode == BackgroundMode.solidColor) {
      return Positioned.fill(
        child: Container(
          key: const ValueKey('bg-solid'),
          color: theme.colorScheme.surface,
        ),
      );
    } else if (backgroundMode == BackgroundMode.customImage && customBackgroundImage.isNotEmpty) {
      return Positioned.fill(
        child: AnimatedSwitcher(
          duration: _isPageTransitioning
              ? Duration.zero
              : policy.animation(const Duration(milliseconds: 360)),
            child: TweenAnimationBuilder<double>(
              key: ValueKey('bg-custom-tween-$customBackgroundImage'),
              tween: Tween<double>(begin: blur, end: _isPlayerVisible ? blur + 20 : blur),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeInOutCubic,
              builder: (context, currentBlur, child) {
                return BlurredCoverBackground(
                  coverArtPath: customBackgroundImage,
                surfaceColor: theme.colorScheme.surface,
                overlayColor: theme.colorScheme.surface.withOpacity(
                  blur > 0
                      ? (theme.brightness == Brightness.dark ? 0.74 : 0.80)
                      : (theme.brightness == Brightness.dark ? 0.88 : 0.92),
                ),
                blur: currentBlur,
              );
            },
          ),
        ),
      );
    }

    return Positioned.fill(
      child: AnimatedSwitcher(
        duration: _isPageTransitioning
            ? Duration.zero
            : policy.animation(const Duration(milliseconds: 360)),
        child: coverPath == null || coverPath.isEmpty
            ? Container(
                key: const ValueKey('bg-empty'),
                color: theme.colorScheme.surface,
              )
            : TweenAnimationBuilder<double>(
                key: ValueKey('bg-cover-tween-$coverPath'),
                tween: Tween<double>(begin: blur, end: _isPlayerVisible ? blur + 20 : blur),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeInOutCubic,
                builder: (context, currentBlur, child) {
                  return BlurredCoverBackground(
                    coverArtPath: coverPath,
                    surfaceColor: theme.colorScheme.surface,
                    overlayColor: theme.colorScheme.surface.withOpacity(
                      blur > 0
                          ? (theme.brightness == Brightness.dark ? 0.74 : 0.80)
                          : (theme.brightness == Brightness.dark ? 0.88 : 0.92),
                    ),
                    blur: currentBlur,
                  );
                },
              ),
      ),
    );
  }

  double _effectiveTopMargin(double topMargin) {
    if (!Responsive.isTablet) return 0;
    final height = MediaQuery.sizeOf(context).height;
    final cap = height < 520
        ? 12.0
        : height < 700
            ? 32.0
            : 96.0;
    return topMargin.clamp(0.0, cap).toDouble();
  }

  double get _navDockCrossExtent =>
      ((Responsive.isCompact ? 64.0 : 72.0).s + (24.0.s));

  double _mobileBottomNavMiniPlayerOffset(double safeBottom) {
    final dockHeight = 60.0.s;
    final verticalPadding = 8.0.h;
    final safeAreaMinimum = 4.0.h;
    return dockHeight + verticalPadding + safeAreaMinimum + safeBottom + 8.h;
  }

  Widget _buildTopAppBar(ThemeData theme) {
    final isPhone = !Responsive.isTablet;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isPhone ? 14.w : 20,
        isPhone ? 4.h : 8,
        isPhone ? 10.w : 20,
        isPhone ? 4.h : 8,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Text('PlayerVf',
                    style: TextStyle(
                        fontSize: isPhone ? 20.sp : 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
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
                    _searchDebounce?.cancel();
                    _searchController.clear();
                    _searchQuery = '';
                  }
                }),
              ),
              IconButton(
                icon: const Icon(Icons.settings_rounded),
                onPressed: () => showFastSettingsMenu(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationDock(NavPosition navPosition, ThemeData theme) {
    final isPhone = !Responsive.isTablet;
    final effectivePosition = navPosition;
    final isVertical = effectivePosition == NavPosition.left ||
        effectivePosition == NavPosition.right;
    final dockHeight = isPhone ? 60.0 : (Responsive.isCompact ? 62.0 : 68.0);
    final dockWidth = isPhone ? 56.0 : (Responsive.isCompact ? 64.0 : 72.0);

    return SafeArea(
      top: false,
      left: false,
      right: false,
      minimum: EdgeInsets.only(bottom: isPhone ? 4.h : 0),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isPhone ? 8.w : 12.s,
          isPhone ? 4.h : 12.s,
          isPhone ? 8.w : 12.s,
          isPhone ? 4.h : 12.s,
        ),
        child: GlassContainer(
          width: isVertical ? dockWidth.s : double.infinity,
          height: isVertical ? double.infinity : dockHeight.s,
          borderRadius: BorderRadius.circular(isPhone ? 10.s : 12.s),
          color: null,
          blur: 0,
          child: Flex(
            direction: isVertical ? Axis.vertical : Axis.horizontal,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildNavItem(0, Icons.home_rounded),
              _buildNavItem(1, Icons.inventory_2_rounded),
              _buildNavItem(2, Icons.favorite_rounded),
              _buildNavItem(3, Icons.playlist_play_rounded),
              _buildNavItem(4, Icons.library_music_rounded),
              _buildNavItem(5, Icons.ios_share_rounded),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon) {
    final isSelected = _selectedIndex == index;
    final theme = Theme.of(context);
    final isPhone = !Responsive.isTablet;

    return GestureDetector(
      onTap: () => _onDestinationSelected(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutQuart,
        padding: EdgeInsets.symmetric(
          horizontal: Responsive.isTablet ? 12.s : (isSelected ? 11.s : 9.s),
          vertical: Responsive.isTablet ? 8.s : 8.s,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primaryContainer.withOpacity(0.92)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(Responsive.isTablet ? 9.s : 8.s),
          border: isSelected
              ? Border.all(
                  color: theme.colorScheme.primary.withOpacity(0.46),
                  width: 1,
                )
              : null,
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
              size: (isPhone ? 25 : 24).s,
            ),
          ],
        ),
      ),
    );
  }

  static const Duration _pageTransitionDuration = Duration(milliseconds: 350);

  Widget _buildMainContentArea(ThemeData theme) {
    if (_isSearchOpen) {
      return Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
                horizontal: Responsive.isTablet ? 20 : 14.w),
            child: _buildSearchBar(theme),
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildSearchResults(theme)),
        ],
      );
    }
    return Column(
      children: [
        Expanded(
          child: RepaintBoundary(
            child: PageView(
              controller: _pageController,
              physics: const PageScrollPhysics(),
              allowImplicitScrolling: true,
              onPageChanged: (index) {
                if (index != _selectedIndex) {
                  setState(() {
                    _selectedIndex = index;
                  });
                }
              },
              children: _screens.map((screen) => _CachedPage(child: screen)).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResults(ThemeData theme) {
    final musicService = context.read<MusicService>();
    final query = _searchQuery;
    final results = query.isEmpty
        ? <Music>[]
        : musicService.musicList
            .where((m) => m.searchText.contains(query))
            .toList();
    if (query.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_rounded,
                size: 48, color: theme.colorScheme.onSurface.withOpacity(0.15)),
            const SizedBox(height: 8),
            Text(
              'Type to search your library',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.4),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }
    if (results.isEmpty) {
      return Center(
        child: Text(
          'No results found',
          style: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.4),
            fontSize: 14,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: Responsive.isTablet ? 20 : 14.w),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final music = results[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 44,
              height: 44,
              child: music.coverPath.isNotEmpty
                  ? CoverArtTexture(
                      coverArtPath: music.coverPath,
                      width: 44,
                      height: 44,
                    )
                  : Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Icon(Icons.music_note_rounded,
                          color: theme.colorScheme.onSurface.withOpacity(0.4)),
                    ),
            ),
          ),
          title: Text(
            music.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: RichText(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
              children: [
                if (music.artist.isNotEmpty)
                  TextSpan(
                    text: music.artist,
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        Navigator.of(context).push(
                          PageRouteBuilder(
                            transitionDuration: const Duration(milliseconds: 320),
                            reverseTransitionDuration: const Duration(milliseconds: 280),
                            pageBuilder: (_, __, ___) => ArtistPage(
                              artistName: music.artist,
                              localCoverPath: music.coverPath,
                            ),
                            transitionsBuilder: (_, anim, __, child) {
                              return FadeTransition(
                                opacity: CurvedAnimation(
                                  parent: anim,
                                  curve: Curves.easeOutCubic,
                                ),
                                child: child,
                              );
                            },
                          ),
                        );
                      },
                  ),
                if (music.album.isNotEmpty) ...[
                  const TextSpan(text: ' · '),
                  TextSpan(
                    text: music.album,
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AlbumDetailPage(
                                albumName: music.album),
                          ),
                        );
                      },
                  ),
                ],
              ],
            ),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.play_circle_outline_rounded),
            onPressed: () {
              musicService.playMusicFromQueue(musicService.musicList, music);
              setState(() {
                _isSearchOpen = false;
                _searchQuery = '';
                _searchController.clear();
              });
            },
          ),
          onTap: () {
            musicService.playMusicFromQueue(musicService.musicList, music);
            setState(() {
              _isSearchOpen = false;
              _searchQuery = '';
              _searchController.clear();
            });
          },
        );
      },
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return SizedBox(
      height: 48.h.clamp(44.0, 52.0),
      child: GlassContainer(
        borderRadius: BorderRadius.circular(8.s),
        color: null,
        blur: 0,
        child: TextField(
          controller: _searchController,
          textAlignVertical: TextAlignVertical.center,
          onChanged: (q) {
            _searchDebounce?.cancel();
            final trimmed = q.trim().toLowerCase();
            _searchDebounce = Timer(const Duration(milliseconds: 250), () {
              setState(() => _searchQuery = trimmed);
            });
          },
          decoration: InputDecoration(
            hintText: 'Search library...',
            border: InputBorder.none,
            isDense: true,
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            contentPadding: EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }

  static bool _isNetworkCover(String path) {
    return path.startsWith('http://') || path.startsWith('https://');
  }

  Widget _buildMiniPlayer(Music? currentMusic) {
    if (currentMusic == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final height = Responsive.isCompact ? 66.0.s : 74.0.s;
    final coverTag = 'cover-art-${currentMusic.id}';
    final titleTag = 'title-${currentMusic.id}';
    final artistTag = 'artist-${currentMusic.id}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: _togglePlayer,
        child: GlassContainer(
          height: height,
          borderRadius: BorderRadius.circular(10.s),
          blur: 0,
          color: null,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 9.h),
            child: Row(
              children: [
                ClipRRect(
                    borderRadius:
                        BorderRadius.circular(Responsive.listArtRadius),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 360),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: SizedBox(
                        width: Responsive.listArtSize,
                        height: Responsive.listArtSize,
                        child: Hero(
                          key: ValueKey(currentMusic.coverPath),
                          tag: coverTag,
                          child: Material(
                            color: Colors.transparent,
                            child: _isNetworkCover(currentMusic.coverPath)
                                ? CoverArtTexture(
                                    coverArtPath: currentMusic.coverPath,
                                    width: Responsive.listArtSize,
                                    height: Responsive.listArtSize,
                                    borderRadius: BorderRadius.circular(
                                        Responsive.listArtRadius),
                                  )
                                : LanczosCoverArt(
                                    coverArtPath: currentMusic.coverPath,
                                    width: Responsive.listArtSize,
                                    height: Responsive.listArtSize,
                                    borderRadius: BorderRadius.circular(
                                        Responsive.listArtRadius),
                                  ),
                          ),
                        ),
                      ),
                    )),
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
                          Hero(
                            tag: titleTag,
                            child: Material(
                              color: Colors.transparent,
                              child: Text(currentMusic.title,
                                  style:
                                      const TextStyle(fontWeight: FontWeight.bold),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ),
                          Hero(
                            tag: artistTag,
                            child: Material(
                              color: Colors.transparent,
                              child: ValueListenableBuilder<Duration>(
                                valueListenable:
                                    context.read<MusicService>().songGapRemainingNotifier,
                                builder: (context, remaining, _) {
                                  final text = remaining > Duration.zero
                                      ? 'next track: ${(remaining.inMilliseconds / 1000).ceil().clamp(1, 99)} sec'
                                      : currentMusic.artist;
                                  return Text(text,
                                      style: TextStyle(
                                          fontSize: 12.sp,
                                          fontWeight: remaining > Duration.zero
                                              ? FontWeight.w800
                                              : FontWeight.w400,
                                          color: (remaining > Duration.zero
                                                  ? theme.colorScheme.primary
                                                  : theme.colorScheme.onSurface)
                                              .withOpacity(0.68)),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis);
                                },
                              ),
                            ),
                          ),
                        ]),
                  ),
                ),
                Consumer<ListenTogetherService>(
                  builder: (context, party, _) {
                    final isActive = party.isPartyHosting || party.isPartyJoined;
                    return IconButton(
                      tooltip: 'Listen Together',
                      icon: Icon(
                        isActive ? Icons.groups_rounded : Icons.group_add_rounded,
                        color: isActive
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface.withOpacity(0.44),
                      ),
                      onPressed: () => showListenTogetherSheet(context),
                    );
                  },
                ),
                SizedBox(width: 6.w),
                ValueListenableBuilder<bool>(
                  valueListenable: context.read<MusicService>().playingNotifier,
                  builder: (_, isPlaying, __) {
                    return _MiniPlayPauseButton(
                      isPlaying: isPlaying,
                      onPressed: () {
                        final party = context.read<ListenTogetherService>();
                        party.runPartyPlaybackCommand('toggle', context.read<MusicService>());
                      },
                    );
                  },
                ),
                SizedBox(width: 6.w),
                IconButton(
                    icon: const Icon(Icons.skip_next_rounded),
                    onPressed: () {
                      final party = context.read<ListenTogetherService>();
                      party.runPartyPlaybackCommand('next', context.read<MusicService>());
                    }),
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
                borderRadius: BorderRadius.circular(8.s),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MiniPlayerOverlay extends StatelessWidget {
  final double leftOffset;
  final double rightOffset;
  final double bottomOffset;
  final Widget child;

  const _MiniPlayerOverlay({
    super.key,
    required this.leftOffset,
    required this.rightOffset,
    required this.bottomOffset,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: leftOffset,
      right: rightOffset,
      bottom: bottomOffset,
      child: child,
    );
  }
}

class _PlayerContentOverlay extends StatelessWidget {
  final Widget mainLayout;
  final Widget appBar;
  final double topMargin;

  const _PlayerContentOverlay({
    super.key,
    required this.mainLayout,
    required this.appBar,
    required this.topMargin,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          SizedBox(height: topMargin),
          appBar,
          Expanded(
            child: RepaintBoundary(child: mainLayout),
          ),
        ],
      ),
    );
  }
}



class _CachedPage extends StatefulWidget {
  final Widget child;

  const _CachedPage({required this.child});

  @override
  State<_CachedPage> createState() => _CachedPageState();
}

class _CachedPageState extends State<_CachedPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RepaintBoundary(child: widget.child);
  }
}
