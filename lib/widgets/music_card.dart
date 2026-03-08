import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../models/music_model.dart';
import '../models/cover_model.dart';
import '../services/music_service.dart';
import '../services/responsive.dart';
import 'cover_art_texture.dart';

class MusicCard extends StatelessWidget {
  final Music music;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const MusicCard({
    super.key,
    required this.music,
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
                CoverArtTexture(
                  coverArtPath: music.coverPath,
                  musicId: music.id,
                  width: double.infinity,
                  height: double.infinity,
                ),
                
                // Transparent gradient overlay with text
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
                        color: Colors.black.withOpacity(0.5),
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
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        music.artist,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 8.sp,
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
        PopupMenuItem<String>(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit, color: Colors.teal[300], size: 20),
              const SizedBox(width: 12),
              const Text('Edit Metadata', style: TextStyle(color: Colors.white)),
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
      } else if (value == 'edit') {
        _showEditMetadataDialog(context);
      }
    });
  }

  void _showEditMetadataDialog(BuildContext context) {
    final musicService = Provider.of<MusicService>(context, listen: false);
    final titleController = TextEditingController(text: music.title);
    final artistController = TextEditingController(text: music.artist);
    final albumController = TextEditingController(text: music.album);
    final genreController = TextEditingController(text: music.genre);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Metadata'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              TextField(
                controller: artistController,
                decoration: const InputDecoration(labelText: 'Artist'),
              ),
              TextField(
                controller: albumController,
                decoration: const InputDecoration(labelText: 'Album'),
              ),
              TextField(
                controller: genreController,
                decoration: const InputDecoration(labelText: 'Genre'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              musicService.updateMusicMetadata(
                music.id,
                titleController.text,
                artistController.text,
                albumController.text,
                genreController.text,
              );
              Navigator.pop(context);
            },
            child: const Text('Save', style: TextStyle(color: Colors.teal)),
          ),
        ],
      ),
    );
  }

  void _showAddToPlaylistDialog(BuildContext context) {
    final musicService = Provider.of<MusicService>(context, listen: false);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add to Playlist'),
        content: SizedBox(
          width: double.maxFinite,
          child: musicService.playlists.isEmpty 
            ? const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('No playlists created yet.'),
              )
            : ListView.builder(
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
}
