import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/settings_model.dart';
import '../services/music_service.dart';
import '../widgets/glass_container.dart';
import '../pages/appearance_screen.dart';
import '../widgets/audio_effects_menu.dart';
import 'package:file_picker/file_picker.dart';

class SettingsDrawer extends StatelessWidget {
  const SettingsDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final musicService = context.watch<MusicService>();
    final settings = context.watch<SettingsModel>();
    final theme = Theme.of(context);

    return Container(
      width: 320,
      height: double.infinity,
      color: Colors.transparent,
      child: GlassContainer(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(32),
          bottomLeft: Radius.circular(32),
        ),
        blur: 20,
        color: theme.colorScheme.surface.withOpacity(0.7),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Settings',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _buildSectionTitle('Audio'),
                    _buildListTile(
                      icon: Icons.equalizer_rounded,
                      title: 'Audio Effects',
                      subtitle: 'EQ, Pitch, Reverb',
                      onTap: () {
                        Navigator.pop(context);
                        showAudioEffectsMenu(context);
                      },
                    ),
                    const SizedBox(height: 24),
                    _buildSectionTitle('Interface'),
                    _buildListTile(
                      icon: Icons.palette_rounded,
                      title: 'Appearance',
                      subtitle: 'Theme, Layout, Colors',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AppearanceScreen()),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    _buildSectionTitle('Playback'),
                    SwitchListTile(
                      title: const Text('Remember playback', style: TextStyle(fontSize: 14)),
                      value: musicService.rememberPlayback,
                      activeColor: settings.accentColor,
                      onChanged: (v) => musicService.setRememberPlayback(v),
                    ),
                    const SizedBox(height: 24),
                    _buildSectionTitle('Library'),
                    ...settings.musicSourcePaths.map((path) => _buildPathTile(context, settings, path)),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () => _addPath(context, settings),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add Folder'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: settings.accentColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildSectionTitle('System'),
                    _buildListTile(
                      icon: Icons.refresh_rounded,
                      title: 'Update Library',
                      subtitle: 'Rescan music folders',
                      onTap: () => musicService.loadSystemMusic(
                        customPaths: settings.musicSourcePaths.isEmpty ? null : settings.musicSourcePaths,
                        clearExisting: true,
                      ),
                    ),
                    _buildListTile(
                      icon: Icons.delete_sweep_rounded,
                      title: 'Clear Cache',
                      subtitle: 'Delete artwork cache',
                      onTap: () => musicService.clearCache(),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Colors.teal,
          fontWeight: FontWeight.bold,
          fontSize: 12,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildListTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.teal),
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _buildPathTile(BuildContext context, SettingsModel settings, String path) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder_open_rounded, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              path,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline_rounded, size: 16, color: Colors.redAccent),
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
