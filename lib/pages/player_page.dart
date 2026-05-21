import 'dart:async';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/music_model.dart';
import '../models/lyrics_model.dart';
import '../services/cover_color_service.dart';
import '../services/music_service.dart';
import '../services/performance_policy.dart';
import '../services/responsive.dart';
import '../widgets/audio_effects_menu.dart';
import '../widgets/cover_art_texture.dart';
import '../widgets/glass_container.dart';
import '../widgets/playback_progress_control.dart';
import '../models/settings_model.dart';

String? _lyricsOwnerKey(Music? music) {
  return music == null ? null : '${music.id}\n${music.filePath}';
}

class PlayerPage extends StatefulWidget {
  final VoidCallback onClose;

  const PlayerPage({super.key, required this.onClose});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  Future<CoverArtPalette>? _paletteFuture;
  String _palettePath = '';
  bool _isLyricsSheetOpen = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPalette(context.read<MusicService>().currentMusic?.coverPath);
  }

  void _syncPalette(String? path) {
    final normalized = path ?? '';
    if (_paletteFuture == null || normalized != _palettePath) {
      _palettePath = normalized;
      _paletteFuture = CoverColorService.fromPath(normalized);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final musicService = Provider.of<MusicService>(context);
    final settings = Provider.of<SettingsModel>(context);
    final currentMusic = musicService.currentMusic;
    _syncPalette(currentMusic?.coverPath);

    return FutureBuilder<CoverArtPalette>(
      future: _paletteFuture,
      builder: (context, snapshot) {
        final palette = snapshot.data ?? CoverColorService.fallbackPalette;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              // ── Background layer ──
              Positioned.fill(
                child: _buildBackground(context, currentMusic, theme),
              ),

              // ── Maximalist Background Text ──
              Positioned(
                left: -20,
                top: 150.h,
                child: Opacity(
                  opacity: 0.08,
                  child: RotatedBox(
                    quarterTurns: 1,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 320),
                      child: Text(
                        currentMusic?.title.toUpperCase() ?? 'PLAYERVF',
                        key: ValueKey(currentMusic?.id ?? 'bg-text'),
                        style: TextStyle(
                          fontSize: 120.sp,
                          fontWeight: FontWeight.w900,
                          color: theme.colorScheme.onSurface,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ── Main Content ──
              SafeArea(
                child: Column(
                  children: [
                    _buildTopBar(context, currentMusic, palette),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.symmetric(
                            horizontal: 24.w, vertical: 12.h),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(height: 10.h),
                            _buildHeroArtwork(
                                currentMusic, palette, musicService, settings),

                            SizedBox(height: 48.h),

                            // ── Metadata section ──
                            _buildMetadata(currentMusic, theme),

                            SizedBox(height: 40.h),

                            _buildControlsSection(musicService, theme, palette),

                            SizedBox(height: 32.h),

                            _buildQuickQueue(
                                context, musicService, theme, palette),

                            SizedBox(height: 40.h),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopBar(
      BuildContext context, Music? music, CoverArtPalette palette) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
            onPressed: widget.onClose,
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                music?.album.toUpperCase() ?? 'SINGLE',
                key: ValueKey(music?.album ?? 'none'),
                style: TextStyle(
                  fontSize: 10.sp,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: () => _showMoreOptions(context, palette),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground(
      BuildContext context, Music? currentMusic, ThemeData theme) {
    final policy = PerformancePolicy.of(context);
    final blur = policy.backgroundBlur;
    return AnimatedSwitcher(
      duration: policy.animation(const Duration(milliseconds: 520)),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 1.015, end: 1).animate(animation),
            child: child,
          ),
        );
      },
      child: Stack(
        key: ValueKey(currentMusic?.id ?? 'bg-none'),
        fit: StackFit.expand,
        children: [
          if (currentMusic != null)
            Transform.scale(
              scale: 1.08,
              child: CoverArtTexture(
                coverArtPath: currentMusic.coverPath,
                width: double.infinity,
                height: double.infinity,
              ),
            )
          else
            Container(color: theme.colorScheme.surface),
          if (blur > 0)
            ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: blur,
                  sigmaY: blur,
                ),
                child: ColoredBox(
                  color: theme.colorScheme.surface.withOpacity(
                    theme.brightness == Brightness.dark ? 0.72 : 0.78,
                  ),
                ),
              ),
            )
          else
            ColoredBox(
              color: theme.colorScheme.surface.withOpacity(
                theme.brightness == Brightness.dark ? 0.86 : 0.90,
              ),
            ),
        ],
      ),
    );
  }

  /// Hero artwork card for MUSIC (always shows cover art).
  Widget _buildHeroArtwork(Music? music, CoverArtPalette palette,
      MusicService musicService, SettingsModel settings) {
    final size = 320.s;

    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 340),
            width: size * 0.9,
            height: size * 0.9,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 460),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale:
                      Tween<double>(begin: 0.96, end: 1.0).animate(animation),
                  child: child,
                ),
              );
            },
            child: Hero(
              key: ValueKey(music?.id ?? 'none'),
              tag: 'music-art-${music?.id ?? 'none'}',
              child: GestureDetector(
                onTap: music == null
                    ? null
                    : () => _showLyricsSheet(context, musicService),
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28.s),
                    color: Colors.black,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28.s),
                    child: CoverArtTexture(
                      coverArtPath: music?.coverPath ?? '',
                      width: size,
                      height: size,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetadata(Music? music, ThemeData theme) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final offset = Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offset, child: child),
        );
      },
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.centerLeft,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      child: Column(
        key: ValueKey(music?.id ?? 'none'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            music?.title ?? 'Unknown Track',
            style: TextStyle(
              fontSize: 36.sp,
              fontWeight: FontWeight.w900,
              color: theme.colorScheme.onSurface,
              height: 1.1,
              letterSpacing: 0,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.left,
          ),
          SizedBox(height: 8.h),
          Text(
            music?.artist ?? 'Unknown Artist',
            style: TextStyle(
              fontSize: 20.sp,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withOpacity(0.5),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.left,
          ),
        ],
      ),
    );
  }

  Widget _buildControlsSection(
      MusicService musicService, ThemeData theme, CoverArtPalette palette) {
    return GlassContainer(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 18.h),
      borderRadius: BorderRadius.circular(24.s),
      color: null,
      blur: 8,
      child: Column(
        children: [
          PlaybackProgressControl(
            musicService: musicService,
            activeColor: theme.colorScheme.primary,
            inactiveColor: theme.colorScheme.onSurface.withOpacity(0.10),
            timeStyle: _timeStyle(theme),
          ),

          SizedBox(height: 20.h),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                iconSize: 22.s,
                icon: Icon(
                  musicService.isShuffle
                      ? Icons.shuffle_on_rounded
                      : Icons.shuffle_rounded,
                  color: musicService.isShuffle
                      ? palette.accent
                      : theme.colorScheme.onSurface.withOpacity(0.4),
                ),
                onPressed: musicService.toggleShuffle,
              ),
              IconButton(
                iconSize: 32.s,
                icon: const Icon(Icons.skip_previous_rounded),
                onPressed: musicService.previousTrack,
              ),
              ValueListenableBuilder<bool>(
                valueListenable: musicService.playingNotifier,
                builder: (context, isPlaying, child) {
                  return _SmoothPlayPauseButton(
                    isPlaying: isPlaying,
                    onPressed: musicService.togglePlayPause,
                    size: Size(72.s, 56.s),
                    iconSize: 34.s,
                  );
                },
              ),
              IconButton(
                iconSize: 32.s,
                icon: const Icon(Icons.skip_next_rounded),
                onPressed: musicService.next,
              ),
              IconButton(
                iconSize: 22.s,
                icon: Icon(
                  musicService.isRepeatOne
                      ? Icons.repeat_one_rounded
                      : Icons.repeat_rounded,
                  color: (musicService.isRepeatOne || musicService.isRepeatAll)
                      ? palette.accent
                      : theme.colorScheme.onSurface.withOpacity(0.4),
                ),
                onPressed: musicService.toggleRepeatMode,
              ),
            ],
          ),

          SizedBox(height: 20.h),

          // Volume Control with Percentage
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: ValueListenableBuilder<double>(
              valueListenable: musicService.volumeNotifier,
              builder: (context, volume, child) {
                return Row(
                  children: [
                    Icon(
                      volume == 0
                          ? Icons.volume_off_rounded
                          : volume < 50
                              ? Icons.volume_down_rounded
                              : Icons.volume_up_rounded,
                      size: 20.s,
                      color: theme.colorScheme.onSurface.withOpacity(0.3),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 6.h,
                          thumbShape:
                              RoundSliderThumbShape(enabledThumbRadius: 6.s),
                          activeTrackColor:
                              theme.colorScheme.onSurface.withOpacity(0.28),
                          inactiveTrackColor:
                              theme.colorScheme.onSurface.withOpacity(0.10),
                          thumbColor:
                              theme.colorScheme.onSurface.withOpacity(0.48),
                          overlayColor:
                              theme.colorScheme.onSurface.withOpacity(0.08),
                        ),
                        child: Slider(
                          value: volume,
                          min: 0,
                          max: 100,
                          onChanged: (val) => musicService.setVolume(val),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 40.w,
                      child: Text(
                        '${volume.toInt()}%',
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface.withOpacity(0.3),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickQueue(BuildContext context, MusicService musicService,
      ThemeData theme, CoverArtPalette palette) {
    final queue = musicService.queueMusicList;
    if (queue.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 8.w),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Next Tracks',
                style: TextStyle(
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface),
              ),
              TextButton(
                onPressed: () =>
                    _showQueueSheet(context, musicService, theme, palette),
                child: Text('Open Queue',
                    style: TextStyle(
                        color: palette.accent, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        SizedBox(height: 12.h),
        ...queue
            .skip(musicService.currentQueuePosition + 1)
            .take(3)
            .map((item) {
          return GlassContainer(
            margin: EdgeInsets.only(bottom: 12.h),
            padding: EdgeInsets.all(16.s),
            borderRadius: BorderRadius.circular(20.s),
            color: theme.colorScheme.onSurface.withOpacity(0.03),
            blur: 4,
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14.s),
                  child: CoverArtTexture(
                      coverArtPath: item.coverPath, width: 54.s, height: 54.s),
                ),
                SizedBox(width: 16.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14.sp),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(item.artist,
                          style: TextStyle(
                              fontSize: 12.sp,
                              color:
                                  theme.colorScheme.onSurface.withOpacity(0.4)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                IconButton(
                    icon: const Icon(Icons.playlist_play_rounded, size: 20),
                    onPressed: () => musicService.playMusicFromQueue(
                        musicService.queueMusicList, item)),
              ],
            ),
          );
        }),
      ],
    );
  }

  TextStyle _timeStyle(ThemeData theme) {
    return TextStyle(
        fontSize: 12.sp,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurface.withOpacity(0.4));
  }

  void _showMoreOptions(BuildContext context, CoverArtPalette palette) {
    final musicService = context.read<MusicService>();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => GlassContainer(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        color: Theme.of(sheetContext).colorScheme.surface.withOpacity(0.85),
        blur: 10,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                  leading: const Icon(Icons.equalizer_rounded),
                  title: const Text('Audio Effects'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) showAudioEffectsMenu(context);
                    });
                  }),
              ListTile(
                  leading: const Icon(Icons.playlist_add_rounded),
                  title: const Text('Add to Playlist'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        _showAddCurrentTrackToPlaylistDialog(
                            context, musicService);
                      }
                    });
                  }),
              ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('Track Details'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _showCurrentTrackDetails(context);
                    });
                  }),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddCurrentTrackToPlaylistDialog(
      BuildContext context, MusicService musicService) {
    final music = musicService.currentMusic;
    if (music == null) {
      _showPlayerSnack(context, 'No track selected.');
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: GlassContainer(
          width: 320,
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Add to Playlist',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (musicService.playlists.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Text('No playlists available.'),
                )
              else
                ...musicService.playlists.map(
                  (playlist) => ListTile(
                    leading: const Icon(Icons.playlist_play_rounded),
                    title: Text(playlist.name),
                    subtitle: Text('${playlist.musicIds.length} tracks'),
                    onTap: () {
                      musicService.addMusicToPlaylist(playlist.id, music.id);
                      Navigator.pop(dialogContext);
                      _showPlayerSnack(context, 'Added to ${playlist.name}.');
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCurrentTrackDetails(BuildContext context) {
    final music = context.read<MusicService>().currentMusic;
    if (music == null) {
      _showPlayerSnack(context, 'No track selected.');
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: GlassContainer(
          width: 420,
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: CoverArtTexture(
                      coverArtPath: music.coverPath,
                      width: 72,
                      height: 72,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          music.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          music.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _buildTrackDetailRow('Album', music.album),
              _buildTrackDetailRow('Genre', music.genre),
              _buildTrackDetailRow(
                  'Duration', _formatTrackDuration(music.duration)),
              _buildTrackDetailRow('Play count', music.playCount.toString()),
              _buildTrackDetailRow('File', music.filePath, maxLines: 2),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrackDetailRow(
    String label,
    String value, {
    int maxLines = 1,
  }) {
    final cleanValue = value.trim().isEmpty ? 'Unknown' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              cleanValue,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTrackDuration(Duration? duration) {
    if (duration == null || duration <= Duration.zero) return 'Unknown';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _showPlayerSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _showQueueSheet(BuildContext context, MusicService musicService,
      ThemeData theme, CoverArtPalette palette) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) => GlassContainer(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          color: theme.colorScheme.surface.withOpacity(0.92),
          blur: 10,
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Up Next',
                            style: TextStyle(
                                fontSize: 24.sp, fontWeight: FontWeight.w900)),
                        Text('Drag tracks to reorder',
                            style: TextStyle(
                                fontSize: 12.sp,
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.5))),
                      ],
                    ),
                    const Spacer(),
                    IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context)),
                  ],
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  scrollController: controller,
                  buildDefaultDragHandles: false,
                  itemCount: musicService.queueMusicList.length,
                  padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 40.h),
                  onReorder: (oldIndex, newIndex) {
                    musicService.moveQueueItem(oldIndex, newIndex);
                  },
                  itemBuilder: (context, index) {
                    final item = musicService.queueMusicList[index];
                    final isCurrent = musicService.currentMusic?.id == item.id;

                    return GlassContainer(
                      key: ValueKey(item.id),
                      margin: EdgeInsets.only(bottom: 8.h),
                      padding:
                          EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                      borderRadius: BorderRadius.circular(16),
                      color: isCurrent
                          ? palette.accent.withOpacity(0.1)
                          : Colors.white.withOpacity(0.02),
                      blur: 2,
                      child: ListTile(
                        contentPadding: EdgeInsets.symmetric(horizontal: 12.w),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox.square(
                            dimension: 44,
                            child: CoverArtTexture(
                              coverArtPath: item.coverPath,
                              width: 44,
                              height: 44,
                            ),
                          ),
                        ),
                        title: Text(
                          item.title,
                          style: TextStyle(
                            fontWeight:
                                isCurrent ? FontWeight.w900 : FontWeight.bold,
                            fontSize: 14.sp,
                            color: isCurrent ? palette.accent : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(item.artist,
                            style: TextStyle(fontSize: 12.sp)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isCurrent)
                              Icon(Icons.graphic_eq_rounded,
                                  color: palette.accent, size: 20),
                            const SizedBox(width: 8),
                            ReorderableDragStartListener(
                              index: index,
                              child: const Icon(Icons.drag_handle_rounded,
                                  color: Colors.white24),
                            ),
                          ],
                        ),
                        onTap: () => musicService.playMusicFromQueue(
                            musicService.queueMusicList, item),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showLyricsSheet(
      BuildContext context, MusicService musicService) async {
    if (_isLyricsSheetOpen) return;
    _isLyricsSheetOpen = true;
    final initialLyricsKey = _lyricsOwnerKey(musicService.currentMusic);
    final lyrics =
        await musicService.loadLyricsDocumentForCurrent(searchOnline: false);
    if (!context.mounted) {
      _isLyricsSheetOpen = false;
      return;
    }
    final currentLyricsKey = _lyricsOwnerKey(musicService.currentMusic);
    final initialLyrics = initialLyricsKey == currentLyricsKey ? lyrics : null;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.42,
        maxChildSize: 0.92,
        builder: (_, controller) => _LyricsSheetContent(
          musicService: musicService,
          initialLyrics: initialLyrics,
          initialLyricsKey: initialLyrics == null ? null : initialLyricsKey,
          scrollController: controller,
          pickLyricsFile: _pickLyricsFile,
        ),
      ),
    );
    if (mounted) _isLyricsSheetOpen = false;
  }

  Future<String?> _pickLyricsFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['lrc', 'txt', 'lyrics'],
      withData: false,
    );
    return result?.files.single.path;
  }
}

