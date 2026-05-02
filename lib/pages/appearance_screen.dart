import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/settings_model.dart';
import '../widgets/glass_container.dart';

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsModel>(
      builder: (context, settings, child) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('Appearance', style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            children: [
              _buildSectionTitle('Theme & Colors'),
              _buildGlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('App Theme', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildThemeButton(context, settings, 'Light', ThemeMode.light, Icons.light_mode_rounded),
                        _buildThemeButton(context, settings, 'Dark', ThemeMode.dark, Icons.dark_mode_rounded),
                        _buildThemeButton(context, settings, 'System', ThemeMode.system, Icons.settings_suggest_rounded),
                      ],
                    ),
                    const Divider(height: 32, color: Colors.white10),
                    const Text('Accent Color', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 50,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _buildColorOption(context, settings, Colors.teal),
                          _buildColorOption(context, settings, Colors.blue),
                          _buildColorOption(context, settings, Colors.purple),
                          _buildColorOption(context, settings, Colors.red),
                          _buildColorOption(context, settings, Colors.orange),
                          _buildColorOption(context, settings, Colors.pink),
                          _buildColorOption(context, settings, Colors.green),
                          _buildColorOption(context, settings, Colors.amber),
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
                    const Text('Panel Position', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
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

              _buildSectionTitle('Layout & View'),
              _buildGlassCard(
                child: Column(
                  children: [
                    const Text('View Mode', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildViewModeButton(context, settings, 'Cards', ViewMode.card, Icons.grid_view_rounded),
                        _buildViewModeButton(context, settings, 'List', ViewMode.list, Icons.view_list_rounded),
                      ],
                    ),
                    const Divider(height: 32, color: Colors.white10),
                    SwitchListTile(
                      title: const Text('Auto Card Layout'),
                      subtitle: const Text('Automatically fit cards to screen', style: TextStyle(fontSize: 11)),
                      value: settings.useAutoCardCount,
                      onChanged: (v) => settings.setUseAutoCardCount(v),
                      activeColor: settings.accentColor,
                      contentPadding: EdgeInsets.zero,
                    ),
                    const Divider(height: 24, color: Colors.white10),
                    if (settings.useAutoCardCount)
                      _buildSliderRow(context, 'Preferred Card Size', settings.cardSize, 80, 300, (v) => settings.setCardSize(v))
                    else
                      _buildSliderRow(context, 'Cards per Row', settings.cardCount.toDouble(), 1, 10, (v) => settings.setCardCount(v.toInt()), divisions: 9),
                    const Divider(height: 24, color: Colors.white10),
                    _buildSliderRow(context, 'Spacing / Margins', settings.cardMargins, 0, 32, (v) => settings.setCardMargins(v)),
                    const Divider(height: 24, color: Colors.white10),
                    _buildSliderRow(context, 'Top Margin (Status Bar)', settings.topMargin, 0, 200, (v) => settings.setTopMargin(v)),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              _buildSectionTitle('Typography & Shapes'),
              _buildGlassCard(
                child: Column(
                  children: [
                    _buildSliderRow(context, 'Global Font Size', settings.fontSize, 10, 24, (v) => settings.setFontSize(v)),
                    const Divider(height: 24, color: Colors.white10),
                    _buildSliderRow(context, 'Corner Radius', settings.borderRadius, 0, 32, (v) => settings.setBorderRadius(v)),
                  ],
                ),
              ),
              const SizedBox(height: 40),
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
        style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.5),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child}) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(20),
      child: child,
    );
  }

  Widget _buildSliderRow(BuildContext context, String label, double val, double min, double max, ValueChanged<double> cb, {int? divisions}) {
    final settings = Provider.of<SettingsModel>(context, listen: false);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 14)),
              Text(val.toStringAsFixed(0), style: TextStyle(color: settings.accentColor, fontWeight: FontWeight.bold)),
            ],
          ),
          Slider(
            value: val, min: min, max: max, divisions: divisions, onChanged: cb,
            activeColor: settings.accentColor,
            inactiveColor: Colors.white12,
          ),
        ],
      ),
    );
  }

  Widget _buildThemeButton(BuildContext context, SettingsModel settings, String label, ThemeMode mode, IconData icon) {
    final isSelected = settings.themeMode == mode;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          onTap: () => settings.setThemeMode(mode),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? settings.accentColor.withOpacity(0.15) : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isSelected ? settings.accentColor : Colors.white12, width: 1),
            ),
            child: Column(
              children: [
                Icon(icon, color: isSelected ? settings.accentColor : Colors.white60, size: 20),
                const SizedBox(height: 4),
                Text(label, style: TextStyle(fontSize: 11, color: isSelected ? settings.accentColor : Colors.white60)),
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
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? settings.accentColor.withOpacity(0.15) : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isSelected ? settings.accentColor : Colors.white12, width: 1),
            ),
            child: Column(
              children: [
                Icon(icon, color: isSelected ? settings.accentColor : Colors.white60, size: 20),
                const SizedBox(height: 4),
                Text(label, style: TextStyle(fontSize: 10, color: isSelected ? settings.accentColor : Colors.white60)),
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
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          onTap: () => settings.setViewMode(mode),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? settings.accentColor.withOpacity(0.15) : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isSelected ? settings.accentColor : Colors.white12, width: 1),
            ),
            child: Column(
              children: [
                Icon(icon, color: isSelected ? settings.accentColor : Colors.white60, size: 20),
                const SizedBox(height: 4),
                Text(label, style: TextStyle(fontSize: 11, color: isSelected ? settings.accentColor : Colors.white60)),
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
        width: 38, height: 38, margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: color, shape: BoxShape.circle,
          border: isSelected ? Border.all(color: Colors.white, width: 2) : null,
          boxShadow: isSelected ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 6, spreadRadius: 1)] : null,
        ),
        child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
      ),
    );
  }
}
