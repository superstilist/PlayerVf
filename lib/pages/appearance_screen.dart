import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../models/settings_model.dart';
import '../widgets/glass_container.dart';
import '../services/responsive.dart';

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsModel>(
      builder: (context, settings, child) {
        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          appBar: AppBar(
            title: const Text('Appearance',
                style:
                    TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0)),
            backgroundColor: Theme.of(context).colorScheme.surface,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: ListView(
            padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 10.h),
            physics: const BouncingScrollPhysics(),
            children: [
              _buildSectionTitle(context, 'Theme Presets'),
              _buildGlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Select Atmosphere',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 16),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          _buildPresetButton(context, settings, 'Material',
                              ThemePreset.material, Icons.layers_rounded),
                          _buildPresetButton(context, settings, 'Graphite',
                              ThemePreset.graphite, Icons.texture_rounded),
                          _buildPresetButton(context, settings, 'Classical',
                              ThemePreset.classic, Icons.palette_outlined),
                          _buildPresetButton(context, settings, 'Fox',
                              ThemePreset.fox, Icons.auto_awesome_rounded),
                          _buildPresetButton(
                              context,
                              settings,
                              'Anime',
                              ThemePreset.anime,
                              Icons.face_retouching_natural_rounded),
                          _buildPresetButton(context, settings, 'Azure',
                              ThemePreset.azure, Icons.water_drop_rounded),
                          _buildPresetButton(context, settings, 'Cosmic',
                              ThemePreset.cosmic, Icons.rocket_launch_rounded),
                          _buildPresetButton(context, settings, 'Sunset',
                              ThemePreset.sunset, Icons.wb_twilight_rounded),
                          _buildPresetButton(context, settings, 'Midnight',
                              ThemePreset.midnight, Icons.dark_mode_rounded),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle(context, 'Accent Color'),
              _buildGlassCard(
                child: _buildAccentColorPicker(context, settings),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle(context, 'Background Style'),
              _buildGlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildBackgroundModeButton(context, settings, 'Cover Art',
                            BackgroundMode.coverArt, Icons.album_rounded),
                        _buildBackgroundModeButton(context, settings, 'Custom Image',
                            BackgroundMode.customImage, Icons.image_rounded),
                        _buildBackgroundModeButton(context, settings, 'Solid Color',
                            BackgroundMode.solidColor, Icons.format_color_fill_rounded),
                      ],
                    ),
                    if (settings.backgroundMode == BackgroundMode.customImage) ...[
                      const Divider(height: 24, color: Colors.white10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              settings.customBackgroundImage.isEmpty
                                  ? 'No image selected'
                                  : settings.customBackgroundImage.split(RegExp(r'[/\\]')).last,
                              style: const TextStyle(fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              final result = await FilePicker.platform.pickFiles(type: FileType.image);
                              if (result != null && result.files.single.path != null) {
                                settings.setCustomBackgroundImage(result.files.single.path!);
                              }
                            },
                            icon: const Icon(Icons.folder_open_rounded, size: 16),
                            label: const Text('Pick Image'),
                          ),
                        ],
                      ),
                    ],
                    if (settings.backgroundMode == BackgroundMode.solidColor) ...[
                      const Divider(height: 24, color: Colors.white10),
                      Text(
                        'Orb settings are in the Solid Color section below.',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                    if (settings.backgroundMode != BackgroundMode.solidColor) ...[
                      const Divider(height: 24, color: Colors.white10),
                      _buildSliderRow(
                          context,
                          'Background Blur',
                          settings.backgroundBlurScale * 100,
                          0,
                          250,
                          (v) => settings.setBackgroundBlurScale(v / 100)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle(context, 'Solid Color'),
              _buildGlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Customize the orb effect that appears on solid color backgrounds. Orbs are colored from the current album art palette.',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const Divider(height: 24, color: Colors.white10),
                    _buildSliderRow(
                        context,
                        'Orb Palette Colors',
                        settings.orbPaletteSize.toDouble(),
                        2,
                        5,
                        (v) => settings.setOrbPaletteSize(v.round()),
                        divisions: 3),
                    const Divider(height: 24, color: Colors.white10),
                    _buildSliderRow(
                        context,
                        'Orb Size',
                        settings.orbSize,
                        0.5,
                        3.0,
                        (v) => settings.setOrbSize(v)),
                    const Divider(height: 24, color: Colors.white10),
                    _buildSliderRow(
                        context,
                        'Orb Speed',
                        settings.orbSpeed,
                        0.2,
                        3.0,
                        (v) => settings.setOrbSpeed(v)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle(context, 'Particle Effects'),
              _buildGlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildParticleWarning(context, settings),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                       children: [
                         _buildParticleButton(context, settings, 'None',
                             ParticleEffect.none, Icons.block_rounded),
                         _buildParticleButton(context, settings, 'Sakura',
                             ParticleEffect.sakura, Icons.local_florist_rounded),
                         _buildParticleButton(context, settings, 'Snow',
                             ParticleEffect.snow, Icons.ac_unit_rounded),
                         _buildParticleButton(context, settings, 'Stars',
                             ParticleEffect.stars, Icons.auto_awesome_rounded),
                         _buildParticleButton(context, settings, 'Bubbles',
                             ParticleEffect.bubbles, Icons.bubble_chart_rounded),
                         _buildParticleButton(context, settings, 'Rain',
                             ParticleEffect.rain, Icons.water_drop_rounded),
                         _buildParticleButton(context, settings, 'Hearts',
                             ParticleEffect.hearts, Icons.favorite_rounded),
                         _buildParticleButton(context, settings, 'Fireflies',
                             ParticleEffect.fireflies, Icons.lightbulb_rounded),
                         _buildParticleButton(context, settings, 'Confetti',
                             ParticleEffect.confetti, Icons.celebration_rounded),
                         _buildParticleButton(context, settings, 'Orbs',
                             ParticleEffect.coverArtShadowPoints, Icons.circle_rounded),
                         _buildParticleButton(context, settings, 'Custom',
                             ParticleEffect.custom, Icons.edit_rounded),
                       ],
                    ),
                    if (settings.particleEffect == ParticleEffect.custom) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: settings.customParticlePack,
                        decoration: const InputDecoration(
                          labelText: 'Custom particle pack',
                          helperText:
                              'Separate symbols with spaces, like: * + . ♥',
                          prefixIcon: Icon(Icons.auto_awesome_rounded),
                        ),
                        onChanged: settings.setCustomParticlePack,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle(context, 'Video'),
              _buildGlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSwitchRow(
                        context,
                        'Play Video in Background',
                        settings.playVideoBackground,
                        (val) => settings.setPlayVideoBackground(val),
                        settings),
                    const Divider(height: 20, color: Colors.white10),
                    _buildSwitchRow(
                        context,
                        'Cover Art: Show Live Video',
                        settings.videoCoverShowLive,
                        (val) => settings.setVideoCoverShowLive(val),
                        settings),
                    const Divider(height: 20, color: Colors.white10),
                    _buildSwitchRow(
                        context,
                        'Double-Tap Fullscreen',
                        settings.videoDoubleTapFullscreen,
                        (val) => settings.setVideoDoubleTapFullscreen(val),
                        settings),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle(context, 'Navigation Layout'),
              _buildGlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Panel Position',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _buildNavPosButton(context, settings, 'Top',
                            NavPosition.top, Icons.align_vertical_top_rounded),
                        _buildNavPosButton(
                            context,
                            settings,
                            'Down',
                            NavPosition.bottom,
                            Icons.align_vertical_bottom_rounded),
                        _buildNavPosButton(
                            context,
                            settings,
                            'Left',
                            NavPosition.left,
                            Icons.align_horizontal_left_rounded),
                        _buildNavPosButton(
                            context,
                            settings,
                            'Right',
                            NavPosition.right,
                            Icons.align_horizontal_right_rounded),
                      ],
                    ),
                    const Divider(height: 28, color: Colors.white10),
                    _buildSliderRow(context, 'Top Spacing', settings.topMargin,
                        0, 96, (v) => settings.setTopMargin(v)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle(context, 'Theme Mode'),
              _buildGlassCard(
                child: Row(
                  children: [
                    _buildThemeButton(context, settings, 'Light',
                        ThemeMode.light, Icons.wb_sunny_rounded),
                    _buildThemeButton(context, settings, 'Dark', ThemeMode.dark,
                        Icons.nightlight_round),
                    _buildThemeButton(context, settings, 'System',
                        ThemeMode.system, Icons.brightness_auto_rounded),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle(context, 'Library Layout'),
              _buildGlassCard(
                child: Column(
                  children: [
                    Row(
                      children: [
                        _buildViewModeButton(context, settings, 'Grid View',
                            ViewMode.card, Icons.grid_view_rounded),
                        _buildViewModeButton(context, settings, 'List View',
                            ViewMode.list, Icons.format_list_bulleted_rounded),
                      ],
                    ),
                    const Divider(height: 32, color: Colors.white10),
                    _buildSliderRow(
                        context,
                        settings.viewMode == ViewMode.card
                            ? 'Grid Card Size'
                            : 'List Item Height',
                        settings.cardSize,
                        80,
                        300,
                        (v) => settings.setCardSize(v)),
                    const Divider(height: 24, color: Colors.white10),
                    _buildSliderRow(
                        context,
                        'Global Spacing',
                        settings.cardMargins,
                        0,
                        32,
                        (v) => settings.setCardMargins(v)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle(context, 'Visual Style'),
              _buildGlassCard(
                child: Column(
                  children: [
                    _buildSliderRow(
                        context,
                        'Typography Scale',
                        settings.fontSize,
                        10,
                        20,
                        (v) => settings.setFontSize(v)),
                    const Divider(height: 24, color: Colors.white10),
                    _buildSliderRow(
                        context,
                        'Surface Roundness',
                        settings.borderRadius,
                        0,
                        40,
                        (v) => settings.setBorderRadius(v)),
                    const Divider(height: 24, color: Colors.white10),
                    _buildSliderRow(
                        context,
                        'Glass Effect',
                        settings.glassEffect * 100,
                        0,
                        100,
                        (v) => settings.setGlassEffect(v / 100)),
                  ],
                ),
              ),
              const SizedBox(height: 60),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
            color: theme.colorScheme.primary.withOpacity(0.84),
            fontWeight: FontWeight.w900,
            fontSize: 11,
            letterSpacing: 0),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child}) {
    return GlassContainer(
      padding: const EdgeInsets.all(18),
      borderRadius: BorderRadius.circular(16),
      color: null,
      blur: 14,
      child: child,
    );
  }

  Widget _buildSwitchRow(BuildContext context, String label, bool value,
      ValueChanged<bool> onChanged, SettingsModel settings) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
            child: Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: theme.colorScheme.onSurface.withOpacity(0.70)))),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: settings.accentColor,
        ),
      ],
    );
  }

  Widget _buildPresetButton(BuildContext context, SettingsModel settings,
      String label, ThemePreset preset, IconData icon) {
    final isSelected = settings.themePreset == preset;
    final theme = Theme.of(context);
    return Container(
      width: 85,
      margin: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: () => settings.setThemePreset(preset),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colorScheme.primaryContainer.withOpacity(0.64)
                : theme.colorScheme.surfaceContainerHighest.withOpacity(0.30),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: isSelected
                    ? theme.colorScheme.primary.withOpacity(0.32)
                    : theme.colorScheme.outlineVariant.withOpacity(0.5),
                width: 1),
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: isSelected
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                  size: 22),
              const SizedBox(height: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParticleButton(BuildContext context, SettingsModel settings,
      String label, ParticleEffect effect, IconData icon) {
    final isSelected = settings.particleEffect == effect;
    final theme = Theme.of(context);
    return ChoiceChip(
      selected: isSelected,
      avatar: Icon(
        icon,
        size: 16,
        color: isSelected
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurfaceVariant,
      ),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onSelected: (_) => settings.setParticleEffect(effect),
      selectedColor: theme.colorScheme.primaryContainer.withOpacity(0.68),
      backgroundColor:
          theme.colorScheme.surfaceContainerHighest.withOpacity(0.34),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      visualDensity: VisualDensity.compact,
      side: BorderSide(
        color: isSelected
            ? theme.colorScheme.primary.withOpacity(0.34)
            : theme.colorScheme.outlineVariant.withOpacity(0.5),
      ),
      labelStyle: TextStyle(
        color: isSelected
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurface.withOpacity(0.74),
        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
      ),
    );
  }

  Widget _buildParticleWarning(BuildContext context, SettingsModel settings) {
    final theme = Theme.of(context);
    final enabled = settings.particleEffect != ParticleEffect.none;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: enabled
            ? theme.colorScheme.errorContainer.withOpacity(0.42)
            : theme.colorScheme.surfaceContainerHighest.withOpacity(0.30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: enabled
              ? theme.colorScheme.error.withOpacity(0.38)
              : theme.colorScheme.outlineVariant.withOpacity(0.38),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            enabled ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
            size: 20,
            color: enabled
                ? theme.colorScheme.error
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              enabled
                  ? 'Particle effects can decrease performance, increase GPU usage, and use more battery on some devices.'
                  : 'Particle effects are decorative. Enable them only if you want extra motion on the interface.',
              style: TextStyle(
                color: enabled
                    ? theme.colorScheme.onErrorContainer
                    : theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccentColorPicker(BuildContext context, SettingsModel settings) {
    return _AccentColorPicker(settings: settings);
  }

  Widget _buildNavPosButton(BuildContext context, SettingsModel settings,
      String label, NavPosition position, IconData icon) {
    final isSelected = settings.navPosition == position;
    final theme = Theme.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          onTap: () => settings.setNavPosition(position),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.colorScheme.primaryContainer.withOpacity(0.64)
                  : theme.colorScheme.surfaceContainerHighest.withOpacity(0.30),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: isSelected
                      ? theme.colorScheme.primary.withOpacity(0.32)
                      : theme.colorScheme.outlineVariant.withOpacity(0.5),
                  width: 1),
            ),
            child: Column(
              children: [
                Icon(icon,
                    color: isSelected
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurfaceVariant,
                    size: 22),
                const SizedBox(height: 6),
                Text(label,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSliderRow(BuildContext context, String label, double val,
      double min, double max, ValueChanged<double> cb,
      {int? divisions}) {
    final theme = Theme.of(context);
    return _ReleaseSlider(
      label: label,
      value: val,
      min: min,
      max: max,
      divisions: divisions,
      onChangeEnd: cb,
      labelColor: theme.colorScheme.onSurface.withOpacity(0.72),
      valueColor: theme.colorScheme.primary,
    );
  }

  Widget _buildThemeButton(BuildContext context, SettingsModel settings,
      String label, ThemeMode mode, IconData icon) {
    final isSelected = settings.themeMode == mode;
    final theme = Theme.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          onTap: () => settings.setThemeMode(mode),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.colorScheme.primaryContainer.withOpacity(0.64)
                  : theme.colorScheme.surfaceContainerHighest.withOpacity(0.30),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: isSelected
                      ? theme.colorScheme.primary.withOpacity(0.32)
                      : theme.colorScheme.outlineVariant.withOpacity(0.5),
                  width: 1),
            ),
            child: Column(
              children: [
                Icon(icon,
                    color: isSelected
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurfaceVariant,
                    size: 22),
                const SizedBox(height: 6),
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildViewModeButton(BuildContext context, SettingsModel settings,
      String label, ViewMode mode, IconData icon) {
    final isSelected = settings.viewMode == mode;
    final theme = Theme.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: InkWell(
          onTap: () => settings.setViewMode(mode),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.colorScheme.primaryContainer.withOpacity(0.64)
                  : theme.colorScheme.surfaceContainerHighest.withOpacity(0.30),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: isSelected
                      ? theme.colorScheme.primary.withOpacity(0.32)
                      : theme.colorScheme.outlineVariant.withOpacity(0.5),
                  width: 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    color: isSelected
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurfaceVariant,
                    size: 20),
                const SizedBox(width: 10),
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackgroundModeButton(BuildContext context, SettingsModel settings,
      String label, BackgroundMode mode, IconData icon) {
    final isSelected = settings.backgroundMode == mode;
    final theme = Theme.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          onTap: () => settings.setBackgroundMode(mode),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.colorScheme.primaryContainer.withOpacity(0.64)
                  : theme.colorScheme.surfaceContainerHighest.withOpacity(0.30),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: isSelected
                      ? theme.colorScheme.primary.withOpacity(0.32)
                      : theme.colorScheme.outlineVariant.withOpacity(0.5),
                  width: 1),
            ),
            child: Column(
              children: [
                Icon(icon,
                    color: isSelected
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurfaceVariant,
                    size: 22),
                const SizedBox(height: 6),
                Text(label,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReleaseSlider extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChangeEnd;
  final Color labelColor;
  final Color valueColor;

  const _ReleaseSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChangeEnd,
    required this.labelColor,
    required this.valueColor,
    this.divisions,
  });

  @override
  State<_ReleaseSlider> createState() => _ReleaseSliderState();
}

class _ReleaseSliderState extends State<_ReleaseSlider> {
  double? _dragValue;

  @override
  void didUpdateWidget(covariant _ReleaseSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _dragValue = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final value =
        (_dragValue ?? widget.value).clamp(widget.min, widget.max).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(widget.label,
                style: TextStyle(fontSize: 14, color: widget.labelColor)),
            Text(value.toStringAsFixed(0),
                style: TextStyle(
                    color: widget.valueColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
          ],
        ),
        Slider(
          value: value,
          min: widget.min,
          max: widget.max,
          divisions: widget.divisions,
          onChanged: (next) {
            setState(() => _dragValue = next);
            widget.onChangeEnd(next);
          },
          onChangeEnd: (next) {
            widget.onChangeEnd(next);
            setState(() => _dragValue = null);
          },
        ),
      ],
    );
  }
}

class _AccentColorPicker extends StatefulWidget {
  final SettingsModel settings;

  const _AccentColorPicker({required this.settings});

  @override
  State<_AccentColorPicker> createState() => _AccentColorPickerState();
}

class _AccentColorPickerState extends State<_AccentColorPicker> {
  late final TextEditingController _hexController;
  late final TextEditingController _redController;
  late final TextEditingController _greenController;
  late final TextEditingController _blueController;

  static const List<Color> _presets = [
    Color(0xFF14B8A6),
    Color(0xFF38BDF8),
    Color(0xFF6366F1),
    Color(0xFFA855F7),
    Color(0xFFF472B6),
    Color(0xFFF87171),
    Color(0xFFFB923C),
    Color(0xFFFACC15),
    Color(0xFF22C55E),
    Color(0xFF94A3B8),
    Color(0xFFFFFFFF),
    Color(0xFF111827),
  ];

  @override
  void initState() {
    super.initState();
    _hexController = TextEditingController(
      text: _hexFromColor(widget.settings.accentColor),
    );
    _redController = TextEditingController(
      text: widget.settings.accentColor.red.toString(),
    );
    _greenController = TextEditingController(
      text: widget.settings.accentColor.green.toString(),
    );
    _blueController = TextEditingController(
      text: widget.settings.accentColor.blue.toString(),
    );
  }

  @override
  void didUpdateWidget(covariant _AccentColorPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hex = _hexFromColor(widget.settings.accentColor);
    if (_hexController.text.toUpperCase() != hex) {
      _hexController.text = hex;
    }
    _syncRgbControllers(widget.settings.accentColor);
  }

  @override
  void dispose() {
    _hexController.dispose();
    _redController.dispose();
    _greenController.dispose();
    _blueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.settings.accentColor;
    final hsv = HSVColor.fromColor(color);
    final isNarrow = MediaQuery.sizeOf(context).width < 460;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ColorHeader(
          color: color,
          hexController: _hexController,
          onHexSubmitted: _applyHex,
          onApplyHex: () => _applyHex(_hexController.text),
        ),
        const SizedBox(height: 14),
        AspectRatio(
          aspectRatio: isNarrow ? 2.25 : 2.8,
          child: _SaturationValuePicker(
            hsv: hsv,
            onChanged: _setHsv,
          ),
        ),
        const SizedBox(height: 10),
        _HueSlider(
          hue: hsv.hue,
          onChanged: (hue) => _setHsv(hsv.withHue(hue)),
        ),
        const SizedBox(height: 12),
        _RgbNumberRow(
          redController: _redController,
          greenController: _greenController,
          blueController: _blueController,
          onChanged: _applyRgbFromControllers,
        ),
        const Divider(height: 24, color: Colors.white10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in _presets)
              _ColorSwatchButton(
                color: preset,
                selected: preset.value == color.value,
                onTap: () => _setColor(preset),
              ),
          ],
        ),
      ],
    );
  }

  void _applyHex(String raw) {
    final parsed = _colorFromHex(raw);
    if (parsed == null) return;
    _setColor(parsed);
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _setHsv(HSVColor hsv) => _setColor(hsv.toColor());

  void _setColor(Color color) {
    _hexController.text = _hexFromColor(color);
    _syncRgbControllers(color);
    widget.settings.setAccentColor(color);
  }

  void _applyRgbFromControllers() {
    final red = _parseRgbValue(_redController.text);
    final green = _parseRgbValue(_greenController.text);
    final blue = _parseRgbValue(_blueController.text);
    if (red == null || green == null || blue == null) return;
    _setColor(Color.fromARGB(255, red, green, blue));
  }

  void _syncRgbControllers(Color color) {
    void sync(TextEditingController controller, int value) {
      final text = value.toString();
      if (controller.text == text) return;
      controller.text = text;
    }

    sync(_redController, color.red);
    sync(_greenController, color.green);
    sync(_blueController, color.blue);
  }

  int? _parseRgbValue(String raw) {
    if (raw.trim().isEmpty) return null;
    final parsed = int.tryParse(raw.trim());
    if (parsed == null) return null;
    return parsed.clamp(0, 255);
  }

  static String _hexFromColor(Color color) {
    return '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }

  static Color? _colorFromHex(String raw) {
    final cleaned = raw.trim().replaceAll('#', '');
    if (cleaned.length != 6) return null;
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return null;
    return Color(0xFF000000 | value);
  }
}

class _SaturationValuePicker extends StatelessWidget {
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  const _SaturationValuePicker({
    required this.hsv,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final thumb = Offset(
          hsv.saturation * size.width,
          (1 - hsv.value) * size.height,
        );
        return GestureDetector(
          onPanDown: (details) => _pick(details.localPosition, size),
          onPanUpdate: (details) => _pick(details.localPosition, size),
          child: CustomPaint(
            painter: _SaturationValuePainter(hue: hsv.hue),
            child: Stack(
              children: [
                Positioned(
                  left: thumb.dx - 9,
                  top: thumb.dy - 9,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: const [
                        BoxShadow(color: Colors.black45, blurRadius: 5),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _pick(Offset position, Size size) {
    final saturation = (position.dx / size.width).clamp(0.0, 1.0).toDouble();
    final value = (1 - (position.dy / size.height)).clamp(0.0, 1.0).toDouble();
    onChanged(hsv.withSaturation(saturation).withValue(value));
  }
}

class _ColorHeader extends StatelessWidget {
  final Color color;
  final TextEditingController hexController;
  final ValueChanged<String> onHexSubmitted;
  final VoidCallback onApplyHex;

  const _ColorHeader({
    required this.color,
    required this.hexController,
    required this.onHexSubmitted,
    required this.onApplyHex,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withOpacity(0.55),
            ),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.22),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: hexController,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F#]')),
              LengthLimitingTextInputFormatter(7),
            ],
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'HEX',
              hintText: '#14B8A6',
              prefixIcon: Icon(Icons.tag_rounded),
            ),
            onSubmitted: onHexSubmitted,
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Apply color',
          onPressed: onApplyHex,
          icon: const Icon(Icons.check_rounded),
        ),
      ],
    );
  }
}

class _RgbNumberRow extends StatelessWidget {
  final TextEditingController redController;
  final TextEditingController greenController;
  final TextEditingController blueController;
  final VoidCallback onChanged;

  const _RgbNumberRow({
    required this.redController,
    required this.greenController,
    required this.blueController,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _RgbNumberField(
            label: 'R',
            controller: redController,
            color: Colors.redAccent,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _RgbNumberField(
            label: 'G',
            controller: greenController,
            color: Colors.greenAccent,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _RgbNumberField(
            label: 'B',
            controller: blueController,
            color: Colors.lightBlueAccent,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _RgbNumberField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final Color color;
  final VoidCallback onChanged;

  const _RgbNumberField({
    required this.label,
    required this.controller,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      textAlign: TextAlign.center,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(3),
      ],
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        prefixIcon: Padding(
          padding: const EdgeInsets.all(12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withOpacity(0.5),
              ),
            ),
            child: const SizedBox(width: 10, height: 10),
          ),
        ),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 34, minHeight: 34),
      ),
      onChanged: (_) => onChanged(),
      onSubmitted: (_) => onChanged(),
    );
  }
}

class _SaturationValuePainter extends CustomPainter {
  final double hue;

  const _SaturationValuePainter({required this.hue});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final base = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    final paint = Paint();
    paint.shader = LinearGradient(
      colors: [Colors.white, base],
    ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(18)),
      paint,
    );
    paint.shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.transparent, Colors.black],
    ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(18)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _SaturationValuePainter oldDelegate) {
    return oldDelegate.hue != hue;
  }
}

class _HueSlider extends StatelessWidget {
  final double hue;
  final ValueChanged<double> onChanged;

  const _HueSlider({required this.hue, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hue ${hue.round()}',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.72),
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackShape: const _HueTrackShape(),
          ),
          child: Slider(
            min: 0,
            max: 360,
            value: hue,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _HueTrackShape extends RoundedRectSliderTrackShape {
  const _HueTrackShape();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
    Offset? secondaryOffset,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Colors.red,
          Colors.yellow,
          Colors.green,
          Colors.cyan,
          Colors.blue,
          Colors.purple,
          Colors.red,
        ],
      ).createShader(rect);
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)),
      paint,
    );
  }
}

class _ColorSwatchButton extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorSwatchButton({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: 'Use ${_AccentColorPickerState._hexFromColor(color)}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.outlineVariant.withOpacity(0.56),
              width: selected ? 3 : 1,
            ),
            boxShadow: [
              if (selected)
                BoxShadow(
                  color: color.withOpacity(0.28),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
            ],
          ),
          child: selected
              ? Icon(
                  Icons.check_rounded,
                  color: ThemeData.estimateBrightnessForColor(color) ==
                          Brightness.dark
                      ? Colors.white
                      : Colors.black,
                )
              : null,
        ),
      ),
    );
  }
}
