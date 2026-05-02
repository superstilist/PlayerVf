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
              _buildSectionTitle('Theme & Accent'),
              _buildGlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Brightness Mode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _buildThemeButton(context, settings, 'Light', ThemeMode.light, Icons.wb_sunny_rounded),
                        _buildThemeButton(context, settings, 'Dark', ThemeMode.dark, Icons.nightlight_round),
                        _buildThemeButton(context, settings, 'System', ThemeMode.system, Icons.brightness_auto_rounded),
                      ],
                    ),
                    const Divider(height: 40, color: Colors.white10),
                    const Text('Accent Color', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 54,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        children: [
                          _buildColorOption(context, settings, Colors.teal),
                          _buildColorOption(context, settings, const Color(0xFF6366f1)), // Indigo
                          _buildColorOption(context, settings, const Color(0xFFec4899)), // Pink
                          _buildColorOption(context, settings, const Color(0xFFf59e0b)), // Amber
                          _buildColorOption(context, settings, const Color(0xFF10b981)), // Emerald
                          _buildColorOption(context, settings, const Color(0xFFef4444)), // Red
                          _buildColorOption(context, settings, const Color(0xFF8b5cf6)), // Violet
                          _buildColorOption(context, settings, const Color(0xFF06b6d4)), // Cyan
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              _buildSectionTitle('Library Layout'),
              _buildGlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Navigation Position', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _buildNavPosButton(context, settings, 'Top', NavPosition.top, Icons.keyboard_arrow_up_rounded),
                        _buildNavPosButton(context, settings, 'Bottom', NavPosition.bottom, Icons.keyboard_arrow_down_rounded),
                        _buildNavPosButton(context, settings, 'Left', NavPosition.left, Icons.keyboard_arrow_left_rounded),
                        _buildNavPosButton(context, settings, 'Right', NavPosition.right, Icons.keyboard_arrow_right_rounded),
                      ],
                    ),
                    const Divider(height: 40, color: Colors.white10),
                    const Text('Default View', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _buildViewModeButton(context, settings, 'Grid View', ViewMode.card, Icons.grid_view_rounded),
                        _buildViewModeButton(context, settings, 'List View', ViewMode.list, Icons.format_list_bulleted_rounded),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              _buildSectionTitle('Sizing & Optimization'),
              _buildGlassCard(
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Dynamic Grid Layout', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      subtitle: const Text('Scales music cards based on window size', style: TextStyle(fontSize: 11, color: Colors.white38)),
                      value: settings.useAutoCardCount,
                      onChanged: (v) => settings.setUseAutoCardCount(v),
                      activeColor: settings.accentColor,
                      contentPadding: EdgeInsets.zero,
                    ),
                    const Divider(height: 32, color: Colors.white10),
                    
                    // Unified Size Control
                    _buildSliderRow(
                      context, 
                      settings.viewMode == ViewMode.card ? 'Grid Card Size' : 'List Item Height', 
                      settings.cardSize, 80, 300, 
                      (v) => settings.setCardSize(v)
                    ),
                    
                    if (!settings.useAutoCardCount && settings.viewMode == ViewMode.card) ...[
                       const Divider(height: 24, color: Colors.white10),
                       _buildSliderRow(context, 'Cards per Row', settings.cardCount.toDouble(), 1, 10, (v) => settings.setCardCount(v.toInt()), divisions: 9),
                    ],
                    
                    const Divider(height: 24, color: Colors.white10),
                    _buildSliderRow(context, 'Global Spacing', settings.cardMargins, 0, 32, (v) => settings.setCardMargins(v)),
                    const Divider(height: 24, color: Colors.white10),
                    _buildSliderRow(context, 'Top Safe Area', settings.topMargin, 0, 120, (v) => settings.setTopMargin(v)),
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
            value: val.clamp(min, max), 
            min: min, 
            max: max, 
            divisions: divisions, 
            onChanged: (v) {
              cb(v);
            },
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

  Widget _buildNavPosButton(BuildContext context, SettingsModel settings, String label, NavPosition position, IconData icon) {
    final isSelected = settings.navPosition == position;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          onTap: () => settings.setNavPosition(position),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: isSelected ? settings.accentColor.withOpacity(0.12) : Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isSelected ? settings.accentColor.withOpacity(0.5) : Colors.white10, width: 1.5),
            ),
            child: Column(
              children: [
                Icon(icon, color: isSelected ? settings.accentColor : Colors.white38, size: 20),
                const SizedBox(height: 6),
                Text(label, style: TextStyle(fontSize: 10, color: isSelected ? settings.accentColor : Colors.white38)),
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

  Widget _buildColorOption(BuildContext context, SettingsModel settings, Color color) {
    final isSelected = settings.accentColor.value == color.value;
    return GestureDetector(
      onTap: () => settings.setAccentColor(color),
      child: Container(
        width: 44, height: 44, margin: const EdgeInsets.only(right: 14),
        decoration: BoxDecoration(
          color: color, shape: BoxShape.circle,
          border: isSelected ? Border.all(color: Colors.white, width: 3) : Border.all(color: Colors.white10, width: 1),
          boxShadow: isSelected ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 10, spreadRadius: 2)] : null,
        ),
        child: isSelected ? const Icon(Icons.check_rounded, color: Colors.white, size: 22) : null,
      ),
    );
  }
}
