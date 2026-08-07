import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher, PointerDeviceKind;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, kIsWeb;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'services/music_service.dart';
import 'services/listen_together_service.dart';
import 'services/orb_controller.dart';
import 'services/player_audio_handler.dart';
import 'models/settings_model.dart';
import 'security/auth_manager.dart';
import 'services/debug_service.dart';
import 'services/spotify_service.dart';
import 'core/app_navigator.dart';
import 'v2/core/theme/app_theme.dart';
import 'v2/navigation/player_shell.dart';

DateTime _lastKeyboardAssertionLog = DateTime.fromMillisecondsSinceEpoch(0);

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

  // Initialize Unison authentication (ECDSA P-256 keypair)
  // Generates new keypair on first run, loads from secure storage thereafter.
  final authManager = AuthManager();
  await authManager.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsModel>.value(value: settings),
        ChangeNotifierProvider<MusicService>(create: (_) => MusicService()),
        ChangeNotifierProvider<ListenTogetherService>(
            create: (_) => ListenTogetherService()),
        ChangeNotifierProvider<OrbController>.value(
            value: OrbController.instance),
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
          navigatorKey: appNavigatorKey,
          themeMode: settings.themeMode,
          theme: PlayerTheme.build(settings, Brightness.light),
          darkTheme: PlayerTheme.build(settings, Brightness.dark),
          builder: (context, child) {
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
              child: child ?? const SizedBox.shrink(),
            );
          },
          scrollBehavior: const _SmoothScrollBehavior(),
          home: const PlayerShell(),
          debugShowCheckedModeBanner: false,
        );
      },
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
