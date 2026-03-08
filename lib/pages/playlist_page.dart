import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/music_service.dart';
import '../models/playlist_model.dart';
import '../widgets/fade_in_up_animation.dart';
import '../widgets/small_playlist_card.dart';
import 'playlist_detail_page.dart';

import '../services/responsive.dart';

class PlaylistPage extends StatelessWidget {
  final String searchQuery;
  const PlaylistPage({super.key, this.searchQuery = ''});

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicService>(
      builder: (context, musicService, child) {
        var allPlaylists = musicService.allPlaylists;
        
        // Filter playlists based on search query
        if (searchQuery.isNotEmpty) {
          allPlaylists = allPlaylists.where((playlist) {
            // Check if playlist name matches search query
            final playlistNameMatch = playlist.name.toLowerCase().contains(searchQuery.toLowerCase());
            
            // Check if any song in the playlist matches search query
            final musicList = musicService.getMusicListForPlaylist(playlist.id);
            final hasMatchingSongs = musicList.any((music) {
              return music.title.toLowerCase().contains(searchQuery.toLowerCase()) ||
                     music.artist.toLowerCase().contains(searchQuery.toLowerCase());
            });
            
            return playlistNameMatch || hasMatchingSongs;
          }).toList();
        }
        
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: Text('Playlists', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20.sp)),
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              IconButton(
                icon: Icon(Icons.add_rounded, size: 24.s),
                onPressed: () => _showCreatePlaylistDialog(context, musicService),
              ),
            ],
            toolbarHeight: 80.h, // Increase toolbar height for better spacing
          ),
          body: SafeArea(
            child: allPlaylists.isEmpty
                ? _buildEmptyState(context, musicService)
                : _buildPlaylistGrid(context, musicService, allPlaylists),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, MusicService musicService) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.playlist_add_rounded, size: 80.s, color: Colors.grey[800]),
          SizedBox(height: 16.h),
          Text('No playlists yet', style: TextStyle(color: Colors.grey, fontSize: 18.sp)),
          SizedBox(height: 24.h),
          ElevatedButton.icon(
            onPressed: () => _showCreatePlaylistDialog(context, musicService),
            icon: Icon(Icons.add, size: 20.s),
            label: Text('Create Playlist', style: TextStyle(fontSize: 14.sp)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.s)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistGrid(BuildContext context, MusicService musicService, List<Playlist> playlists) {
    return ListView.builder(
      padding: EdgeInsets.all(16.s),
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        final isSystem = ['favorites', 'most_listened', 'early_listened', 'daily_mix'].contains(playlist.id);
        
        return FadeInUpAnimation(
          delay: 0.05 * index,
          child: Padding(
            padding: EdgeInsets.only(bottom: 12.h),
            child: SmallPlaylistCard(
              playlist: playlist,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PlaylistDetailPage(playlist: playlist),
                  ),
                );
              },
              onDelete: isSystem ? null : () => musicService.deletePlaylist(playlist.id),
            ),
          ),
        );
      },
    );
  }


  void _showCreatePlaylistDialog(BuildContext context, MusicService musicService) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('New Playlist', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Name...',
            hintStyle: TextStyle(color: Colors.white24),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.teal)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                musicService.createPlaylist(controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text('Create', style: TextStyle(color: Colors.teal)),
          ),
        ],
      ),
    );
  }
}
