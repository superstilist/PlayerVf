import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';

import '../models/music_model.dart';
import '../services/cover_color_service.dart';
import '../services/music_service.dart';
import '../services/responsive.dart';
import '../widgets/audio_effects_menu.dart';
import '../widgets/cover_art_texture.dart';
import '../widgets/glass_container.dart';
import '../models/settings_model.dart';
import 'package:media_kit_video/media_kit_video.dart';

class PlayerPage extends StatefulWidget {
  final VoidCallback onClose;

  const PlayerPage({super.key, required this.onClose});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with SingleTickerProviderStateMixin {
  Future<CoverArtPalette>? _paletteFuture;
  String _palettePath = '';
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

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
                child: _buildBackground(musicService, settings, currentMusic, theme),
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
                      duration: const Duration(milliseconds: 800),
                      child: Text(
                        currentMusic?.title.toUpperCase() ?? 'PLAYERVF',
                        key: ValueKey(currentMusic?.id ?? 'bg-text'),
                        style: TextStyle(
                          fontSize: 120.sp,
                          fontWeight: FontWeight.w900,
                          color: theme.colorScheme.onSurface,
                          letterSpacing: -5,
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
                        padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(height: 10.h),
                            _buildHeroArtwork(currentMusic, palette, musicService, settings),
                            
                            SizedBox(height: 48.h),

                            // ── Metadata section (Bigger & Left Aligned) ──
                            _buildMetadata(currentMusic, theme),

                            SizedBox(height: 40.h),

                            _buildControlsSection(musicService, theme, palette),

                            SizedBox(height: 32.h),

                            _buildQuickQueue(context, musicService, theme, palette),
                            
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

  Widget _buildTopBar(BuildContext context, Music? music, CoverArtPalette palette) {
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
              duration: const Duration(milliseconds: 400),
              child: Text(
                music?.album.toUpperCase() ?? 'SINGLE',
                key: ValueKey(music?.album ?? 'none'),
                style: TextStyle(
                  fontSize: 10.sp,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.5,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
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

  /// Build the full-screen background: video or blurred cover art
  Widget _buildBackground(MusicService musicService, SettingsModel settings, Music? currentMusic, ThemeData theme) {
    final bool showVideo = musicService.isCurrentMediaVideo && settings.playVideoBackground && musicService.videoController != null;
    
    return AnimatedSwitcher(
      duration: const Duration(seconds: 1),
      transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
      child: Stack(
        key: ValueKey('${showVideo ? 'video' : 'art'}-${currentMusic?.id}'),
        fit: StackFit.expand,
        children: [
          // ALWAYS SHOW COVER ART (Base Layer / Fallback / Placeholder)
          CoverArtTexture(
            coverArtPath: currentMusic?.coverPath ?? '',
            width: double.infinity,
            height: double.infinity,
          ),

          // Overlay Video if available and enabled
          if (showVideo)
            SizedBox.expand(
              child: Video(
                controller: musicService.videoController!,
                fit: BoxFit.cover,
                controls: NoVideoControls,
              ),
            ),

          // Blur Layer: Only apply blur if we are in "Art Mode" (no video showing)
          if (!showVideo)
            ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 40.0, sigmaY: 40.0),
                child: Container(color: Colors.transparent),
              ),
            ),

          // Final Dimming Overlay
          Container(
            color: theme.brightness == Brightness.dark
                ? Colors.black.withOpacity(showVideo ? 0.45 : 0.75)
                : Colors.white.withOpacity(showVideo ? 0.45 : 0.75),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroArtwork(Music? music, CoverArtPalette palette, MusicService musicService, SettingsModel settings) {
    final size = 320.s;
    final bool hasVideo = musicService.isCurrentMediaVideo && musicService.videoController != null;
    final bool showLiveVideo = hasVideo && settings.videoCoverShowLive;

    // STACKED CONTENT: Cover art is always the base, Video overlays if live
    Widget artworkContent = Stack(
      fit: StackFit.expand,
      children: [
        CoverArtTexture(
          coverArtPath: music?.coverPath ?? '',
          width: size,
          height: size,
        ),
        if (showLiveVideo)
          SizedBox.expand(
            child: Video(
              controller: musicService.videoController!,
              fit: BoxFit.cover,
              controls: NoVideoControls,
            ),
          ),
      ],
    );

    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(seconds: 1),
            width: size * 0.9,
            height: size * 0.9,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 600),
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: Tween<double>(begin: 0.85, end: 1.0).animate(animation), child: child),
              );
            },
            child: GestureDetector(
              onDoubleTap: (hasVideo && settings.videoDoubleTapFullscreen)
                  ? () => _openFullscreenVideo(context, musicService)
                  : null,
              child: Hero(
                key: ValueKey(music?.id ?? 'none'),
                tag: 'music-art-${music?.id ?? 'none'}',
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(40.s),
                    color: Colors.black,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(40.s),
                    child: artworkContent,
                  ),
                ),
              ),
            ),
          ),
          // Show a small fullscreen hint icon when video is available
          if (hasVideo && settings.videoDoubleTapFullscreen)
            Positioned(
              bottom: 0,
              right: 0,
              child: GestureDetector(
                onTap: () => _openFullscreenVideo(context, musicService),
                child: Container(
                  padding: EdgeInsets.all(14.s),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(24.s),
                      bottomRight: Radius.circular(40.s),
                    ),
                  ),
                  child: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 28),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _openFullscreenVideo(BuildContext context, MusicService musicService) {
    if (musicService.videoController == null) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: Scaffold(
              backgroundColor: Colors.black,
              body: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                onDoubleTap: () => Navigator.of(context).pop(),
                child: Center(
                  child: Video(
                    controller: musicService.videoController!,
                    fit: BoxFit.contain,
                    controls: NoVideoControls,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMetadata(Music? music, ThemeData theme) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.centerLeft,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      child: Row(
        key: ValueKey(music?.id ?? 'none'),
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Permanent Small Thumbnail (Visible even if main video is playing)
          Container(
            width: 60.s,
            height: 60.s,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16.s),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16.s),
              child: CoverArtTexture(
                coverArtPath: music?.coverPath ?? '',
                width: 60.s,
                height: 60.s,
              ),
            ),
          ),
          SizedBox(width: 20.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  music?.title ?? 'Unknown Track',
                  style: TextStyle(
                    fontSize: 32.sp,
                    fontWeight: FontWeight.w900,
                    color: theme.colorScheme.onSurface,
                    height: 1.1,
                    letterSpacing: -0.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 4.h),
                Text(
                  music?.artist ?? 'Unknown Artist',
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsSection(MusicService musicService, ThemeData theme, CoverArtPalette palette) {
    return GlassContainer(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 24.h),
      borderRadius: BorderRadius.circular(40.s),
      color: theme.colorScheme.onSurface.withOpacity(0.04),
      blur: 15,
      child: Column(
        children: [
          ValueListenableBuilder<Duration>(
            valueListenable: musicService.positionNotifier,
            builder: (context, position, child) {
              final duration = musicService.durationNotifier.value;
              final progress = duration.inMilliseconds > 0 
                  ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
                  : 0.0;
              return Column(
                children: [
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 6.h,
                      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8.s),
                      activeTrackColor: palette.accent,
                      inactiveTrackColor: theme.colorScheme.onSurface.withOpacity(0.08),
                      thumbColor: palette.accent,
                      overlayColor: palette.accent.withOpacity(0.15),
                    ),
                    child: Slider(
                      value: progress,
                      onChanged: (value) {
                        final target = Duration(milliseconds: (value * duration.inMilliseconds).toInt());
                        musicService.seekTo(target);
                      },
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20.w),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_formatDuration(position), style: _timeStyle(theme)),
                        Text(_formatDuration(duration), style: _timeStyle(theme)),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          
          SizedBox(height: 24.h),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                iconSize: 24.s,
                icon: Icon(
                  musicService.isShuffle ? Icons.shuffle_on_rounded : Icons.shuffle_rounded,
                  color: musicService.isShuffle ? palette.accent : theme.colorScheme.onSurface.withOpacity(0.4),
                ),
                onPressed: musicService.toggleShuffle,
              ),
              IconButton(
                iconSize: 48.s,
                icon: const Icon(Icons.skip_previous_rounded),
                onPressed: musicService.previous,
              ),
              GestureDetector(
                onTap: musicService.togglePlayPause,
                child: Container(
                  width: 84.s,
                  height: 84.s,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.accent,
                  ),
                  child: ValueListenableBuilder<bool>(
                    valueListenable: musicService.playingNotifier,
                    builder: (context, isPlaying, child) {
                      return Icon(
                        isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 48.s,
                      );
                    },
                  ),
                ),
              ),
              IconButton(
                iconSize: 48.s,
                icon: const Icon(Icons.skip_next_rounded),
                onPressed: musicService.next,
              ),
              IconButton(
                iconSize: 24.s,
                icon: Icon(
                  musicService.isRepeatOne ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                  color: (musicService.isRepeatOne || musicService.isRepeatAll) ? palette.accent : theme.colorScheme.onSurface.withOpacity(0.4),
                ),
                onPressed: musicService.toggleRepeatMode,
              ),
            ],
          ),

          SizedBox(height: 24.h),
          
          // Volume Control with Percentage
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: ValueListenableBuilder<double>(
              valueListenable: musicService.volumeNotifier,
              builder: (context, volume, child) {
                return Row(
                  children: [
                    Icon(
                      volume == 0 ? Icons.volume_off_rounded : volume < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded,
                      size: 20.s, 
                      color: theme.colorScheme.onSurface.withOpacity(0.3),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 4.h,
                          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6.s),
                          activeTrackColor: theme.colorScheme.onSurface.withOpacity(0.2),
                          inactiveTrackColor: theme.colorScheme.onSurface.withOpacity(0.05),
                          thumbColor: theme.colorScheme.onSurface.withOpacity(0.4),
                          overlayColor: Colors.transparent,
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

  Widget _buildQuickQueue(BuildContext context, MusicService musicService, ThemeData theme, CoverArtPalette palette) {
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
                style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface),
              ),
              TextButton(
                onPressed: () => _showQueueSheet(context, musicService, theme, palette),
                child: Text('Open Queue', style: TextStyle(color: palette.accent, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        SizedBox(height: 12.h),
        ...queue.skip(musicService.currentQueuePosition + 1).take(3).map((item) {
          return GlassContainer(
            margin: EdgeInsets.only(bottom: 12.h),
            padding: EdgeInsets.all(16.s),
            borderRadius: BorderRadius.circular(24.s),
            color: theme.colorScheme.onSurface.withOpacity(0.03),
            blur: 10,
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14.s),
                  child: CoverArtTexture(coverArtPath: item.coverPath, width: 54.s, height: 54.s),
                ),
                SizedBox(width: 16.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(item.artist, style: TextStyle(fontSize: 12.sp, color: theme.colorScheme.onSurface.withOpacity(0.4)), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.playlist_play_rounded, size: 20), onPressed: () => musicService.playMusicFromQueue(musicService.queueMusicList, item)),
              ],
            ),
          );
        }),
      ],
    );
  }

  TextStyle _timeStyle(ThemeData theme) {
    return TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface.withOpacity(0.4));
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _showMoreOptions(BuildContext context, CoverArtPalette palette) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => GlassContainer(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        color: Theme.of(context).colorScheme.surface.withOpacity(0.85),
        blur: 25,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(leading: const Icon(Icons.equalizer_rounded), title: const Text('Audio Effects'), onTap: () { Navigator.pop(context); showAudioEffectsMenu(context); }),
              ListTile(leading: const Icon(Icons.playlist_add_rounded), title: const Text('Add to Playlist'), onTap: () => Navigator.pop(context)),
              ListTile(leading: const Icon(Icons.info_outline_rounded), title: const Text('Track Details'), onTap: () => Navigator.pop(context)),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _showQueueSheet(BuildContext context, MusicService musicService, ThemeData theme, CoverArtPalette palette) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85, minChildSize: 0.5, maxChildSize: 0.95,
        builder: (_, controller) => GlassContainer(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          color: theme.colorScheme.surface.withOpacity(0.92),
          blur: 25,
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: theme.colorScheme.onSurface.withOpacity(0.1), borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Up Next', style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.w900)),
                        Text('Drag tracks to reorder', style: TextStyle(fontSize: 12.sp, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                      ],
                    ),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
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
                      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                      borderRadius: BorderRadius.circular(16),
                      color: isCurrent ? palette.accent.withOpacity(0.1) : Colors.white.withOpacity(0.02),
                      blur: 5,
                      child: ListTile(
                        contentPadding: EdgeInsets.symmetric(horizontal: 12.w),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: CoverArtTexture(coverArtPath: item.coverPath, width: 44, height: 44),
                        ),
                        title: Text(
                          item.title,
                          style: TextStyle(
                            fontWeight: isCurrent ? FontWeight.w900 : FontWeight.bold,
                            fontSize: 14.sp,
                            color: isCurrent ? palette.accent : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(item.artist, style: TextStyle(fontSize: 12.sp)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isCurrent) Icon(Icons.graphic_eq_rounded, color: palette.accent, size: 20),
                            const SizedBox(width: 8),
                            ReorderableDragStartListener(
                              index: index,
                              child: const Icon(Icons.drag_handle_rounded, color: Colors.white24),
                            ),
                          ],
                        ),
                        onTap: () => musicService.playMusicFromQueue(musicService.queueMusicList, item),
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
}
