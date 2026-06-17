import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/settings_model.dart';
import '../services/app_directories.dart';
import '../services/music_service.dart';
import '../services/safe_file_picker.dart';
import '../widgets/audio_effects_menu.dart';
import '../widgets/glass_container.dart';
import 'appearance_screen.dart';
import 'library_stats_screen.dart';
import 'playback_settings_screen.dart';
import 'web_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final musicService = context.watch<MusicService>();
    final theme = Theme.of(context);

    return Consumer<SettingsModel>(
      builder: (context, settings, child) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('Settings',
                style: TextStyle(fontWeight: FontWeight.bold)),
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
              _buildSectionTitle('Audio'),
              _buildGlassSettingCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.equalizer_rounded,
                      color: theme.colorScheme.primary),
                  title: const Text('Audio Effects'),
                  trailing:
                      const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onTap: () => showAudioEffectsMenu(context),
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle('Interface'),
              _buildGlassSettingCard(
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.palette_rounded,
                          color: settings.accentColor),
                      title: const Text('Appearance'),
                      trailing:
                          const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const AppearanceScreen())),
                    ),
                    const Divider(height: 20),
                    _buildPerformanceModeRow(context, settings),
                    const SizedBox(height: 18),
                    _buildBackgroundBlurRow(context, settings),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle('Playback'),
              _buildGlassSettingCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.play_circle_rounded,
                      color: theme.colorScheme.primary),
                  title: const Text('Playback'),
                  subtitle: const Text(
                      'Decoders, lyrics, resume, seek step, and song gap'),
                  trailing:
                      const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PlaybackSettingsScreen(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle('Video'),
              _buildVideoSettingsCard(context, settings, musicService, theme),
              const SizedBox(height: 24),
              _buildSectionTitle('Recording'),
              _buildRecordingSettingsCard(context, settings, theme),
              const SizedBox(height: 24),
              _buildSectionTitle('Web'),
              _buildGlassSettingCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.language_rounded,
                      color: theme.colorScheme.primary),
                  title: const Text('Web & YouTube'),
                  subtitle: const Text(
                      'YouTube downloads, stream cache, and web folder import'),
                  trailing:
                      const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const WebSettingsScreen(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle('Sharing'),
              _buildGlassSettingCard(
                child: SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  activeColor: settings.accentColor,
                  title: const Text('Back up before sync'),
                  subtitle: const Text(
                    'Save a library backup before importing shared songs.',
                  ),
                  value: settings.shareSyncBackupsEnabled,
                  onChanged: settings.setShareSyncBackupsEnabled,
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle('Music Library'),
              _buildGlassSettingCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.auto_graph_rounded,
                          color: theme.colorScheme.primary),
                      title: const Text('Mini Stats'),
                      subtitle: const Text(
                          'Library totals, likes, genres, artists, years, and AI signals'),
                      trailing:
                          const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LibraryStatsScreen(),
                        ),
                      ),
                    ),
                    const Divider(height: 22),
                    const Text('Storage Locations',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ...settings.musicSourcePaths
                        .map((path) => _buildPathTile(context, settings, path)),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () =>
                          _addPath(context, settings, musicService),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add Folder'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle('Maintenance'),
              _buildGlassSettingCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Library Tools',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () =>
                          _updateAllMusic(context, settings, musicService),
                      icon: const Icon(Icons.system_update_alt_rounded),
                      label: const Text('Update Library'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: musicService.isLoadingSystemMusic
                          ? null
                          : () => _showClearCacheDialog(context, musicService),
                      icon: const Icon(Icons.delete_sweep_rounded,
                          color: Colors.redAccent),
                      label: const Text('Clear Cache',
                          style: TextStyle(color: Colors.redAccent)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.redAccent),
                        minimumSize: const Size(double.infinity, 45),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
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

  void _updateAllMusic(
      BuildContext context, SettingsModel settings, MusicService musicService) {
    final paths =
        settings.musicSourcePaths.isEmpty ? null : settings.musicSourcePaths;
    musicService.loadSystemMusic(customPaths: paths, clearExisting: true);
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
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      musicService.clearCache();
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white),
                    child: const Text('Clear'),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          color: ThemeData.estimateBrightnessForColor(Colors.teal) ==
                  Brightness.dark
              ? Colors.teal.shade300
              : Colors.teal.shade700,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildGlassSettingCard({required Widget child}) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(16),
      blur: 14,
      child: child,
    );
  }

  Widget _buildPathTile(
      BuildContext context, SettingsModel settings, String path) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withOpacity(0.32),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder_open_rounded, size: 20, color: Colors.grey),
          const SizedBox(width: 12),
          Expanded(
              child: Text(path,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis)),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline_rounded,
                size: 20, color: Colors.redAccent),
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

    final path = await pickDirectorySafely(context);
    if (path != null) settings.addMusicPath(path);
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

  Widget _buildVideoSettingsCard(
    BuildContext context,
    SettingsModel settings,
    MusicService musicService,
    ThemeData theme,
  ) {
    final isVideo = musicService.isCurrentMediaVideo;

    return _buildGlassSettingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.videocam_rounded,
                  color: isVideo ? theme.colorScheme.primary : Colors.grey,
                  size: 18),
              const SizedBox(width: 8),
              Text(
                'Video Playback',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: isVideo
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurface.withOpacity(0.4),
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          Opacity(
            opacity: isVideo ? 1.0 : 0.4,
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              activeColor: theme.colorScheme.primary,
              title: const Text('Live video card'),
              value: settings.playVideoBackground,
              onChanged: isVideo ? settings.setPlayVideoBackground : null,
            ),
          ),
          const Divider(height: 8),
          Opacity(
            opacity: isVideo ? 1.0 : 0.4,
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              activeColor: theme.colorScheme.primary,
              title: const Text('Double-tap fullscreen'),
              value: settings.videoDoubleTapFullscreen,
              onChanged: isVideo ? settings.setVideoDoubleTapFullscreen : null,
            ),
          ),
          const Divider(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.subtitles_rounded),
            title: const Text('Open subtitles'),
            subtitle: const Text('SRT, VTT, ASS, SSA'),
            onTap: () => _pickSubtitleFile(context, musicService),
            trailing: IconButton(
              tooltip: 'Disable subtitles',
              icon: const Icon(Icons.closed_caption_disabled_rounded),
              onPressed: musicService.disableSubtitles,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingSettingsCard(
    BuildContext context,
    SettingsModel settings,
    ThemeData theme,
  ) {
    final path = settings.recordingSavePath.trim();
    return _buildGlassSettingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.video_file_rounded,
              color: theme.colorScheme.primary,
            ),
            title: const Text('Recording save folder'),
            subtitle: Text(
              path.isEmpty ? 'Default: PlayerVF documents / Recordings' : path,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (path.isEmpty)
            FutureBuilder<String>(
              future: _defaultRecordingSavePath(),
              builder: (context, snapshot) {
                final value = snapshot.data;
                if (value == null || value.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.52),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _pickRecordingSavePath(context, settings),
                  icon: const Icon(Icons.folder_open_rounded),
                  label: const Text('Choose Folder'),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                tooltip: 'Type folder path',
                onPressed: () => _showRecordingPathDialog(context, settings),
                icon: const Icon(Icons.edit_location_alt_rounded),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                tooltip: 'Use default folder',
                onPressed: path.isEmpty
                    ? null
                    : () => settings.setRecordingSavePath(''),
                icon: const Icon(Icons.restore_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Recording saves a 16:9 MP4. Windows captures the app window; mobile records the fullscreen lyrics scene and locks the current orientation while saving.',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withOpacity(0.62),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickRecordingSavePath(
    BuildContext context,
    SettingsModel settings,
  ) async {
    final path = await pickDirectorySafely(context);
    if (path == null || path.trim().isEmpty) return;
    if (!context.mounted) return;
    await _saveRecordingPath(context, settings, path);
  }

  Future<void> _showRecordingPathDialog(
    BuildContext context,
    SettingsModel settings,
  ) async {
    final controller =
        TextEditingController(text: settings.recordingSavePath.trim());
    final path = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Recording Folder Path'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Folder path',
              hintText: r'C:\Users\You\Videos\PlayerVF',
              prefixIcon: Icon(Icons.folder_rounded),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (path == null) return;
    if (!context.mounted) return;
    await _saveRecordingPath(context, settings, path);
  }

  Future<void> _saveRecordingPath(
    BuildContext context,
    SettingsModel settings,
    String rawPath,
  ) async {
    final path = rawPath.trim();
    if (path.isEmpty) {
      await settings.setRecordingSavePath('');
      return;
    }
    try {
      final directory = Directory(path);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      await settings.setRecordingSavePath(directory.path);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Recording folder saved: ${directory.path}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not use that folder: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<String> _defaultRecordingSavePath() async {
    final dir = await getPlayerVfDocumentsDirectory();
    return '${dir.path}${Platform.pathSeparator}Recordings';
  }

  Widget _buildPerformanceModeRow(
      BuildContext context, SettingsModel settings) {
    final theme = Theme.of(context);
    const labels = {
      PerformanceMode.auto: 'Auto',
      PerformanceMode.quality: 'Quality',
      PerformanceMode.balanced: 'Balanced',
      PerformanceMode.batterySaver: 'Battery',
      PerformanceMode.maxPerformance: 'Max FPS',
    };
    const icons = {
      PerformanceMode.auto: Icons.auto_awesome_rounded,
      PerformanceMode.quality: Icons.high_quality_rounded,
      PerformanceMode.balanced: Icons.speed_rounded,
      PerformanceMode.batterySaver: Icons.battery_saver_rounded,
      PerformanceMode.maxPerformance: Icons.rocket_launch_rounded,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Performance mode',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(
          'Controls GPU-heavy blur, particles, cover quality, and animation cost.',
          style: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.58),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: PerformanceMode.values.map((mode) {
            final selected = settings.performanceMode == mode;
            return ChoiceChip(
              avatar: Icon(
                icons[mode],
                size: 16,
                color: selected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
              label: Text(labels[mode]!),
              selected: selected,
              onSelected: (_) => settings.setPerformanceMode(mode),
              selectedColor:
                  theme.colorScheme.primaryContainer.withOpacity(0.72),
              backgroundColor:
                  theme.colorScheme.surfaceContainerHighest.withOpacity(0.34),
              labelStyle: TextStyle(
                color: selected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
              visualDensity: VisualDensity.compact,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildBackgroundBlurRow(BuildContext context, SettingsModel settings) {
    final theme = Theme.of(context);
    final percent = (settings.backgroundBlurScale * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.blur_on_rounded,
                size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Background blur',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Text(
              '$percent%',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.64),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        Slider(
          value: settings.backgroundBlurScale,
          min: 0,
          max: 2.5,
          divisions: 25,
          label: '$percent%',
          onChanged: settings.setBackgroundBlurScale,
        ),
      ],
    );
  }

  Future<void> _pickSubtitleFile(
      BuildContext context, MusicService musicService) async {
    final path = await pickFilePathSafely(
      context,
      allowedExtensions: const ['srt', 'vtt', 'ass', 'ssa'],
    );
    if (path == null || path.isEmpty) return;
    await musicService.loadSubtitleFile(path);
  }
}
