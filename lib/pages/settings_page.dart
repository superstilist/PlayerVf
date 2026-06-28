import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/settings_model.dart';
import '../services/music_service.dart';
import '../services/responsive.dart';
import '../widgets/glass_container.dart';
import '../pages/appearance_screen.dart';
import '../pages/playback_settings_screen.dart';
import '../pages/web_settings_screen.dart';
import '../pages/library_stats_screen.dart';
import '../widgets/audio_effects_menu.dart';
import '../services/safe_file_picker.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Consumer<SettingsModel>(
        builder: (context, settings, _) {
          return ListView(
            padding: EdgeInsets.fromLTRB(20.w, 10.h, 20.w, 40.h),
            physics: const BouncingScrollPhysics(),
            children: [
              _buildSectionHeader(context, 'Playback', Icons.play_circle_rounded),
              _PlaybackSection(settings: settings),
              SizedBox(height: 24.h),
              _buildSectionHeader(context, 'Lyrics', Icons.lyrics_rounded),
              _LyricsSection(settings: settings),
              SizedBox(height: 24.h),
              _buildSectionHeader(context, 'Appearance', Icons.palette_rounded),
              _AppearanceSection(settings: settings),
              SizedBox(height: 24.h),
              _buildSectionHeader(context, 'Performance', Icons.speed_rounded),
              _PerformanceSection(settings: settings),
              SizedBox(height: 24.h),
              _buildSectionHeader(context, 'Library', Icons.library_music_rounded),
              _LibrarySection(settings: settings),
              SizedBox(height: 24.h),
              _buildSectionHeader(context, 'Advanced', Icons.settings_suggest_rounded),
              _AdvancedSection(settings: settings),
              SizedBox(height: 40.h),
            ],
          );
        },
      ),
    );
  }

  static Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(left: 4.w, bottom: 12.h),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary.withOpacity(0.84)),
          SizedBox(width: 8.w),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: theme.colorScheme.primary.withOpacity(0.84),
              fontWeight: FontWeight.w900,
              fontSize: 11.sp,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Playback Section
// ---------------------------------------------------------------------------
class _PlaybackSection extends StatelessWidget {
  final SettingsModel settings;
  const _PlaybackSection({required this.settings});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final musicService = context.watch<MusicService>();

