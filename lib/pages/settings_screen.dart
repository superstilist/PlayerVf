import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../models/settings_model.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsModel>(
      builder: (context, settings, child) {
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            children: [
              _buildSectionTitle('Layout & Appearance'),
              _buildSettingCard(
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Auto Card Layout', style: TextStyle(color: Colors.white)),
                      subtitle: Text('Automatically fit cards to screen', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                      value: settings.useAutoCardCount,
                      onChanged: (v) => settings.setUseAutoCardCount(v),
                      activeColor: Colors.teal,
                      contentPadding: EdgeInsets.zero,
                    ),
                    const Divider(color: Colors.white10),
                    if (settings.useAutoCardCount)
                      _buildSliderRow(
                        'Preferred Size',
                        settings.cardSize,
                        80, 300,
                        (v) => settings.setCardSize(v),
                      )
                    else
                      _buildSliderRow(
                        'Cards per Row',
                        settings.cardCount.toDouble(),
                        1, 10,
                        (v) => settings.setCardCount(v.toInt()),
                        divisions: 9,
                      ),
                    const Divider(color: Colors.white10),
                    _buildSliderRow(
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
                    const Text('Storage Locations', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
              const SizedBox(height: 40),
              Center(
                child: Text('Version 1.2.0', style: TextStyle(color: Colors.grey[700], fontSize: 12)),
              ),
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

  Widget _buildSettingCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }

  Widget _buildSliderRow(String label, double val, double min, double max, ValueChanged<double> cb, {int? divisions}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
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
            inactiveColor: Colors.white10,
          ),
        ],
      ),
    );
  }

  Widget _buildPathTile(BuildContext context, SettingsModel settings, String path) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder_open_rounded, size: 20, color: Colors.grey),
          const SizedBox(width: 12),
          Expanded(child: Text(path, style: const TextStyle(color: Colors.white70, fontSize: 13), overflow: TextOverflow.ellipsis)),
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
