import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ViewMode { card, list }

enum NavPosition { top, bottom, left, right }

enum ThemePreset {
  material,
  graphite,
  classic,
  fox,
  anime,
  azure,
  cosmic,
  sunset,
  midnight
}

enum ParticleEffect { none, sakura, snow, stars, bubbles, rain }

enum DecoderMode { auto, software, hardware }

enum PerformanceMode { auto, quality, balanced, batterySaver, maxPerformance }

class SettingsModel extends ChangeNotifier {
  static const String _musicPathsKey = 'music_source_paths';
  static const String youtubeMusicDownloadPathKey =
      'youtube_music_download_path';
  static const String shareSyncBackupsEnabledKey = 'share_sync_backups_enabled';
  static const String _cardSizeKey = 'card_size';
  static const String _cardMarginsKey = 'card_margins';
  static const String _cardCountKey = 'card_count';
  static const String _useAutoCardCountKey = 'use_auto_card_count';
  static const String _themeModeKey = 'theme_mode';
  static const String _topMarginKey = 'top_margin';
  static const String _viewModeKey = 'view_mode';
  static const String _fontSizeKey = 'font_size';
  static const String _borderRadiusKey = 'border_radius';
  static const String _glassEffectKey = 'glass_effect';
  static const String _accentColorKey = 'accent_color';
  static const String _seekStepSecondsKey = 'seek_step_seconds';
  static const String _navPositionKey = 'nav_position';
  static const String _themePresetKey = 'theme_preset';
  static const String _particleEffectKey = 'particle_effect';
  static const String _playVideoBackgroundKey = 'play_video_background';
  static const String _videoCoverShowLiveKey = 'video_cover_show_live';
  static const String _videoDoubleTapFullscreenKey =
      'video_double_tap_fullscreen';
  static const String audioDecoderModeKey = 'audio_decoder_mode';
  static const String videoDecoderModeKey = 'video_decoder_mode';
  static const String songGapMsKey = 'song_gap_ms';
  static const String _performanceModeKey = 'performance_mode';
  static const String _backgroundBlurScaleKey = 'background_blur_scale';

  List<String> musicSourcePaths = [];
  String youtubeMusicDownloadPath = '';
  double cardSize = 140.0;
  double cardMargins = 8.0;
  double topMargin = 60.0;
  int cardCount = 3;
  bool useAutoCardCount = true;
  ThemeMode themeMode = ThemeMode.dark;
  ViewMode viewMode = ViewMode.card;
  NavPosition navPosition = NavPosition.bottom;
  ThemePreset themePreset = ThemePreset.material;
  ParticleEffect particleEffect = ParticleEffect.none;
  double fontSize = 14.0;
  double borderRadius = 12.0;
  double glassEffect = 0.35;
  Color accentColor = Colors.teal;
  int seekStepSeconds = 5;
  int songGapMs = 0;
  bool playVideoBackground = true;
  bool videoCoverShowLive = true;
  bool videoDoubleTapFullscreen = true;
  DecoderMode audioDecoderMode = DecoderMode.auto;
  DecoderMode videoDecoderMode = DecoderMode.auto;
  PerformanceMode performanceMode = PerformanceMode.auto;
  double backgroundBlurScale = 1.0;
  bool shareSyncBackupsEnabled = true;

  SettingsModel() {
    loadSettings();
  }

  Future<void> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      musicSourcePaths = prefs.getStringList(_musicPathsKey) ?? [];
      youtubeMusicDownloadPath =
          prefs.getString(youtubeMusicDownloadPathKey) ?? '';
      cardSize = prefs.getDouble(_cardSizeKey) ?? 140.0;
      cardMargins = prefs.getDouble(_cardMarginsKey) ?? 8.0;
      topMargin = prefs.getDouble(_topMarginKey) ?? 60.0;
      cardCount = prefs.getInt(_cardCountKey) ?? 3;
      useAutoCardCount = prefs.getBool(_useAutoCardCountKey) ?? true;

      final themeModeIndex =
          prefs.getInt(_themeModeKey) ?? ThemeMode.dark.index;
      themeMode = ThemeMode.values[themeModeIndex];

      final viewModeIndex = prefs.getInt(_viewModeKey) ?? ViewMode.card.index;
      viewMode = ViewMode.values[viewModeIndex];

      final navPosIndex =
          prefs.getInt(_navPositionKey) ?? NavPosition.bottom.index;
      navPosition = NavPosition.values[navPosIndex];

      final themePresetIndex =
          prefs.getInt(_themePresetKey) ?? ThemePreset.material.index;
      themePreset =
          themePresetIndex >= 0 && themePresetIndex < ThemePreset.values.length
              ? ThemePreset.values[themePresetIndex]
              : ThemePreset.material;

