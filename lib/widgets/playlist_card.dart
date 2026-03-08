import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/playlist_model.dart';
import '../services/music_service.dart';
import '../models/music_model.dart';
import '../models/cover_model.dart';

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
    final coverList = musicService.getCoverListForPlaylist(playlist.id);

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
              blurRadius: 6,
              offset: const Offset(0, 3),
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
                _buildPlaylistCover(musicList, coverList),
                
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
                
                // Playlist name text
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        playlist.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(
                              color: Colors.black54,
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${musicList.length} song${musicList.length != 1 ? 's' : ''}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 8,
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

  Widget _buildPlaylistCover(List<Music> musicList, List<Cover> coverList) {
    if (musicList.isEmpty) {
      return _buildEmptyPlaylistCover();
    } else if (musicList.length == 1) {
      return _buildSingleSongCover(coverList.first);
    } else {
      return _buildMultipleSongsCover(coverList);
    }
  }

  Widget _buildEmptyPlaylistCover() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.purple.shade700,
            Colors.purple.shade900,
            Colors.black,
          ],
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.playlist_play,
          color: Colors.white54,
          size: 30,
        ),
      ),
    );
  }

  Widget _buildSingleSongCover(Cover cover) {
    if (cover.imageData != null) {
      return Image.memory(
        cover.imageData!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildPlaceholderCover();
        },
      );
    } else {
      return _buildPlaceholderCover();
    }
  }

  Widget _buildMultipleSongsCover(List<Cover> coverList) {
    // Take first 2 covers for the split cover effect
    final firstCover = coverList.isNotEmpty ? coverList[0] : Cover();
    final secondCover = coverList.length > 1 ? coverList[1] : Cover();

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.purple.shade700,
            Colors.purple.shade900,
            Colors.black,
          ],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildCoverImage(firstCover, Alignment.topLeft),
          ),
          Expanded(
            child: _buildCoverImage(secondCover, Alignment.bottomRight),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverImage(Cover cover, Alignment alignment) {
    return Container(
      alignment: alignment,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(
            color: Colors.black.withOpacity(0.3),
            width: 2,
          ),
        ),
        child: cover.imageData != null
            ? Image.memory(
                cover.imageData!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildPlaceholderCover();
                },
              )
            : _buildPlaceholderCover(),
      ),
    );
  }

  Widget _buildPlaceholderCover() {
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
      child: const Center(
        child: Icon(
          Icons.music_note,
          color: Colors.white54,
          size: 20,
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
