import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/playlist_model.dart';
import '../services/music_service.dart';
import '../models/music_model.dart';
import '../models/cover_model.dart';
import 'cover_art_texture.dart';

class PlaylistCard extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const PlaylistCard({
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
      onSecondaryTapDown: (details) {
        _showContextMenu(context, details.globalPosition);
      },
      onLongPress: () {
        _showContextMenuFromLongPress(context);
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 1.0,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildPlaylistCover(musicList),
                
                // Overlay Gradient
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.8),
                      ],
                      stops: const [0.6, 1.0],
                    ),
                  ),
                ),
                
                // Playlist Info
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        playlist.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${musicList.length} tracks',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaylistCover(List<Music> musicList) {
    if (musicList.isEmpty) {
      return _buildEmptyPlaylistCover();
    }

    // Centered Collage Logic
    if (musicList.length == 1) {
      // 1 TRACK: Clean Full Image
      return CoverArtTexture(coverArtPath: musicList[0].coverPath);
    } else if (musicList.length < 4) {
      // 2 or 3 TRACKS: Symmetrical vertical split (Showing first 2)
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: CoverArtTexture(coverArtPath: musicList[0].coverPath)),
          const VerticalDivider(width: 1, color: Colors.black26, thickness: 1),
          Expanded(child: CoverArtTexture(coverArtPath: musicList[1].coverPath)),
        ],
      );
    } else {
      // 4+ TRACKS: Balanced 2x2 Grid
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: CoverArtTexture(coverArtPath: musicList[0].coverPath)),
                const VerticalDivider(width: 1, color: Colors.black26, thickness: 1),
                Expanded(child: CoverArtTexture(coverArtPath: musicList[1].coverPath)),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.black26, thickness: 1),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: CoverArtTexture(coverArtPath: musicList[2].coverPath)),
                const VerticalDivider(width: 1, color: Colors.black26, thickness: 1),
                Expanded(child: CoverArtTexture(coverArtPath: musicList[3].coverPath)),
              ],
            ),
          ),
        ],
      );
    }
  }

  Widget _buildEmptyPlaylistCover() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _getPlaylistColor(playlist.id).withOpacity(0.8),
            Colors.black,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          _getPlaylistIcon(playlist.id),
          color: Colors.white38,
          size: 40,
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
      default: return Colors.grey;
    }
  }

  void _showContextMenuFromLongPress(BuildContext context) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final RenderBox card = context.findRenderObject() as RenderBox;
    final position = card.localToGlobal(Offset.zero, ancestor: overlay);
    final centerPosition = Offset(
      position.dx + card.size.width / 2,
      position.dy + card.size.height / 2,
    );
    _showContextMenu(context, centerPosition);
  }

  void _showContextMenu(BuildContext context, Offset position) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      color: Colors.grey[850],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem<String>(
          value: 'play',
          child: Row(
            children: [
              Icon(Icons.play_arrow, color: Colors.teal[300], size: 20),
              const SizedBox(width: 12),
              const Text('Play', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, color: Colors.red[300], size: 20),
              const SizedBox(width: 12),
              Text('Delete', style: TextStyle(color: Colors.red[300])),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'play') {
        onTap();
      } else if (value == 'delete') {
        onDelete?.call();
      }
    });
  }
}
