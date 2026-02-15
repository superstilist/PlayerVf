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

        return Scaffold(
backgroundColor: Colors.black,
body: SafeArea(
  child: LayoutBuilder(
    builder: (context, constraints) {
      // Responsive sizing for cover art
      double coverSize = constraints.maxWidth * 0.8;
      if (coverSize > 450) coverSize = 450;
      if (coverSize < 200) coverSize = constraints.maxWidth * 0.9;

      return SingleChildScrollView(
        child: Column(
          children: [
                    // App bar with close button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                              fontSize: 20,
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
                    ),

                    const Spacer(),

                    // Cover art with animated container
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeInOut,
                      width: coverSize,
                      height: coverSize,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.teal.withOpacity(0.4),
                            blurRadius: 40,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: _buildCoverWidget(currentCover, currentMusic, coverSize),
                      ),
                    ),

                    const Spacer(),

                    // Song info
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        children: [
                          Text(
                            currentMusic?.title ?? 'Unknown Title',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '${currentMusic?.artist ?? 'Unknown Artist'} - ${currentMusic?.album ?? 'Unknown Album'}',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 18,
                              letterSpacing: 0.3,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 40),

                    // Progress slider
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 6,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                              activeTrackColor: Colors.teal,
                              inactiveTrackColor: Colors.grey[700],
                              thumbColor: Colors.teal,
                              overlayColor: Colors.teal.withOpacity(0.2),
                            ),
                            child: Slider(
                              value: musicService.position.inSeconds.toDouble(),
                              min: 0,
                              max: musicService.duration.inSeconds.toDouble().clamp(1, double.infinity),
                              onChanged: (value) {
                                musicService.seekTo(Duration(seconds: value.toInt()));
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDuration(musicService.position),
                                  style: TextStyle(color: Colors.grey[500], fontSize: 14),
                                ),
                                Text(
                                  _formatDuration(musicService.duration),
                                  style: TextStyle(color: Colors.grey[500], fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Playback controls
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.shuffle),
                            onPressed: () {},
                            color: Colors.grey[500],
                            iconSize: 32,
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_previous),
                            onPressed: () => musicService.previous(),
                            color: Colors.white,
                            iconSize: 44,
                          ),
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.teal,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.teal.withOpacity(0.5),
                                  blurRadius: 20,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: IconButton(
                              icon: Icon(
                                musicService.isPlaying ? Icons.pause : Icons.play_arrow,
                              ),
                              onPressed: () => musicService.togglePlayPause(),
                              color: Colors.white,
                              iconSize: 56,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_next),
                            onPressed: () => musicService.next(),
                            color: Colors.white,
                            iconSize: 44,
                          ),
                          IconButton(
                            icon: const Icon(Icons.repeat),
                            onPressed: () {},
                            color: Colors.grey[500],
                            iconSize: 32,
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // Bottom actions
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.favorite_border),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Added to favorites')),
                              );
                            },
                            color: Colors.white,
                            iconSize: 28,
                          ),
                          IconButton(
                            icon: const Icon(Icons.share),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Share functionality')),
                              );
                            },
                            color: Colors.white,
                            iconSize: 28,
                          ),
                          IconButton(
                            icon: const Icon(Icons.playlist_add),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Added to playlist')),
                              );
                            },
                            color: Colors.white,
                            iconSize: 28,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildCoverWidget(Cover? cover, Music? music, double size) {
    if (cover != null && cover.imageData != null) {
      try {
        return Image.memory(
          cover.imageData!,
          width: size,
          height: size,
          fit: BoxFit.cover,
        );
      } catch (_) {
        return _buildDefaultCover(size);
      }
    } else if (music != null && music.coverPath.isNotEmpty) {
      try {
        if (music.coverPath.startsWith('assets/')) {
          return CoverArtTexture(
            coverArtPath: music.coverPath,
            width: size,
            height: size,
            borderRadius: BorderRadius.circular(28),
          );
        } else {
          final file = io.File(music.coverPath);
          if (file.existsSync()) {
            return CoverArtTexture(
              coverArtPath: music.coverPath,
              width: size,
              height: size,
              borderRadius: BorderRadius.circular(28),
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
            Colors.black,
          ],
        ),
      ),
      child: const Icon(
        Icons.music_note,
        color: Colors.white54,
        size: 100,
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
