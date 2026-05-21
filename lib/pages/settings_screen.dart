import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/settings_model.dart';
import '../services/music_service.dart';
import '../services/youtube_music_service.dart';
import '../widgets/audio_effects_menu.dart';
import '../widgets/glass_container.dart';
import 'appearance_screen.dart';

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
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.equalizer_rounded,
                          color: theme.colorScheme.primary),
                      title: const Text('Audio Effects'),
                      trailing:
                          const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                      onTap: () => showAudioEffectsMenu(context),
                    ),
                    const Divider(height: 20),
                    _buildDecoderModeRow(
                      context,
                      title: 'Audio decoder',
                      value: settings.audioDecoderMode,
                      onChanged: (mode) =>
                          _setAudioDecoderMode(settings, musicService, mode),
                    ),
                  ],
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
              _buildSectionTitle('Video'),
              _buildVideoSettingsCard(context, settings, musicService, theme),
              const SizedBox(height: 24),
              _buildSectionTitle('YouTube Music'),
              _buildGlassSettingCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Download Folder',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                      settings.youtubeMusicDownloadPath.isEmpty
                          ? 'Using default folder'
                          : settings.youtubeMusicDownloadPath,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                          fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _setYoutubeDownloadPath(
                                context, settings, musicService),
                            icon: const Icon(Icons.folder_rounded),
                            label: const Text('Choose'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton(
                          onPressed: () => _useDefaultYoutubeDownloadPath(
                              settings, musicService),
                          icon: const Icon(Icons.restore_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle('Playback'),
              _buildGlassSettingCard(
                child: SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  activeColor: Colors.teal,
                  title: const Text('Remember playback'),
                  value: musicService.rememberPlayback,
                  onChanged: musicService.setRememberPlayback,
                ),
              ),
              const SizedBox(height: 12),
              _buildGlassSettingCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Seek Step',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [5, 10, 15, 30].map((seconds) {
                        final selected = settings.seekStepSeconds == seconds;
                        return ChoiceChip(
                          label: Text(
                            '$seconds sec',
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: selected,
                          onSelected: (_) =>
                              settings.setSeekStepSeconds(seconds),
                          selectedColor: theme.colorScheme.primaryContainer
                              .withOpacity(0.68),
                          backgroundColor: theme
                              .colorScheme.surfaceContainerHighest
                              .withOpacity(0.34),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          visualDensity: VisualDensity.compact,
                          labelStyle: TextStyle(
                            color: selected
                                ? theme.colorScheme.onPrimaryContainer
                                : theme.colorScheme.onSurface.withOpacity(0.8),
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _buildGlassSettingCard(
                child: _buildSongGapSetting(context, settings, musicService),
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

  Widget _buildSongGapSetting(
    BuildContext context,
    SettingsModel settings,
    MusicService musicService,
  ) {
    final theme = Theme.of(context);
    final seconds = settings.songGapMs / 1000.0;
    final label = settings.songGapMs == 0
        ? 'No empty time'
        : '${seconds.toStringAsFixed(seconds % 1 == 0 ? 0 : 1)} sec';

    Future<void> setGapMs(int milliseconds) async {
      await settings.setSongGapMs(milliseconds);
      await musicService.setSongGapDuration(
        Duration(milliseconds: settings.songGapMs),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Empty time between songs',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Adds clean silence before the next track. Set to 0 for smooth crossfade.',
          style: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.58),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 10),
        Slider(
          value: settings.songGapMs.toDouble(),
          min: 0,
          max: 5000,
          divisions: 10,
          label: label,
          onChanged: (value) => setGapMs(value.round()),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: const [0, 500, 1000, 2000, 5000].map((milliseconds) {
            final selected = settings.songGapMs == milliseconds;
            final chipLabel = milliseconds == 0
                ? 'Off'
                : '${(milliseconds / 1000).toStringAsFixed(milliseconds % 1000 == 0 ? 0 : 1)}s';
            return ChoiceChip(
              label: Text(chipLabel),
              selected: selected,
              onSelected: (_) => setGapMs(milliseconds),
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

  Future<void> _useDefaultYoutubeDownloadPath(
    SettingsModel settings,
    MusicService musicService,
  ) async {
    final path =
        await YoutubeMusicService.defaultYoutubeMusicDownloadDirectory();
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
          _buildDecoderModeRow(
            context,
            title: 'Video decoder',
            value: settings.videoDecoderMode,
            onChanged: (mode) =>
                _setVideoDecoderMode(settings, musicService, mode),
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

  Widget _buildDecoderModeRow(
    BuildContext context, {
    required String title,
    required DecoderMode value,
    required ValueChanged<DecoderMode> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        SegmentedButton<DecoderMode>(
          segments: const [
            ButtonSegment(
              value: DecoderMode.auto,
              icon: Icon(Icons.auto_mode_rounded),
              label: Text('Auto'),
            ),
            ButtonSegment(
              value: DecoderMode.software,
              icon: Icon(Icons.memory_rounded),
              label: Text('Soft'),
            ),
            ButtonSegment(
              value: DecoderMode.hardware,
              icon: Icon(Icons.developer_board_rounded),
              label: Text('Hardware'),
            ),
          ],
          selected: {value},
          onSelectionChanged: (next) => onChanged(next.first),
        ),
      ],
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

  Future<void> _setAudioDecoderMode(
    SettingsModel settings,
    MusicService musicService,
    DecoderMode mode,
  ) async {
    await settings.setAudioDecoderMode(mode);
    await musicService.setDecoderModes(
      audio: settings.audioDecoderMode,
      video: settings.videoDecoderMode,
    );
  }

  Future<void> _setVideoDecoderMode(
    SettingsModel settings,
    MusicService musicService,
    DecoderMode mode,
  ) async {
    await settings.setVideoDecoderMode(mode);
    await musicService.setDecoderModes(
      audio: settings.audioDecoderMode,
      video: settings.videoDecoderMode,
    );
  }

  Future<void> _pickSubtitleFile(
      BuildContext context, MusicService musicService) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['srt', 'vtt', 'ass', 'ssa'],
      withData: false,
    );
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) return;
    await musicService.loadSubtitleFile(path);
  }
}
