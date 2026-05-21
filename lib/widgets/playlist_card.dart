import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/playlist_model.dart';
import '../services/music_service.dart';
import '../models/music_model.dart';
import '../models/settings_model.dart';
import '../services/responsive.dart';
import 'cover_art_texture.dart';
import 'glass_container.dart';

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
    final settings = Provider.of<SettingsModel>(context);
    final musicService = Provider.of<MusicService>(context);
    final theme = Theme.of(context);
    final musicList = musicService.getMusicListForPlaylist(playlist.id);

    return GestureDetector(
      onTap: onTap,
      onSecondaryTapDown: (details) =>
          _showGlassContextMenu(context, details.globalPosition),
      onLongPress: () => _showGlassContextMenuFromLongPress(context),
      child: GlassContainer(
        borderRadius: BorderRadius.circular(18.s),
        padding: EdgeInsets.all(12.s),
        color: null,
        blur: 14,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(settings.borderRadius.s),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(settings.borderRadius.s),
                  child: _buildPlaylistCover(musicList),
                ),
              ),
            ),
            SizedBox(height: 12.h),
            Text(
              playlist.name,
              style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 2.h),
            Text(
              '${musicList.length} Tracks',
              style: TextStyle(
                  fontSize: 10.sp,
                  color: theme.colorScheme.onSurface.withOpacity(0.56)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistCover(List<Music> musicList) {
    final musicWithCovers =
        musicList.where((m) => m.coverPath.isNotEmpty).toList();
    if (musicWithCovers.isEmpty) {
      return _buildEmptyPlaylistCover();
    } else if (musicWithCovers.length == 1) {
      return _buildSingleSongCover(musicWithCovers.first.coverPath);
    } else {
      return _buildMultipleSongsCover(musicWithCovers);
    }
  }

  Widget _buildEmptyPlaylistCover() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.teal.shade800, Colors.teal.shade400],
        ),
      ),
      child: const Center(
          child: Icon(Icons.playlist_play_rounded,
              color: Colors.white30, size: 40)),
    );
  }

  Widget _buildSingleSongCover(String coverPath) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return CoverArtTexture(
          coverArtPath: coverPath,
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          filterQuality: FilterQuality.medium,
          cacheScale: 2.0,
        );
      },
    );
  }

  Widget _buildMultipleSongsCover(List<Music> musicList) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double halfWidth = constraints.maxWidth / 2;
        if (musicList.length < 4) {
          return Row(
            children: [
              Expanded(
                  child: CoverArtTexture(
                coverArtPath: musicList[0].coverPath,
                width: halfWidth,
                height: constraints.maxHeight,
                filterQuality: FilterQuality.medium,
                cacheScale: 2.0,
              )),
              Expanded(
                  child: CoverArtTexture(
                coverArtPath: musicList[1].coverPath,
                width: halfWidth,
                height: constraints.maxHeight,
                filterQuality: FilterQuality.medium,
                cacheScale: 2.0,
              )),
            ],
          );
        }

        return Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(
                      child: CoverArtTexture(
                          coverArtPath: musicList[0].coverPath,
                          width: halfWidth,
                          height: constraints.maxHeight / 2,
                          filterQuality: FilterQuality.medium,
                          cacheScale: 2.0)),
                  Expanded(
                      child: CoverArtTexture(
                          coverArtPath: musicList[1].coverPath,
                          width: halfWidth,
                          height: constraints.maxHeight / 2,
                          filterQuality: FilterQuality.medium,
                          cacheScale: 2.0)),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                      child: CoverArtTexture(
                          coverArtPath: musicList[2].coverPath,
                          width: halfWidth,
                          height: constraints.maxHeight / 2,
                          filterQuality: FilterQuality.medium,
                          cacheScale: 2.0)),
                  Expanded(
                      child: CoverArtTexture(
                          coverArtPath: musicList[3].coverPath,
                          width: halfWidth,
                          height: constraints.maxHeight / 2,
                          filterQuality: FilterQuality.medium,
                          cacheScale: 2.0)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _showGlassContextMenuFromLongPress(BuildContext context) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final card = context.findRenderObject() as RenderBox;
    final position = card.localToGlobal(Offset.zero, ancestor: overlay);
    final centerPosition = Offset(
        position.dx + card.size.width / 2, position.dy + card.size.height / 2);
    _showGlassContextMenu(context, centerPosition);
  }

  void _showGlassContextMenu(BuildContext context, Offset position) {
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) => Stack(
        children: [
          Positioned(
            left: position.dx,
            top: position.dy,
            child: Material(
              color: Colors.transparent,
              child: GlassContainer(
                width: 180,
                padding: const EdgeInsets.all(8),
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildMenuItem(context, 'Play Playlist',
                        Icons.play_arrow_rounded, Colors.teal, () {
                      Provider.of<MusicService>(context, listen: false)
                          .playPlaylist(playlist.id);
                    }),
                    if (onDelete != null) ...[
                      const Divider(color: Colors.white10),
                      _buildMenuItem(
                          context,
                          'Delete',
                          Icons.delete_outline_rounded,
                          Colors.redAccent,
                          () => onDelete?.call()),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(BuildContext context, String title, IconData icon,
      Color color, VoidCallback action) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        action();
      },
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 13))
        ]),
      ),
    );
  }
}
