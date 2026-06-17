import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ViewMode { card, list }

enum NavPosition { top, bottom, left, right }

enum BackgroundMode { coverArt, customImage, solidColor }

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

enum ParticleEffect {
  none,
  sakura,
  snow,
  stars,
  bubbles,
  rain,
  hearts,
  fireflies,
  confetti,
  custom,
  coverArtShadowPoints
}

enum DecoderMode { auto, software, hardware }

enum PerformanceMode { auto, quality, balanced, batterySaver, maxPerformance }

enum LyricsFullscreenPosition { top, center, bottom }

enum LyricsFullscreenHeaderPosition { topLeft, topCenter, topRight }

enum LyricsFullscreenCoverStyle { rounded, circle, shadow, glow }

enum CoverArtDisplayMode { fit, crop, square, custom }

enum LyricsFullscreenFontPreset {
  system,
  serif,
  mono,
  rounded,
  notoSans,
  notoJapanese,
  notoChinese,
  display,
  handwritten
}

enum LyricsFullscreenHeaderStyle { compact, bigCover, coverAbove, fullCover, nameOnly }

enum LyricsFullscreenControlsStyle { classic, pill, minimal, glow, panel43 }

enum LyricsFullscreenSpecialEffect { none, softGlow, pulse, float, particles }

enum LyricsFullscreenParticlePack {
  sparkles,
  stars,
  snow,
  bubbles,
  hearts,
  sakura,
  fireflies,
  confetti,
  custom
}

class LyricsFullscreenVisualItem {
  final String id;
  final String path;
  final bool show;
  final double offsetX;
  final double offsetY;
  final double scale;
  final double rotation;
  final int layer;
  final double opacity;

  const LyricsFullscreenVisualItem({
    required this.id,
    required this.path,
    required this.show,
    required this.offsetX,
    required this.offsetY,
    required this.scale,
    required this.rotation,
    required this.layer,
    required this.opacity,
  });

  factory LyricsFullscreenVisualItem.fromLegacy({
    required String path,
    required bool show,
    required double offsetX,
    required double offsetY,
    required double scale,
    required double rotation,
    required int layer,
    required double opacity,
  }) {
    return LyricsFullscreenVisualItem(
      id: 'visual_${DateTime.now().microsecondsSinceEpoch}',
      path: path.trim(),
      show: show && path.trim().isNotEmpty,
      offsetX: offsetX,
      offsetY: offsetY,
      scale: scale,
      rotation: rotation,
      layer: layer,
      opacity: opacity,
    );
  }

  factory LyricsFullscreenVisualItem.fromJson(Map<String, dynamic> json) {
    return LyricsFullscreenVisualItem(
      id: (json['id'] as String?)?.trim().isNotEmpty == true
          ? (json['id'] as String).trim()
          : 'visual_${DateTime.now().microsecondsSinceEpoch}',
      path: (json['path'] as String? ?? '').trim(),
      show: json['show'] as bool? ?? true,
      offsetX: (json['offsetX'] as num? ?? 0).toDouble(),
      offsetY: (json['offsetY'] as num? ?? -40).toDouble(),
      scale: (json['scale'] as num? ?? 1).toDouble(),
      rotation: (json['rotation'] as num? ?? 0).toDouble(),
      layer: (json['layer'] as num? ?? 4).toInt(),
      opacity: (json['opacity'] as num? ?? 0.82).toDouble(),
    ).sanitized();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'path': path,
      'show': show,
      'offsetX': offsetX,
      'offsetY': offsetY,
      'scale': scale,
      'rotation': rotation,
      'layer': layer,
      'opacity': opacity,
    };
  }

  LyricsFullscreenVisualItem sanitized() {
    final cleanPath = path.trim();
    return LyricsFullscreenVisualItem(
      id: id.trim().isEmpty
          ? 'visual_${DateTime.now().microsecondsSinceEpoch}'
          : id.trim(),
      path: cleanPath,
      show: show && cleanPath.isNotEmpty,
      offsetX: offsetX
          .clamp(-SettingsModel.lyricsFullscreenMaxOffsetX,
              SettingsModel.lyricsFullscreenMaxOffsetX)
          .toDouble(),
      offsetY: offsetY
          .clamp(-SettingsModel.lyricsFullscreenMaxOffsetY,
              SettingsModel.lyricsFullscreenMaxOffsetY)
          .toDouble(),
      scale: scale.clamp(0.35, 2.25).toDouble(),
      rotation: rotation.clamp(-180.0, 180.0).toDouble(),
      layer: layer.clamp(0, 9),
      opacity: opacity.clamp(0.12, 1.0).toDouble(),
    );
  }
}

class SettingsModel extends ChangeNotifier {
  Timer? _saveSettingsDebounce;

