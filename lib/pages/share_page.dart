import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/settings_model.dart';
import '../services/local_share_service.dart';
import '../services/music_scanner_service.dart';
import '../services/music_service.dart';
import '../services/responsive.dart';
import '../services/wifi_direct_service.dart';
import '../widgets/glass_container.dart';

class SharePage extends StatefulWidget {
  const SharePage({super.key});

  @override
  State<SharePage> createState() => _SharePageState();
}

class _SharePageState extends State<SharePage> {
  final LocalShareService _shareService = LocalShareService();
  late final WifiDirectService _nearbyService =
      WifiDirectService(localShareService: _shareService);

  ShareServerInfo? _serverInfo;
  List<NearbyShareDevice> _foundDevices = [];
  NearbyShareDevice? _selectedDevice;
  RemoteShareManifest? _remoteManifest;
  ShareTransferProgress? _transferProgress;
  bool _isStartingServer = false;
  bool _isScanning = false;
  bool _isConnecting = false;
  bool _isSyncing = false;
  bool _isTransferPaused = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_autoFindDevices());
    });
  }

  @override
  void dispose() {
    unawaited(_shareService.stopSharing());
    unawaited(_nearbyService.stopDiscovery());
    super.dispose();
  }

  Future<void> _startSharing(ShareScope scope) async {
    final musicService = context.read<MusicService>();
    setState(() {
      _isStartingServer = true;
      _message = null;
    });

    try {
      final info = await _shareService.startSharing(
        library: musicService.musicList,
        currentTrack: musicService.currentMusic,
        scope: scope,
      );
      setState(() {
        _serverInfo = info;
        _message =
            'Sharing ${info.trackCount} track${info.trackCount == 1 ? '' : 's'}.';
      });
    } catch (error) {
      setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _isStartingServer = false);
    }
  }

  Future<void> _stopSharing() async {
    await _shareService.stopSharing();
    if (mounted) {
      setState(() {
        _serverInfo = null;
        _message = 'Sharing stopped.';
      });
    }
  }

  Future<void> _autoFindDevices() async {
    if (_isScanning || _isSyncing) return;

    setState(() {
      _isScanning = true;
      _foundDevices = [];
      _selectedDevice = null;
      _remoteManifest = null;
      _transferProgress = null;
      _message = 'Searching for PlayerVF devices...';
    });

    try {
      final devices = await _nearbyService.searchDevices();
      if (!mounted) return;
      setState(() => _foundDevices = devices);

      if (devices.isEmpty) {
        setState(() => _message =
            'No PlayerVF devices found. Make sure the other device is sharing on the same Wi-Fi or hotspot.');
        return;
      }

      await _connectToDevice(devices.first);
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _connectToDevice(NearbyShareDevice device) async {
    setState(() {
      _isConnecting = true;
      _selectedDevice = device;
      _remoteManifest = null;
      _transferProgress = null;
      _message = 'Connecting to ${device.name}...';
    });

    try {
      var url = device.url;
      if (device.transport == NearbyDeviceTransport.wifiDirect) {
        final connection = await _nearbyService.connectWifiDirect(device);
        final host = connection.groupOwnerAddress;
        if (host == null || host.isEmpty) {
          throw const FormatException(
            'Wi-Fi Direct connected, but no group owner address was reported.',
          );
        }
        url = 'http://$host:45780';
        await _nearbyService.trustDevice(device.id);
      }
      if (url == null || url.isEmpty) {
        throw const FormatException(
            'No transfer URL available for this device.');
      }
      final manifest = await _shareService.fetchManifest(url);
      setState(() {
        _remoteManifest = manifest;
        _selectedDevice = device.copyWith(url: url, status: 'connected');
        _message = 'Connected to ${manifest.deviceName}.';
      });
    } catch (error) {
      setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  Future<void> _syncTracks(Iterable<RemoteShareTrack> tracks) async {
    final musicService = context.read<MusicService>();
    final settings = context.read<SettingsModel>();
    final selectedTracks = tracks.toList();
    if (selectedTracks.isEmpty) {
      setState(() => _message = 'No tracks available to sync.');
      return;
    }

    setState(() {
      _isSyncing = true;
      _isTransferPaused = false;
      _transferProgress = null;
      _message =
          'Syncing ${selectedTracks.length} track${selectedTracks.length == 1 ? '' : 's'}...';
    });

    try {
      final syncPath = await MusicScannerService.playerVfSyncDirectoryPath();
      await settings.addMusicPath(syncPath);

      var importedCount = 0;
      var completedCount = 0;
      final seenCompletedPaths = <String>{};
      await _shareService.downloadTracks(
        address: _selectedDevice?.url ?? '',
        tracks: selectedTracks,
        onProgress: (progress) {
          if (mounted) setState(() => _transferProgress = progress);
        },
        onFileComplete: (path) async {
          if (!seenCompletedPaths.add(path)) return;
          final added = await musicService.importSharedMusicFiles(
            [path],
            createBackup: completedCount == 0,
          );
          completedCount++;
          importedCount += added;
          if (!mounted) return;
          setState(() {
            _message = added == 0
                ? 'Saved $completedCount/${selectedTracks.length}. Library already has this track.'
                : 'Saved $completedCount/${selectedTracks.length}. Added $importedCount new track${importedCount == 1 ? '' : 's'}.';
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _message = importedCount == 0
            ? 'Files saved in PlayerVF Sync. Library already had these tracks.'
            : 'Synced $importedCount new track${importedCount == 1 ? '' : 's'} into your library.';
      });
    } catch (error) {
      setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _pauseTransfer() {
    _shareService.pauseTransfer();
    setState(() {
      _isTransferPaused = true;
      _message = 'Transfer paused.';
    });
  }

  void _resumeTransfer() {
    _shareService.resumeTransfer();
    setState(() {
      _isTransferPaused = false;
      _message = 'Transfer resumed.';
    });
  }

  void _cancelTransfer() {
    _shareService.cancelTransfer();
    setState(() {
      _isTransferPaused = false;
      _message = 'Cancelling transfer...';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final musicService = context.watch<MusicService>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(20.w, 18.h, 20.w, 120.h),
          children: [
            Row(
              children: [
                Icon(Icons.nearby_error_rounded,
                    color: theme.colorScheme.primary, size: 26.s),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    'Nearby Share',
                    style: TextStyle(
                      fontSize: 26.sp,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 18.h),
            _buildHostCard(theme, musicService),
            SizedBox(height: 14.h),
            _buildConnectCard(theme),
            if (_message != null) ...[
              SizedBox(height: 14.h),
              _buildMessage(theme, _message!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHostCard(
    ThemeData theme,
    MusicService musicService,
  ) {
    final info = _serverInfo;
    return GlassContainer(
      padding: EdgeInsets.all(16.s),
      borderRadius: BorderRadius.circular(22.s),
      color: null,
      blur: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(theme, Icons.wifi_tethering_rounded, 'This device'),
          SizedBox(height: 12.h),
          Wrap(
            spacing: 10.w,
            runSpacing: 10.h,
            children: [
              FilledButton.icon(
                onPressed:
                    _isStartingServer || musicService.currentMusic == null
                        ? null
                        : () => _startSharing(ShareScope.currentSong),
                icon: const Icon(Icons.music_note_rounded),
                label: const Text('Share Song'),
              ),
              FilledButton.tonalIcon(
                onPressed: _isStartingServer || musicService.musicList.isEmpty
                    ? null
                    : () => _startSharing(ShareScope.fullLibrary),
                icon: const Icon(Icons.library_music_rounded),
                label: const Text('Share Library'),
              ),
              if (info != null)
                OutlinedButton.icon(
                  onPressed: _stopSharing,
                  icon: const Icon(Icons.stop_circle_rounded),
                  label: const Text('Stop'),
                ),
            ],
          ),
          if (info != null) ...[
            SizedBox(height: 14.h),
            _statusPill(
              theme,
              Icons.radio_button_checked_rounded,
              info.scope == ShareScope.currentSong
                  ? 'Sharing current song'
                  : 'Sharing ${info.trackCount} songs',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConnectCard(ThemeData theme) {
    final manifest = _remoteManifest;
    final progress = _transferProgress;
    return GlassContainer(
      padding: EdgeInsets.all(16.s),
      borderRadius: BorderRadius.circular(22.s),
      color: null,
      blur: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(theme, Icons.sync_rounded, 'Sync from device'),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isScanning || _isConnecting || _isSyncing
                      ? null
                      : _autoFindDevices,
                  icon: _isScanning || _isConnecting
                      ? SizedBox.square(
                          dimension: 18.s,
                          child:
                              const CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.radar_rounded),
                  label: const Text('Search'),
                ),
              ),
            ],
          ),
          if (_foundDevices.isNotEmpty) ...[
            SizedBox(height: 12.h),
            ..._foundDevices.map((device) => _deviceTile(theme, device)),
          ],
          if (manifest != null) ...[
            SizedBox(height: 16.h),
            _statusPill(
              theme,
              Icons.link_rounded,
              '${manifest.deviceName} • ${manifest.tracks.length} songs',
            ),
            SizedBox(height: 12.h),
            Wrap(
              spacing: 10.w,
              runSpacing: 10.h,
              children: [
                FilledButton.icon(
                  onPressed:
                      _isSyncing ? null : () => _syncTracks(manifest.tracks),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Sync All Files'),
                ),
                OutlinedButton.icon(
                  onPressed: _isSyncing || manifest.currentTrack == null
                      ? null
                      : () => _syncTracks([manifest.currentTrack!]),
                  icon: const Icon(Icons.music_note_rounded),
                  label: const Text('Sync Current'),
                ),
              ],
            ),
            if (_isSyncing || progress != null) ...[
              SizedBox(height: 14.h),
              _buildTransferFlowCard(theme, progress),
              SizedBox(height: 10.h),
              _buildTransferControls(),
            ],
            SizedBox(height: 12.h),
            ...manifest.tracks.take(5).map((track) => _trackTile(theme, track)),
            if (manifest.tracks.length > 5)
              Padding(
                padding: EdgeInsets.only(top: 8.h),
                child: Text(
                  '+ ${manifest.tracks.length - 5} more',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: theme.colorScheme.primary),
        SizedBox(width: 9.w),
        Text(
          title,
          style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  Widget _trackTile(ThemeData theme, RemoteShareTrack track) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 2.w),
      leading: Icon(Icons.audio_file_rounded, color: theme.colorScheme.primary),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${track.artist} • ${_formatBytes(track.sizeBytes)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _deviceTile(ThemeData theme, NearbyShareDevice device) {
    final selected = _selectedDevice?.url == device.url;
    final isWifiDirect = device.transport == NearbyDeviceTransport.wifiDirect;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 2.w),
      leading: Icon(
        selected
            ? Icons.check_circle_rounded
            : isWifiDirect
                ? Icons.wifi_tethering_rounded
                : Icons.devices_rounded,
        color: selected ? theme.colorScheme.primary : theme.colorScheme.outline,
      ),
      title: Text(device.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${device.type} • ${device.status}${device.trusted ? ' • trusted' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: TextButton(
        onPressed:
            _isConnecting || _isSyncing ? null : () => _connectToDevice(device),
        child: const Text('Use'),
      ),
      onTap:
          _isConnecting || _isSyncing ? null : () => _connectToDevice(device),
    );
  }

  Widget _statusPill(ThemeData theme, IconData icon, String label) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 9.h),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(
          theme.brightness == Brightness.dark ? 0.22 : 0.54,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16.s, color: theme.colorScheme.primary),
          SizedBox(width: 8.w),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 12.sp,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransferControls() {
    return Wrap(
      spacing: 10.w,
      runSpacing: 8.h,
      children: [
        OutlinedButton.icon(
          onPressed: !_isSyncing || _isTransferPaused ? null : _pauseTransfer,
          icon: const Icon(Icons.pause_rounded),
          label: const Text('Pause'),
        ),
        OutlinedButton.icon(
          onPressed: !_isSyncing || !_isTransferPaused ? null : _resumeTransfer,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Resume'),
        ),
        OutlinedButton.icon(
          onPressed: !_isSyncing ? null : _cancelTransfer,
          icon: const Icon(Icons.close_rounded),
          label: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildTransferFlowCard(
    ThemeData theme,
    ShareTransferProgress? progress,
  ) {
    final source = _selectedDevice?.name ?? 'PlayerVF device';
    final fileName = progress?.currentFileName ?? 'Preparing transfer';
    final fraction = progress?.fraction ?? 0.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.all(14.s),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(
          theme.brightness == Brightness.dark ? 0.18 : 0.42,
        ),
        borderRadius: BorderRadius.circular(18.s),
        border: Border.all(
          color: theme.colorScheme.primary.withOpacity(0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _transferEndpoint(
                  theme,
                  Icons.devices_rounded,
                  'From',
                  source,
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: _transferEndpoint(
                  theme,
                  Icons.phone_android_rounded,
                  'To',
                  'This PlayerVF',
                ),
              ),
            ],
          ),
          SizedBox(height: 14.h),
          SizedBox(
            height: 30.h,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final travel =
                    (constraints.maxWidth - 28.s).clamp(0.0, double.infinity);
                return Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Positioned.fill(
                      child: Center(
                        child: Container(
                          height: 3.h,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                    TweenAnimationBuilder<double>(
                      key: ValueKey('${fileName}_${(fraction * 20).floor()}'),
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 850),
                      curve: Curves.easeInOutCubic,
                      builder: (context, value, child) {
                        return Transform.translate(
                          offset: Offset(travel * value, 0),
                          child: child,
                        );
                      },
                      child: CircleAvatar(
                        radius: 14.s,
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        child: Icon(Icons.music_note_rounded, size: 16.s),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          SizedBox(height: 10.h),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: Text(
              fileName,
              key: ValueKey(fileName),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          SizedBox(height: 10.h),
          LinearProgressIndicator(value: fraction),
          if (progress != null) ...[
            SizedBox(height: 8.h),
            Text(
              '${progress.completedFiles}/${progress.totalFiles} files  ${_formatBytes(progress.receivedBytes)} / ${_formatBytes(progress.totalBytes)}  •  ${_formatBytes(progress.bytesPerSecond.round())}/s',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _transferEndpoint(
    ThemeData theme,
    IconData icon,
    String label,
    String value,
  ) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 9.h),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withOpacity(
          theme.brightness == Brightness.dark ? 0.36 : 0.72,
        ),
        borderRadius: BorderRadius.circular(14.s),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18.s, color: theme.colorScheme.primary),
          SizedBox(width: 8.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(ThemeData theme, String message) {
    return GlassContainer(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      borderRadius: BorderRadius.circular(18.s),
      color: null,
      blur: 14,
      child: Row(
        children: [
          Icon(Icons.info_rounded, color: theme.colorScheme.primary),
          SizedBox(width: 10.w),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }
}
