import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';

import '../models/music_model.dart';
import '../models/settings_model.dart';
import '../services/music_service.dart';
import '../services/musicbrainz_tag_service.dart';
import '../services/responsive.dart';
import 'cover_art_texture.dart';
import 'glass_container.dart';

class MusicCard extends StatelessWidget {
  final Music music;
  final VoidCallback onTap;
  final VoidCallback? onOpen;
  final VoidCallback? onDelete;
  final ViewMode viewMode;
  final String? heroPrefix;
  final int? listIndex;
  final int? listLength;

  const MusicCard({
    super.key,
    required this.music,
    required this.onTap,
    this.onOpen,
    this.onDelete,
    this.viewMode = ViewMode.card,
    this.heroPrefix,
    this.listIndex,
    this.listLength,
  });

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsModel>(context);
    if (viewMode == ViewMode.list) {
      return _buildListView(context, settings);
    }
    return _buildCardView(context, settings);
  }

  String get _heroTag {
    final prefix = heroPrefix ?? 'music-art';
    final stableIdentity = music.filePath.isNotEmpty
        ? music.filePath
        : '${music.id}-${music.artist}-${music.title}';
    final position = listIndex == null ? '' : '-$listIndex';
    return '$prefix-$stableIdentity$position';
  }

  Widget _buildListView(BuildContext context, SettingsModel settings) {
    final musicService = Provider.of<MusicService>(context, listen: false);
    final theme = Theme.of(context);
    // Calculate adaptive height based on settings.cardSize
    // Base height is 60, scaled by the ratio of cardSize to default 140
    final double scale = settings.cardSize / 140.0;
    final double leadingSize = (44 * scale).clamp(32.0, 80.0).s;
    final double tileHeight = (64 * scale).clamp(48.0, 100.0).h;
    final double coverSize = leadingSize.clamp(28.0, tileHeight - 8).toDouble();
    final isFirst = listIndex == null || listIndex == 0;
    final isLast =
        listIndex == null || listLength == null || listIndex == listLength! - 1;
    final rowRadius = BorderRadius.vertical(
      top: Radius.circular(isFirst ? 22.s : 0),
      bottom: Radius.circular(isLast ? 22.s : 0),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) =>
          _showGlassContextMenu(context, details.globalPosition),
      onLongPress: () => _showGlassContextMenuFromLongPress(context),
      child: GlassContainer(
        margin: EdgeInsets.symmetric(horizontal: 10.w),
        color: null,
        borderRadius: rowRadius,
        blur: 0.0,
        border: Border.all(color: Colors.transparent, width: 0),
        child: Column(
          children: [
            Container(
              height: tileHeight,
              alignment: Alignment.center,
              child: ListTile(
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(borderRadius: rowRadius),
                contentPadding: EdgeInsets.symmetric(horizontal: 12.w),
                leading: ClipRRect(
                  borderRadius:
                      BorderRadius.circular(settings.borderRadius.s / 2.5),
                  child: Hero(
                    tag: _heroTag,
                    child: SizedBox.square(
                      dimension: coverSize,
                      child: CoverArtTexture(
                        coverArtPath: music.coverPath,
                        width: coverSize,
                        height: coverSize,
                      ),
                    ),
                  ),
                ),
                title: Text(
                  music.title,
                  style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: (12 * scale).clamp(10.0, 16.0).sp,
                      fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  music.artist,
                  style: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.58),
                      fontSize: (10 * scale).clamp(8.0, 14.0).sp),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        music.isFavorite
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: music.isFavorite
                            ? settings.accentColor
                            : theme.colorScheme.onSurfaceVariant,
                        size: (20 * scale).clamp(16.0, 24.0).s,
                      ),
                      onPressed: () => musicService.toggleFavorite(music.id),
                    ),
                    IconButton(
                      icon: Icon(Icons.more_vert,
                          color: theme.colorScheme.onSurfaceVariant,
                          size: (20 * scale).clamp(16.0, 24.0).s),
                      onPressed: () =>
                          _showGlassContextMenuFromLongPress(context),
                    ),
                  ],
                ),
                onTap: onTap,
              ),
            ),
            if (!isLast)
              Padding(
                padding: EdgeInsets.only(left: 68.w, right: 12.w),
                child: Divider(
                  height: 1,
                  thickness: 0.7,
                  color: theme.colorScheme.outlineVariant.withOpacity(0.18),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardView(BuildContext context, SettingsModel settings) {
    final musicService = Provider.of<MusicService>(context, listen: false);

    return GestureDetector(
      onTap: onTap,
      onSecondaryTapDown: (details) =>
          _showGlassContextMenu(context, details.globalPosition),
      onLongPress: () => _showGlassContextMenuFromLongPress(context),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular((settings.borderRadius + 4).s),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular((settings.borderRadius + 4).s),
          child: AspectRatio(
            aspectRatio: 1.0,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Hero(
                  tag: _heroTag,
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
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.8)
                      ],
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
                      color: Colors.black.withOpacity(0.22),
                      borderRadius: BorderRadius.circular(12.s),
                      blur: 0.0,
                      child: Icon(
                        music.isFavorite
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: music.isFavorite
                            ? settings.accentColor
                            : Colors.white,
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
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 10.sp,
                            fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        music.artist,
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 8.sp),
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
    final actionContext = context;
    final media = MediaQuery.of(context);
    final safeRect = Offset.zero & media.size;
    const menuWidth = 220.0;
    const itemHeight = 44.0;
    const menuPadding = 8.0;
    const menuItems = 10;
    const menuHeight = (menuItems * itemHeight) + (menuPadding * 2) + 12;
    final left = _fitMenuAxis(
      requested: position.dx,
      size: menuWidth,
      min: media.padding.left + 8,
      max: safeRect.width - media.padding.right - 8,
    );
    final top = _fitMenuAxis(
      requested: position.dy,
      size: menuHeight,
      min: media.padding.top + 8,
      max: safeRect.height - media.padding.bottom - 8,
      preferBefore: position.dy > safeRect.height * 0.62,
    );

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (menuContext) => Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            child: Material(
              color: Colors.transparent,
              child: GlassContainer(
                width: menuWidth,
                padding: const EdgeInsets.all(8),
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildMenuItem(menuContext, 'Play',
                        Icons.play_arrow_rounded, Colors.teal, () => onTap()),
                    _buildMenuItem(
                        menuContext,
                        'Open',
                        Icons.open_in_full_rounded,
                        Colors.lightGreenAccent,
                        () => _openTrack()),
                    _buildMenuItem(menuContext, 'Add to Queue',
                        Icons.queue_music_rounded, Colors.blue, () {
                      Provider.of<MusicService>(actionContext, listen: false)
                          .addToQueue(music.id);
                    }),
                    _buildMenuItem(
                        menuContext,
                        'Track Info',
                        Icons.info_outline_rounded,
                        Colors.amberAccent,
                        () => _showTrackInfoDialog(actionContext)),
                    _buildMenuItem(
                        menuContext,
                        'Add to Playlist',
                        Icons.playlist_add_rounded,
                        Colors.purple,
                        () => _showAddToPlaylistDialog(actionContext)),
                    _buildMenuItem(
                        menuContext,
                        'Auto Tag',
                        Icons.auto_fix_high_rounded,
                        Colors.greenAccent,
                        () => _autoTagWithMusicBrainz(actionContext)),
                    _buildMenuItem(
                        menuContext,
                        'Manual Tag',
                        Icons.manage_search_rounded,
                        Colors.lightBlueAccent,
                        () => _showManualMusicBrainzTagDialog(actionContext)),
                    _buildMenuItem(
                        menuContext,
                        'Edit Info',
                        Icons.edit_note_rounded,
                        Colors.orange,
                        () => _showEditMetadataDialog(actionContext)),
                    _buildMenuItem(
                        menuContext,
                        'Edit Cover',
                        Icons.image_rounded,
                        Colors.cyan,
                        () => _pickCoverArt(actionContext)),
                    const Divider(color: Colors.white10),
                    _buildMenuItem(
                        menuContext,
                        'Delete',
                        Icons.delete_outline_rounded,
                        Colors.redAccent,
                        () => onDelete?.call()),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _fitMenuAxis({
    required double requested,
    required double size,
    required double min,
    required double max,
    bool preferBefore = false,
  }) {
    final available = max - min;
    if (available <= size) return min;

    final target = preferBefore ? requested - size : requested;
    return target.clamp(min, max - size).toDouble();
  }

  Widget _buildMenuItem(BuildContext context, String title, IconData icon,
      Color color, VoidCallback action) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        WidgetsBinding.instance.addPostFrameCallback((_) => action());
      },
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Text(title,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  void _showTrackInfoDialog(BuildContext context) {
    final musicService = Provider.of<MusicService>(context, listen: false);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: GlassContainer(
          width: 420,
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: CoverArtTexture(
                      coverArtPath: music.coverPath,
                      width: 72,
                      height: 72,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          music.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          music.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _buildInfoRow('Album', music.album),
              _buildInfoRow('Genre', music.genre),
              _buildInfoRow('Duration', _formatTrackDuration(music.duration)),
              _buildInfoRow('File', music.filePath),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildInfoAction(
                    icon: Icons.play_arrow_rounded,
                    label: 'Play',
                    onPressed: () => _closeDialogAndRun(dialogContext, onTap),
                  ),
                  _buildInfoAction(
                    icon: Icons.open_in_full_rounded,
                    label: 'Open',
                    onPressed: () =>
                        _closeDialogAndRun(dialogContext, _openTrack),
                  ),
                  _buildInfoAction(
                    icon: music.isFavorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    label: music.isFavorite ? 'Unfavorite' : 'Favorite',
                    onPressed: () {
                      musicService.toggleFavorite(music.id);
                      _showSnack(
                        context,
                        music.isFavorite
                            ? 'Removed from favorites.'
                            : 'Added to favorites.',
                      );
                    },
                  ),
                  _buildInfoAction(
                    icon: Icons.auto_fix_high_rounded,
                    label: 'Auto Tag',
                    onPressed: () => _closeDialogAndRun(
                      dialogContext,
                      () => _autoTagWithMusicBrainz(context),
                    ),
                  ),
                  _buildInfoAction(
                    icon: Icons.manage_search_rounded,
                    label: 'Manual Tag',
                    onPressed: () => _closeDialogAndRun(
                      dialogContext,
                      () => _showManualMusicBrainzTagDialog(context),
                    ),
                  ),
                  _buildInfoAction(
                    icon: Icons.edit_note_rounded,
                    label: 'Edit Info',
                    onPressed: () => _closeDialogAndRun(
                      dialogContext,
                      () => _showEditMetadataDialog(context),
                    ),
                  ),
                  _buildInfoAction(
                    icon: Icons.image_rounded,
                    label: 'Cover',
                    onPressed: () => _closeDialogAndRun(
                      dialogContext,
                      () => _pickCoverArt(context),
                    ),
                  ),
                  _buildInfoAction(
                    icon: Icons.playlist_add_rounded,
                    label: 'Playlist',
                    onPressed: () => _closeDialogAndRun(
                      dialogContext,
                      () => _showAddToPlaylistDialog(context),
                    ),
                  ),
                  if (onDelete != null)
                    _buildInfoAction(
                      icon: Icons.delete_outline_rounded,
                      label: 'Delete',
                      onPressed: () => _closeDialogAndRun(
                        dialogContext,
                        () => onDelete?.call(),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    final cleanValue = value.trim().isEmpty ? 'Unknown' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              cleanValue,
              maxLines: label == 'File' ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoAction({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    );
  }

  void _closeDialogAndRun(BuildContext dialogContext, VoidCallback action) {
    Navigator.pop(dialogContext);
    WidgetsBinding.instance.addPostFrameCallback((_) => action());
  }

  void _openTrack() {
    onTap();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onOpen?.call();
    });
  }

  String _formatTrackDuration(Duration? duration) {
    if (duration == null || duration <= Duration.zero) return 'Unknown';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
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
              const Text('Edit Metadata',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              _buildGlassField('Title', titleController),
              const SizedBox(height: 12),
              _buildGlassField('Artist', artistController),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  ElevatedButton(
                    onPressed: () {
                      musicService.updateMusicMetadata(
                          music.id,
                          titleController.text,
                          artistController.text,
                          music.album,
                          music.genre);
                      Navigator.pop(context);
                    },
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.teal),
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

  Future<void> _autoTagWithMusicBrainz(BuildContext context) async {
    await _showMusicBrainzResultsDialog(
      context,
      title: music.title,
      artist: music.artist,
      album: music.album,
      heading: 'Auto Tag Results',
    );
  }

  Future<void> _showManualMusicBrainzTagDialog(BuildContext context) async {
    final titleController = TextEditingController(text: music.title);
    final artistController = TextEditingController(text: music.artist);
    final albumController = TextEditingController(text: music.album);

    final request = await showDialog<_MusicBrainzManualTagRequest>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: GlassContainer(
          width: 340,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Manual MusicBrainz Tag',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _buildGlassField('Title', titleController),
              const SizedBox(height: 12),
              _buildGlassField('Artist', artistController),
              const SizedBox(height: 12),
              _buildGlassField('Album', albumController),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(
                        context,
                        _MusicBrainzManualTagRequest(
                          title: titleController.text,
                          artist: artistController.text,
                          album: albumController.text,
                        ),
                      );
                    },
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                    child: const Text('Search'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    titleController.dispose();
    artistController.dispose();
    albumController.dispose();

    if (request == null || !context.mounted) return;
    await _showMusicBrainzResultsDialog(
      context,
      title: request.title,
      artist: request.artist,
      album: request.album,
      heading: 'Manual Tag Results',
    );
  }

  Future<void> _showMusicBrainzResultsDialog(
    BuildContext context, {
    required String title,
    required String artist,
    required String album,
    required String heading,
  }) async {
    final musicService = Provider.of<MusicService>(context, listen: false);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _MusicBrainzResultsDialog(
        heading: heading,
        title: title,
        artist: artist,
        album: album,
        duration: music.duration,
        onSelected: (tag) async {
          await _applyMusicBrainzTag(
            dialogContext,
            musicService,
            tag,
          );
          if (dialogContext.mounted) {
            Navigator.pop(dialogContext);
          }
        },
      ),
    );
  }

  Future<void> _applyMusicBrainzTag(
    BuildContext context,
    MusicService musicService,
    MusicBrainzTag tag,
  ) async {
    await musicService.updateMusicMetadata(
      music.id,
      tag.title,
      tag.artist,
      tag.album,
      music.genre,
    );
    if (!context.mounted) return;
    _showSnack(context, 'Tagged as ${tag.title} - ${tag.artist}.');
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _pickCoverArt(BuildContext context) async {
    final musicService = Provider.of<MusicService>(context, listen: false);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      withData: false,
    );
    final path = result?.files.single.path;
    if (path == null || path.trim().isEmpty) return;

    await musicService.updateMusicCover(music.id, path);
  }

  Widget _buildGlassField(String label, TextEditingController controller) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12)),
      child: TextField(
        controller: controller,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
            labelText: label,
            border: InputBorder.none,
            labelStyle: const TextStyle(color: Colors.white54, fontSize: 12)),
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
              const Text('Add to Playlist',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              if (musicService.playlists.isEmpty)
                const Text('No playlists available',
                    style: TextStyle(color: Colors.white54))
              else
                ...musicService.playlists.map((pl) => ListTile(
                      title:
                          Text(pl.name, style: const TextStyle(fontSize: 14)),
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

class _MusicBrainzManualTagRequest {
  final String title;
  final String artist;
  final String album;

  const _MusicBrainzManualTagRequest({
    required this.title,
    required this.artist,
    required this.album,
  });
}

class _MusicBrainzResultsDialog extends StatefulWidget {
  final String heading;
  final String title;
  final String artist;
  final String album;
  final Duration? duration;
  final Future<void> Function(MusicBrainzTag tag) onSelected;

  const _MusicBrainzResultsDialog({
    required this.heading,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.onSelected,
  });

  @override
  State<_MusicBrainzResultsDialog> createState() =>
      _MusicBrainzResultsDialogState();
}

class _MusicBrainzResultsDialogState extends State<_MusicBrainzResultsDialog> {
  Future<List<MusicBrainzTag>>? _resultsFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _resultsFuture = MusicBrainzTagService().searchTags(
          title: widget.title,
          artist: widget.artist,
          album: widget.album,
          duration: widget.duration,
          limit: 12,
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final resultsFuture = _resultsFuture;
    return AlertDialog(
      backgroundColor: Colors.transparent,
      contentPadding: EdgeInsets.zero,
      content: GlassContainer(
        width: 420,
        padding: const EdgeInsets.all(18),
        child: SizedBox(
          height: 460,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.heading,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  [
                    widget.title.trim(),
                    if (widget.artist.trim().isNotEmpty) widget.artist.trim(),
                    if (widget.album.trim().isNotEmpty) widget.album.trim(),
                  ].join(' - '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: resultsFuture == null
                    ? _buildLoading()
                    : FutureBuilder<List<MusicBrainzTag>>(
                        future: resultsFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
                            return _buildLoading();
                          }

                          final results =
                              snapshot.data ?? const <MusicBrainzTag>[];
                          if (results.isEmpty) {
                            return const Center(
                              child: Text(
                                'No MusicBrainz results found.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white70),
                              ),
                            );
                          }

                          return ListView.separated(
                            itemCount: results.length,
                            separatorBuilder: (_, __) =>
                                const Divider(color: Colors.white10),
                            itemBuilder: (context, index) {
                              final tag = results[index];
                              return ListTile(
                                dense: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                leading: CircleAvatar(
                                  radius: 16,
                                  backgroundColor:
                                      Colors.teal.withOpacity(0.24),
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                title: Text(
                                  tag.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  [
                                    tag.artist,
                                    tag.album,
                                    if (tag.duration != null)
                                      _formatTagDuration(tag.duration!),
                                    'Score ${tag.musicBrainzScore}',
                                  ].join(' - '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(
                                  Icons.check_circle_outline_rounded,
                                ),
                                onTap: () => widget.onSelected(tag),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 14),
          Text('Searching MusicBrainz...'),
        ],
      ),
    );
  }

  String _formatTagDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