  static const String musicPathsKey = 'music_source_paths';
  static const String youtubeMusicDownloadPathKey =
      'youtube_music_download_path';
  static const String recordingSavePathKey = 'recording_save_path';
  static const String youtubeStreamCacheEnabledKey =
      'youtube_stream_cache_enabled';
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
  static const String _backgroundModeKey = 'background_mode';
  static const String _customBackgroundImageKey = 'custom_background_image';
  static const String _seekStepSecondsKey = 'seek_step_seconds';
  static const String _navPositionKey = 'nav_position';
  static const String _themePresetKey = 'theme_preset';
  static const String _particleEffectKey = 'particle_effect';
  static const String _customParticlePackKey = 'custom_particle_pack';
  static const String _playVideoBackgroundKey = 'play_video_background';
  static const String _videoCoverShowLiveKey = 'video_cover_show_live';
  static const String _videoDoubleTapFullscreenKey =
      'video_double_tap_fullscreen';
  static const String audioDecoderModeKey = 'audio_decoder_mode';
  static const String videoDecoderModeKey = 'video_decoder_mode';
  static const String songGapMsKey = 'song_gap_ms';
  static const String _performanceModeKey = 'performance_mode';
  static const String _backgroundBlurScaleKey = 'background_blur_scale';
  static const String _generateKanaLyricsKey = 'generate_kana_lyrics';
  static const String _homeRecommendedCountKey = 'home_recommended_count';
  static const String _homeEarlyListenedCountKey = 'home_early_listened_count';
  static const String _homeRecentlyAddedCountKey = 'home_recently_added_count';
  static const String _lyricsFullscreenTextColorKey =
      'lyrics_fullscreen_text_color';
  static const String _lyricsFullscreenPositionKey =
      'lyrics_fullscreen_position';
  static const String _lyricsFullscreenShowCoverKey =
      'lyrics_fullscreen_show_cover';
  static const String _lyricsFullscreenShowTrackNameKey =
      'lyrics_fullscreen_show_track_name';
  static const String _lyricsFullscreenShowControlsKey =
      'lyrics_fullscreen_show_controls';
  static const String _lyricsFullscreenShowProgressKey =
      'lyrics_fullscreen_show_progress';
  static const String _lyricsFullscreenFontScaleKey =
      'lyrics_fullscreen_font_scale';
  static const String _lyricsFullscreenDimBackgroundKey =
      'lyrics_fullscreen_dim_background';
  static const String _lyricsFullscreenHeaderPositionKey =
      'lyrics_fullscreen_header_position';
  static const String _lyricsFullscreenCoverStyleKey =
      'lyrics_fullscreen_cover_style';
  static const String _lyricsFullscreenCustomLayoutKey =
      'lyrics_fullscreen_custom_layout';
  static const String _lyricsFullscreenLyricsOffsetXKey =
      'lyrics_fullscreen_lyrics_offset_x';
  static const String _lyricsFullscreenLyricsOffsetYKey =
      'lyrics_fullscreen_lyrics_offset_y';
  static const String _lyricsFullscreenHeaderOffsetXKey =
      'lyrics_fullscreen_header_offset_x';
  static const String _lyricsFullscreenHeaderOffsetYKey =
      'lyrics_fullscreen_header_offset_y';
  static const String _lyricsFullscreenControlsOffsetYKey =
      'lyrics_fullscreen_controls_offset_y';
  static const String _lyricsFullscreenControlsOffsetXKey =
      'lyrics_fullscreen_controls_offset_x';
  static const String _lyricsFullscreenHeaderScaleKey =
      'lyrics_fullscreen_header_scale';
  static const String _lyricsFullscreenLyricsScaleKey =
      'lyrics_fullscreen_lyrics_scale';
  static const String _lyricsFullscreenControlsScaleKey =
      'lyrics_fullscreen_controls_scale';
  static const String _lyricsFullscreenHeaderRotationKey =
      'lyrics_fullscreen_header_rotation';
  static const String _lyricsFullscreenLyricsRotationKey =
      'lyrics_fullscreen_lyrics_rotation';
  static const String _lyricsFullscreenControlsRotationKey =
      'lyrics_fullscreen_controls_rotation';
  static const String _lyricsFullscreenFontPresetKey =
      'lyrics_fullscreen_font_preset';
  static const String _lyricsFullscreenHeaderStyleKey =
      'lyrics_fullscreen_header_style';
  static const String _lyricsFullscreenControlsStyleKey =
      'lyrics_fullscreen_controls_style';
  static const String _lyricsFullscreenSpecialEffectKey =
      'lyrics_fullscreen_special_effect';
  static const String _lyricsFullscreenHeaderLayerKey =
      'lyrics_fullscreen_header_layer';
  static const String _lyricsFullscreenLyricsLayerKey =
      'lyrics_fullscreen_lyrics_layer';
  static const String _lyricsFullscreenControlsLayerKey =
      'lyrics_fullscreen_controls_layer';
  static const String _lyricsFullscreenVisualPathKey =
      'lyrics_fullscreen_visual_path';
  static const String _lyricsFullscreenShowVisualKey =
      'lyrics_fullscreen_show_visual';
  static const String _lyricsFullscreenVisualOffsetXKey =
      'lyrics_fullscreen_visual_offset_x';
  static const String _lyricsFullscreenVisualOffsetYKey =
      'lyrics_fullscreen_visual_offset_y';
  static const String _lyricsFullscreenVisualScaleKey =
      'lyrics_fullscreen_visual_scale';
  static const String _lyricsFullscreenVisualRotationKey =
      'lyrics_fullscreen_visual_rotation';
  static const String _lyricsFullscreenVisualLayerKey =
      'lyrics_fullscreen_visual_layer';
  static const String _lyricsFullscreenVisualOpacityKey =
      'lyrics_fullscreen_visual_opacity';
  static const String _lyricsFullscreenVisualItemsKey =
      'lyrics_fullscreen_visual_items';
  static const String _lyricsFullscreenParticlePackKey =
      'lyrics_fullscreen_particle_pack';
  static const String _lyricsFullscreenCustomParticlePackKey =
      'lyrics_fullscreen_custom_particle_pack';
  static const String _coverArtDisplayModeKey = 'cover_art_display_mode';
  static const String _orbPaletteSizeKey = 'orb_palette_size';
  static const String _orbSizeKey = 'orb_size';
  static const String _orbSpeedKey = 'orb_speed';

  List<String> musicSourcePaths = [];
  String youtubeMusicDownloadPath = '';
  String recordingSavePath = '';
  bool youtubeStreamCacheEnabled = true;
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
  String customParticlePack = '* + .';
  int orbPaletteSize = 4;
  double orbSize = 1.5;
  double orbSpeed = 1.0;
  double fontSize = 14.0;
  double borderRadius = 12.0;
  double glassEffect = 0.35;
  Color accentColor = Colors.teal;
  BackgroundMode backgroundMode = BackgroundMode.coverArt;
  String customBackgroundImage = '';
  int seekStepSeconds = 5;
  int songGapMs = 0;
  bool playVideoBackground = true;
  bool videoCoverShowLive = true;
  bool videoDoubleTapFullscreen = true;
  DecoderMode audioDecoderMode = DecoderMode.auto;
  DecoderMode videoDecoderMode = DecoderMode.auto;
  PerformanceMode performanceMode = PerformanceMode.auto;
  double backgroundBlurScale = 1.0;
  bool generateKanaLyrics = false;
  bool shareSyncBackupsEnabled = true;
  int homeRecommendedCount = 3;
  int homeEarlyListenedCount = 5;
  int homeRecentlyAddedCount = 5;
  static const double lyricsFullscreenMaxOffsetX = 1600.0;
  static const double lyricsFullscreenMaxOffsetY = 1400.0;
  Color lyricsFullscreenTextColor = Colors.white;
  LyricsFullscreenPosition lyricsFullscreenPosition =
      LyricsFullscreenPosition.center;
  bool lyricsFullscreenShowCover = true;
  bool lyricsFullscreenShowTrackName = true;
  bool lyricsFullscreenShowControls = true;
  bool lyricsFullscreenShowProgress = true;
  double lyricsFullscreenFontScale = 1.0;
  double lyricsFullscreenDimBackground = 0.62;
  LyricsFullscreenHeaderPosition lyricsFullscreenHeaderPosition =
      LyricsFullscreenHeaderPosition.topLeft;
  LyricsFullscreenCoverStyle lyricsFullscreenCoverStyle =
      LyricsFullscreenCoverStyle.rounded;
  bool lyricsFullscreenCustomLayout = false;
  double lyricsFullscreenLyricsOffsetX = 0.0;
  double lyricsFullscreenLyricsOffsetY = 0.0;
  double lyricsFullscreenHeaderOffsetX = 0.0;
  double lyricsFullscreenHeaderOffsetY = 0.0;
  double lyricsFullscreenControlsOffsetX = 0.0;
  double lyricsFullscreenControlsOffsetY = 0.0;
  double lyricsFullscreenHeaderScale = 1.0;
  double lyricsFullscreenLyricsScale = 1.0;
  double lyricsFullscreenControlsScale = 1.0;
  double lyricsFullscreenHeaderRotation = 0.0;
  double lyricsFullscreenLyricsRotation = 0.0;
  double lyricsFullscreenControlsRotation = 0.0;
  LyricsFullscreenFontPreset lyricsFullscreenFontPreset =
      LyricsFullscreenFontPreset.system;
  LyricsFullscreenHeaderStyle lyricsFullscreenHeaderStyle =
      LyricsFullscreenHeaderStyle.compact;
  LyricsFullscreenControlsStyle lyricsFullscreenControlsStyle =
      LyricsFullscreenControlsStyle.classic;
  LyricsFullscreenSpecialEffect lyricsFullscreenSpecialEffect =
      LyricsFullscreenSpecialEffect.none;
  int lyricsFullscreenHeaderLayer = 2;
  int lyricsFullscreenLyricsLayer = 1;
  int lyricsFullscreenControlsLayer = 3;
  String lyricsFullscreenVisualPath = '';
  bool lyricsFullscreenShowVisual = false;
  double lyricsFullscreenVisualOffsetX = 0.0;
  double lyricsFullscreenVisualOffsetY = -40.0;
  double lyricsFullscreenVisualScale = 1.0;
  double lyricsFullscreenVisualRotation = 0.0;
  int lyricsFullscreenVisualLayer = 4;
  double lyricsFullscreenVisualOpacity = 0.82;
  List<LyricsFullscreenVisualItem> lyricsFullscreenVisualItems = [];
  LyricsFullscreenParticlePack lyricsFullscreenParticlePack =
      LyricsFullscreenParticlePack.sparkles;
  String lyricsFullscreenCustomParticlePack = '* + .';
  CoverArtDisplayMode coverArtDisplayMode = CoverArtDisplayMode.fit;

