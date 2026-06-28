import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/settings_model.dart';
import '../services/app_directories.dart';
import '../services/music_service.dart';
import '../services/safe_file_picker.dart';
import '../services/spotify_service.dart';
import '../services/responsive.dart';
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
          backgroundColor: theme.colorScheme.surface,
          appBar: AppBar(
            title: const Text('Settings',
                style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: theme.colorScheme.surface,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(20.w, 10.h, 20.w, 40.h),
            children: [
              _buildQuickAccessGrid(context, settings, musicService, theme),
              SizedBox(height: 28.h),
              _buildSectionTitle(context, 'Appearance'),
              _buildAppearanceCard(context, settings, theme),
              SizedBox(height: 20.h),
              _buildSectionTitle(context, 'Playback'),
              _buildPlaybackCard(context, settings, musicService, theme),
              SizedBox(height: 20.h),
              _buildSectionTitle(context, 'Library'),
              _buildLibraryCard(context, settings, musicService, theme),
              SizedBox(height: 20.h),
              _buildSectionTitle(context, 'Video & Recording'),
              _buildVideoCard(context, settings, musicService, theme),
              SizedBox(height: 20.h),
              _buildSectionTitle(context, 'Web & Online'),
              _buildOnlineCard(context, settings, theme),
              SizedBox(height: 20.h),
              _buildSectionTitle(context, 'Data'),
              _buildDataCard(context, settings, musicService, theme),
              SizedBox(height: 40.h),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickAccessGrid(
    BuildContext context,
    SettingsModel settings,
    MusicService musicService,
    ThemeData theme,
  ) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(20),
      blur: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 14),
            child: Text(
              'Quick Access',
              style: TextStyle(
                fontSize: 15.sp,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _buildQuickTile(
                  context,
                  icon: Icons.palette_rounded,
                  label: 'Theme',
                  color: settings.accentColor,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AppearanceScreen()),
                  ),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: _buildQuickTile(
                  context,
                  icon: Icons.equalizer_rounded,
                  label: 'Audio FX',
                  color: theme.colorScheme.primary,
                  onTap: () => showAudioEffectsMenu(context),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: _buildQuickTile(
                  context,
                  icon: Icons.language_rounded,
                  label: 'YouTube',
                  color: theme.colorScheme.primary,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const WebSettingsScreen()),
                  ),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: _buildQuickTile(
                  context,
                  icon: Icons.auto_graph_rounded,
                  label: 'Stats',
                  color: theme.colorScheme.primary,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const LibraryStatsScreen()),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withOpacity(0.4),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            SizedBox(height: 6.h),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.sp,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface.withOpacity(0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppearanceCard(
    BuildContext context,
    SettingsModel settings,
    ThemeData theme,
  ) {
    return _buildCard(
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.palette_rounded, color: settings.accentColor),
            title: const Text('Theme & Appearance'),
            subtitle: const Text('Presets, accent color, particles, glass'),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AppearanceScreen()),
            ),
          ),
          const Divider(height: 20),
          _buildPerformanceModeRow(context, settings),
          SizedBox(height: 18.h),
          _buildBackgroundBlurRow(context, settings),
        ],
      ),
    );
  }

  Widget _buildPlaybackCard(
    BuildContext context,
    SettingsModel settings,
    MusicService musicService,
    ThemeData theme,
  ) {
    return _buildCard(
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.play_circle_rounded,
                color: theme.colorScheme.primary),
            title: const Text('Playback Settings'),
            subtitle: const Text('Decoders, lyrics, resume, seek step, gap'),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PlaybackSettingsScreen()),
            ),
          ),
          const Divider(height: 20),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeColor: settings.accentColor,
            secondary:
                Icon(Icons.history_rounded, color: theme.colorScheme.primary),
            title: const Text('Remember playback'),
            subtitle: const Text('Resume last track and position'),
            value: musicService.rememberPlayback,
            onChanged: musicService.setRememberPlayback,
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryCard(
    BuildContext context,
    SettingsModel settings,
    MusicService musicService,
    ThemeData theme,
  ) {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Storage Locations',
              style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 10.h),
          ...settings.musicSourcePaths
              .map((path) => _buildPathTile(context, settings, path)),
          SizedBox(height: 10.h),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _addPath(context, settings, musicService),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Folder'),
            ),
          ),
          const Divider(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.system_update_alt_rounded,
                color: theme.colorScheme.primary),
            title: const Text('Update Library'),
            subtitle: const Text('Rescan all music folders'),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            onTap: () => _updateAllMusic(context, settings, musicService),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoCard(
    BuildContext context,
    SettingsModel settings,
    MusicService musicService,
    ThemeData theme,
  ) {
    final isVideo = musicService.isCurrentMediaVideo;
    final path = settings.recordingSavePath.trim();

    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Opacity(
            opacity: isVideo ? 1.0 : 0.5,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: theme.colorScheme.primary,
              title: const Text('Live video card'),
              value: settings.playVideoBackground,
              onChanged: isVideo ? settings.setPlayVideoBackground : null,
            ),
          ),
          const Divider(height: 8),
          Opacity(
            opacity: isVideo ? 1.0 : 0.5,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: theme.colorScheme.primary,
              title: const Text('Double-tap fullscreen'),
              value: settings.videoDoubleTapFullscreen,
              onChanged:
                  isVideo ? settings.setVideoDoubleTapFullscreen : null,
            ),
          ),
          const Divider(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.subtitles_rounded),
            title: const Text('Subtitles'),
            subtitle: const Text('SRT, VTT, ASS, SSA'),
            onTap: () => _pickSubtitleFile(context, musicService),
            trailing: IconButton(
              tooltip: 'Disable',
              icon: const Icon(Icons.closed_caption_disabled_rounded),
              onPressed: musicService.disableSubtitles,
            ),
          ),
          const Divider(height: 20),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading:
                Icon(Icons.video_file_rounded, color: theme.colorScheme.primary),
            title: const Text('Recording folder'),
            subtitle: Text(
              path.isEmpty
                  ? 'Default: PlayerVF documents / Recordings'
                  : path.split(RegExp(r'[/\\]')).last,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(height: 8.h),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _pickRecordingSavePath(context, settings),
                  icon: const Icon(Icons.folder_open_rounded),
                  label: const Text('Choose'),
                ),
              ),
              SizedBox(width: 8.w),
              IconButton.filledTonal(
                tooltip: 'Type path',
                onPressed: () => _showRecordingPathDialog(context, settings),
                icon: const Icon(Icons.edit_location_alt_rounded),
              ),
              SizedBox(width: 8.w),
              IconButton.filledTonal(
                tooltip: 'Default',
                onPressed: path.isEmpty
                    ? null
                    : () => settings.setRecordingSavePath(''),
                icon: const Icon(Icons.restore_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOnlineCard(
    BuildContext context,
    SettingsModel settings,
    ThemeData theme,
  ) {
    return _buildCard(
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.language_rounded,
                color: theme.colorScheme.primary),
            title: const Text('YouTube Downloads'),
            subtitle: const Text('Stream cache, download folder, web import'),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WebSettingsScreen()),
            ),
          ),
          const Divider(height: 20),
          Consumer<SpotifyService>(
            builder: (context, spotify, _) {
              return Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.music_note_rounded,
                        color: Color(0xFF1DB954), size: 20),
                    title: const Text('Spotify'),
                    subtitle: Text(
                      spotify.isAuthenticated
                          ? '${spotify.pinnedTrackIds.length} track(s) pinned'
                          : 'Connect to pin local tracks',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Icon(
                      spotify.isAuthenticated
                          ? Icons.check_circle_rounded
                          : Icons.arrow_forward_ios_rounded,
                      size: 16,
                      color: spotify.isAuthenticated
                          ? const Color(0xFF1DB954)
                          : null,
                    ),
                  ),
                  if (spotify.isAuthenticated) ...[
                    SizedBox(height: 4.h),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          spotify.logout();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Disconnected from Spotify'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        },
                        icon: const Icon(Icons.logout_rounded, size: 16),
                        label: const Text('Disconnect'),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.redAccent),
                          foregroundColor: Colors.redAccent,
                        ),
                      ),
                    ),
                  ] else ...[
                    SizedBox(height: 4.h),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1DB954),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: spotify.isAuthenticating
                            ? null
                            : () async {
                                await spotify.authenticate();
                                if (!context.mounted) return;
                                if (spotify.lastError != null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(spotify.lastError!),
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  );
                                }
                              },
                        icon: spotify.isAuthenticating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.login_rounded, size: 18),
                        label: Text(spotify.isAuthenticating
                            ? 'Connecting...'
                            : 'Connect Spotify'),
                      ),
                    ),
                    if (spotify.lastError != null) ...[
                      SizedBox(height: 6.h),
                      Text(
                        spotify.lastError!,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 11),
                      ),
                    ],
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDataCard(
    BuildContext context,
    SettingsModel settings,
    MusicService musicService,
    ThemeData theme,
  ) {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeColor: settings.accentColor,
            title: const Text('Back up before sync'),
            subtitle: const Text(
                'Save a library backup before importing shared songs'),
            value: settings.shareSyncBackupsEnabled,
            onChanged: settings.setShareSyncBackupsEnabled,
          ),
          const Divider(height: 22),
          const Text('Maintenance',
              style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 12.h),
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
    );
  }

  Widget _buildCard({required Widget child}) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(16),
      blur: 14,
      child: child,
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
          letterSpacing: 0,
        ),
      ),
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
          const Icon(Icons.folder_open_rounded, size: 18, color: Colors.grey),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              path.split(RegExp(r'[/\\]')).last,
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline_rounded,
                size: 18, color: Colors.redAccent),
            onPressed: () => settings.removeMusicPath(path),
          ),
        ],
      ),
    );
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
        SizedBox(height: 4.h),
        Text(
          'GPU blur, particles, cover quality, animation cost',
          style: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.52),
            fontSize: 12,
          ),
        ),
        SizedBox(height: 10.h),
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

    return Row(
      children: [
        Icon(Icons.blur_on_rounded,
            size: 18, color: theme.colorScheme.primary),
        SizedBox(width: 8.w),
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

  void _updateAllMusic(
      BuildContext context, SettingsModel settings, MusicService musicService) {
    final paths =
        settings.musicSourcePaths.isEmpty ? null : settings.musicSourcePaths;
    musicService.loadSystemMusic(customPaths: paths, clearExisting: true);
  }

  void _showFolderImportMessage(BuildContext context, int count) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          count == 0
              ? 'No supported media files were imported.'
              : 'Imported $count media file${count == 1 ? '' : 's'}.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
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

  Future<void> _pickSubtitleFile(
      BuildContext context, MusicService musicService) async {
    final path = await pickFilePathSafely(
      context,
      allowedExtensions: const ['srt', 'vtt', 'ass', 'ssa'],
    );
    if (path == null || path.isEmpty) return;
    await musicService.loadSubtitleFile(path);
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
}