    return GlassContainer(
      padding: EdgeInsets.all(16.w),
      borderRadius: BorderRadius.circular(16.s),
      blur: 14,
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.play_circle_rounded, color: theme.colorScheme.primary),
            title: const Text('Playback Settings'),
            subtitle: const Text('Decoders, seek step, song gap, lyrics, cover art'),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PlaybackSettingsScreen()),
            ),
          ),
          const Divider(height: 20),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeColor: settings.accentColor,
            secondary: Icon(Icons.history_rounded, color: theme.colorScheme.primary),
            title: const Text('Remember playback'),
            subtitle: const Text('Resume last track and position'),
            value: musicService.rememberPlayback,
            onChanged: musicService.setRememberPlayback,
          ),
          const Divider(height: 20),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.equalizer_rounded, color: theme.colorScheme.primary),
            title: const Text('Audio Effects'),
            subtitle: const Text('Equalizer, pitch, speed, reverb'),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            onTap: () => showAudioEffectsMenu(context),
          ),
          const Divider(height: 20),
          _seekStepRow(context, settings),
          SizedBox(height: 12.h),
          _songGapRow(context, settings),
          SizedBox(height: 12.h),
          _coverArtModeRow(context, settings),
          SizedBox(height: 12.h),
          _romajiRow(context, settings),
        ],
      ),
    );
  }

  static Widget _seekStepRow(BuildContext context, SettingsModel settings) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.fast_rewind_rounded, size: 18, color: theme.colorScheme.primary),
        SizedBox(width: 8.w),
        const Expanded(
          child: Text('Seek step', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Text(
          '${settings.seekStepSeconds}s',
          style: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.64),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  static Widget _songGapRow(BuildContext context, SettingsModel settings) {
    final theme = Theme.of(context);
    final ms = settings.songGapMs;
    return Row(
      children: [
        Icon(Icons.timer_outlined, size: 18, color: theme.colorScheme.primary),
        SizedBox(width: 8.w),
        const Expanded(
          child: Text('Song gap', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Text(
          ms == 0 ? 'None' : '${ms}ms',
          style: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.64),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  static Widget _coverArtModeRow(BuildContext context, SettingsModel settings) {
    final theme = Theme.of(context);
    const labels = {
      CoverArtDisplayMode.fit: 'Fit',
      CoverArtDisplayMode.crop: 'Crop',
      CoverArtDisplayMode.square: 'Square',
      CoverArtDisplayMode.custom: 'Custom',
    };
    return Row(
      children: [
        Icon(Icons.album_rounded, size: 18, color: theme.colorScheme.primary),
        SizedBox(width: 8.w),
        const Expanded(
          child: Text('Cover art', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Text(
          labels[settings.coverArtDisplayMode] ?? 'Fit',
          style: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.64),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  static Widget _romajiRow(BuildContext context, SettingsModel settings) {
    final theme = Theme.of(context);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      activeColor: settings.accentColor,
      secondary: Icon(Icons.translate_rounded, color: theme.colorScheme.primary),
      title: const Text('Lyrics (romaji)'),
      subtitle: const Text('Generate romaji from Japanese lyrics'),
      value: settings.generateKanaLyrics,
      onChanged: settings.setGenerateKanaLyrics,
    );
  }
}

// ---------------------------------------------------------------------------
// Lyrics Section
// ---------------------------------------------------------------------------
class _LyricsSection extends StatelessWidget {
  final SettingsModel settings;
  const _LyricsSection({required this.settings});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GlassContainer(
      padding: EdgeInsets.all(16.w),
      borderRadius: BorderRadius.circular(16.s),
      blur: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lyrics_rounded, color: theme.colorScheme.primary),
              SizedBox(width: 8.w),
              const Expanded(
                child: Text('Fullscreen Lyrics',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          _buildChipSelector<LyricsFullscreenPosition>(
            context: context,
            label: 'Position',
            icon: Icons.vertical_align_center_rounded,
            value: settings.lyricsFullscreenPosition,
            labels: const {
              LyricsFullscreenPosition.top: 'Top',
              LyricsFullscreenPosition.center: 'Center',
              LyricsFullscreenPosition.bottom: 'Bottom',
            },
            onSelected: settings.setLyricsFullscreenPosition,
          ),
          SizedBox(height: 12.h),
          _buildChipSelector<LyricsFullscreenTextAlign>(
            context: context,
            label: 'Text align',
            icon: Icons.format_align_center_rounded,
            value: settings.lyricsFullscreenTextAlign,
            labels: const {
              LyricsFullscreenTextAlign.left: 'Left',
              LyricsFullscreenTextAlign.center: 'Center',
              LyricsFullscreenTextAlign.right: 'Right',
            },
            onSelected: settings.setLyricsFullscreenTextAlign,
          ),
          SizedBox(height: 12.h),
          _buildChipSelector<LyricsFullscreenCoverStyle>(
            context: context,
            label: 'Cover style',
            icon: Icons.photo_size_select_actual_rounded,
            value: settings.lyricsFullscreenCoverStyle,
            labels: const {
              LyricsFullscreenCoverStyle.rounded: 'Rounded',
              LyricsFullscreenCoverStyle.circle: 'Circle',
              LyricsFullscreenCoverStyle.shadow: 'Shadow',
              LyricsFullscreenCoverStyle.glow: 'Glow',
            },
            onSelected: settings.setLyricsFullscreenCoverStyle,
          ),
          SizedBox(height: 12.h),
          _buildChipSelector<LyricsFullscreenHeaderStyle>(
            context: context,
            label: 'Header style',
            icon: Icons.title_rounded,
            value: settings.lyricsFullscreenHeaderStyle,
            labels: const {
              LyricsFullscreenHeaderStyle.compact: 'Compact',
              LyricsFullscreenHeaderStyle.bigCover: 'Big Cover',
              LyricsFullscreenHeaderStyle.coverAbove: 'Cover Above',
              LyricsFullscreenHeaderStyle.fullCover: 'Full Cover',
              LyricsFullscreenHeaderStyle.nameOnly: 'Name Only',
            },
            onSelected: settings.setLyricsFullscreenHeaderStyle,
          ),
          SizedBox(height: 12.h),
          _buildChipSelector<LyricsFullscreenControlsStyle>(
            context: context,
            label: 'Controls style',
            icon: Icons.slideshow_rounded,
            value: settings.lyricsFullscreenControlsStyle,
            labels: const {
              LyricsFullscreenControlsStyle.classic: 'Classic',
              LyricsFullscreenControlsStyle.pill: 'Pill',
              LyricsFullscreenControlsStyle.minimal: 'Minimal',
              LyricsFullscreenControlsStyle.glow: 'Glow',
              LyricsFullscreenControlsStyle.panel43: '4:3 Panel',
            },
            onSelected: settings.setLyricsFullscreenControlsStyle,
          ),
          SizedBox(height: 12.h),
          _buildChipSelector<LyricsFullscreenFontPreset>(
            context: context,
            label: 'Font preset',
            icon: Icons.font_download_rounded,
            value: settings.lyricsFullscreenFontPreset,
            labels: const {
              LyricsFullscreenFontPreset.system: 'System',
              LyricsFullscreenFontPreset.serif: 'Serif',
              LyricsFullscreenFontPreset.mono: 'Mono',
              LyricsFullscreenFontPreset.rounded: 'Rounded',
              LyricsFullscreenFontPreset.notoSans: 'Noto Sans',
              LyricsFullscreenFontPreset.display: 'Display',
              LyricsFullscreenFontPreset.handwritten: 'Handwritten',
              LyricsFullscreenFontPreset.robot: 'Robot',
            },
            onSelected: settings.setLyricsFullscreenFontPreset,
          ),
          SizedBox(height: 12.h),
          _buildChipSelector<LyricsFullscreenSpecialEffect>(
            context: context,
            label: 'Special effect',
            icon: Icons.auto_awesome_rounded,
            value: settings.lyricsFullscreenSpecialEffect,
            labels: const {
              LyricsFullscreenSpecialEffect.none: 'None',
              LyricsFullscreenSpecialEffect.softGlow: 'Soft Glow',
              LyricsFullscreenSpecialEffect.pulse: 'Pulse',
              LyricsFullscreenSpecialEffect.float: 'Float',
              LyricsFullscreenSpecialEffect.particles: 'Particles',
            },
            onSelected: settings.setLyricsFullscreenSpecialEffect,
          ),
          SizedBox(height: 12.h),
          _buildChipSelector<LyricsFullscreenFadeMode>(
            context: context,
            label: 'Fade mode',
            icon: Icons.gradient_rounded,
            value: settings.lyricsFullscreenFadeMode,
            labels: const {
              LyricsFullscreenFadeMode.none: 'None',
              LyricsFullscreenFadeMode.top: 'Top',
              LyricsFullscreenFadeMode.bottom: 'Bottom',
              LyricsFullscreenFadeMode.both: 'Both',
            },
            onSelected: settings.setLyricsFullscreenFadeMode,
          ),
          SizedBox(height: 12.h),
          _buildChipSelector<LyricsFullscreenParticlePack>(
            context: context,
            label: 'Particle pack',
            icon: Icons.bubble_chart_rounded,
            value: settings.lyricsFullscreenParticlePack,
            labels: const {
              LyricsFullscreenParticlePack.sparkles: 'Sparkles',
              LyricsFullscreenParticlePack.stars: 'Stars',
              LyricsFullscreenParticlePack.snow: 'Snow',
              LyricsFullscreenParticlePack.bubbles: 'Bubbles',
              LyricsFullscreenParticlePack.hearts: 'Hearts',
              LyricsFullscreenParticlePack.sakura: 'Sakura',
              LyricsFullscreenParticlePack.fireflies: 'Fireflies',
              LyricsFullscreenParticlePack.confetti: 'Confetti',
            },
            onSelected: settings.setLyricsFullscreenParticlePack,
          ),
          const Divider(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeColor: settings.accentColor,
            title: const Text('Show cover', style: TextStyle(fontSize: 13)),
            value: settings.lyricsFullscreenShowCover,
            onChanged: settings.setLyricsFullscreenShowCover,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeColor: settings.accentColor,
            title: const Text('Show track name', style: TextStyle(fontSize: 13)),
            value: settings.lyricsFullscreenShowTrackName,
            onChanged: settings.setLyricsFullscreenShowTrackName,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeColor: settings.accentColor,
            title: const Text('Show controls', style: TextStyle(fontSize: 13)),
            value: settings.lyricsFullscreenShowControls,
            onChanged: settings.setLyricsFullscreenShowControls,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeColor: settings.accentColor,
            title: const Text('Show progress', style: TextStyle(fontSize: 13)),
            value: settings.lyricsFullscreenShowProgress,
            onChanged: settings.setLyricsFullscreenShowProgress,
          ),
          const Divider(height: 24),
          _buildSliderRow(
            context: context,
            label: 'Font scale',
            icon: Icons.format_size_rounded,
            value: settings.lyricsFullscreenFontScale,
            min: 0.5,
            max: 3.0,
            divisions: 50,
            suffix: 'x',
            accentColor: settings.accentColor,
            onChanged: settings.setLyricsFullscreenFontScale,
          ),
          SizedBox(height: 8.h),
          _buildSliderRow(
            context: context,
            label: 'Dim background',
            icon: Icons.brightness_low_rounded,
            value: settings.lyricsFullscreenDimBackground,
            min: 0.25,
            max: 0.85,
            divisions: 24,
            suffix: '%',
            multiplier: 100,
            roundToInt: true,
            accentColor: settings.accentColor,
            onChanged: settings.setLyricsFullscreenDimBackground,
          ),
        ],
      ),
    );
  }

  static Widget _buildChipSelector<T extends Enum>({
    required BuildContext context,
    required String label,
    required IconData icon,
    required T value,
    required Map<T, String> labels,
    required ValueChanged<T> onSelected,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            SizedBox(width: 8.w),
            Text(label,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
        SizedBox(height: 8.h),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: labels.entries.map((entry) {
            final isSelected = entry.key == value;
            return ChoiceChip(
              label: Text(entry.value, style: const TextStyle(fontSize: 11)),
              selected: isSelected,
              onSelected: (_) => onSelected(entry.key),
              selectedColor: theme.colorScheme.primaryContainer.withOpacity(0.72),
              backgroundColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.34),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              visualDensity: VisualDensity.compact,
              labelStyle: TextStyle(
                color: isSelected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurface.withOpacity(0.8),
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  static Widget _buildSliderRow({
    required BuildContext context,
    required String label,
    required IconData icon,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required Color accentColor,
    String suffix = '',
    double multiplier = 1.0,
    bool roundToInt = false,
  }) {
    final theme = Theme.of(context);
    final displayValue = roundToInt
        ? (value * multiplier).round().toString()
        : value.toStringAsFixed(2);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        SizedBox(width: 8.w),
        Expanded(
          child: Text(label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ),
        Expanded(
          flex: 2,
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: accentColor,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            '$displayValue$suffix',
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurface.withOpacity(0.64),
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Appearance Section
// ---------------------------------------------------------------------------
class _AppearanceSection extends StatelessWidget {
  final SettingsModel settings;
  const _AppearanceSection({required this.settings});

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: EdgeInsets.all(16.w),
      borderRadius: BorderRadius.circular(16.s),
      blur: 14,
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.palette_rounded, color: settings.accentColor),
            title: const Text('Appearance'),
            subtitle: const Text('Themes, accent color, particles, navigation, layout'),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AppearanceScreen()),
            ),
          ),
          const Divider(height: 20),
          _themeModeRow(context, settings),
          SizedBox(height: 12.h),
          _themePresetRow(context, settings),
          SizedBox(height: 12.h),
          _accentColorRow(context, settings),
          SizedBox(height: 12.h),
          _backgroundModeRow(context, settings),
          SizedBox(height: 12.h),
          _particleRow(context, settings),
          SizedBox(height: 12.h),
          _navPositionRow(context, settings),
          SizedBox(height: 12.h),
          _viewModeRow(context, settings),
        ],
      ),
    );
  }

  static Widget _themeModeRow(BuildContext context, SettingsModel settings) {
    final theme = Theme.of(context);
    const labels = {
      ThemeMode.system: 'System',
      ThemeMode.light: 'Light',
      ThemeMode.dark: 'Dark',
    };
    return Row(
      children: [
        Icon(Icons.dark_mode_rounded, size: 18, color: theme.colorScheme.primary),
        SizedBox(width: 8.w),
        const Expanded(
          child: Text('Theme mode', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Text(
          labels[settings.themeMode] ?? 'Dark',
          style: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.64),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  static Widget _themePresetRow(BuildContext context, SettingsModel settings) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.auto_awesome_rounded, size: 18, color: theme.colorScheme.primary),
        SizedBox(width: 8.w),
        const Expanded(
          child: Text('Theme preset', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Text(
          settings.themePreset.name[0].toUpperCase() + settings.themePreset.name.substring(1),
          style: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.64),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  static Widget _accentColorRow(BuildContext context, SettingsModel settings) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.colorize_rounded, size: 18, color: theme.colorScheme.primary),
        SizedBox(width: 8.w),
        const Expanded(
          child: Text('Accent color', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Container(
          width: 20.s,
          height: 20.s,
          decoration: BoxDecoration(
            color: settings.accentColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withOpacity(0.6),
            ),
          ),
        ),
      ],
    );
  }

  static Widget _backgroundModeRow(BuildContext context, SettingsModel settings) {
    final theme = Theme.of(context);
    const labels = {
      BackgroundMode.coverArt: 'Cover Art',
      BackgroundMode.customImage: 'Custom Image',
      BackgroundMode.solidColor: 'Solid Color',
    };
    return Row(
      children: [
        Icon(Icons.wallpaper_rounded, size: 18, color: theme.colorScheme.primary),
        SizedBox(width: 8.w),
        const Expanded(
          child: Text('Background', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Text(
          labels[settings.backgroundMode] ?? 'Cover Art',
          style: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.64),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  static Widget _particleRow(BuildContext context, SettingsModel settings) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.grain_rounded, size: 18, color: theme.colorScheme.primary),
        SizedBox(width: 8.w),
        const Expanded(
          child: Text('Particle effect', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Text(
          settings.particleEffect.name[0].toUpperCase() + settings.particleEffect.name.substring(1),
          style: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.64),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  static Widget _navPositionRow(BuildContext context, SettingsModel settings) {
    final theme = Theme.of(context);
    const labels = {
      NavPosition.top: 'Top',
      NavPosition.bottom: 'Bottom',
      NavPosition.left: 'Left',
      NavPosition.right: 'Right',
    };
    return Row(
      children: [
        Icon(Icons.swap_vert_circle_rounded, size: 18, color: theme.colorScheme.primary),
        SizedBox(width: 8.w),
        const Expanded(
          child: Text('Navigation', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Text(
          labels[settings.navPosition] ?? 'Bottom',
          style: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.64),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  static Widget _viewModeRow(BuildContext context, SettingsModel settings) {
    final theme = Theme.of(context);
    const labels = {
      ViewMode.card: 'Card',
      ViewMode.list: 'List',
    };
    return Row(
      children: [
        Icon(Icons.view_module_rounded, size: 18, color: theme.colorScheme.primary),
        SizedBox(width: 8.w),
        const Expanded(
          child: Text('Library layout', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Text(
          labels[settings.viewMode] ?? 'Card',
          style: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.64),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Performance Section (inline controls)
// ---------------------------------------------------------------------------
class _PerformanceSection extends StatefulWidget {
  final SettingsModel settings;
  const _PerformanceSection({required this.settings});

  @override
  State<_PerformanceSection> createState() => _PerformanceSectionState();
}

class _PerformanceSectionState extends State<_PerformanceSection> {
  late PerformanceMode _selectedMode;
  late double _blurScale;

  @override
  void initState() {
    super.initState();
    _selectedMode = widget.settings.performanceMode;
    _blurScale = widget.settings.backgroundBlurScale;
  }

  @override
  void didUpdateWidget(covariant _PerformanceSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.performanceMode != widget.settings.performanceMode) {
      _selectedMode = widget.settings.performanceMode;
    }
    if ((oldWidget.settings.backgroundBlurScale - widget.settings.backgroundBlurScale).abs() > 0.01) {
      _blurScale = widget.settings.backgroundBlurScale;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final theme = Theme.of(context);

    const modeLabels = {
      PerformanceMode.auto: 'Auto',
      PerformanceMode.quality: 'Quality',
      PerformanceMode.balanced: 'Balanced',
      PerformanceMode.batterySaver: 'Battery',
      PerformanceMode.maxPerformance: 'Max FPS',
    };
    const modeIcons = {
      PerformanceMode.auto: Icons.auto_awesome_rounded,
      PerformanceMode.quality: Icons.high_quality_rounded,
      PerformanceMode.balanced: Icons.speed_rounded,
      PerformanceMode.batterySaver: Icons.battery_saver_rounded,
      PerformanceMode.maxPerformance: Icons.rocket_launch_rounded,
    };

    final blurPercent = (_blurScale * 100).round();

    return GlassContainer(
      padding: EdgeInsets.all(16.w),
      borderRadius: BorderRadius.circular(16.s),
      blur: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: 10.h),
            child: Text(
              'Performance mode',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.sp),
            ),
          ),
          Text(
            'GPU blur, particles, cover quality, animation cost',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withOpacity(0.52),
              fontSize: 12.sp,
            ),
          ),
          SizedBox(height: 10.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: PerformanceMode.values.map((mode) {
              final selected = _selectedMode == mode;
              return ChoiceChip(
                avatar: Icon(
                  modeIcons[mode],
                  size: 16,
                  color: selected
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                ),
                label: Text(modeLabels[mode]!),
                selected: selected,
                onSelected: (value) {
                  setState(() => _selectedMode = mode);
                  settings.setPerformanceMode(mode);
                },
                selectedColor: theme.colorScheme.primaryContainer.withOpacity(0.72),
                backgroundColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.34),
                labelStyle: TextStyle(
                  color: selected
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.sp,
                ),
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
          SizedBox(height: 16.h),
          Row(
            children: [
              Icon(Icons.blur_on_rounded, size: 18, color: theme.colorScheme.primary),
              SizedBox(width: 8.w),
              const Expanded(
                child: Text('Background blur', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              Text(
                '$blurPercent%',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.64),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          Slider(
            value: _blurScale,
            min: 0.0,
            max: 2.5,
            divisions: 25,
            activeColor: settings.accentColor,
            onChanged: (value) {
              setState(() => _blurScale = value);
              settings.setBackgroundBlurScale(value);
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Library Section (inline path management)
// ---------------------------------------------------------------------------
class _LibrarySection extends StatelessWidget {
  final SettingsModel settings;
  const _LibrarySection({required this.settings});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final musicService = context.watch<MusicService>();

    return GlassContainer(
      padding: EdgeInsets.all(16.w),
      borderRadius: BorderRadius.circular(16.s),
      blur: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.library_music_rounded, color: theme.colorScheme.primary),
            title: const Text('Music Folders'),
            subtitle: Text(
              '${settings.musicSourcePaths.length} path${settings.musicSourcePaths.length == 1 ? '' : 's'} configured',
            ),
          ),
          if (settings.musicSourcePaths.isEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: 10.h),
              child: Text(
                'No custom folders added. Default directories are used.',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.52),
                  fontSize: 12.sp,
                ),
              ),
            )
          else
            ...settings.musicSourcePaths.map(
              (path) => _buildPathTile(context, settings, path),
            ),
          SizedBox(height: 10.h),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _addPath(context, settings, musicService),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Folder'),
            ),
          ),
          const Divider(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.auto_graph_rounded, color: theme.colorScheme.primary),
            title: const Text('Mini Stats'),
            subtitle: const Text('Library analytics and listening insights'),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LibraryStatsScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPathTile(BuildContext context, SettingsModel settings, String path) {
    final theme = Theme.of(context);
    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.32),
        borderRadius: BorderRadius.circular(12.s),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder_open_rounded, size: 18, color: Colors.grey),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              path.split(RegExp(r'[/\\]')).last,
              style: TextStyle(fontSize: 13.sp),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline_rounded,
                size: 18, color: Colors.redAccent),
            onPressed: () => settings.removeMusicPath(path),
          ),
        ],
      ),
    );
  }

  Future<void> _addPath(
    BuildContext context,
    SettingsModel settings,
    MusicService musicService,
  ) async {
    if (kIsWeb) {
      final count = await musicService.importWebFolderMusic();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 0
                ? 'No supported media files were imported.'
                : 'Imported $count media file${count == 1 ? '' : 's'}.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final path = await pickDirectorySafely(context);
    if (path != null) settings.addMusicPath(path);
  }
}

// ---------------------------------------------------------------------------
// Advanced Section (inline actions)
// ---------------------------------------------------------------------------
class _AdvancedSection extends StatelessWidget {
  final SettingsModel settings;
  const _AdvancedSection({required this.settings});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final musicService = context.watch<MusicService>();

    return GlassContainer(
      padding: EdgeInsets.all(16.w),
      borderRadius: BorderRadius.circular(16.s),
      blur: 14,
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.language_rounded, color: theme.colorScheme.primary),
            title: const Text('Web & YouTube'),
            subtitle: const Text('Stream cache, download folder, web import'),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WebSettingsScreen()),
            ),
          ),
          const Divider(height: 20),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeColor: settings.accentColor,
            secondary: Icon(Icons.sync_rounded, color: theme.colorScheme.primary),
            title: const Text('Share sync backups'),
            subtitle: const Text('Backup library before importing shared songs'),
            value: settings.shareSyncBackupsEnabled,
            onChanged: settings.setShareSyncBackupsEnabled,
          ),
          const Divider(height: 20),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.system_update_alt_rounded, color: theme.colorScheme.primary),
            title: const Text('Update Library'),
            subtitle: const Text('Rescan all music folders'),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            onTap: () {
              final paths = settings.musicSourcePaths.isEmpty
                  ? null
                  : settings.musicSourcePaths;
              musicService.loadSystemMusic(customPaths: paths, clearExisting: true);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Library update started'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
          const Divider(height: 20),
          OutlinedButton.icon(
            onPressed: musicService.isLoadingSystemMusic
                ? null
                : () => _showClearCacheDialog(context, musicService),
            icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
            label: const Text('Clear Cache',
                style: TextStyle(color: Colors.redAccent)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.redAccent),
              minimumSize: Size(double.infinity, 45.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.s),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showClearCacheDialog(BuildContext context, MusicService musicService) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: GlassContainer(
          padding: const EdgeInsets.all(24),
          borderRadius: BorderRadius.circular(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Clear Cache?',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text(
                'This will delete cached cover art and metadata, then rescan your music library.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      musicService.clearCache();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
