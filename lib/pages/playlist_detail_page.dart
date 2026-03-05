import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../widgets/music_card.dart';
import '../services/music_service.dart';
import '../models/playlist_model.dart';
import '../models/music_model.dart';
import '../services/responsive.dart';

class PlaylistDetailPage extends StatelessWidget {
  final Playlist playlist;

  const PlaylistDetailPage({super.key, required this.playlist});

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicService>(
      builder: (context, musicService, child) {
        final musicList = musicService.getMusicListForPlaylist(playlist.id);
        final bool isMobile = Responsive.screenWidth < 600;

        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: Text(playlist.name, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
            backgroundColor: Colors.grey[900],
            elevation: 0,
            actions: [
              IconButton(
                icon: Icon(Icons.play_circle_fill, color: Colors.teal, size: 28.s),
                onPressed: () => musicService.playPlaylist(playlist.id),
              ),
            ],
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
                        Icon(Icons.music_off, size: 60.s, color: Colors.grey[600]),
                        SizedBox(height: 16.h),
                        Text('No songs in this playlist', style: TextStyle(color: Colors.grey[500], fontSize: 16.sp)),
                        SizedBox(height: 8.h),
                        Text('Add songs to start playing', style: TextStyle(color: Colors.grey[600], fontSize: 14.sp)),
                      ],
                    ),
                  )
                : isMobile
                    ? _buildGridView(musicService, musicList)
                    : _buildListView(musicService, musicList),
          ),
        );
      },
    );
  }

  Widget _buildGridView(MusicService musicService, List<Music> musicList) {
    return GridView.builder(
      padding: EdgeInsets.all(16.s),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12.w,
        mainAxisSpacing: 12.h,
        childAspectRatio: 1.0,
      ),
      itemCount: musicList.length,
      itemBuilder: (context, index) {
        final music = musicList[index];
        final originalIndex = musicService.musicList.indexWhere((m) => m.id == music.id);

        return MusicCard(
          music: music,
          onTap: () {
            if (originalIndex != -1) {
              musicService.currentPlaylistId = playlist.id;
              musicService.currentIndex = originalIndex;
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

  Widget _buildListView(MusicService musicService, List<Music> musicList) {
    return ListView.builder(
      padding: EdgeInsets.all(16.s),
      itemCount: musicList.length,
      itemBuilder: (context, index) {
        final music = musicList[index];
        final originalIndex = musicService.musicList.indexWhere((m) => m.id == music.id);

        return Container(
          margin: EdgeInsets.only(bottom: 12.h),
          child: ListTile(
            contentPadding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
            leading: Container(
              width: 50.s,
              height: 50.s,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8.s),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 4.s,
                    offset: Offset(0, 2.h),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8.s),
                child: music.coverPath.isNotEmpty
                    ? Image.file(
                        File(music.coverPath),
                        fit: BoxFit.cover,
                        cacheWidth: 100,
                        cacheHeight: 100,
                      )
                    : Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Colors.teal.shade700, Colors.teal.shade900, Colors.black],
                          ),
                        ),
                        child: Icon(Icons.music_note, color: Colors.white54, size: 20.s),
                      ),
              ),
            ),
            title: Text(
              music.title,
              style: TextStyle(color: Colors.white, fontSize: 14.sp, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              music.artist,
              style: TextStyle(color: Colors.grey[400], fontSize: 12.sp),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              icon: Icon(Icons.delete_outline_rounded, color: Colors.grey[500], size: 20.s),
              onPressed: () => musicService.removeMusicFromPlaylist(playlist.id, music.id),
            ),
            onTap: () {
              if (originalIndex != -1) {
                musicService.currentPlaylistId = playlist.id;
                musicService.currentIndex = originalIndex;
                musicService.play();
              }
            },
          ),
        );
      },
    );
  }
}
