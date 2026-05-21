import 'package:flutter/material.dart';
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
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('Appearance',
                style:
                    TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0)),
            backgroundColor: Colors.transparent,
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
                      ],
                    ),
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
    final colors = <Color>[
      const Color(0xFF14B8A6),
      const Color(0xFF38BDF8),
      const Color(0xFF6366F1),
      const Color(0xFFA855F7),
      const Color(0xFFF472B6),
      const Color(0xFFF87171),
      const Color(0xFFFB923C),
      const Color(0xFFFACC15),
      const Color(0xFF22C55E),
      const Color(0xFF94A3B8),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: colors
              .map((color) => _buildColorButton(context, settings, color))
              .toList(),
        ),
        const Divider(height: 28, color: Colors.white10),
        _buildColorChannelSlider(context, settings, 'Red', 0),
        _buildColorChannelSlider(context, settings, 'Green', 1),
        _buildColorChannelSlider(context, settings, 'Blue', 2),
      ],
    );
  }

  Widget _buildColorChannelSlider(
      BuildContext context, SettingsModel settings, String label, int channel) {
    final color = settings.accentColor;
    final values = [color.red, color.green, color.blue];
    return _buildSliderRow(
      context,
      label,
      values[channel].toDouble(),
      0,
      255,
      (value) {
        values[channel] = value.round().clamp(0, 255);
        settings.setAccentColor(
          Color.fromARGB(255, values[0], values[1], values[2]),
        );
      },
      divisions: 255,
    );
  }

  Widget _buildColorButton(
      BuildContext context, SettingsModel settings, Color color) {
    final isSelected = settings.accentColor.value == color.value;
    final theme = Theme.of(context);

    return Tooltip(
      message: 'Use color',
      child: InkWell(
        onTap: () => settings.setAccentColor(color),
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.outlineVariant.withOpacity(0.56),
              width: isSelected ? 3 : 1,
            ),
            boxShadow: [
              if (isSelected)
                BoxShadow(
                  color: color.withOpacity(0.26),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
            ],
          ),
          child: isSelected
              ? Icon(Icons.check_rounded,
                  color: ThemeData.estimateBrightnessForColor(color) ==
                          Brightness.dark
                      ? Colors.white
                      : Colors.black,
                  size: 22)
              : null,
        ),
      ),
    );
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
          onChanged: (next) => setState(() => _dragValue = next),
          onChangeEnd: (next) {
            widget.onChangeEnd(next);
            setState(() => _dragValue = null);
          },
        ),
      ],
    );
  }
}
