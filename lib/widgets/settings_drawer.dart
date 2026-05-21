import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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

    return Container(
      width: 320,
      height: double.infinity,
      color: Colors.transparent,
      child: GlassContainer(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          bottomLeft: Radius.circular(18),
        ),
        blur: 6,
        color: null,
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
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
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
                    _buildSectionTitle(context, 'Audio'),
                    _buildListTile(
                      context: context,
                      icon: Icons.equalizer_rounded,
                      title: 'Audio Effects',
                      onTap: () {
                        Navigator.pop(context);
                        showAudioEffectsMenu(context);
                      },
                    ),
                    const SizedBox(height: 24),
                    _buildSectionTitle(context, 'Interface'),
                    _buildListTile(
                      context: context,
                      icon: Icons.palette_rounded,
                      title: 'Appearance',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const AppearanceScreen()),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    _buildSectionTitle(context, 'Playback'),
                    SwitchListTile(
                      title: const Text('Remember playback',
                          style: TextStyle(fontSize: 14)),
                      value: musicService.rememberPlayback,
                      activeColor: settings.accentColor,
                      onChanged: (v) => musicService.setRememberPlayback(v),
                    ),
                    const SizedBox(height: 24),
                    _buildSectionTitle(context, 'Sharing'),
                    SwitchListTile(
                      title: const Text('Back up before sync',
                          style: TextStyle(fontSize: 14)),
                      subtitle: const Text('Save library backup on import'),
                      value: settings.shareSyncBackupsEnabled,
                      activeColor: settings.accentColor,
                      onChanged: settings.setShareSyncBackupsEnabled,
                    ),
                    const SizedBox(height: 24),
                    _buildSectionTitle(context, 'Library'),
                    ...settings.musicSourcePaths
                        .map((path) => _buildPathTile(context, settings, path)),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () =>
                          _addPath(context, settings, musicService),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add Folder'),
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildSectionTitle(context, 'YouTube Music'),
                    _buildListTile(
                      context: context,
                      icon: Icons.download_rounded,
                      title: 'Download Folder',
                      subtitle: settings.youtubeMusicDownloadPath.isEmpty
                          ? 'Using default folder'
                          : settings.youtubeMusicDownloadPath,
                      onTap: () => _setYoutubeDownloadPath(
                          context, settings, musicService),
                    ),
                    const SizedBox(height: 24),
                    _buildSectionTitle(context, 'System'),
                    _buildListTile(
                      context: context,
                      icon: Icons.refresh_rounded,
                      title: 'Update Library',
                      onTap: () => musicService.loadSystemMusic(
                        customPaths: settings.musicSourcePaths.isEmpty
                            ? null
                            : settings.musicSourcePaths,
                        clearExisting: true,
                      ),
                    ),
                    _buildListTile(
                      context: context,
                      icon: Icons.delete_sweep_rounded,
                      title: 'Clear Cache',
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

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildListTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: const TextStyle(fontSize: 12)),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _buildPathTile(
      BuildContext context, SettingsModel settings, String path) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withOpacity(0.32),
        borderRadius: BorderRadius.circular(12),
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
            icon: const Icon(Icons.remove_circle_outline_rounded,
                size: 16, color: Colors.redAccent),
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
      _showFolderImportMessage(context, count);
      return;
    }

    final path = await FilePicker.platform.getDirectoryPath();
    if (path != null) settings.addMusicPath(path);
  }

  Future<void> _setYoutubeDownloadPath(
    BuildContext context,
    SettingsModel settings,
    MusicService musicService,
  ) async {
    if (kIsWeb) {
      _showWebFolderMessage(context);
      return;
    }

    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null || path.isEmpty) return;
    await settings.setYoutubeMusicDownloadPath(path);
    await musicService.loadSystemMusic(
        customPaths: settings.musicSourcePaths, clearExisting: true);
  }

  void _showWebFolderMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content:
            Text('Download folder selection is available in the desktop app.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showFolderImportMessage(BuildContext context, int count) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          count == 0
              ? 'No supported media files were imported.'
              : 'Imported $count media file${count == 1 ? '' : 's'} from the folder.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
