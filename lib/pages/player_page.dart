import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/music_service.dart';
import '../models/music_model.dart';
import '../widgets/cover_art_texture.dart';
import '../widgets/audio_effects_menu.dart';

import '../services/responsive.dart';

class PlayerPage extends StatelessWidget {
  final VoidCallback onClose;

  const PlayerPage({super.key, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Consumer<MusicService>(
      builder: (context, musicService, child) {
        final currentMusic = musicService.currentMusic;

        double coverSize = 300.s; // Base size using 's' for aspect ratio maintenance

        return Scaffold(
          backgroundColor: theme.colorScheme.surface,
          body: SafeArea(
            child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 24.w),
                child: Column(
                  children: [
                    SizedBox(height: 40.h),
                  _buildTopBar(context, currentMusic, theme),
                  SizedBox(height: 40.h),
                  _buildCoverSection(currentMusic, coverSize, theme),
                  SizedBox(height: 50.h),
                  _buildSongInfo(currentMusic, theme),
                  SizedBox(height: 40.h),
                  _buildProgressSlider(musicService, theme),
                  SizedBox(height: 20.h),
                  _buildPlaybackControls(musicService, theme),
                  SizedBox(height: 40.h),
                  _buildBottomActions(context, musicService, currentMusic, theme),
                  SizedBox(height: 20.h),
                ],
              ),
            ),
          ),
        );
      },
    );
  }


  Widget _buildTopBar(BuildContext context, Music? currentMusic, ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: Icon(Icons.keyboard_arrow_down_rounded, size: 36.s, color: theme.colorScheme.onSurface),
          onPressed: onClose,
        ),
        Text(
          'Now Playing',
          style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 16.sp, fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        IconButton(
          icon: Icon(Icons.more_vert_rounded, color: theme.colorScheme.onSurface, size: 24.s),
          onPressed: () {},
        ),
      ],
    );
  }

  Widget _buildCoverSection(Music? music, double size, ThemeData theme) {
    // Use a unique key based on music ID to prevent unnecessary rebuilds
    final coverKey = ValueKey('cover_${music?.id ?? 'empty'}');
    
    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30.s),
          boxShadow: [
            BoxShadow(
              color: Colors.teal.withOpacity(0.2),
              blurRadius: 40.s,
              spreadRadius: 5.s,
            ),
          ],
        ),
        child: CoverArtTexture(
          key: coverKey,
          coverArtPath: music?.coverPath ?? '',
          musicId: music?.id,
          width: size,
          height: size,
          borderRadius: BorderRadius.circular(30.s),
        ),
      ),
    );
  }


  Widget _buildSongInfo(Music? music, ThemeData theme) {
    return Column(
      children: [
        Text(
          music?.title ?? 'Unknown Title',
          style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 24.sp, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: 8.h),
        Text(
          music?.artist ?? 'Unknown Artist',
          style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 16.sp),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildProgressSlider(MusicService musicService, ThemeData theme) {
    // Use ValueListenableBuilder for efficient position updates without rebuilding entire page
    return ValueListenableBuilder<Duration>(
      valueListenable: musicService.positionNotifier,
      builder: (context, pos, child) {
        return ValueListenableBuilder<Duration>(
          valueListenable: musicService.durationNotifier,
          builder: (context, dur, child) {
            return Column(
              children: [
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 4.h,
                    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6.s),
                    overlayShape: RoundSliderOverlayShape(overlayRadius: 14.s),
                    activeTrackColor: Colors.teal,
                    inactiveTrackColor: theme.colorScheme.onSurface.withOpacity(0.2),
                    thumbColor: theme.colorScheme.onSurface,
                  ),
                  child: Slider(
                    value: pos.inSeconds.toDouble().clamp(0, dur.inSeconds.toDouble() + 1),
                    max: dur.inSeconds > 0 ? dur.inSeconds.toDouble() : 1,
                    onChanged: (v) => musicService.seekTo(Duration(seconds: v.toInt())),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(pos), style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 12.sp)),
                      Text(_formatDuration(dur), style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 12.sp)),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPlaybackControls(MusicService musicService, ThemeData theme) {
    // Use ValueListenableBuilder for efficient playing state updates
    return ValueListenableBuilder<bool>(
      valueListenable: musicService.playingNotifier,
      builder: (context, isPlaying, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              iconSize: 24.s,
              icon: Icon(
                Icons.shuffle_rounded,
                color: musicService.isShuffle ? Colors.teal : theme.colorScheme.onSurface.withOpacity(0.6),
              ),
              onPressed: musicService.toggleShuffle,
            ),
            IconButton(
              icon: Icon(Icons.skip_previous_rounded, size: 40.s, color: theme.colorScheme.onSurface),
              onPressed: musicService.previous,
            ),
            GestureDetector(
              onTap: musicService.togglePlayPause,
              child: Container(
                padding: EdgeInsets.all(16.s),
                decoration: const BoxDecoration(color: Colors.teal, shape: BoxShape.circle),
                child: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 40.s,
                  color: Colors.white,
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.skip_next_rounded, size: 40.s, color: theme.colorScheme.onSurface),
              onPressed: musicService.next,
            ),
            IconButton(
              iconSize: 24.s,
              icon: Icon(
                musicService.isRepeatOne ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                color: (musicService.isRepeatOne || musicService.isRepeatAll) ? Colors.teal : theme.colorScheme.onSurface.withOpacity(0.6),
              ),
              onPressed: musicService.toggleRepeatMode,
            ),
          ],
        );
      },
    );
  }

  Widget _buildBottomActions(BuildContext context, MusicService musicService, Music? music, ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          icon: Icon(
            music?.isFavorite == true ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: music?.isFavorite == true ? Colors.red : theme.colorScheme.onSurface.withOpacity(0.6),
            size: 24.s,
          ),
          onPressed: () {
            if (music != null) musicService.toggleFavorite(music.id);
          },
        ),
        IconButton(
          icon: Icon(Icons.playlist_add_rounded, color: theme.colorScheme.onSurface.withOpacity(0.6), size: 24.s),
          onPressed: () {},
        ),
        IconButton(
          icon: Icon(Icons.tune_rounded, color: theme.colorScheme.onSurface.withOpacity(0.6), size: 24.s),
          onPressed: () {
            _showAudioEffects(context);
          },
        ),
        IconButton(
          icon: Icon(Icons.share_rounded, color: theme.colorScheme.onSurface.withOpacity(0.6), size: 24.s),
          onPressed: () {},
        ),
      ],
    );
  }

  void _showAudioEffects(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) => const AudioEffectsMenu(),
    );
  }


  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
