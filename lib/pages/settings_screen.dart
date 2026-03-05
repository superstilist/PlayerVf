import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../models/settings_model.dart';
import '../services/music_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final musicService = context.read<MusicService>();
    final theme = Theme.of(context);
    
    return Consumer<SettingsModel>(
      builder: (context, settings, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            children: [
              _buildSectionTitle('Theme & Style'),
              _buildSettingCard(
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
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle('Layout & Appearance'),
              _buildSettingCard(
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Auto Card Layout'),
                      subtitle: Text('Automatically fit cards to screen', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 12)),
                      value: settings.useAutoCardCount,
                      onChanged: (v) => settings.setUseAutoCardCount(v),
                      activeColor: Colors.teal,
                      contentPadding: EdgeInsets.zero,
                    ),
                    const Divider(height: 24),
                    if (settings.useAutoCardCount)
                      _buildSliderRow(
                        context,
                        'Preferred Size',
                        settings.cardSize,
                        80, 300,
                        (v) => settings.setCardSize(v),
                      )
                    else
                      _buildSliderRow(
                        context,
                        'Cards per Row',
                        settings.cardCount.toDouble(),
                        1, 10,
                        (v) => settings.setCardCount(v.toInt()),
                        divisions: 9,
                      ),
                    const Divider(height: 24),
                    _buildSliderRow(
                      context,
                      'Spacing',
                      settings.cardMargins,
                      0, 32,
                      (v) => settings.setCardMargins(v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle('Music Library'),
              _buildSettingCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Storage Locations', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ...settings.musicSourcePaths.map((path) => _buildPathTile(context, settings, path)),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () => _addPath(context, settings),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add Folder'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 45),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle('Maintenance'),
              _buildSettingCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Cache & Optimization', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('Clear cached cover art and metadata if images are not showing correctly.', 
                      style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 12)),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => _showClearCacheDialog(context, musicService),
                      icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
                      label: const Text('Clear Cache', style: TextStyle(color: Colors.redAccent)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.redAccent),
                        minimumSize: const Size(double.infinity, 45),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              Center(
                child: Text('Version 1.2.0', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4), fontSize: 12)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildThemeButton(BuildContext context, SettingsModel settings, String label, ThemeMode mode, IconData icon) {
    final isSelected = settings.themeMode == mode;
    final theme = Theme.of(context);
    
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          onTap: () => settings.setThemeMode(mode),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? Colors.teal.withOpacity(0.2) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? Colors.teal : theme.colorScheme.onSurface.withOpacity(0.1),
                width: 1.5,
              ),
            ),
            child: Column(
              children: [
                Icon(icon, color: isSelected ? Colors.teal : theme.colorScheme.onSurface.withOpacity(0.6)),
                const SizedBox(height: 4),
                Text(label, style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? Colors.teal : theme.colorScheme.onSurface.withOpacity(0.6),
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showClearCacheDialog(BuildContext context, MusicService musicService) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cache?'),
        content: const Text('This will delete all cached cover art and metadata. The app will need to re-scan your music library.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              musicService.clearCache();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cache cleared. Re-scanning...'), backgroundColor: Colors.teal),
              );
            },
            child: const Text('Clear', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
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

  Widget _buildSettingCard({required Widget child}) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
            borderRadius: BorderRadius.circular(16),
          ),
          child: child,
        );
      }
    );
  }

  Widget _buildSliderRow(BuildContext context, String label, double val, double min, double max, ValueChanged<double> cb, {int? divisions}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7), fontSize: 14)),
              Text(val.toStringAsFixed(0), style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold)),
            ],
          ),
          Slider(
            value: val,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: cb,
            activeColor: Colors.teal,
            inactiveColor: theme.colorScheme.onSurface.withOpacity(0.1),
          ),
        ],
      ),
    );
  }

  Widget _buildPathTile(BuildContext context, SettingsModel settings, String path) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder_open_rounded, size: 20, color: Colors.grey),
          const SizedBox(width: 12),
          Expanded(child: Text(path, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7), fontSize: 13), overflow: TextOverflow.ellipsis)),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline_rounded, size: 20, color: Colors.redAccent),
            onPressed: () => settings.removeMusicPath(path),
          ),
        ],
      ),
    );
  }

  Future<void> _addPath(BuildContext context, SettingsModel settings) async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path != null) settings.addMusicPath(path);
  }
}
