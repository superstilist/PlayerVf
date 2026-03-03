import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../widgets/music_card.dart';
import '../services/music_service.dart';
import '../models/playlist_model.dart';

class PlaylistDetailPage extends StatelessWidget {
  final Playlist playlist;

  const PlaylistDetailPage({super.key, required this.playlist});

  bool _isMobileDevice() {
    return kIsWeb ||
           defaultTargetPlatform == TargetPlatform.android ||
           defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  Widget build(BuildContext context) {
    final musicService = Provider.of<MusicService>(context);
    final musicList = musicService.getMusicListForPlaylist(playlist.id);
    final coverList = musicService.getCoverListForPlaylist(playlist.id);
    final size = MediaQuery.of(context).size;
    final bool isMobile = _isMobileDevice() || size.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: Text(playlist.name),
        backgroundColor: Colors.grey[900],
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1a1a1a),
              Color(0xFF0a0a0a),
            ],
          ),
        ),
        child: musicList.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.music_off, size: 60, color: Colors.grey[600]),
                    const SizedBox(height: 16),
                    Text('No songs in this playlist', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
                    const SizedBox(height: 8),
                    Text('Add songs to start playing', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                  ],
                ),
              )
            : isMobile
                ? _buildGridView(musicService, musicList, coverList, isMobile)
                : _buildListView(musicService, musicList, coverList),
      ),
    );
  }

  Widget _buildGridView(MusicService musicService, List musicList, List coverList, bool isMobile) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: isMobile ? 8.0 : 16.0,
        mainAxisSpacing: isMobile ? 8.0 : 16.0,
        childAspectRatio: 1.0,
      ),
      itemCount: musicList.length,
      itemBuilder: (context, index) {
        final music = musicList[index];
        final cover = index < coverList.length ? coverList[index] : null;
        final originalIndex = musicService.musicList.indexWhere((m) => m.id == music.id);

        return MusicCard(
          music: music,
          cover: cover,
          onTap: () {
            // Set current playlist and play the selected song
            final playlistMusicList = musicService.getMusicListForPlaylist(playlist.id);
            final songIndex = playlistMusicList.indexWhere((m) => m.id == music.id);
            if (songIndex != -1) {
              musicService.currentPlaylistId = playlist.id;
              musicService.currentPlaylistIndex = songIndex;
              musicService.currentIndex = originalIndex >= 0 ? originalIndex : 0;
              musicService.play();
            }
          },
          onDelete: () {
            musicService.removeMusicFromPlaylist(playlist.id, music.id);
          },
        );
      },
    );
  }

  Widget _buildListView(MusicService musicService, List musicList, List coverList) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: musicList.length,
      itemBuilder: (context, index) {
        final music = musicList[index];
        final cover = index < coverList.length ? coverList[index] : null;
        final originalIndex = musicService.musicList.indexWhere((m) => m.id == music.id);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: cover?.imageData != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        cover!.imageData!,
                        fit: BoxFit.cover,
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
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
                    ),
            ),
            title: Text(
              music.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              music.artist,
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              icon: Icon(Icons.delete, color: Colors.grey[500]),
              onPressed: () {
                musicService.removeMusicFromPlaylist(playlist.id, music.id);
              },
            ),
            onTap: () {
              // Set current playlist and play the selected song
              final playlistMusicList = musicService.getMusicListForPlaylist(playlist.id);
              final songIndex = playlistMusicList.indexWhere((m) => m.id == music.id);
              if (songIndex != -1) {
                musicService.currentPlaylistId = playlist.id;
                musicService.currentPlaylistIndex = songIndex;
                musicService.currentIndex = originalIndex >= 0 ? originalIndex : 0;
                musicService.play();
              }
            },
          ),
        );
      },
    );
  }
}
