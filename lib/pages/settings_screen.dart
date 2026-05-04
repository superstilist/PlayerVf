import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/settings_model.dart';
import '../services/music_service.dart';
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
            title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
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
                  leading: const Icon(Icons.equalizer_rounded, color: Colors.teal),
                  title: const Text('Audio Effects'),
                  subtitle: const Text('Equalizer, pitch, speed, reverb'),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onTap: () => showAudioEffectsMenu(context),
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle('Interface'),
              _buildGlassSettingCard(
                child: ListTile(
                  leading: Icon(Icons.palette_rounded, color: settings.accentColor),
                  title: const Text('Appearance'),
                  subtitle: const Text('Theme, colors, layout, typography'),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AppearanceScreen())),
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle('Video'),
              _buildVideoSettingsCard(context, settings, musicService, theme),
              const SizedBox(height: 24),
              _buildSectionTitle('Music'),
              _buildGlassSettingCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.music_note_rounded, color: Colors.teal, size: 18),
                        const SizedBox(width: 8),
                        const Text('Music Background', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'For music files, the full cover art is always shown as the player background.',
                      style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5), fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.teal.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.teal.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, color: Colors.teal, size: 18),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Cover art always shown as full-screen blurred background',
                              style: TextStyle(fontSize: 12, color: Colors.teal, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
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
                  subtitle: const Text('Restore current song, queue, and exact stopped timestamp when the app opens again.'),
                  value: musicService.rememberPlayback,
                  onChanged: musicService.setRememberPlayback,
                ),
              ),
              const SizedBox(height: 12),
              _buildGlassSettingCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Seek Step', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      'Desktop hotkeys use this jump amount for left/right arrows and A / D.',
                      style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [5, 10, 15, 30].map((seconds) {
                        final selected = settings.seekStepSeconds == seconds;
                        return ChoiceChip(
                          label: Text('$seconds sec'),
                          selected: selected,
                          onSelected: (_) => settings.setSeekStepSeconds(seconds),
                          selectedColor: Colors.teal.withOpacity(0.2),
                          labelStyle: TextStyle(
                            color: selected ? Colors.teal : theme.colorScheme.onSurface.withOpacity(0.8),
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle('Music Library'),
              _buildGlassSettingCard(
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
              _buildGlassSettingCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Library Tools', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => _updateAllMusic(context, settings, musicService),
                      icon: const Icon(Icons.system_update_alt_rounded),
                      label: const Text('Update All Player Music'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 45),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: musicService.isLoadingSystemMusic ? null : () => _showClearCacheDialog(context, musicService),
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
            ],
          ),
        );
      },
    );
  }

  void _updateAllMusic(BuildContext context, SettingsModel settings, MusicService musicService) {
    final paths = settings.musicSourcePaths.isEmpty ? null : settings.musicSourcePaths;
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
              const Text('Clear Cache?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text('This will delete cached cover art and metadata, then rescan your music library.', textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      musicService.clearCache();
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
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
        title.toUpperCase(),
        style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.5),
      ),
    );
  }

  Widget _buildGlassSettingCard({required Widget child}) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(20),
      child: child,
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
          Expanded(child: Text(path, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
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
          // ── Header row ──
          Row(
            children: [
              Icon(Icons.videocam_rounded, color: isVideo ? Colors.teal : Colors.grey, size: 18),
              const SizedBox(width: 8),
              Text(
                'Video Playback',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: isVideo ? theme.colorScheme.onSurface : theme.colorScheme.onSurface.withOpacity(0.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // ── "video only" status banner ──
          if (!isVideo)
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: Colors.orange, size: 16),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'These settings only activate for video files (mp4, avi, mkv, hevc…).',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ),
                ],
              ),
            )
          else
            Text(
              'Settings apply to the current video file.',
              style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5), fontSize: 12),
            ),

          const Divider(height: 24),

          // ── Show Live Video switch ──
          Opacity(
            opacity: isVideo ? 1.0 : 0.4,
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              activeColor: Colors.teal,
              title: const Text('Show Live Video in Card'),
              subtitle: const Text(
                'Display live video in the artwork card. Cover art is always shown as background.',
                style: TextStyle(fontSize: 12),
              ),
              value: settings.playVideoBackground,
              onChanged: isVideo ? settings.setPlayVideoBackground : null,
            ),
          ),

          const Divider(height: 8),

          // ── Double-Tap Fullscreen switch ──
          Opacity(
            opacity: isVideo ? 1.0 : 0.4,
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              activeColor: Colors.teal,
              title: const Text('Double-Tap for Fullscreen'),
              subtitle: const Text(
                'Double-tap the video card to open it in fullscreen.',
                style: TextStyle(fontSize: 12),
              ),
              value: settings.videoDoubleTapFullscreen,
              onChanged: isVideo ? settings.setVideoDoubleTapFullscreen : null,
            ),
          ),
        ],
      ),
    );
  }
}
