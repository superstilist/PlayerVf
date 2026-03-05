import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/music_service.dart';
import '../models/music_model.dart';
import '../models/cover_model.dart';
import '../widgets/cover_art_texture.dart';
import '../widgets/fade_in_up_animation.dart';

import '../services/responsive.dart';

class PlayerPage extends StatelessWidget {
  final VoidCallback onClose;

  const PlayerPage({super.key, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicService>(
      builder: (context, musicService, child) {
        final currentMusic = musicService.currentMusic;

        double coverSize = 300.s; // Base size using 's' for aspect ratio maintenance

        return Scaffold(
          backgroundColor: const Color(0xFF0A0A0A),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 24.w),
              child: Column(
                children: [
                  SizedBox(height: 20.h),
                  _buildTopBar(context, currentMusic),
                  SizedBox(height: 40.h),
                  _buildCoverSection(currentMusic, coverSize),
                  SizedBox(height: 50.h),
                  _buildSongInfo(currentMusic),
                  SizedBox(height: 40.h),
                  _buildProgressSlider(musicService),
                  SizedBox(height: 20.h),
                  _buildPlaybackControls(musicService),
                  SizedBox(height: 40.h),
                  _buildBottomActions(context, musicService, currentMusic),
                  SizedBox(height: 20.h),
                ],
              ),
            ),
          ),
        );
      },
    );
  }


  Widget _buildTopBar(BuildContext context, Music? currentMusic) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: Icon(Icons.keyboard_arrow_down_rounded, size: 36.s, color: Colors.white),
          onPressed: onClose,
        ),
        Text(
          'Now Playing',
          style: TextStyle(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        IconButton(
          icon: Icon(Icons.more_vert_rounded, color: Colors.white, size: 24.s),
          onPressed: () {},
        ),
      ],
    );
  }

  Widget _buildCoverSection(Music? music, double size) {
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
          coverArtPath: music?.coverPath ?? '',
          width: size,
          height: size,
          borderRadius: BorderRadius.circular(30.s),
        ),
      ),
    );
  }


  Widget _buildSongInfo(Music? music) {
    return Column(
      children: [
        Text(
          music?.title ?? 'Unknown Title',
          style: TextStyle(color: Colors.white, fontSize: 24.sp, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: 8.h),
        Text(
          music?.artist ?? 'Unknown Artist',
          style: TextStyle(color: Colors.grey[400], fontSize: 16.sp),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildProgressSlider(MusicService musicService) {
    final pos = musicService.position;
    final dur = musicService.duration;
    
    return Column(
      children: [
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4.h,
            thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6.s),
            overlayShape: RoundSliderOverlayShape(overlayRadius: 14.s),
            activeTrackColor: Colors.teal,
            inactiveTrackColor: Colors.grey[800],
            thumbColor: Colors.white,
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
              Text(_formatDuration(pos), style: TextStyle(color: Colors.grey, fontSize: 12.sp)),
              Text(_formatDuration(dur), style: TextStyle(color: Colors.grey, fontSize: 12.sp)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlaybackControls(MusicService musicService) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          iconSize: 24.s,
          icon: Icon(
            Icons.shuffle_rounded,
            color: musicService.isShuffle ? Colors.teal : Colors.grey[600],
          ),
          onPressed: musicService.toggleShuffle,
        ),
        IconButton(
          icon: Icon(Icons.skip_previous_rounded, size: 40.s, color: Colors.white),
          onPressed: musicService.previous,
        ),
        GestureDetector(
          onTap: musicService.togglePlayPause,
          child: Container(
            padding: EdgeInsets.all(16.s),
            decoration: const BoxDecoration(color: Colors.teal, shape: BoxShape.circle),
            child: Icon(
              musicService.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 40.s,
              color: Colors.white,
            ),
          ),
        ),
        IconButton(
          icon: Icon(Icons.skip_next_rounded, size: 40.s, color: Colors.white),
          onPressed: musicService.next,
        ),
        IconButton(
          iconSize: 24.s,
          icon: Icon(
            musicService.isRepeatOne ? Icons.repeat_one_rounded : Icons.repeat_rounded,
            color: (musicService.isRepeatOne || musicService.isRepeatAll) ? Colors.teal : Colors.grey[600],
          ),
          onPressed: musicService.toggleRepeatMode,
        ),
      ],
    );
  }

  Widget _buildBottomActions(BuildContext context, MusicService musicService, Music? music) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          icon: Icon(
            music?.isFavorite == true ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: music?.isFavorite == true ? Colors.red : Colors.grey[400],
            size: 24.s,
          ),
          onPressed: () {
            if (music != null) musicService.toggleFavorite(music.id);
          },
        ),
        IconButton(
          icon: Icon(Icons.playlist_add_rounded, color: Colors.grey[400], size: 24.s),
          onPressed: () {},
        ),
        IconButton(
          icon: Icon(Icons.share_rounded, color: Colors.grey[400], size: 24.s),
          onPressed: () {},
        ),
      ],
    );
  }


  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
