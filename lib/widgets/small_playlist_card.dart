import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../models/playlist_model.dart';
import '../services/music_service.dart';
import '../models/music_model.dart';
import '../models/cover_model.dart';
import '../services/responsive.dart';

class SmallPlaylistCard extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const SmallPlaylistCard({
    super.key,
    required this.playlist,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final musicService = Provider.of<MusicService>(context);
    final musicList = musicService.getMusicListForPlaylist(playlist.id);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.s),
          color: Colors.grey[900],
        ),
        padding: EdgeInsets.all(12.s),
        child: Row(
          children: [
            Container(
              width: 50.s,
              height: 50.s,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8.s),
                color: _getPlaylistColor(playlist.id).withOpacity(0.2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8.s),
                child: musicList.isNotEmpty && musicList[0].coverPath.isNotEmpty
                  ? Image.file(
                      File(musicList[0].coverPath),
                      fit: BoxFit.cover,
                      cacheWidth: 100,
                      cacheHeight: 100,
                    )
                  : Icon(_getPlaylistIcon(playlist.id), color: _getPlaylistColor(playlist.id), size: 24.s),
              ),
            ),
            SizedBox(width: 16.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.name,
                    style: TextStyle(color: Colors.white, fontSize: 14.sp, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    '${musicList.length} tracks',
                    style: TextStyle(color: Colors.grey[400], fontSize: 12.sp),
                  ),
                ],
              ),
            ),
            if (onDelete != null)
              IconButton(
                iconSize: 20.s,
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.grey),
                onPressed: onDelete,
              ),
            IconButton(
              iconSize: 30.s,
              icon: const Icon(Icons.play_circle_fill_rounded, color: Colors.teal),
              onPressed: () => musicService.playPlaylist(playlist.id),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getPlaylistIcon(String id) {
    switch (id) {
      case 'favorites': return Icons.favorite_rounded;
      case 'most_listened': return Icons.trending_up_rounded;
      case 'early_listened': return Icons.access_time_rounded;
      case 'daily_mix': return Icons.auto_awesome_rounded;
      default: return Icons.playlist_play_rounded;
    }
  }

  Color _getPlaylistColor(String id) {
    switch (id) {
      case 'favorites': return Colors.redAccent;
      case 'most_listened': return Colors.purpleAccent;
      case 'early_listened': return Colors.blueAccent;
      case 'daily_mix': return Colors.tealAccent;
      default: return Colors.white54;
    }
  }
}
