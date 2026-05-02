import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/music_model.dart';
import '../models/settings_model.dart';
import '../services/music_service.dart';
import '../services/responsive.dart';
import 'cover_art_texture.dart';
import 'glass_container.dart';

class MusicCard extends StatelessWidget {
  final Music music;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final ViewMode viewMode;
  final String? heroPrefix;

  const MusicCard({
    super.key,
    required this.music,
    required this.onTap,
    this.onDelete,
    this.viewMode = ViewMode.card,
    this.heroPrefix,
  });

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsModel>(context);
    if (viewMode == ViewMode.list) {
      return _buildListView(context, settings);
    }
    return _buildCardView(context, settings);
  }

  Widget _buildListView(BuildContext context, SettingsModel settings) {
    final musicService = Provider.of<MusicService>(context, listen: false);
    // Calculate adaptive height based on settings.cardSize
    // Base height is 60, scaled by the ratio of cardSize to default 140
    final double scale = settings.cardSize / 140.0;
    final double leadingSize = (44 * scale).clamp(32.0, 80.0).s;
    final double tileHeight = (64 * scale).clamp(48.0, 100.0).h;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) => _showGlassContextMenu(context, details.globalPosition),
      onLongPress: () => _showGlassContextMenuFromLongPress(context),
      child: GlassContainer(
        margin: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular((settings.borderRadius + 4).s),
        blur: 10.0,
        child: Container(
          height: tileHeight,
          alignment: Alignment.center,
          child: ListTile(
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular((settings.borderRadius + 4).s),
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 12.w),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(settings.borderRadius.s / 2.5),
              child: Hero(
                tag: '${heroPrefix ?? 'music-art'}-${music.id}',
                child: SizedBox(
                  width: leadingSize,
                  height: leadingSize,
                  child: CoverArtTexture(
                    coverArtPath: music.coverPath,
                    width: leadingSize,
                    height: leadingSize,
                  ),
                ),
              ),
            ),
            title: Text(
              music.title,
              style: TextStyle(color: Colors.white, fontSize: (12 * scale).clamp(10.0, 16.0).sp, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              music.artist,
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: (10 * scale).clamp(8.0, 14.0).sp),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    music.isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: music.isFavorite ? settings.accentColor : Colors.white54,
                    size: (20 * scale).clamp(16.0, 24.0).s,
                  ),
                  onPressed: () => musicService.toggleFavorite(music.id),
                ),
                IconButton(
                  icon: Icon(Icons.more_vert, color: Colors.white54, size: (20 * scale).clamp(16.0, 24.0).s),
                  onPressed: () => _showGlassContextMenuFromLongPress(context),
                ),
              ],
            ),
            onTap: onTap,
          ),
        ),
      ),
    );
  }

  Widget _buildCardView(BuildContext context, SettingsModel settings) {
    final musicService = Provider.of<MusicService>(context, listen: false);

    return GestureDetector(
      onTap: onTap,
      onSecondaryTapDown: (details) => _showGlassContextMenu(context, details.globalPosition),
      onLongPress: () => _showGlassContextMenuFromLongPress(context),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(settings.borderRadius.s),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 6.s,
              offset: Offset(0, 3.h),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(settings.borderRadius.s),
          child: AspectRatio(
            aspectRatio: 1.0,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Hero(
                  tag: '${heroPrefix ?? 'music-art'}-${music.id}',
                  child: CoverArtTexture(
                    coverArtPath: music.coverPath,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                      stops: const [0.6, 1.0],
                    ),
                  ),
                ),
                Positioned(
                  top: 6.s,
                  right: 6.s,
                  child: GestureDetector(
                    onTap: () => musicService.toggleFavorite(music.id),
                    child: GlassContainer(
                      padding: EdgeInsets.all(4.s),
                      color: Colors.black.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8.s),
                      blur: 8.0,
                      child: Icon(
                        music.isFavorite ? Icons.favorite : Icons.favorite_border,
                        color: music.isFavorite ? settings.accentColor : Colors.white,
                        size: 14.s,
                      ),
                    ),
                  ),
                ),
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
                        style: TextStyle(color: Colors.white, fontSize: 10.sp, fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        music.artist,
                        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 8.sp),
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

  void _showGlassContextMenuFromLongPress(BuildContext context) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final card = context.findRenderObject() as RenderBox;
    final position = card.localToGlobal(Offset.zero, ancestor: overlay);
    final centerPosition = Offset(
      position.dx + card.size.width / 2,
      position.dy + card.size.height / 2,
    );
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
                width: 200,
                padding: const EdgeInsets.all(8),
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildMenuItem(context, 'Play', Icons.play_arrow_rounded, Colors.teal, () => onTap()),
                    _buildMenuItem(context, 'Add to Queue', Icons.queue_music_rounded, Colors.blue, () {
                      Provider.of<MusicService>(context, listen: false).addToQueue(music.id);
                    }),
                    _buildMenuItem(context, 'Add to Playlist', Icons.playlist_add_rounded, Colors.purple, () => _showAddToPlaylistDialog(context)),
                    _buildMenuItem(context, 'Edit Info', Icons.edit_note_rounded, Colors.orange, () => _showEditMetadataDialog(context)),
                    const Divider(color: Colors.white10),
                    _buildMenuItem(context, 'Delete', Icons.delete_outline_rounded, Colors.redAccent, () => onDelete?.call()),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(BuildContext context, String title, IconData icon, Color color, VoidCallback action) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        action();
      },
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  void _showEditMetadataDialog(BuildContext context) {
    final musicService = Provider.of<MusicService>(context, listen: false);
    final titleController = TextEditingController(text: music.title);
    final artistController = TextEditingController(text: music.artist);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: GlassContainer(
          width: 320,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Edit Metadata', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              _buildGlassField('Title', titleController),
              const SizedBox(height: 12),
              _buildGlassField('Artist', artistController),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  ElevatedButton(
                    onPressed: () {
                      musicService.updateMusicMetadata(music.id, titleController.text, artistController.text, music.album, music.genre);
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                    child: const Text('Save'),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassField(String label, TextEditingController controller) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
      child: TextField(
        controller: controller,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(labelText: label, border: InputBorder.none, labelStyle: const TextStyle(color: Colors.white54, fontSize: 12)),
      ),
    );
  }

  void _showAddToPlaylistDialog(BuildContext context) {
    final musicService = Provider.of<MusicService>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: GlassContainer(
          width: 300,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Add to Playlist', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              if (musicService.playlists.isEmpty)
                const Text('No playlists available', style: TextStyle(color: Colors.white54))
              else
                ...musicService.playlists.map((pl) => ListTile(
                  title: Text(pl.name, style: const TextStyle(fontSize: 14)),
                  onTap: () {
                    musicService.addMusicToPlaylist(pl.id, music.id);
                    Navigator.pop(context);
                  },
                )),
            ],
          ),
        ),
      ),
    );
  }
}
