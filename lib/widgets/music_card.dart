import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/music_model.dart';
import '../models/cover_model.dart';
import 'dart:io' as io;
import 'cover_art_texture.dart';

class MusicCard extends StatelessWidget {
  final Music music;
  final Cover? cover;
  final VoidCallback? onTap;

  const MusicCard({
    super.key,
    required this.music,
    this.cover,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: () => _showSongMenu(context),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.grey[900],
          border: Border.all(
            color: Colors.grey[800]!,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Cover image with fallback
            _buildCoverImage(),
            
            // Gradient overlay
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.8),
                  ],
                  stops: const [0.5, 1.0],
                ),
              ),
            ),
            
            // Play icon overlay with pulse animation
            Positioned(
              top: 16,
              right: 16,
              child: AnimatedOpacity(
                opacity: 0.9,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.teal.withOpacity(0.9),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.teal.withOpacity(0.4),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
            
            // Song info at bottom
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      music.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 0.5,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${music.artist} • ${music.album}',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                        letterSpacing: 0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    // Duration indicator
                    Row(
                      children: [
                        Icon(
                          Icons.timer,
                          color: Colors.teal[300],
                          size: 12,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDuration(music.duration),
                          style: TextStyle(
                            color: Colors.teal[300],
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverImage() {
    // Prioritize memory image (from extracted cover) over file path
    if (cover != null && cover!.imageData != null) {
      try {
        return ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.memory(
            cover!.imageData!,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        );
      } catch (e) {
        return _buildDefaultCover();
      }
    }

    // Check if we have a cover path
    if (music.coverPath.isNotEmpty) {
      try {
        // Handle asset paths
        if (music.coverPath.startsWith('assets/')) {
          return CoverArtTexture(
            coverArtPath: music.coverPath,
            width: double.infinity,
            height: double.infinity,
            borderRadius: BorderRadius.circular(20),
          );
        } else {
          // Handle file paths
          final file = io.File(music.coverPath);
          if (file.existsSync()) {
            return CoverArtTexture(
              coverArtPath: music.coverPath,
              width: double.infinity,
              height: double.infinity,
              borderRadius: BorderRadius.circular(20),
            );
          }
        }
      } catch (e) {
        // Fallback to default if there's an error
      }
    }

    // Default cover if nothing else works
    return _buildDefaultCover();
  }

  Widget _buildDefaultCover() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
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
      child: const Center(
        child: Icon(
          Icons.music_note,
          color: Colors.white54,
          size: 60,
        ),
      ),
    );
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '0:00';
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  void _showSongMenu(BuildContext context) {
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
              context: context,
              icon: Icons.play_arrow,
              title: 'Play',
              onTap: () {
                Navigator.pop(context);
                onTap?.call();
              },
            ),
            _buildMenuItem(
              context: context,
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
              context: context,
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
              context: context,
              icon: Icons.share,
              title: 'Share',
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Share functionality')),
                );
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required BuildContext context,
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
}
