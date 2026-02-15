import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/music_service.dart';
import '../models/music_model.dart';
import '../models/cover_model.dart';
import '../widgets/cover_art_texture.dart';
import 'dart:io' as io;

class PlayerPage extends StatelessWidget {
  final VoidCallback onClose;

  const PlayerPage({super.key, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicService>(
      builder: (context, musicService, child) {
        final currentMusic = musicService.currentMusic;
        final currentCover = musicService.currentCover;
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;

        // Calculate responsive cover size
        double coverSize = screenWidth * 0.75;
        if (coverSize > 400) coverSize = 400;
        if (coverSize < 250) coverSize = screenWidth * 0.85;

        return Scaffold(
          backgroundColor: const Color(0xFF0D0D0D),
          body: SafeArea(
            child: Column(
              children: [
                // Top bar
                _buildTopBar(context, currentMusic),
                
                // Main content area
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: screenWidth * 0.06,
                      ),
                      child: Column(
                        children: [
                          SizedBox(height: screenHeight * 0.03),
                          
                          // Cover art
                          _buildCoverSection(
                            currentCover, 
                            currentMusic, 
                            coverSize,
                          ),
                          
                          SizedBox(height: screenHeight * 0.04),
                          
                          // Song info
                          _buildSongInfo(currentMusic),
                          
                          SizedBox(height: screenHeight * 0.03),
                          
                          // Progress slider
                          _buildProgressSlider(musicService),
                          
                          SizedBox(height: screenHeight * 0.02),
                          
                          // Playback controls
                          _buildPlaybackControls(musicService),
                          
                          SizedBox(height: screenHeight * 0.03),
                          
                          // Bottom actions
                          _buildBottomActions(context),
                          
                          SizedBox(height: screenHeight * 0.02),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopBar(BuildContext context, Music? currentMusic) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, size: 36),
            onPressed: onClose,
            color: Colors.white,
          ),
          const Text(
            'Now Playing',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showSongMenu(context, currentMusic),
            color: Colors.white,
          ),
        ],
      ),
    );
  }

  Widget _buildCoverSection(Cover? cover, Music? music, double coverSize) {
    return Center(
      child: Container(
        width: coverSize,
        height: coverSize,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.teal.withOpacity(0.3),
              blurRadius: 30,
              spreadRadius: 5,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: _buildCoverWidget(cover, music, coverSize),
        ),
      ),
    );
  }

  Widget _buildCoverWidget(Cover? cover, Music? music, double size) {
    // First try to use imageData from cover
    if (cover != null && cover.imageData != null) {
      try {
        return Image.memory(
          cover.imageData!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildDefaultCover(size);
          },
        );
      } catch (_) {
        return _buildDefaultCover(size);
      }
    }

    // Try to load from file path
    if (music != null && music.coverPath.isNotEmpty) {
      try {
        if (music.coverPath.startsWith('assets/')) {
          return CoverArtTexture(
            coverArtPath: music.coverPath,
            width: size,
            height: size,
            borderRadius: BorderRadius.circular(24),
          );
        } else {
          final file = io.File(music.coverPath);
          if (file.existsSync()) {
            return CoverArtTexture(
              coverArtPath: music.coverPath,
              width: size,
              height: size,
              borderRadius: BorderRadius.circular(24),
            );
          }
        }
      } catch (_) {
        return _buildDefaultCover(size);
      }
    }

    return _buildDefaultCover(size);
  }

  Widget _buildDefaultCover(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.teal.shade700,
            Colors.teal.shade900,
            Colors.black87,
          ],
        ),
      ),
      child: const Icon(
        Icons.music_note,
        color: Colors.white54,
        size: 80,
      ),
    );
  }

  Widget _buildSongInfo(Music? currentMusic) {
    final title = currentMusic?.title ?? 'No Track Playing';
    final artist = currentMusic?.artist ?? 'Unknown Artist';
    final album = currentMusic?.album ?? 'Unknown Album';

    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Text(
          '$artist • $album',
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 16,
            letterSpacing: 0.3,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildProgressSlider(MusicService musicService) {
    final position = musicService.position;
    final duration = musicService.duration;
    final maxSeconds = duration.inSeconds.toDouble();
    final positionSeconds = position.inSeconds.toDouble();

    // Handle edge cases for slider
    double sliderValue = positionSeconds;
    double sliderMax = maxSeconds > 0 ? maxSeconds : 1;
    if (sliderValue > sliderMax) sliderValue = sliderMax;
    if (sliderValue < 0) sliderValue = 0;

    return Column(
      children: [
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: Colors.teal,
            inactiveTrackColor: Colors.grey[700],
            thumbColor: Colors.teal,
            overlayColor: Colors.teal.withOpacity(0.2),
          ),
          child: Slider(
            value: sliderValue,
            min: 0,
            max: sliderMax,
            onChanged: (value) {
              musicService.seekTo(Duration(seconds: value.toInt()));
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(position),
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              ),
              Text(
                _formatDuration(duration),
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlaybackControls(MusicService musicService) {
    final isPlaying = musicService.isPlaying;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Shuffle button
        IconButton(
          icon: const Icon(Icons.shuffle),
          onPressed: () {},
          color: Colors.grey[500],
          iconSize: 28,
        ),
        
        // Previous button
        IconButton(
          icon: const Icon(Icons.skip_previous),
          onPressed: () => musicService.previous(),
          color: Colors.white,
          iconSize: 40,
        ),
        
        // Play/Pause button
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.teal,
            boxShadow: [
              BoxShadow(
                color: Colors.teal.withOpacity(0.4),
                blurRadius: 15,
                spreadRadius: 2,
              ),
            ],
          ),
          child: IconButton(
            icon: Icon(
              isPlaying ? Icons.pause : Icons.play_arrow,
            ),
            onPressed: () => musicService.togglePlayPause(),
            color: Colors.white,
            iconSize: 48,
          ),
        ),
        
        // Next button
        IconButton(
          icon: const Icon(Icons.skip_next),
          onPressed: () => musicService.next(),
          color: Colors.white,
          iconSize: 40,
        ),
        
        // Repeat button
        IconButton(
          icon: const Icon(Icons.repeat),
          onPressed: () {},
          color: Colors.grey[500],
          iconSize: 28,
        ),
      ],
    );
  }

  Widget _buildBottomActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildActionButton(
            icon: Icons.favorite_border,
            label: 'Favorite',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Added to favorites'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
          _buildActionButton(
            icon: Icons.share,
            label: 'Share',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Share functionality'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
          _buildActionButton(
            icon: Icons.playlist_add,
            label: 'Playlist',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Added to playlist'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 26),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  void _showSongMenu(BuildContext context, Music? music) {
    if (music == null) return;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            
            // Song title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                music.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${music.artist} - ${music.album}',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),
            const Divider(color: Color(0xFF424242)),
            
            // Menu options
            _buildMenuItem(
              icon: Icons.favorite_border,
              title: 'Add to Favorites',
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Added to favorites')),
                );
              },
            ),
            _buildMenuItem(
              icon: Icons.playlist_add,
              title: 'Add to Playlist',
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Added to playlist')),
                );
              },
            ),
            _buildMenuItem(
              icon: Icons.share,
              title: 'Share',
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Share functionality')),
                );
              },
            ),
            _buildMenuItem(
              icon: Icons.info_outline,
              title: 'Song Info',
              onTap: () {
                Navigator.pop(context);
                _showSongInfo(context, music);
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white),
      ),
      onTap: onTap,
    );
  }

  void _showSongInfo(BuildContext context, Music music) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Song Info',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Title', music.title),
            _buildInfoRow('Artist', music.artist),
            _buildInfoRow('Album', music.album),
            _buildInfoRow('Duration', _formatDuration(music.duration ?? Duration.zero)),
            _buildInfoRow('File', music.filePath.split('/').last),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