      final particleIndex =
          prefs.getInt(_particleEffectKey) ?? ParticleEffect.none.index;
      particleEffect = ParticleEffect.values[particleIndex];

      fontSize = prefs.getDouble(_fontSizeKey) ?? 14.0;
      borderRadius = prefs.getDouble(_borderRadiusKey) ?? 12.0;
      glassEffect =
          (prefs.getDouble(_glassEffectKey) ?? 0.35).clamp(0.0, 1.0).toDouble();
      final accentColorValue =
          prefs.getInt(_accentColorKey) ?? Colors.teal.value;
      accentColor = Color(accentColorValue);
      seekStepSeconds = prefs.getInt(_seekStepSecondsKey) ?? 5;
      songGapMs = (prefs.getInt(songGapMsKey) ?? 0).clamp(0, 5000);
      playVideoBackground = prefs.getBool(_playVideoBackgroundKey) ?? true;
      videoCoverShowLive = prefs.getBool(_videoCoverShowLiveKey) ?? true;
      videoDoubleTapFullscreen =
          prefs.getBool(_videoDoubleTapFullscreenKey) ?? true;
      audioDecoderMode = _decoderModeFromIndex(
          prefs.getInt(audioDecoderModeKey) ?? DecoderMode.auto.index);
      videoDecoderMode = _decoderModeFromIndex(
          prefs.getInt(videoDecoderModeKey) ?? DecoderMode.auto.index);
      performanceMode = _performanceModeFromIndex(
          prefs.getInt(_performanceModeKey) ?? PerformanceMode.auto.index);
      backgroundBlurScale = (prefs.getDouble(_backgroundBlurScaleKey) ?? 1.0)
          .clamp(0.0, 2.5)
          .toDouble();
      shareSyncBackupsEnabled =
          prefs.getBool(shareSyncBackupsEnabledKey) ?? true;

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading settings: $e');
      musicSourcePaths = [];
    }
  }

  void _applyThemeDefaults(ThemePreset preset) {
    switch (preset) {
      case ThemePreset.material:
        accentColor = const Color(0xFF5F6368);
        particleEffect = ParticleEffect.none;
        break;
      case ThemePreset.graphite:
        accentColor = const Color(0xFF78909C);
        particleEffect = ParticleEffect.none;
        break;
      case ThemePreset.classic:
        particleEffect = ParticleEffect.none;
        break;
      case ThemePreset.fox:
        accentColor = const Color(0xFFFB923C);
        particleEffect = ParticleEffect.snow;
        break;
      case ThemePreset.anime:
        accentColor = const Color(0xFFF472B6);
        particleEffect = ParticleEffect.sakura;
        break;
      case ThemePreset.azure:
        accentColor = const Color(0xFF38BDF8);
        particleEffect = ParticleEffect.bubbles;
        break;
      case ThemePreset.cosmic:
        accentColor = const Color(0xFFA855F7);
        particleEffect = ParticleEffect.stars;
        break;
      case ThemePreset.sunset:
        accentColor = const Color(0xFFF87171);
        particleEffect = ParticleEffect.none;
        break;
      case ThemePreset.midnight:
        accentColor = const Color(0xFF6366F1);
        particleEffect = ParticleEffect.rain;
        break;
      default:
        break;
    }
  }

  Future<void> setThemePreset(ThemePreset preset) async {
    themePreset = preset;
    _applyThemeDefaults(preset);
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setParticleEffect(ParticleEffect effect) async {
    // If user manual change anything, go to classic
    if (particleEffect != effect) {
      themePreset = ThemePreset.classic;
      particleEffect = effect;
      notifyListeners();
      await _saveSettings();
    }
  }

  Future<void> setNavPosition(NavPosition position) async {
    navPosition = position;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setFontSize(double size) async {
    fontSize = size;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setBorderRadius(double radius) async {
    borderRadius = radius;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setGlassEffect(double value) async {
    glassEffect = value.clamp(0.0, 1.0);
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setAccentColor(Color color) async {
    if (accentColor.value != color.value) {
      accentColor = color;
      themePreset = ThemePreset.classic; // manual choice always classic
      notifyListeners();
      await _saveSettings();
    }
  }

  Future<void> setSeekStepSeconds(int seconds) async {
    seekStepSeconds = seconds;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setSongGapMs(int milliseconds) async {
    songGapMs = milliseconds.clamp(0, 5000);
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setViewMode(ViewMode mode) async {
    viewMode = mode;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setCardSize(double size) async {
    cardSize = size;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setCardMargins(double margins) async {
    cardMargins = margins;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setTopMargin(double margin) async {
    topMargin = margin;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setCardCount(int count) async {
    cardCount = count;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setUseAutoCardCount(bool useAuto) async {
    useAutoCardCount = useAuto;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setPlayVideoBackground(bool playVideo) async {
    playVideoBackground = playVideo;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setVideoCoverShowLive(bool showLive) async {
    videoCoverShowLive = showLive;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setVideoDoubleTapFullscreen(bool enabled) async {
    videoDoubleTapFullscreen = enabled;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setAudioDecoderMode(DecoderMode mode) async {
    audioDecoderMode = mode;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setVideoDecoderMode(DecoderMode mode) async {
    videoDecoderMode = mode;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setPerformanceMode(PerformanceMode mode) async {
    performanceMode = mode;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setBackgroundBlurScale(double value) async {
    backgroundBlurScale = value.clamp(0.0, 2.5).toDouble();
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setShareSyncBackupsEnabled(bool enabled) async {
    shareSyncBackupsEnabled = enabled;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> addMusicPath(String path) async {
    final normalized = path.trim();
    if (normalized.isNotEmpty && !musicSourcePaths.contains(normalized)) {
      musicSourcePaths.add(normalized);
      notifyListeners();
      await _saveSettings();
    }
  }

  Future<void> setYoutubeMusicDownloadPath(String path) async {
    final normalized = path.trim();
    final previous = youtubeMusicDownloadPath;
    youtubeMusicDownloadPath = normalized;
    if (previous.isNotEmpty &&
        previous != normalized &&
        musicSourcePaths.contains(previous)) {
      musicSourcePaths.remove(previous);
    }
    if (normalized.isNotEmpty && !musicSourcePaths.contains(normalized)) {
      musicSourcePaths.add(normalized);
    }
    notifyListeners();
    await _saveSettings();
  }

  Future<void> removeMusicPath(String path) async {
    musicSourcePaths.remove(path);
    if (youtubeMusicDownloadPath == path) {
      youtubeMusicDownloadPath = '';
    }
    notifyListeners();
    await _saveSettings();
  }

  Future<void> clearAllPaths() async {
    musicSourcePaths.clear();
    notifyListeners();
    await _saveSettings();
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_musicPathsKey, musicSourcePaths);
      await prefs.setString(
          youtubeMusicDownloadPathKey, youtubeMusicDownloadPath);
      await prefs.setDouble(_cardSizeKey, cardSize);
      await prefs.setDouble(_cardMarginsKey, cardMargins);
      await prefs.setDouble(_topMarginKey, topMargin);
      await prefs.setInt(_cardCountKey, cardCount);
      await prefs.setBool(_useAutoCardCountKey, useAutoCardCount);
      await prefs.setInt(_themeModeKey, themeMode.index);
      await prefs.setInt(_viewModeKey, viewMode.index);
      await prefs.setInt(_navPositionKey, navPosition.index);
      await prefs.setInt(_themePresetKey, themePreset.index);
      await prefs.setInt(_particleEffectKey, particleEffect.index);
      await prefs.setDouble(_fontSizeKey, fontSize);
      await prefs.setDouble(_borderRadiusKey, borderRadius);
      await prefs.setDouble(
          _glassEffectKey, glassEffect.clamp(0.0, 1.0).toDouble());
      await prefs.setInt(_accentColorKey, accentColor.value);
      await prefs.setInt(_seekStepSecondsKey, seekStepSeconds);
      await prefs.setInt(songGapMsKey, songGapMs);
      await prefs.setBool(_playVideoBackgroundKey, playVideoBackground);
      await prefs.setBool(_videoCoverShowLiveKey, videoCoverShowLive);
      await prefs.setBool(
          _videoDoubleTapFullscreenKey, videoDoubleTapFullscreen);
      await prefs.setInt(audioDecoderModeKey, audioDecoderMode.index);
      await prefs.setInt(videoDecoderModeKey, videoDecoderMode.index);
      await prefs.setInt(_performanceModeKey, performanceMode.index);
      await prefs.setDouble(_backgroundBlurScaleKey, backgroundBlurScale);
      await prefs.setBool(shareSyncBackupsEnabledKey, shareSyncBackupsEnabled);
    } catch (e) {
      debugPrint('Error saving settings: $e');
    }
  }

  DecoderMode _decoderModeFromIndex(int index) {
    return index >= 0 && index < DecoderMode.values.length
        ? DecoderMode.values[index]
        : DecoderMode.auto;
  }

  PerformanceMode _performanceModeFromIndex(int index) {
    return index >= 0 && index < PerformanceMode.values.length
        ? PerformanceMode.values[index]
        : PerformanceMode.auto;
  }
}