class _LyricsSheetContent extends StatefulWidget {
  final MusicService musicService;
  final LyricsDocument? initialLyrics;
  final String? initialLyricsKey;
  final ScrollController scrollController;
  final Future<String?> Function() pickLyricsFile;

  const _LyricsSheetContent({
    required this.musicService,
    required this.initialLyrics,
    required this.initialLyricsKey,
    required this.scrollController,
    required this.pickLyricsFile,
  });

  @override
  State<_LyricsSheetContent> createState() => _LyricsSheetContentState();
}

class _LyricsSheetContentState extends State<_LyricsSheetContent> {
  late LyricsDocument? _lyrics = widget.initialLyrics;
  String? _trackKey;
  String? _lyricsKey;
  int _lastActiveIndex = -1;
  bool _isSearchingLyrics = false;

  @override
  void initState() {
    super.initState();
    _trackKey = _currentLyricsKey;
    _lyricsKey =
        widget.initialLyricsKey == _trackKey ? widget.initialLyricsKey : null;
    if (_lyricsKey == null) _lyrics = null;
    widget.musicService.addListener(_handleMusicServiceChanged);
    if (_lyrics == null || _lyrics!.lines.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchLyrics(showResultMessage: false);
      });
    }
  }

  @override
  void dispose() {
    widget.musicService.removeListener(_handleMusicServiceChanged);
    super.dispose();
  }

  String? get _currentLyricsKey =>
      _lyricsOwnerKey(widget.musicService.currentMusic);

  void _handleMusicServiceChanged() {
    final nextTrackKey = _currentLyricsKey;
    if (nextTrackKey == _trackKey) return;
    _trackKey = nextTrackKey;
    _lastActiveIndex = -1;
    setState(() {
      _lyrics = null;
      _lyricsKey = null;
    });
    unawaited(_reloadLyricsForCurrentTrack());
  }

  Future<void> _reloadLyricsForCurrentTrack() async {
    final expectedTrackKey = _currentLyricsKey;
    final loaded = await widget.musicService
        .loadLyricsDocumentForCurrent(searchOnline: false);
    if (!mounted || expectedTrackKey != _currentLyricsKey) {
      return;
    }
    setState(() {
      _lyrics = loaded;
      _lyricsKey = loaded == null ? null : expectedTrackKey;
    });
    if (loaded == null || loaded.lines.isEmpty) {
      await _searchLyrics(showResultMessage: false, trackKey: expectedTrackKey);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleLyrics = _lyricsKey == _trackKey ? _lyrics : null;
    return GlassContainer(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      color: theme.colorScheme.surface.withOpacity(0.92),
      blur: 10,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withOpacity(0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.musicService.currentMusic?.title ?? 'Lyrics',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 22.sp,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Edit timed lyrics',
                  icon: const Icon(Icons.edit_note_rounded),
                  onPressed: _editLyrics,
                ),
                IconButton(
                  tooltip: 'Open fullscreen lyrics',
                  icon: const Icon(Icons.fullscreen_rounded),
                  onPressed:
                      visibleLyrics == null || visibleLyrics.lines.isEmpty
                          ? null
                          : _openFullscreenLyrics,
                ),
                IconButton(
                  tooltip: 'Search lyrics',
                  icon: _isSearchingLyrics
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : const Icon(Icons.manage_search_rounded),
                  onPressed: _isSearchingLyrics ? null : _searchLyrics,
                ),
                IconButton(
                  tooltip: 'Custom lyrics search',
                  icon: const Icon(Icons.tune_rounded),
                  onPressed:
                      _isSearchingLyrics ? null : _searchLyricsWithCustomInput,
                ),
                IconButton(
                  tooltip: 'Open lyrics file',
                  icon: const Icon(Icons.file_open_rounded),
                  onPressed: _openLyricsFile,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: visibleLyrics == null || visibleLyrics.lines.isEmpty
                  ? Center(
                      child: Text(
                        'No lyrics found. Edit lyrics, open an .lrc/.txt file, or let auto search try online.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    )
                  : visibleLyrics.hasTimedLines
                      ? _buildTimedLyrics(theme, visibleLyrics)
                      : SingleChildScrollView(
                          controller: widget.scrollController,
                          child: Text(
                            visibleLyrics.plainText,
                            style: TextStyle(fontSize: 18.sp, height: 1.55),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimedLyrics(ThemeData theme, LyricsDocument lyrics) {
    return ValueListenableBuilder<Duration>(
      valueListenable: widget.musicService.positionNotifier,
      builder: (context, position, _) {
        final activeIndex = lyrics.activeIndexAt(position);
        _scrollActiveLineIntoView(activeIndex);
        return ListView.builder(
          controller: widget.scrollController,
          padding: EdgeInsets.symmetric(vertical: 96.h),
          itemCount: lyrics.lines.length,
          itemBuilder: (context, index) {
            final line = lyrics.lines[index];
            final isActive = index == activeIndex;
            final isNear = (index - activeIndex).abs() == 1;
            final color = isActive
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withOpacity(isNear ? 0.72 : 0.38);
            return AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(
                horizontal: isActive ? 6.w : 0,
                vertical: isActive ? 14.h : 9.h,
              ),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontSize: isActive ? 23.sp : 18.sp,
                  height: 1.25,
                  fontWeight: isActive ? FontWeight.w900 : FontWeight.w600,
                ),
                child: Text(line.text),
              ),
            );
          },
        );
      },
    );
  }

  void _scrollActiveLineIntoView(int activeIndex) {
    if (activeIndex < 0 || activeIndex == _lastActiveIndex) return;
    _lastActiveIndex = activeIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.scrollController.hasClients) return;
      final target = (activeIndex * 54.0).clamp(
        0.0,
        widget.scrollController.position.maxScrollExtent,
      );
      widget.scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _openLyricsFile() async {
    final picked = await widget.pickLyricsFile();
    if (picked == null) return;
    final expectedTrackKey = _currentLyricsKey;
    final loaded = await widget.musicService
        .loadLyricsDocumentForCurrent(explicitPath: picked);
    if (!mounted || expectedTrackKey != _currentLyricsKey) {
      return;
    }
    setState(() {
      _lyrics = loaded;
      _lyricsKey = loaded == null ? null : expectedTrackKey;
    });
  }

  void _openFullscreenLyrics() {
    final lyrics = _lyrics;
    if (lyrics == null || lyrics.lines.isEmpty || _lyricsKey != _trackKey) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullscreenLyricsPage(
          musicService: widget.musicService,
          lyrics: lyrics,
          lyricsKey: _lyricsKey,
        ),
      ),
    );
  }

  Future<void> _searchLyrics({
    bool showResultMessage = true,
    String? trackKey,
  }) async {
    final expectedTrackKey = trackKey ?? _currentLyricsKey;
    setState(() => _isSearchingLyrics = true);
    final found = await widget.musicService.searchLyricsForCurrentOnline();
    if (!mounted || expectedTrackKey != _currentLyricsKey) {
      if (mounted) setState(() => _isSearchingLyrics = false);
      return;
    }
    setState(() {
      _lyrics = found;
      _lyricsKey = found == null ? null : expectedTrackKey;
      _isSearchingLyrics = false;
    });
    if (showResultMessage) _showLyricsSearchMessage(found != null);
  }

  Future<void> _searchLyricsWithCustomInput() async {
    final music = widget.musicService.currentMusic;
    final titleController = TextEditingController(text: music?.title ?? '');
    final artistController = TextEditingController(text: music?.artist ?? '');
    final albumController = TextEditingController(text: music?.album ?? '');
    final duration = music?.duration ?? widget.musicService.duration;
    final durationController = TextEditingController(
      text: duration > Duration.zero ? duration.inSeconds.toString() : '',
    );

    final params = await showModalBottomSheet<_LyricsSearchParameters?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: GlassContainer(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          color: Theme.of(context).colorScheme.surface.withOpacity(0.96),
          blur: 8,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Search Lyrics',
                        style: TextStyle(
                          fontSize: 20.sp,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () {
                        Navigator.pop(
                          context,
                          _LyricsSearchParameters(
                            title: titleController.text,
                            artist: artistController.text,
                            album: albumController.text,
                            durationSeconds:
                                int.tryParse(durationController.text.trim()),
                          ),
                        );
                      },
                      child: const Text('Search'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: artistController,
                  decoration: const InputDecoration(
                    labelText: 'Artist',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: albumController,
                  decoration: const InputDecoration(
                    labelText: 'Album',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: durationController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Duration seconds',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    titleController.dispose();
    artistController.dispose();
    albumController.dispose();
    durationController.dispose();
    if (params == null) return;

    setState(() => _isSearchingLyrics = true);
    final results = await widget.musicService.searchLyricsResultsForCurrent(
      title: params.title,
      artist: params.artist,
      album: params.album,
      durationSeconds: params.durationSeconds,
    );
    if (!mounted) {
      return;
    }
    setState(() => _isSearchingLyrics = false);
    if (results.isEmpty) {
      _showLyricsSearchMessage(false);
      return;
    }

    final selected = await _showLyricsSearchResults(results);
    if (selected == null) return;

    final expectedTrackKey = _currentLyricsKey;
    setState(() => _isSearchingLyrics = true);
    final found =
        await widget.musicService.saveLyricsResultForCurrent(selected);
    if (!mounted || expectedTrackKey != _currentLyricsKey) {
      if (mounted) setState(() => _isSearchingLyrics = false);
      return;
    }
    setState(() {
      _lyrics = found;
      _lyricsKey = found == null ? null : expectedTrackKey;
      _isSearchingLyrics = false;
    });
    _showLyricsSearchMessage(found != null);
  }

  Future<LrclibLyrics?> _showLyricsSearchResults(
    List<LrclibLyrics> results,
  ) {
    return showModalBottomSheet<LrclibLyrics>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.62,
        minChildSize: 0.38,
        maxChildSize: 0.88,
        builder: (_, controller) => GlassContainer(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          color: Theme.of(context).colorScheme.surface.withOpacity(0.96),
          blur: 8,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Choose Lyrics',
                        style: TextStyle(
                          fontSize: 20.sp,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    controller: controller,
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final result = results[index];
                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        tileColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withOpacity(0.42),
                        title: Text(
                          result.trackName ?? 'Unknown title',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          [
                            result.artistName ?? 'Unknown artist',
                            if (result.albumName?.trim().isNotEmpty == true)
                              result.albumName!,
                            if (result.durationSeconds != null)
                              _formatLyricsDuration(result.durationSeconds!),
                          ].join(' • '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Wrap(
                          spacing: 6,
                          children: [
                            if (result.hasSyncedLyrics)
                              const Chip(
                                label: Text('Sync'),
                                visualDensity: VisualDensity.compact,
                              ),
                            if (result.hasPlainLyrics)
                              const Chip(
                                label: Text('Plain'),
                                visualDensity: VisualDensity.compact,
                              ),
                          ],
                        ),
                        onTap: () => Navigator.pop(context, result),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatLyricsDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }

  void _showLyricsSearchMessage(bool found) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(found ? 'Lyrics saved.' : 'No lyrics found.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _editLyrics() async {
    final expectedTrackKey = _currentLyricsKey;
    final visibleLyrics = _lyricsKey == _trackKey ? _lyrics : null;
    final controller = TextEditingController(
      text: visibleLyrics?.rawText ??
          await widget.musicService.editableLyricsForCurrent(),
    );
    if (!mounted) return;
    final saved = await showModalBottomSheet<LyricsDocument?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: GlassContainer(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          color: Theme.of(context).colorScheme.surface.withOpacity(0.96),
          blur: 8,
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.78,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Edit Lyrics',
                          style: TextStyle(
                            fontSize: 20.sp,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () async {
                          final document = await widget.musicService
                              .saveLyricsForCurrent(controller.text);
                          if (context.mounted) {
                            Navigator.pop(context, document);
                          }
                        },
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        hintText:
                            '[00:12.50] First lyric line\n[00:18.00] Next lyric line',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    controller.dispose();
    if (saved != null && mounted && expectedTrackKey == _currentLyricsKey) {
      setState(() {
        _lyrics = saved;
        _lyricsKey = expectedTrackKey;
      });
    }
  }
}

class _FullscreenLyricsPage extends StatefulWidget {
  final MusicService musicService;
  final LyricsDocument lyrics;
  final String? lyricsKey;

  const _FullscreenLyricsPage({
    required this.musicService,
    required this.lyrics,
    required this.lyricsKey,
  });

  @override
  State<_FullscreenLyricsPage> createState() => _FullscreenLyricsPageState();
}

class _FullscreenLyricsPageState extends State<_FullscreenLyricsPage> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _lineKeys = {};
  late LyricsDocument _lyrics = widget.lyrics;
  String? _trackKey;
  String? _lyricsKey;
  int _lastActiveIndex = -1;

  @override
  void initState() {
    super.initState();
    _trackKey = _currentLyricsKey;
    _lyricsKey = widget.lyricsKey == _trackKey ? widget.lyricsKey : null;
    if (_lyricsKey == null) _lyrics = LyricsDocument.parse('', source: 'empty');
    widget.musicService.addListener(_handleMusicServiceChanged);
  }

  @override
  void dispose() {
    widget.musicService.removeListener(_handleMusicServiceChanged);
    _scrollController.dispose();
    super.dispose();
  }

  String? get _currentLyricsKey =>
      _lyricsOwnerKey(widget.musicService.currentMusic);

  void _handleMusicServiceChanged() {
    final nextTrackKey = _currentLyricsKey;
    if (nextTrackKey == _trackKey) return;
    _trackKey = nextTrackKey;
    _lastActiveIndex = -1;
    setState(() {
      _lyrics = LyricsDocument.parse('', source: 'empty');
      _lyricsKey = null;
    });
    _jumpLyricsToTop();
    unawaited(_reloadLyricsForCurrentTrack(nextTrackKey));
  }

  Future<void> _reloadLyricsForCurrentTrack(String? expectedTrackKey) async {
    final loaded = await widget.musicService
        .loadLyricsDocumentForCurrent(searchOnline: false);
    if (!mounted || expectedTrackKey != _currentLyricsKey) {
      return;
    }
    if (loaded != null && loaded.lines.isNotEmpty) {
      setState(() {
        _lyrics = loaded;
        _lyricsKey = expectedTrackKey;
      });
      _jumpLyricsToTop();
      return;
    }

    final searched = await widget.musicService.searchLyricsForCurrentOnline();
    if (!mounted || expectedTrackKey != _currentLyricsKey) {
      return;
    }
    setState(() {
      _lyrics = searched ?? LyricsDocument.parse('', source: 'empty');
      _lyricsKey = searched == null ? null : expectedTrackKey;
    });
    _jumpLyricsToTop();
  }

  void _jumpLyricsToTop() {
    _lineKeys.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final music = widget.musicService.currentMusic;
    final visibleLyrics = _lyricsKey == _trackKey
        ? _lyrics
        : LyricsDocument.parse('', source: 'empty');

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (music != null)
            CoverArtTexture(
              coverArtPath: music.coverPath,
              width: double.infinity,
              height: double.infinity,
            ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Container(color: Colors.black.withOpacity(0.62)),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
              child: Column(
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: SizedBox(
                          width: 58.s,
                          height: 58.s,
                          child: music == null
                              ? ColoredBox(color: theme.colorScheme.surface)
                              : CoverArtTexture(
                                  coverArtPath: music.coverPath,
                                  width: 58.s,
                                  height: 58.s,
                                ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              music?.title ?? 'Lyrics',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 21.sp,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              music?.artist ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.68),
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        color: Colors.white,
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      child: visibleLyrics.lines.isEmpty
                          ? _buildEmptyLyrics()
                          : visibleLyrics.hasTimedLines
                              ? _buildTimedLyrics(visibleLyrics)
                              : _buildPlainLyrics(visibleLyrics),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlainLyrics(LyricsDocument lyrics) {
    return SingleChildScrollView(
      key: ValueKey('plain-${_trackKey ?? 'none'}'),
      controller: _scrollController,
      padding: EdgeInsets.symmetric(vertical: 30.h),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, 18 * (1 - value)),
              child: child,
            ),
          );
        },
        child: Text(
          lyrics.plainText,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 25.sp,
            height: 1.45,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyLyrics() {
    return SizedBox.expand(
      key: ValueKey('empty-${_trackKey ?? 'none'}'),
    );
  }

  Widget _buildTimedLyrics(LyricsDocument lyrics) {
    return ValueListenableBuilder<Duration>(
      key: ValueKey('timed-${_trackKey ?? 'none'}'),
      valueListenable: widget.musicService.positionNotifier,
      builder: (context, position, _) {
        final activeIndex = lyrics.activeIndexAt(position);
        _scrollActiveLineIntoView(activeIndex);
        return ListView.builder(
          controller: _scrollController,
          padding: EdgeInsets.symmetric(vertical: 260.h),
          itemCount: lyrics.lines.length,
          itemBuilder: (context, index) {
            final line = lyrics.lines[index];
            final isActive = index == activeIndex;
            final distance = (index - activeIndex).abs();
            final opacity = isActive
                ? 1.0
                : distance == 1
                    ? 0.62
                    : 0.28;
            return AnimatedContainer(
              key: _lineKeys.putIfAbsent(index, GlobalKey.new),
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(
                horizontal: isActive ? 4.w : 0,
                vertical: isActive ? 18.h : 10.h,
              ),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(opacity),
                  fontSize: isActive ? 31.sp : 22.sp,
                  height: 1.2,
                  fontWeight: isActive ? FontWeight.w900 : FontWeight.w700,
                ),
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  scale: isActive ? 1.03 : 1.0,
                  child: Text(line.text),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _scrollActiveLineIntoView(int activeIndex) {
    if (activeIndex < 0 || activeIndex == _lastActiveIndex) return;
    _lastActiveIndex = activeIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final lineContext = _lineKeys[activeIndex]?.currentContext;
      if (lineContext != null) {
        Scrollable.ensureVisible(
          lineContext,
          alignment: 0.48,
          duration: const Duration(milliseconds: 460),
          curve: Curves.easeOutCubic,
        );
        return;
      }
      final viewport = _scrollController.position.viewportDimension;
      const estimatedLineExtent = 78.0;
      final target = ((activeIndex * estimatedLineExtent) -
              (viewport / 2) +
              (estimatedLineExtent / 2))
          .clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 460),
        curve: Curves.easeOutCubic,
      );
    });
  }
}

class _LyricsSearchParameters {
  final String title;
  final String artist;
  final String? album;
  final int? durationSeconds;

  _LyricsSearchParameters({
    required this.title,
    required this.artist,
    required String album,
    required this.durationSeconds,
  }) : album = album.trim().isEmpty ? null : album;
}

class _SmoothPlayPauseButton extends StatefulWidget {
  final bool isPlaying;
  final VoidCallback onPressed;
  final Size size;
  final double iconSize;

  const _SmoothPlayPauseButton({
    required this.isPlaying,
    required this.onPressed,
    required this.size,
    required this.iconSize,
  });

  @override
  State<_SmoothPlayPauseButton> createState() => _SmoothPlayPauseButtonState();
}

class _SmoothPlayPauseButtonState extends State<_SmoothPlayPauseButton> {
  bool? _optimisticIsPlaying;
  Timer? _optimisticTimer;

  bool get _visualIsPlaying => _optimisticIsPlaying ?? widget.isPlaying;

  @override
  void didUpdateWidget(covariant _SmoothPlayPauseButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_optimisticIsPlaying != null &&
        widget.isPlaying == _optimisticIsPlaying) {
      _clearOptimisticState();
    }
  }

  @override
  void dispose() {
    _optimisticTimer?.cancel();
    super.dispose();
  }

  void _clearOptimisticState() {
    _optimisticTimer?.cancel();
    _optimisticTimer = null;
    _optimisticIsPlaying = null;
  }

  void _handlePressed() {
    final nextVisualState = !_visualIsPlaying;
    _optimisticTimer?.cancel();
    setState(() => _optimisticIsPlaying = nextVisualState);
    _optimisticTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() => _optimisticIsPlaying = null);
      }
    });
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visualIsPlaying = _visualIsPlaying;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: visualIsPlaying ? 1 : 0),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.scale(
          scale: 0.98 + (value * 0.02),
          child: FilledButton(
            onPressed: _handlePressed,
            style: FilledButton.styleFrom(
              minimumSize: widget.size,
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20.s),
              ),
              backgroundColor: Color.lerp(
                theme.colorScheme.primaryContainer,
                theme.colorScheme.primary.withOpacity(0.24),
                value,
              ),
              foregroundColor: theme.colorScheme.onPrimaryContainer,
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final scale = Tween<double>(begin: 0.9, end: 1).animate(
                  CurvedAnimation(
                      parent: animation, curve: Curves.easeOutCubic),
                );
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: scale, child: child),
                );
              },
              child: Icon(
                visualIsPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                key: ValueKey(visualIsPlaying),
                size: widget.iconSize,
              ),
            ),
          ),
        );
      },
    );
  }
}
