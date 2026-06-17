import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/playlist_model.dart';
import '../services/music_service.dart';
import '../services/responsive.dart';
import 'glass_container.dart';
import 'lanczos_cover_art.dart';

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
    final theme = Theme.of(context);
    final musicList = musicService.getMusicListForPlaylist(playlist.id);

    return GestureDetector(
      onTap: onTap,
      child: GlassContainer(
        borderRadius: BorderRadius.circular(18.s),
        color: null,
        blur: 14.0,
        padding: EdgeInsets.all(12.s),
        child: Row(
          children: [
            Container(
              width: Responsive.listArtSize,
              height: Responsive.listArtSize,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Responsive.listArtRadius),
                color: _getPlaylistColor(playlist.id).withOpacity(0.2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Responsive.listArtRadius),
                child: musicList.isNotEmpty && musicList[0].coverPath.isNotEmpty
                    ? LanczosCoverArt(
                        coverArtPath: musicList[0].coverPath,
                        width: Responsive.listArtSize,
                        height: Responsive.listArtSize,
                        borderRadius:
                            BorderRadius.circular(Responsive.listArtRadius),
                      )
                    : Icon(_getPlaylistIcon(playlist.id),
                        color: _getPlaylistColor(playlist.id),
                        size: 22.s),
              ),
            ),
            SizedBox(width: 16.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.name,
                    style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 14.sp,
                        fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    '${musicList.length} tracks',
                    style: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.58),
                        fontSize: 12.sp),
                  ),
                ],
              ),
            ),
            if (onDelete != null)
              IconButton(
                iconSize: 20.s,
                icon: const Icon(Icons.delete_outline_rounded,
                    color: Colors.grey),
                onPressed: onDelete,
              ),
            IconButton(
              iconSize: 30.s,
              icon: Icon(Icons.play_circle_fill_rounded,
                  color: theme.colorScheme.primary),
              onPressed: () => musicService.playPlaylist(playlist.id),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getPlaylistIcon(String id) {
    switch (id) {
      case 'favorites':
        return Icons.favorite_rounded;
      default:
        return Icons.playlist_play_rounded;
    }
  }

  Color _getPlaylistColor(String id) {
    switch (id) {
      case 'favorites':
        return Colors.redAccent;
      default:
        return Colors.white54;
    }
  }
}
