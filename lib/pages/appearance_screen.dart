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
            title: const Text('Appearance', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.5)),
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
              _buildSectionTitle('Theme Presets'),
              _buildGlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Select Atmosphere', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 16),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          _buildPresetButton(context, settings, 'Classic', ThemePreset.classic, Icons.palette_outlined),
                          _buildPresetButton(context, settings, 'Fox', ThemePreset.fox, Icons.auto_awesome_rounded),
                          _buildPresetButton(context, settings, 'Anime', ThemePreset.anime, Icons.face_retouching_natural_rounded),
                          _buildPresetButton(context, settings, 'Azure', ThemePreset.azure, Icons.water_drop_rounded),
                          _buildPresetButton(context, settings, 'Cosmic', ThemePreset.cosmic, Icons.rocket_launch_rounded),
                          _buildPresetButton(context, settings, 'Sunset', ThemePreset.sunset, Icons.wb_twilight_rounded),
                          _buildPresetButton(context, settings, 'Midnight', ThemePreset.midnight, Icons.dark_mode_rounded),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              _buildSectionTitle('Visual Effects'),
              _buildGlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Particle Overlays', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 16),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          _buildParticleButton(context, settings, 'None', ParticleEffect.none, Icons.block_rounded),
                          _buildParticleButton(context, settings, 'Sakura', ParticleEffect.sakura, Icons.filter_vintage_rounded),
                          _buildParticleButton(context, settings, 'Snow', ParticleEffect.snow, Icons.ac_unit_rounded),
                          _buildParticleButton(context, settings, 'Stars', ParticleEffect.stars, Icons.star_rounded),
                          _buildParticleButton(context, settings, 'Bubbles', ParticleEffect.bubbles, Icons.bubble_chart_rounded),
                          _buildParticleButton(context, settings, 'Rain', ParticleEffect.rain, Icons.umbrella_rounded),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              _buildSectionTitle('Navigation Layout'),
              _buildGlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Panel Position', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _buildNavPosButton(context, settings, 'Top', NavPosition.top, Icons.align_vertical_top_rounded),
                        _buildNavPosButton(context, settings, 'Down', NavPosition.bottom, Icons.align_vertical_bottom_rounded),
                        _buildNavPosButton(context, settings, 'Left', NavPosition.left, Icons.align_horizontal_left_rounded),
                        _buildNavPosButton(context, settings, 'Right', NavPosition.right, Icons.align_horizontal_right_rounded),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              _buildSectionTitle('Theme Mode'),
              _buildGlassCard(
                child: Row(
                  children: [
                    _buildThemeButton(context, settings, 'Light', ThemeMode.light, Icons.wb_sunny_rounded),
                    _buildThemeButton(context, settings, 'Dark', ThemeMode.dark, Icons.nightlight_round),
                    _buildThemeButton(context, settings, 'System', ThemeMode.system, Icons.brightness_auto_rounded),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              _buildSectionTitle('Library Layout'),
              _buildGlassCard(
                child: Column(
                  children: [
                    Row(
                      children: [
                        _buildViewModeButton(context, settings, 'Grid View', ViewMode.card, Icons.grid_view_rounded),
                        _buildViewModeButton(context, settings, 'List View', ViewMode.list, Icons.format_list_bulleted_rounded),
                      ],
                    ),
                    const Divider(height: 32, color: Colors.white10),
                    _buildSliderRow(
                      context, 
                      settings.viewMode == ViewMode.card ? 'Grid Card Size' : 'List Item Height', 
                      settings.cardSize, 80, 300, 
                      (v) => settings.setCardSize(v)
                    ),
                    const Divider(height: 24, color: Colors.white10),
                    _buildSliderRow(context, 'Global Spacing', settings.cardMargins, 0, 32, (v) => settings.setCardMargins(v)),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              _buildSectionTitle('Visual Style'),
              _buildGlassCard(
                child: Column(
                  children: [
                    _buildSliderRow(context, 'Typography Scale', settings.fontSize, 10, 20, (v) => settings.setFontSize(v)),
                    const Divider(height: 24, color: Colors.white10),
                    _buildSliderRow(context, 'Surface Roundness', settings.borderRadius, 0, 40, (v) => settings.setBorderRadius(v)),
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

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Colors.teal.withOpacity(0.8), 
          fontWeight: FontWeight.w900, 
          fontSize: 11, 
          letterSpacing: 2.0
        ),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child}) {
    return GlassContainer(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(24),
      color: Colors.white.withOpacity(0.03),
      child: child,
    );
  }

  Widget _buildPresetButton(BuildContext context, SettingsModel settings, String label, ThemePreset preset, IconData icon) {
    final isSelected = settings.themePreset == preset;
    return Container(
      width: 85,
      margin: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: () => settings.setThemePreset(preset),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? settings.accentColor.withOpacity(0.12) : Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isSelected ? settings.accentColor.withOpacity(0.5) : Colors.white10, width: 1.5),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? settings.accentColor : Colors.white38, size: 22),
              const SizedBox(height: 6),
              Text(label, style: TextStyle(fontSize: 10, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? settings.accentColor : Colors.white38)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParticleButton(BuildContext context, SettingsModel settings, String label, ParticleEffect effect, IconData icon) {
    final isSelected = settings.particleEffect == effect;
    return Container(
      width: 85,
      margin: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: () => settings.setParticleEffect(effect),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? settings.accentColor.withOpacity(0.12) : Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isSelected ? settings.accentColor.withOpacity(0.5) : Colors.white10, width: 1.5),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? settings.accentColor : Colors.white38, size: 22),
              const SizedBox(height: 6),
              Text(label, style: TextStyle(fontSize: 10, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? settings.accentColor : Colors.white38)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavPosButton(BuildContext context, SettingsModel settings, String label, NavPosition position, IconData icon) {
    final isSelected = settings.navPosition == position;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          onTap: () => settings.setNavPosition(position),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: isSelected ? settings.accentColor.withOpacity(0.12) : Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isSelected ? settings.accentColor.withOpacity(0.5) : Colors.white10, width: 1.5),
            ),
            child: Column(
              children: [
                Icon(icon, color: isSelected ? settings.accentColor : Colors.white38, size: 22),
                const SizedBox(height: 6),
                Text(label, style: TextStyle(fontSize: 10, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? settings.accentColor : Colors.white38)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSliderRow(BuildContext context, String label, double val, double min, double max, ValueChanged<double> cb, {int? divisions}) {
    final settings = Provider.of<SettingsModel>(context, listen: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 14, color: Colors.white70)),
            Text(val.toStringAsFixed(0), style: TextStyle(color: settings.accentColor, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: settings.accentColor,
            inactiveTrackColor: Colors.white12,
            thumbColor: settings.accentColor,
          ),
          child: Slider(
            value: val.clamp(min, max), min: min, max: max, divisions: divisions, 
            onChanged: cb,
          ),
        ),
      ],
    );
  }

  Widget _buildThemeButton(BuildContext context, SettingsModel settings, String label, ThemeMode mode, IconData icon) {
    final isSelected = settings.themeMode == mode;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          onTap: () => settings.setThemeMode(mode),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: isSelected ? settings.accentColor.withOpacity(0.12) : Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isSelected ? settings.accentColor.withOpacity(0.5) : Colors.white10, width: 1.5),
            ),
            child: Column(
              children: [
                Icon(icon, color: isSelected ? settings.accentColor : Colors.white38, size: 22),
                const SizedBox(height: 6),
                Text(label, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? settings.accentColor : Colors.white38)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildViewModeButton(BuildContext context, SettingsModel settings, String label, ViewMode mode, IconData icon) {
    final isSelected = settings.viewMode == mode;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: InkWell(
          onTap: () => settings.setViewMode(mode),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: isSelected ? settings.accentColor.withOpacity(0.15) : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isSelected ? settings.accentColor : Colors.white10, width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: isSelected ? settings.accentColor : Colors.white54, size: 20),
                const SizedBox(width: 10),
                Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isSelected ? settings.accentColor : Colors.white54)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