  SettingsModel();

  Future<void> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      musicSourcePaths = prefs.getStringList(musicPathsKey) ?? [];
      youtubeMusicDownloadPath =
          prefs.getString(youtubeMusicDownloadPathKey) ?? '';
      recordingSavePath = prefs.getString(recordingSavePathKey) ?? '';
      youtubeStreamCacheEnabled =
          prefs.getBool(youtubeStreamCacheEnabledKey) ?? true;
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
      final coverArtModeIndex =
          prefs.getInt(_coverArtDisplayModeKey) ?? CoverArtDisplayMode.fit.index;
      coverArtDisplayMode = CoverArtDisplayMode.values[coverArtModeIndex];

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
      particleEffect =
          particleIndex >= 0 && particleIndex < ParticleEffect.values.length
              ? ParticleEffect.values[particleIndex]
              : ParticleEffect.none;
      customParticlePack =
          prefs.getString(_customParticlePackKey) ?? customParticlePack;
      orbPaletteSize = (prefs.getInt(_orbPaletteSizeKey) ?? 4).clamp(2, 5);
      orbSize = (prefs.getDouble(_orbSizeKey) ?? 1.5).clamp(0.5, 3.0);
      orbSpeed = (prefs.getDouble(_orbSpeedKey) ?? 1.0).clamp(0.2, 3.0);

