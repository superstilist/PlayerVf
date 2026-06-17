import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/settings_model.dart';
import '../services/music_service.dart';
import '../services/safe_file_picker.dart';
import '../services/youtube_music_service.dart';
import '../widgets/glass_container.dart';

class WebSettingsScreen extends StatefulWidget {
  const WebSettingsScreen({super.key});

  @override
  State<WebSettingsScreen> createState() => _WebSettingsScreenState();
}

class _WebSettingsScreenState extends State<WebSettingsScreen> {
  final YoutubeMusicService _youtubeService = YoutubeMusicService();
  late Future<String> _cachePathFuture;
  bool _isClearingCache = false;

  @override
  void initState() {
    super.initState();
    _cachePathFuture = _youtubeService.streamVideoCacheDirectory();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsModel>();
    final musicService = context.watch<MusicService>();
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text(
          'Web & YouTube',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
        children: [
          _sectionTitle(context, 'YouTube Music'),
          _glassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.folder_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  title: const Text('Download folder'),
                  subtitle: Text(
                    settings.youtubeMusicDownloadPath.isEmpty
                        ? 'Using default folder'
                        : settings.youtubeMusicDownloadPath,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _setYoutubeDownloadPath(
                          context,
                          settings,
                          musicService,
                        ),
                        icon: const Icon(Icons.folder_open_rounded),
                        label: const Text('Choose'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filledTonal(
                      tooltip: 'Use default',
                      onPressed: () => _useDefaultYoutubeDownloadPath(
                        settings,
                        musicService,
                      ),
                      icon: const Icon(Icons.restore_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _sectionTitle(context, 'Streaming Cache'),
          _glassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.cloud_sync_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  title: const Text('YouTube video cache'),
                  subtitle: const Text(
                    'Streaming uses playable URLs first, then caches up to 1080p in the background.',
                  ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  activeColor: theme.colorScheme.primary,
                  title: const Text('Save stream cache'),
                  subtitle: const Text(
                    'When off, YouTube videos stream without writing cache files.',
                  ),
                  value: settings.youtubeStreamCacheEnabled,
                  onChanged: settings.setYoutubeStreamCacheEnabled,
                ),
                const Divider(height: 20),
                FutureBuilder<String>(
                  future: _cachePathFuture,
                  builder: (context, snapshot) {
                    final path = snapshot.data ?? 'Loading...';
                    return SelectableText(
                      path,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.62),
                        fontSize: 12,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _isClearingCache
                      ? null
                      : () => _clearStreamVideoCache(context),
                  icon: _isClearingCache
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_sweep_rounded),
                  label: const Text('Clear stream cache'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _sectionTitle(context, 'Web Library'),
          _glassCard(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.language_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  title: const Text('Import web folder'),
                  subtitle: const Text(
                    kIsWeb
                        ? 'Pick a browser folder with supported audio or video files.'
                        : 'Available when PlayerVF runs in a browser.',
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: kIsWeb
                        ? () => _importWebFolder(context, musicService)
                        : null,
                    icon: const Icon(Icons.drive_folder_upload_rounded),
                    label: const Text('Import folder'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
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

  Widget _glassCard({required Widget child}) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(16),
      blur: 14,
      child: child,
    );
  }

  Future<void> _setYoutubeDownloadPath(
    BuildContext context,
    SettingsModel settings,
    MusicService musicService,
  ) async {
    if (kIsWeb) {
      _showSnack(context, 'Download folder selection is available on desktop.');
      return;
    }

    final path = await pickDirectorySafely(context);
    if (path == null || path.isEmpty) return;
    await settings.setYoutubeMusicDownloadPath(path);
    await musicService.loadSystemMusic(
      customPaths: settings.musicSourcePaths,
      clearExisting: true,
    );
  }

  Future<void> _useDefaultYoutubeDownloadPath(
    SettingsModel settings,
    MusicService musicService,
  ) async {
    final path =
        await YoutubeMusicService.defaultYoutubeMusicDownloadDirectory();
    await settings.setYoutubeMusicDownloadPath(path);
    await musicService.loadSystemMusic(
      customPaths: settings.musicSourcePaths,
      clearExisting: true,
    );
  }

  Future<void> _clearStreamVideoCache(BuildContext context) async {
    setState(() => _isClearingCache = true);
    try {
      await _youtubeService.clearStreamVideoCache();
      if (!context.mounted) return;
      _showSnack(context, 'Stream cache cleared.');
    } catch (error) {
      if (!context.mounted) return;
      _showSnack(context, 'Could not clear stream cache: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isClearingCache = false;
          _cachePathFuture = _youtubeService.streamVideoCacheDirectory();
        });
      }
    }
  }

  Future<void> _importWebFolder(
    BuildContext context,
    MusicService musicService,
  ) async {
    final count = await musicService.importWebFolderMusic();
    if (!context.mounted) return;
    _showSnack(
      context,
      count == 0
          ? 'No supported media files were imported.'
          : 'Imported $count media file${count == 1 ? '' : 's'}.',
    );
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
