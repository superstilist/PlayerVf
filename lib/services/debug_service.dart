import 'dart:io';

import 'package:flutter/foundation.dart';

/// Categories for debug log filtering.
enum DebugCategory {
  performance,
  playback,
  ui,
  network,
  recording,
  scanner,
  general,
}

/// Centralized debug logging service.
///
/// All messages are printed to the console (debug builds only by default).
/// Enable [forceRelease] to also print in release builds.
class DebugService {
  DebugService._();

  static final DebugService instance = DebugService._();

  /// When true, logs are printed even in release builds.
  bool forceRelease = false;

  /// When false, all logging is suppressed.
  bool enabled = true;

  /// Only categories in this set will be printed.
  /// If empty, all categories are allowed.
  final Set<DebugCategory> activeCategories = {};

  /// Minimum log level: 0 = verbose, 1 = info, 2 = warn, 3 = error.
  int minLevel = 0;

  final Stopwatch _uptime = Stopwatch();
  final List<_LogEntry> _recentLogs = [];
  static const int _maxRecentLogs = 200;

  /// Call once at app startup.
  void init({bool forceRelease = false}) {
    this.forceRelease = forceRelease;
    _uptime.start();
    log(DebugCategory.general, 'DebugService initialized', level: 1);
    log(
      DebugCategory.general,
      'Platform: ${_platformLabel()} | Debug: $kDebugMode',
      level: 1,
    );
  }

  /// Print a debug message.
  void log(
    DebugCategory category,
    String message, {
    int level = 0,
    Object? error,
  }) {
    if (!enabled) return;
    if (!forceRelease && !kDebugMode) return;

    // Only allow warnings/errors (level >= 2) to completely silence debug timing/performance prints.
    final isWarnOrError = level >= 2;
    if (!isWarnOrError) return;

    String enrichedMsg = message;
    try {
      final rssMb = (ProcessInfo.currentRss / (1024 * 1024)).toStringAsFixed(1);
      enrichedMsg = '$message | RSS Memory: ${rssMb}MB';
    } catch (_) {}

    final entry = _LogEntry(
      timestamp: DateTime.now(),
      uptimeMs: _uptime.elapsedMilliseconds,
      category: category,
      level: level,
      message: enrichedMsg,
      error: error,
    );

    _recentLogs.add(entry);
    if (_recentLogs.length > _maxRecentLogs) {
      _recentLogs.removeAt(0);
    }

    final prefix = _levelPrefix(level);
    final tag = category.name.toUpperCase().padRight(11);
    final uptimeStr =
        '${(entry.uptimeMs / 1000).toStringAsFixed(1)}s'.padLeft(8);
    final line = '$prefix[$tag] $uptimeStr | $enrichedMsg';

    // ignore: avoid_print
    print(line);

    if (error != null) {
      // ignore: avoid_print
      print('  └─ ERROR: $error');
    }
  }

  /// Shorthand helpers.
  void perf(String message, {int level = 0, Object? error}) =>
      log(DebugCategory.performance, message, level: level, error: error);

  void playback(String message, {int level = 0, Object? error}) =>
      log(DebugCategory.playback, message, level: level, error: error);

  void ui(String message, {int level = 0, Object? error}) =>
      log(DebugCategory.ui, message, level: level, error: error);

  void net(String message, {int level = 0, Object? error}) =>
      log(DebugCategory.network, message, level: level, error: error);

  void recording(String message, {int level = 0, Object? error}) =>
      log(DebugCategory.recording, message, level: level, error: error);

  void scanner(String message, {int level = 0, Object? error}) =>
      log(DebugCategory.scanner, message, level: level, error: error);

  void info(String message) =>
      log(DebugCategory.general, message, level: 1);

  void warn(String message) =>
      log(DebugCategory.general, message, level: 2);

  void error(String message, {Object? error}) =>
      log(DebugCategory.general, message, level: 3, error: error);

  /// Measure a block of code and log elapsed time.
  Future<T> measure<T>(
    DebugCategory category,
    String label,
    Future<T> Function() work,
  ) async {
    final sw = Stopwatch()..start();
    try {
      final result = await work();
      sw.stop();
      log(category, '$label completed in ${sw.elapsedMilliseconds}ms');
      return result;
    } catch (e) {
      sw.stop();
      log(
        category,
        '$label FAILED after ${sw.elapsedMilliseconds}ms',
        level: 3,
        error: e,
      );
      rethrow;
    }
  }

  /// Synchronous version of [measure].
  T measureSync<T>(
    DebugCategory category,
    String label,
    T Function() work,
  ) {
    final sw = Stopwatch()..start();
    try {
      final result = work();
      sw.stop();
      log(category, '$label completed in ${sw.elapsedMilliseconds}ms');
      return result;
    } catch (e) {
      sw.stop();
      log(
        category,
        '$label FAILED after ${sw.elapsedMilliseconds}ms',
        level: 3,
        error: e,
      );
      rethrow;
    }
  }

  /// Returns the recent log entries (newest last).
  List<String> get recentLogLines =>
      _recentLogs.map((e) => e.formatted).toList(growable: false);

  /// Dump all recent logs to console.
  void dumpRecentLogs() {
    // ignore: avoid_print
    print('═══════════════ PLAYERVF DEBUG DUMP ═══════════════');
    for (final entry in _recentLogs) {
      // ignore: avoid_print
      print(entry.formatted);
    }
    // ignore: avoid_print
    print('═══════════════ END DUMP (${_recentLogs.length} entries) ═══════════════');
  }

  static String _levelPrefix(int level) {
    switch (level) {
      case 0:
        return '🔍 ';
      case 1:
        return 'ℹ️  ';
      case 2:
        return '⚠️  ';
      case 3:
        return '❌ ';
      default:
        return '   ';
    }
  }

  static String _platformLabel() {
    if (kIsWeb) return 'Web';
    try {
      if (Platform.isAndroid) return 'Android';
      if (Platform.isIOS) return 'iOS';
      if (Platform.isWindows) return 'Windows';
      if (Platform.isMacOS) return 'macOS';
      if (Platform.isLinux) return 'Linux';
    } catch (_) {}
    return 'Unknown';
  }
}

class _LogEntry {
  final DateTime timestamp;
  final int uptimeMs;
  final DebugCategory category;
  final int level;
  final String message;
  final Object? error;

  const _LogEntry({
    required this.timestamp,
    required this.uptimeMs,
    required this.category,
    required this.level,
    required this.message,
    this.error,
  });

  String get formatted {
    final prefix = DebugService._levelPrefix(level);
    final tag = category.name.toUpperCase().padRight(11);
    final uptimeStr =
        '${(uptimeMs / 1000).toStringAsFixed(1)}s'.padLeft(8);
    final line = '$prefix[$tag] $uptimeStr | $message';
    if (error != null) return '$line\n  └─ ERROR: $error';
    return line;
  }
}

/// Global shorthand.
DebugService get debug => DebugService.instance;
