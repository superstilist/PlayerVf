import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Directory? _documentsDirectory;
Directory? _supportDirectory;
Directory? _cacheDirectory;
bool _loggedDocumentsFallback = false;
bool _loggedSupportFallback = false;
bool _loggedCacheFallback = false;

Future<Directory> getPlayerVfDocumentsDirectory() async {
  final cached = _documentsDirectory;
  if (cached != null) return cached;

  try {
    final dir = await getApplicationDocumentsDirectory();
    _documentsDirectory = dir;
    return dir;
  } catch (error) {
    if (kDebugMode && !_loggedDocumentsFallback) {
      _loggedDocumentsFallback = true;
      debugPrint(
          'Application documents directory unavailable, using fallback: $error');
    }
  }

  final dir = Directory(_fallbackDocumentsPath());
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  _documentsDirectory = dir;
  return dir;
}

Future<Directory> getPlayerVfSupportDirectory() async {
  final cached = _supportDirectory;
  if (cached != null) return cached;

  try {
    final dir = await getApplicationSupportDirectory();
    _supportDirectory = dir;
    return dir;
  } catch (error) {
    if (kDebugMode && !_loggedSupportFallback) {
      _loggedSupportFallback = true;
      debugPrint(
          'Application support directory unavailable, using fallback: $error');
    }
  }

  final dir = Directory(_fallbackSupportPath());
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  _supportDirectory = dir;
  return dir;
}

Future<Directory> getPlayerVfCacheDirectory() async {
  final cached = _cacheDirectory;
  if (cached != null) return cached;

  try {
    final dir = await getApplicationCacheDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDirectory = dir;
    return dir;
  } catch (error) {
    if (kDebugMode && !_loggedCacheFallback) {
      _loggedCacheFallback = true;
      debugPrint(
          'Application cache directory unavailable, using fallback: $error');
    }
  }

  final dir = Directory(_fallbackCachePath());
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  _cacheDirectory = dir;
  return dir;
}

String _fallbackDocumentsPath() {
  if (Platform.isLinux) {
    final xdgDataHome = Platform.environment['XDG_DATA_HOME'];
    if (xdgDataHome != null && xdgDataHome.isNotEmpty) {
      return p.join(xdgDataHome, 'player_vf');
    }

    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return p.join(home, '.local', 'share', 'player_vf');
    }
  }

  if (Platform.isMacOS) {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return p.join(home, 'Library', 'Application Support', 'PlayerVF');
    }
  }

  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      return p.join(appData, 'PlayerVF');
    }

    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null && userProfile.isNotEmpty) {
      return p.join(userProfile, 'Documents', 'PlayerVF');
    }
  }

  return p.join(Directory.current.path, '.player_vf');
}

String _fallbackSupportPath() {
  if (Platform.isLinux) {
    final xdgDataHome = Platform.environment['XDG_DATA_HOME'];
    if (xdgDataHome != null && xdgDataHome.isNotEmpty) {
      return p.join(xdgDataHome, 'player_vf');
    }

    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return p.join(home, '.local', 'share', 'player_vf');
    }
  }

  if (Platform.isMacOS) {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return p.join(home, 'Library', 'Application Support', 'PlayerVF');
    }
  }

  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      return p.join(appData, 'PlayerVF');
    }
  }

  return _fallbackDocumentsPath();
}

String _fallbackCachePath() {
  if (Platform.isWindows) {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null && localAppData.isNotEmpty) {
      return p.join(localAppData, 'PlayerVF', 'Cache');
    }
  }

  if (Platform.isLinux) {
    final xdgCacheHome = Platform.environment['XDG_CACHE_HOME'];
    if (xdgCacheHome != null && xdgCacheHome.isNotEmpty) {
      return p.join(xdgCacheHome, 'player_vf');
    }

    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return p.join(home, '.cache', 'player_vf');
    }
  }

  if (Platform.isMacOS) {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return p.join(home, 'Library', 'Caches', 'PlayerVF');
    }
  }

  return p.join(_fallbackSupportPath(), 'Cache');
}