      fontSize = prefs.getDouble(_fontSizeKey) ?? 14.0;
      borderRadius = prefs.getDouble(_borderRadiusKey) ?? 12.0;
      glassEffect =
          (prefs.getDouble(_glassEffectKey) ?? 0.35).clamp(0.0, 1.0).toDouble();
      final accentColorValue =
          prefs.getInt(_accentColorKey) ?? Colors.teal.value;
      accentColor = Color(accentColorValue);
      final backgroundModeIndex =
          prefs.getInt(_backgroundModeKey) ?? BackgroundMode.coverArt.index;
      backgroundMode =
          backgroundModeIndex >= 0 && backgroundModeIndex < BackgroundMode.values.length
              ? BackgroundMode.values[backgroundModeIndex]
              : BackgroundMode.coverArt;
      customBackgroundImage = prefs.getString(_customBackgroundImageKey) ?? '';
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
      generateKanaLyrics = prefs.getBool(_generateKanaLyricsKey) ?? false;
      shareSyncBackupsEnabled =
          prefs.getBool(shareSyncBackupsEnabledKey) ?? true;
      homeRecommendedCount =
          (prefs.getInt(_homeRecommendedCountKey) ?? 3).clamp(1, 12);
      homeEarlyListenedCount =
          (prefs.getInt(_homeEarlyListenedCountKey) ?? 5).clamp(1, 12);
      homeRecentlyAddedCount =
          (prefs.getInt(_homeRecentlyAddedCountKey) ?? 5).clamp(1, 12);
      lyricsFullscreenTextColor = Color(
          prefs.getInt(_lyricsFullscreenTextColorKey) ?? Colors.white.value);
      lyricsFullscreenPosition = _lyricsFullscreenPositionFromIndex(
          prefs.getInt(_lyricsFullscreenPositionKey) ??
              LyricsFullscreenPosition.center.index);
      lyricsFullscreenShowCover =
          prefs.getBool(_lyricsFullscreenShowCoverKey) ?? true;
      lyricsFullscreenShowTrackName =
          prefs.getBool(_lyricsFullscreenShowTrackNameKey) ?? true;
      lyricsFullscreenShowControls =
          prefs.getBool(_lyricsFullscreenShowControlsKey) ?? true;
      lyricsFullscreenShowProgress =
          prefs.getBool(_lyricsFullscreenShowProgressKey) ?? true;
      lyricsFullscreenFontScale =
          (prefs.getDouble(_lyricsFullscreenFontScaleKey) ?? 1.0)
              .clamp(0.75, 1.35)
              .toDouble();
      lyricsFullscreenDimBackground =
          (prefs.getDouble(_lyricsFullscreenDimBackgroundKey) ?? 0.62)
              .clamp(0.25, 0.85)
              .toDouble();
      lyricsFullscreenHeaderPosition = _lyricsFullscreenHeaderPositionFromIndex(
          prefs.getInt(_lyricsFullscreenHeaderPositionKey) ??
              LyricsFullscreenHeaderPosition.topLeft.index);
      lyricsFullscreenCoverStyle = _lyricsFullscreenCoverStyleFromIndex(
          prefs.getInt(_lyricsFullscreenCoverStyleKey) ??
              LyricsFullscreenCoverStyle.rounded.index);
      lyricsFullscreenCustomLayout =
          prefs.getBool(_lyricsFullscreenCustomLayoutKey) ?? false;
      lyricsFullscreenLyricsOffsetX =
          (prefs.getDouble(_lyricsFullscreenLyricsOffsetXKey) ?? 0)
              .clamp(-lyricsFullscreenMaxOffsetX, lyricsFullscreenMaxOffsetX)
              .toDouble();
      lyricsFullscreenLyricsOffsetY =
          (prefs.getDouble(_lyricsFullscreenLyricsOffsetYKey) ?? 0)
              .clamp(-lyricsFullscreenMaxOffsetY, lyricsFullscreenMaxOffsetY)
              .toDouble();
      lyricsFullscreenHeaderOffsetX =
          (prefs.getDouble(_lyricsFullscreenHeaderOffsetXKey) ?? 0)
              .clamp(-lyricsFullscreenMaxOffsetX, lyricsFullscreenMaxOffsetX)
              .toDouble();
      lyricsFullscreenHeaderOffsetY =
          (prefs.getDouble(_lyricsFullscreenHeaderOffsetYKey) ?? 0)
              .clamp(-lyricsFullscreenMaxOffsetY, lyricsFullscreenMaxOffsetY)
              .toDouble();
      lyricsFullscreenControlsOffsetX =
          (prefs.getDouble(_lyricsFullscreenControlsOffsetXKey) ?? 0)
              .clamp(-lyricsFullscreenMaxOffsetX, lyricsFullscreenMaxOffsetX)
              .toDouble();
      lyricsFullscreenControlsOffsetY =
          (prefs.getDouble(_lyricsFullscreenControlsOffsetYKey) ?? 0)
              .clamp(-lyricsFullscreenMaxOffsetY, lyricsFullscreenMaxOffsetY)
              .toDouble();
      lyricsFullscreenHeaderScale =
          (prefs.getDouble(_lyricsFullscreenHeaderScaleKey) ?? 1.0)
              .clamp(0.55, 1.75)
              .toDouble();
      lyricsFullscreenLyricsScale =
          (prefs.getDouble(_lyricsFullscreenLyricsScaleKey) ?? 1.0)
              .clamp(0.55, 1.75)
              .toDouble();
      lyricsFullscreenControlsScale =
          (prefs.getDouble(_lyricsFullscreenControlsScaleKey) ?? 1.0)
              .clamp(0.55, 1.75)
              .toDouble();
      lyricsFullscreenHeaderRotation =
          (prefs.getDouble(_lyricsFullscreenHeaderRotationKey) ?? 0.0)
              .clamp(-45.0, 45.0)
              .toDouble();
      lyricsFullscreenLyricsRotation =
          (prefs.getDouble(_lyricsFullscreenLyricsRotationKey) ?? 0.0)
              .clamp(-45.0, 45.0)
              .toDouble();
      lyricsFullscreenControlsRotation =
          (prefs.getDouble(_lyricsFullscreenControlsRotationKey) ?? 0.0)
              .clamp(-45.0, 45.0)
              .toDouble();
      lyricsFullscreenFontPreset = _lyricsFullscreenFontPresetFromIndex(
          prefs.getInt(_lyricsFullscreenFontPresetKey) ??
              LyricsFullscreenFontPreset.system.index);
      lyricsFullscreenHeaderStyle = _lyricsFullscreenHeaderStyleFromIndex(
          prefs.getInt(_lyricsFullscreenHeaderStyleKey) ??
              LyricsFullscreenHeaderStyle.compact.index);
      lyricsFullscreenControlsStyle = _lyricsFullscreenControlsStyleFromIndex(
          prefs.getInt(_lyricsFullscreenControlsStyleKey) ??
              LyricsFullscreenControlsStyle.classic.index);
      lyricsFullscreenSpecialEffect = _lyricsFullscreenSpecialEffectFromIndex(
          prefs.getInt(_lyricsFullscreenSpecialEffectKey) ??
              LyricsFullscreenSpecialEffect.none.index);
      lyricsFullscreenHeaderLayer =
          (prefs.getInt(_lyricsFullscreenHeaderLayerKey) ?? 2).clamp(0, 9);
      lyricsFullscreenLyricsLayer =
          (prefs.getInt(_lyricsFullscreenLyricsLayerKey) ?? 1).clamp(0, 9);
      lyricsFullscreenControlsLayer =
          (prefs.getInt(_lyricsFullscreenControlsLayerKey) ?? 3).clamp(0, 9);
      lyricsFullscreenVisualPath =
          prefs.getString(_lyricsFullscreenVisualPathKey) ?? '';
      lyricsFullscreenShowVisual =
          prefs.getBool(_lyricsFullscreenShowVisualKey) ?? false;
      lyricsFullscreenVisualOffsetX =
          (prefs.getDouble(_lyricsFullscreenVisualOffsetXKey) ?? 0)
              .clamp(-lyricsFullscreenMaxOffsetX, lyricsFullscreenMaxOffsetX)
              .toDouble();
      lyricsFullscreenVisualOffsetY =
          (prefs.getDouble(_lyricsFullscreenVisualOffsetYKey) ?? -40)
              .clamp(-lyricsFullscreenMaxOffsetY, lyricsFullscreenMaxOffsetY)
              .toDouble();
      lyricsFullscreenVisualScale =
          (prefs.getDouble(_lyricsFullscreenVisualScaleKey) ?? 1.0)
              .clamp(0.35, 2.25)
              .toDouble();
      lyricsFullscreenVisualRotation =
          (prefs.getDouble(_lyricsFullscreenVisualRotationKey) ?? 0.0)
              .clamp(-180.0, 180.0)
              .toDouble();
      lyricsFullscreenVisualLayer =
          (prefs.getInt(_lyricsFullscreenVisualLayerKey) ?? 4).clamp(0, 9);
      lyricsFullscreenVisualOpacity =
          (prefs.getDouble(_lyricsFullscreenVisualOpacityKey) ?? 0.82)
              .clamp(0.12, 1.0)
              .toDouble();
      lyricsFullscreenVisualItems =
          _lyricsFullscreenVisualItemsFromPrefs(prefs);
      if (lyricsFullscreenVisualItems.isEmpty &&
          lyricsFullscreenVisualPath.trim().isNotEmpty) {
        lyricsFullscreenVisualItems = [
          LyricsFullscreenVisualItem.fromLegacy(
            path: lyricsFullscreenVisualPath,
            show: lyricsFullscreenShowVisual,
            offsetX: lyricsFullscreenVisualOffsetX,
            offsetY: lyricsFullscreenVisualOffsetY,
            scale: lyricsFullscreenVisualScale,
            rotation: lyricsFullscreenVisualRotation,
            layer: lyricsFullscreenVisualLayer,
            opacity: lyricsFullscreenVisualOpacity,
          ),
        ];
      }
      _syncLegacyVisualFromItems();
      lyricsFullscreenParticlePack = _lyricsFullscreenParticlePackFromIndex(
          prefs.getInt(_lyricsFullscreenParticlePackKey) ??
              LyricsFullscreenParticlePack.sparkles.index);
      lyricsFullscreenCustomParticlePack =
          prefs.getString(_lyricsFullscreenCustomParticlePackKey) ??
              lyricsFullscreenCustomParticlePack;

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
    if (particleEffect != effect) {
      themePreset = ThemePreset.classic;
      particleEffect = effect;
      notifyListeners();
      await _saveSettings();
    }
  }

  Future<void> setCustomParticlePack(String value) async {
    customParticlePack = value.trim().isEmpty ? '* + .' : value.trim();
    if (particleEffect == ParticleEffect.custom) {
      themePreset = ThemePreset.classic;
    }
    notifyListeners();
    _saveSettingsDebounced();
  }

  Future<void> setOrbPaletteSize(int size) async {
    final clamped = size.clamp(2, 5);
    if (orbPaletteSize != clamped) {
      orbPaletteSize = clamped;
      notifyListeners();
      await _saveSettings();
    }
  }

  Future<void> setOrbSize(double size) async {
    final clamped = size.clamp(0.5, 3.0);
    if ((orbSize - clamped).abs() > 0.01) {
      orbSize = clamped;
      notifyListeners();
      await _saveSettings();
    }
  }

  Future<void> setOrbSpeed(double speed) async {
    final clamped = speed.clamp(0.2, 3.0);
    if ((orbSpeed - clamped).abs() > 0.01) {
      orbSpeed = clamped;
      notifyListeners();
      await _saveSettings();
    }
  }

  Future<void> setBackgroundMode(BackgroundMode mode) async {
    backgroundMode = mode;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setCustomBackgroundImage(String path) async {
    customBackgroundImage = path;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setCoverArtDisplayMode(CoverArtDisplayMode mode) async {
    coverArtDisplayMode = mode;
    notifyListeners();
    await _saveSettings();
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
      themePreset = ThemePreset.classic;
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

  Future<void> setGenerateKanaLyrics(bool enabled) async {
    generateKanaLyrics = enabled;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setShareSyncBackupsEnabled(bool enabled) async {
    shareSyncBackupsEnabled = enabled;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setHomeRecommendedCount(int count) async {
    homeRecommendedCount = count.clamp(1, 12);
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setHomeEarlyListenedCount(int count) async {
    homeEarlyListenedCount = count.clamp(1, 12);
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setHomeRecentlyAddedCount(int count) async {
    homeRecentlyAddedCount = count.clamp(1, 12);
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setLyricsFullscreenTextColor(Color color) async {
    lyricsFullscreenTextColor = color;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setLyricsFullscreenPosition(
      LyricsFullscreenPosition position) async {
    lyricsFullscreenPosition = position;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setLyricsFullscreenShowCover(bool enabled) async {
    lyricsFullscreenShowCover = enabled;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setLyricsFullscreenShowTrackName(bool enabled) async {
    lyricsFullscreenShowTrackName = enabled;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setLyricsFullscreenShowControls(bool enabled) async {
    lyricsFullscreenShowControls = enabled;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setLyricsFullscreenShowProgress(bool enabled) async {
    lyricsFullscreenShowProgress = enabled;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setLyricsFullscreenFontScale(double value) async {
    lyricsFullscreenFontScale = value.clamp(0.75, 1.35).toDouble();
    notifyListeners();
    _saveSettingsDebounced();
  }

  Future<void> setLyricsFullscreenDimBackground(double value) async {
    lyricsFullscreenDimBackground = value.clamp(0.25, 0.85).toDouble();
    notifyListeners();
    _saveSettingsDebounced();
  }

  Future<void> setLyricsFullscreenHeaderPosition(
      LyricsFullscreenHeaderPosition position) async {
    lyricsFullscreenHeaderPosition = position;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setLyricsFullscreenCoverStyle(
      LyricsFullscreenCoverStyle style) async {
    lyricsFullscreenCoverStyle = style;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setLyricsFullscreenCustomLayout(bool enabled) async {
    if (lyricsFullscreenCustomLayout == enabled) {
      return;
    }
    lyricsFullscreenCustomLayout = enabled;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setLyricsFullscreenLyricsOffsetX(double value) async {
    lyricsFullscreenLyricsOffsetX = value
        .clamp(-lyricsFullscreenMaxOffsetX, lyricsFullscreenMaxOffsetX)
        .toDouble();
    notifyListeners();
    _saveSettingsDebounced();
  }

  Future<void> setLyricsFullscreenLyricsOffsetY(double value) async {
    lyricsFullscreenLyricsOffsetY = value
        .clamp(-lyricsFullscreenMaxOffsetY, lyricsFullscreenMaxOffsetY)
        .toDouble();
    notifyListeners();
    _saveSettingsDebounced();
  }

  Future<void> setLyricsFullscreenLyricsOffset({
    required double x,
    required double y,
  }) async {
    lyricsFullscreenLyricsOffsetX = x
        .clamp(-lyricsFullscreenMaxOffsetX, lyricsFullscreenMaxOffsetX)
        .toDouble();
    lyricsFullscreenLyricsOffsetY = y
        .clamp(-lyricsFullscreenMaxOffsetY, lyricsFullscreenMaxOffsetY)
        .toDouble();
    notifyListeners();
    _saveSettingsDebounced();
  }

  Future<void> setLyricsFullscreenHeaderOffsetX(double value) async {
    lyricsFullscreenHeaderOffsetX = value
        .clamp(-lyricsFullscreenMaxOffsetX, lyricsFullscreenMaxOffsetX)
        .toDouble();
    notifyListeners();
    _saveSettingsDebounced();
  }

  Future<void> setLyricsFullscreenHeaderOffsetY(double value) async {
    lyricsFullscreenHeaderOffsetY = value
        .clamp(-lyricsFullscreenMaxOffsetY, lyricsFullscreenMaxOffsetY)
        .toDouble();
    notifyListeners();
    _saveSettingsDebounced();
  }

  Future<void> setLyricsFullscreenHeaderOffset({
    required double x,
    required double y,
  }) async {
    lyricsFullscreenHeaderOffsetX = x
        .clamp(-lyricsFullscreenMaxOffsetX, lyricsFullscreenMaxOffsetX)
        .toDouble();
    lyricsFullscreenHeaderOffsetY = y
        .clamp(-lyricsFullscreenMaxOffsetY, lyricsFullscreenMaxOffsetY)
        .toDouble();
    notifyListeners();
    _saveSettingsDebounced();
  }

  Future<void> setLyricsFullscreenControlsOffsetY(double value) async {
    lyricsFullscreenControlsOffsetY = value
        .clamp(-lyricsFullscreenMaxOffsetY, lyricsFullscreenMaxOffsetY)
        .toDouble();
    notifyListeners();
    _saveSettingsDebounced();
  }

  Future<void> setLyricsFullscreenControlsOffset({
    required double x,
    required double y,
  }) async {
    lyricsFullscreenControlsOffsetX = x
        .clamp(-lyricsFullscreenMaxOffsetX, lyricsFullscreenMaxOffsetX)
        .toDouble();
    lyricsFullscreenControlsOffsetY = y
        .clamp(-lyricsFullscreenMaxOffsetY, lyricsFullscreenMaxOffsetY)
        .toDouble();
    notifyListeners();
    _saveSettingsDebounced();
  }

  Future<void> setLyricsFullscreenHeaderScale(double value) async {
    lyricsFullscreenHeaderScale = value.clamp(0.55, 1.75).toDouble();
    notifyListeners();
    _saveSettingsDebounced();
  }

  Future<void> setLyricsFullscreenLyricsScale(double value) async {
    lyricsFullscreenLyricsScale = value.clamp(0.55, 1.75).toDouble();
    notifyListeners();
    _saveSettingsDebounced();
  }

  Future<void> setLyricsFullscreenControlsScale(double value) async {
    lyricsFullscreenControlsScale = value.clamp(0.55, 1.75).toDouble();
    notifyListeners();
    _saveSettingsDebounced();
  }

  Future<void> setLyricsFullscreenHeaderRotation(double value) async {
    lyricsFullscreenHeaderRotation = value.clamp(-45.0, 45.0).toDouble();
    notifyListeners();
    _saveSettingsDebounced();
  }

  Future<void> setLyricsFullscreenLyricsRotation(double value) async {
    lyricsFullscreenLyricsRotation = value.clamp(-45.0, 45.0).toDouble();
    notifyListeners();
    _saveSettingsDebounced();
  }

  Future<void> setLyricsFullscreenControlsRotation(double value) async {
    lyricsFullscreenControlsRotation = value.clamp(-45.0, 45.0).toDouble();
    notifyListeners();
    _saveSettingsDebounced();
  }

  Future<void> resetLyricsFullscreenCustomOffsets() async {
    lyricsFullscreenLyricsOffsetX = 0;
    lyricsFullscreenLyricsOffsetY = 0;
    lyricsFullscreenHeaderOffsetX = 0;
    lyricsFullscreenHeaderOffsetY = 0;
    lyricsFullscreenControlsOffsetX = 0;
    lyricsFullscreenControlsOffsetY = 0;
    lyricsFullscreenHeaderScale = 1;
    lyricsFullscreenLyricsScale = 1;
    lyricsFullscreenControlsScale = 1;
    lyricsFullscreenHeaderRotation = 0;
    lyricsFullscreenLyricsRotation = 0;
    lyricsFullscreenControlsRotation = 0;
    lyricsFullscreenVisualOffsetX = 0;
    lyricsFullscreenVisualOffsetY = -40;
    lyricsFullscreenVisualScale = 1;
    lyricsFullscreenVisualRotation = 0;
    lyricsFullscreenVisualItems = [];
    notifyListeners();
    await _saveSettings();
  }

  Future<void> applyLyricsFullscreenCustomization({
    required Color textColor,
    required LyricsFullscreenPosition position,
    required bool showCover,
    required bool showTrackName,
    required bool showControls,
    required bool showProgress,
    required double fontScale,
    required double dimBackground,
    required LyricsFullscreenHeaderPosition headerPosition,
    required LyricsFullscreenCoverStyle coverStyle,
    required bool customLayout,
    required double lyricsOffsetX,
    required double lyricsOffsetY,
    required double headerOffsetX,
    required double headerOffsetY,
    required double controlsOffsetX,
    required double controlsOffsetY,
    required double headerScale,
    required double lyricsScale,
    required double controlsScale,
    required double headerRotation,
    required double lyricsRotation,
    required double controlsRotation,
    required LyricsFullscreenFontPreset fontPreset,
    required LyricsFullscreenHeaderStyle headerStyle,
    required LyricsFullscreenControlsStyle controlsStyle,
    required LyricsFullscreenSpecialEffect specialEffect,
    required int headerLayer,
    required int lyricsLayer,
    required int controlsLayer,
    required String visualPath,
    required bool showVisual,
    required double visualOffsetX,
    required double visualOffsetY,
    required double visualScale,
    required double visualRotation,
    required int visualLayer,
    required double visualOpacity,
    List<LyricsFullscreenVisualItem>? visualItems,
    required LyricsFullscreenParticlePack particlePack,
    required String customParticlePack,
  }) async {
    lyricsFullscreenTextColor = textColor;
    lyricsFullscreenPosition = position;
    lyricsFullscreenShowCover = showCover;
    lyricsFullscreenShowTrackName = showTrackName;
    lyricsFullscreenShowControls = showControls;
    lyricsFullscreenShowProgress = showProgress;
    lyricsFullscreenFontScale = fontScale.clamp(0.75, 1.35).toDouble();
    lyricsFullscreenDimBackground = dimBackground.clamp(0.25, 0.85).toDouble();
    lyricsFullscreenHeaderPosition = headerPosition;
    lyricsFullscreenCoverStyle = coverStyle;
    lyricsFullscreenCustomLayout = customLayout;
    lyricsFullscreenLyricsOffsetX = lyricsOffsetX
        .clamp(-lyricsFullscreenMaxOffsetX, lyricsFullscreenMaxOffsetX)
        .toDouble();
    lyricsFullscreenLyricsOffsetY = lyricsOffsetY
        .clamp(-lyricsFullscreenMaxOffsetY, lyricsFullscreenMaxOffsetY)
        .toDouble();
    lyricsFullscreenHeaderOffsetX = headerOffsetX
        .clamp(-lyricsFullscreenMaxOffsetX, lyricsFullscreenMaxOffsetX)
        .toDouble();
    lyricsFullscreenHeaderOffsetY = headerOffsetY
        .clamp(-lyricsFullscreenMaxOffsetY, lyricsFullscreenMaxOffsetY)
        .toDouble();
    lyricsFullscreenControlsOffsetX = controlsOffsetX
        .clamp(-lyricsFullscreenMaxOffsetX, lyricsFullscreenMaxOffsetX)
        .toDouble();
    lyricsFullscreenControlsOffsetY = controlsOffsetY
        .clamp(-lyricsFullscreenMaxOffsetY, lyricsFullscreenMaxOffsetY)
        .toDouble();
    lyricsFullscreenHeaderScale = headerScale.clamp(0.55, 1.75).toDouble();
    lyricsFullscreenLyricsScale = lyricsScale.clamp(0.55, 1.75).toDouble();
    lyricsFullscreenControlsScale = controlsScale.clamp(0.55, 1.75).toDouble();
    lyricsFullscreenHeaderRotation =
        headerRotation.clamp(-45.0, 45.0).toDouble();
    lyricsFullscreenLyricsRotation =
        lyricsRotation.clamp(-45.0, 45.0).toDouble();
    lyricsFullscreenControlsRotation =
        controlsRotation.clamp(-45.0, 45.0).toDouble();
    lyricsFullscreenFontPreset = fontPreset;
    lyricsFullscreenHeaderStyle = headerStyle;
    lyricsFullscreenControlsStyle = controlsStyle;
    lyricsFullscreenSpecialEffect = specialEffect;
    lyricsFullscreenHeaderLayer = headerLayer.clamp(0, 9);
    lyricsFullscreenLyricsLayer = lyricsLayer.clamp(0, 9);
    lyricsFullscreenControlsLayer = controlsLayer.clamp(0, 9);
    lyricsFullscreenVisualPath = visualPath.trim();
    lyricsFullscreenShowVisual =
        showVisual && lyricsFullscreenVisualPath.isNotEmpty;
    lyricsFullscreenVisualOffsetX = visualOffsetX
        .clamp(-lyricsFullscreenMaxOffsetX, lyricsFullscreenMaxOffsetX)
        .toDouble();
    lyricsFullscreenVisualOffsetY = visualOffsetY
        .clamp(-lyricsFullscreenMaxOffsetY, lyricsFullscreenMaxOffsetY)
        .toDouble();
    lyricsFullscreenVisualScale = visualScale.clamp(0.35, 2.25).toDouble();
    lyricsFullscreenVisualRotation =
        visualRotation.clamp(-180.0, 180.0).toDouble();
    lyricsFullscreenVisualLayer = visualLayer.clamp(0, 9);
    lyricsFullscreenVisualOpacity = visualOpacity.clamp(0.12, 1.0).toDouble();
    lyricsFullscreenVisualItems = _sanitizeVisualItems(visualItems ?? const []);
    if (lyricsFullscreenVisualItems.isEmpty &&
        lyricsFullscreenVisualPath.isNotEmpty) {
      lyricsFullscreenVisualItems = [
        LyricsFullscreenVisualItem.fromLegacy(
          path: lyricsFullscreenVisualPath,
          show: lyricsFullscreenShowVisual,
          offsetX: lyricsFullscreenVisualOffsetX,
          offsetY: lyricsFullscreenVisualOffsetY,
          scale: lyricsFullscreenVisualScale,
          rotation: lyricsFullscreenVisualRotation,
          layer: lyricsFullscreenVisualLayer,
          opacity: lyricsFullscreenVisualOpacity,
        ),
      ];
    }
    _syncLegacyVisualFromItems();
    lyricsFullscreenParticlePack = particlePack;
    lyricsFullscreenCustomParticlePack =
        customParticlePack.trim().isEmpty ? '* + .' : customParticlePack.trim();
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

  Future<void> setRecordingSavePath(String path) async {
    recordingSavePath = path.trim();
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setYoutubeStreamCacheEnabled(bool enabled) async {
    youtubeStreamCacheEnabled = enabled;
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
      await prefs.setStringList(musicPathsKey, musicSourcePaths);
      await prefs.setString(
          youtubeMusicDownloadPathKey, youtubeMusicDownloadPath);
      await prefs.setString(recordingSavePathKey, recordingSavePath);
      await prefs.setBool(
          youtubeStreamCacheEnabledKey, youtubeStreamCacheEnabled);
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
      await prefs.setString(_customParticlePackKey, customParticlePack);
      await prefs.setInt(_orbPaletteSizeKey, orbPaletteSize);
      await prefs.setDouble(_orbSizeKey, orbSize);
      await prefs.setDouble(_orbSpeedKey, orbSpeed);
      await prefs.setDouble(_fontSizeKey, fontSize);
      await prefs.setDouble(_borderRadiusKey, borderRadius);
      await prefs.setDouble(
          _glassEffectKey, glassEffect.clamp(0.0, 1.0).toDouble());
      await prefs.setInt(_accentColorKey, accentColor.value);
      await prefs.setInt(_backgroundModeKey, backgroundMode.index);
      await prefs.setString(_customBackgroundImageKey, customBackgroundImage);
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
      await prefs.setBool(_generateKanaLyricsKey, generateKanaLyrics);
      await prefs.setBool(shareSyncBackupsEnabledKey, shareSyncBackupsEnabled);
      await prefs.setInt(_homeRecommendedCountKey, homeRecommendedCount);
      await prefs.setInt(_homeEarlyListenedCountKey, homeEarlyListenedCount);
      await prefs.setInt(_homeRecentlyAddedCountKey, homeRecentlyAddedCount);
      await prefs.setInt(
          _lyricsFullscreenTextColorKey, lyricsFullscreenTextColor.value);
      await prefs.setInt(_lyricsFullscreenPositionKey,
          lyricsFullscreenPosition.index);
      await prefs.setBool(
          _lyricsFullscreenShowCoverKey, lyricsFullscreenShowCover);
      await prefs.setBool(
          _lyricsFullscreenShowTrackNameKey, lyricsFullscreenShowTrackName);
      await prefs.setBool(
          _lyricsFullscreenShowControlsKey, lyricsFullscreenShowControls);
      await prefs.setBool(
          _lyricsFullscreenShowProgressKey, lyricsFullscreenShowProgress);
      await prefs.setDouble(
          _lyricsFullscreenFontScaleKey, lyricsFullscreenFontScale);
      await prefs.setDouble(
          _lyricsFullscreenDimBackgroundKey, lyricsFullscreenDimBackground);
      await prefs.setInt(_lyricsFullscreenHeaderPositionKey,
          lyricsFullscreenHeaderPosition.index);
      await prefs.setInt(
          _lyricsFullscreenCoverStyleKey, lyricsFullscreenCoverStyle.index);
      await prefs.setBool(
          _lyricsFullscreenCustomLayoutKey, lyricsFullscreenCustomLayout);
      await prefs.setDouble(
          _lyricsFullscreenLyricsOffsetXKey, lyricsFullscreenLyricsOffsetX);
      await prefs.setDouble(
          _lyricsFullscreenLyricsOffsetYKey, lyricsFullscreenLyricsOffsetY);
      await prefs.setDouble(
          _lyricsFullscreenHeaderOffsetXKey, lyricsFullscreenHeaderOffsetX);
      await prefs.setDouble(
          _lyricsFullscreenHeaderOffsetYKey, lyricsFullscreenHeaderOffsetY);
      await prefs.setDouble(
          _lyricsFullscreenControlsOffsetXKey, lyricsFullscreenControlsOffsetX);
      await prefs.setDouble(
          _lyricsFullscreenControlsOffsetYKey, lyricsFullscreenControlsOffsetY);
      await prefs.setDouble(
          _lyricsFullscreenHeaderScaleKey, lyricsFullscreenHeaderScale);
      await prefs.setDouble(
          _lyricsFullscreenLyricsScaleKey, lyricsFullscreenLyricsScale);
      await prefs.setDouble(
          _lyricsFullscreenControlsScaleKey, lyricsFullscreenControlsScale);
      await prefs.setDouble(
          _lyricsFullscreenHeaderRotationKey, lyricsFullscreenHeaderRotation);
      await prefs.setDouble(
          _lyricsFullscreenLyricsRotationKey, lyricsFullscreenLyricsRotation);
      await prefs.setDouble(_lyricsFullscreenControlsRotationKey,
          lyricsFullscreenControlsRotation);
      await prefs.setInt(
          _lyricsFullscreenFontPresetKey, lyricsFullscreenFontPreset.index);
      await prefs.setInt(
          _lyricsFullscreenHeaderStyleKey, lyricsFullscreenHeaderStyle.index);
      await prefs.setInt(_lyricsFullscreenControlsStyleKey,
          lyricsFullscreenControlsStyle.index);
      await prefs.setInt(_lyricsFullscreenSpecialEffectKey,
          lyricsFullscreenSpecialEffect.index);
      await prefs.setInt(
          _lyricsFullscreenHeaderLayerKey, lyricsFullscreenHeaderLayer);
      await prefs.setInt(
          _lyricsFullscreenLyricsLayerKey, lyricsFullscreenLyricsLayer);
      await prefs.setInt(
          _lyricsFullscreenControlsLayerKey, lyricsFullscreenControlsLayer);
      await prefs.setString(
          _lyricsFullscreenVisualPathKey, lyricsFullscreenVisualPath);
      await prefs.setBool(
          _lyricsFullscreenShowVisualKey, lyricsFullscreenShowVisual);
      await prefs.setDouble(
          _lyricsFullscreenVisualOffsetXKey, lyricsFullscreenVisualOffsetX);
      await prefs.setDouble(
          _lyricsFullscreenVisualOffsetYKey, lyricsFullscreenVisualOffsetY);
      await prefs.setDouble(
          _lyricsFullscreenVisualScaleKey, lyricsFullscreenVisualScale);
      await prefs.setDouble(
          _lyricsFullscreenVisualRotationKey, lyricsFullscreenVisualRotation);
      await prefs.setInt(
          _lyricsFullscreenVisualLayerKey, lyricsFullscreenVisualLayer);
      await prefs.setDouble(
          _lyricsFullscreenVisualOpacityKey, lyricsFullscreenVisualOpacity);
      await prefs.setInt(_coverArtDisplayModeKey, coverArtDisplayMode.index);
      await prefs.setStringList(
        _lyricsFullscreenVisualItemsKey,
        lyricsFullscreenVisualItems
            .map((item) => jsonEncode(item.sanitized().toJson()))
            .toList(growable: false),
      );
      await prefs.setInt(
          _lyricsFullscreenParticlePackKey, lyricsFullscreenParticlePack.index);
      await prefs.setString(_lyricsFullscreenCustomParticlePackKey,
          lyricsFullscreenCustomParticlePack);
    } catch (e) {
      debugPrint('Error saving settings: $e');
    }
  }

  void _saveSettingsDebounced() {
    _saveSettingsDebounce?.cancel();
    _saveSettingsDebounce = Timer(const Duration(milliseconds: 180), () {
      _saveSettingsDebounce = null;
      _saveSettings();
    });
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

  LyricsFullscreenPosition _lyricsFullscreenPositionFromIndex(int index) {
    return index >= 0 && index < LyricsFullscreenPosition.values.length
        ? LyricsFullscreenPosition.values[index]
        : LyricsFullscreenPosition.center;
  }

  LyricsFullscreenHeaderPosition _lyricsFullscreenHeaderPositionFromIndex(
      int index) {
    return index >= 0 && index < LyricsFullscreenHeaderPosition.values.length
        ? LyricsFullscreenHeaderPosition.values[index]
        : LyricsFullscreenHeaderPosition.topLeft;
  }

  LyricsFullscreenCoverStyle _lyricsFullscreenCoverStyleFromIndex(int index) {
    return index >= 0 && index < LyricsFullscreenCoverStyle.values.length
        ? LyricsFullscreenCoverStyle.values[index]
        : LyricsFullscreenCoverStyle.rounded;
  }

  LyricsFullscreenFontPreset _lyricsFullscreenFontPresetFromIndex(int index) {
    return index >= 0 && index < LyricsFullscreenFontPreset.values.length
        ? LyricsFullscreenFontPreset.values[index]
        : LyricsFullscreenFontPreset.system;
  }

  LyricsFullscreenHeaderStyle _lyricsFullscreenHeaderStyleFromIndex(int index) {
    return index >= 0 && index < LyricsFullscreenHeaderStyle.values.length
        ? LyricsFullscreenHeaderStyle.values[index]
        : LyricsFullscreenHeaderStyle.compact;
  }

  LyricsFullscreenControlsStyle _lyricsFullscreenControlsStyleFromIndex(
      int index) {
    return index >= 0 && index < LyricsFullscreenControlsStyle.values.length
        ? LyricsFullscreenControlsStyle.values[index]
        : LyricsFullscreenControlsStyle.classic;
  }

  List<LyricsFullscreenVisualItem> _lyricsFullscreenVisualItemsFromPrefs(
    SharedPreferences prefs,
  ) {
    final rawItems = prefs.getStringList(_lyricsFullscreenVisualItemsKey) ??
        const <String>[];
    final items = <LyricsFullscreenVisualItem>[];
    for (final raw in rawItems) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final item = LyricsFullscreenVisualItem.fromJson(decoded);
          if (item.path.isNotEmpty) items.add(item);
        }
      } catch (_) {
        // Ignore malformed older drafts and keep loading the app.
      }
    }
    return _sanitizeVisualItems(items);
  }

  List<LyricsFullscreenVisualItem> _sanitizeVisualItems(
    List<LyricsFullscreenVisualItem> items,
  ) {
    final seenIds = <String>{};
    final cleanItems = <LyricsFullscreenVisualItem>[];
    for (final item in items) {
      var clean = item.sanitized();
      if (clean.path.isEmpty) continue;
      var id = clean.id;
      if (seenIds.contains(id)) {
        id = '${id}_${cleanItems.length}';
        clean = LyricsFullscreenVisualItem(
          id: id,
          path: clean.path,
          show: clean.show,
          offsetX: clean.offsetX,
          offsetY: clean.offsetY,
          scale: clean.scale,
          rotation: clean.rotation,
          layer: clean.layer,
          opacity: clean.opacity,
        );
      }
      seenIds.add(id);
      cleanItems.add(clean);
      if (cleanItems.length >= 12) break;
    }
    return cleanItems;
  }

  void _syncLegacyVisualFromItems() {
    final first = lyricsFullscreenVisualItems.isEmpty
        ? null
        : lyricsFullscreenVisualItems.first;
    if (first == null) {
      lyricsFullscreenVisualPath = '';
      lyricsFullscreenShowVisual = false;
      return;
    }
    lyricsFullscreenVisualPath = first.path;
    lyricsFullscreenShowVisual = first.show && first.path.isNotEmpty;
    lyricsFullscreenVisualOffsetX = first.offsetX;
    lyricsFullscreenVisualOffsetY = first.offsetY;
    lyricsFullscreenVisualScale = first.scale;
    lyricsFullscreenVisualRotation = first.rotation;
    lyricsFullscreenVisualLayer = first.layer;
    lyricsFullscreenVisualOpacity = first.opacity;
  }

  LyricsFullscreenSpecialEffect _lyricsFullscreenSpecialEffectFromIndex(
      int index) {
    return index >= 0 && index < LyricsFullscreenSpecialEffect.values.length
        ? LyricsFullscreenSpecialEffect.values[index]
        : LyricsFullscreenSpecialEffect.none;
  }

  LyricsFullscreenParticlePack _lyricsFullscreenParticlePackFromIndex(
      int index) {
    return index >= 0 && index < LyricsFullscreenParticlePack.values.length
        ? LyricsFullscreenParticlePack.values[index]
        : LyricsFullscreenParticlePack.sparkles;
  }

  @override
  void dispose() {
    _saveSettingsDebounce?.cancel();
    super.dispose();
  }
}
