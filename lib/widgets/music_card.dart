import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/music_model.dart';
import '../models/cover_model.dart';
import '../services/music_service.dart';

import '../services/responsive.dart';

class MusicCard extends StatelessWidget {
  final Music music;
  final Cover? cover;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const MusicCard({
    super.key,
    required this.music,
    this.cover,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final musicService = Provider.of<MusicService>(context);
    
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
          borderRadius: BorderRadius.circular(12.s),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 6.s,
              offset: Offset(0, 3.h),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12.s),
          child: AspectRatio(
            aspectRatio: 1.0,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Cover art
                _buildCoverArt(context),
                
                // Transparent gradient overlay with text
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.7),
                      ],
                      stops: const [0.5, 1.0],
                    ),
                  ),
                ),
                
                // Favorite button
                Positioned(
                  top: 6.s,
                  right: 6.s,
                  child: GestureDetector(
                    onTap: () {
                      musicService.toggleFavorite(music.id);
                    },
                    child: Container(
                      padding: EdgeInsets.all(4.s),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(8.s),
                      ),
                      child: Icon(
                        music.isFavorite ? Icons.favorite : Icons.favorite_border,
                        color: music.isFavorite ? Colors.red : Colors.white,
                        size: 14.s,
                      ),
                    ),
                  ),
                ),
                
                // Title and artist text
                Positioned(
                  left: 8.w,
                  right: 8.w,
                  bottom: 8.h,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        music.title,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10.sp,
                          fontWeight: FontWeight.bold,
                          shadows: const [
                            Shadow(
                              color: Colors.black54,
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        music.artist,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 8.sp,
                          shadows: const [
                            Shadow(
                              color: Colors.black54,
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
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
        PopupMenuItem<String>(
          value: 'add_queue',
          child: Row(
            children: [
              Icon(Icons.queue_music, color: Colors.teal[300], size: 20),
              const SizedBox(width: 12),
              const Text('Add to Queue', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'add_playlist',
          child: Row(
            children: [
              Icon(Icons.playlist_add, color: Colors.teal[300], size: 20),
              const SizedBox(width: 12),
              const Text('Add to Playlist', style: TextStyle(color: Colors.white)),
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
      } else if (value == 'add_playlist') {
        _showAddToPlaylistDialog(context);
      }
    });
  }

  void _showAddToPlaylistDialog(BuildContext context) {
    final musicService = Provider.of<MusicService>(context, listen: false);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add to Playlist'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: musicService.playlists.length,
            itemBuilder: (context, index) {
              final playlist = musicService.playlists[index];
              return ListTile(
                title: Text(playlist.name),
                subtitle: Text('${playlist.musicIds.length} song${playlist.musicIds.length != 1 ? 's' : ''}'),
                onTap: () {
                  musicService.addMusicToPlaylist(playlist.id, music.id);
                  Navigator.pop(context);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCoverArt(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isMobile = size.width < 600;
    
    if (cover != null && cover!.imageData != null) {
      return Image.memory(
        cover!.imageData!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildPlaceholderCover(isMobile);
        },
      );
    } else {
      return _buildPlaceholderCover(isMobile);
    }
  }

  Widget _buildPlaceholderCover(bool isMobile) {
    return Container(
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
      child: Center(
        child: Icon(
          Icons.music_note,
          color: Colors.white54,
          size: isMobile ? 20 : 30,
        ),
      ),
    );
  }
}
