import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/music_model.dart';
import '../models/settings_model.dart';
import '../services/music_service.dart';
import '../services/musicbrainz_tag_service.dart';
import '../services/responsive.dart';
import '../services/safe_file_picker.dart';
import '../services/performance_policy.dart';
import '../services/spotify_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'cover_art_texture.dart';
import 'glass_container.dart';
import 'lanczos_cover_art.dart';
import 'pressable_scale.dart';

class MusicCard extends StatelessWidget {
  final Music music;
  final VoidCallback onTap;
  final VoidCallback? onOpen;
  final FutureOr<bool> Function()? onDelete;
  final bool deleteRemovesFile;
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback? onSelectionToggle;
  final VoidCallback? onSelectionStart;
  final ViewMode viewMode;
  final String? heroPrefix;
  final int? listIndex;
  final int? listLength;
  final bool isVideoTrack;

  const MusicCard({
    super.key,
    required this.music,
    required this.onTap,
    this.onOpen,
    this.onDelete,
    this.deleteRemovesFile = false,
    this.selectionMode = false,
    this.isSelected = false,
    this.onSelectionToggle,
    this.onSelectionStart,
    this.viewMode = ViewMode.card,
    this.heroPrefix,
    this.listIndex,
    this.listLength,
    this.isVideoTrack = false,
  });

  static double listItemExtent(SettingsModel settings) {
    final scale = settings.cardSize / 140.0;
    final baseHeight = Responsive.isTablet ? 76.0 : 72.0;
    return (baseHeight * scale).clamp(70.0, 100.0).h;
  }

  static bool computeIsVideoTrack(Music music) {
    final genre = music.genre.trim().toLowerCase();
    if (genre.contains('video')) return true;
    if (genre == 'youtube music') return false;
    final target = music.filePath.trim();
    final parsed = Uri.tryParse(target);
    final candidate = parsed != null && parsed.hasScheme
        ? parsed.path
        : target.split('?').first.split('#').first;
    final ext = candidate.split('.').last.toLowerCase();
    return [
      'mp4', 'mkv', 'webm', 'avi', 'mov', 'm4v', 'wmv', 'flv', 'ts', 'm2ts', '3gp', 'm3u8',
    ].contains(ext);
  }

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
    final isFavorite = context
        .select<MusicService, bool>((service) => service.isFavorite(music.id));
    final theme = Theme.of(context);
    final double scale = settings.cardSize / 140.0;
    final double rowExtent = listItemExtent(settings);
    final double iconSize = (19 * scale).clamp(17.0, 22.0).s;
    final isFirst = listIndex == null || listIndex == 0;
    final isLast =
        listIndex == null || listLength == null || listIndex == listLength! - 1;
    final isEven = (listIndex ?? 0).isEven;
    final glass = settings.glassEffect.clamp(0.0, 1.0).toDouble();
    final solidOpacity = theme.brightness == Brightness.dark
        ? (isEven ? 0.92 : 0.86)
        : (isEven ? 0.96 : 0.90);
    final glassOpacity = theme.brightness == Brightness.dark
        ? (isEven ? 0.34 : 0.24)
        : (isEven ? 0.58 : 0.44);
    final rowColor = theme.colorScheme.surfaceContainerHighest.withOpacity(
      solidOpacity + ((glassOpacity - solidOpacity) * glass),
    );
    final rowRadius = BorderRadius.vertical(
      top: Radius.circular(isFirst ? 12.s : 0),
      bottom: Radius.circular(isLast ? 12.s : 0),
    );

     return AnimatedSlide(
       duration: const Duration(milliseconds: 170),
       curve: Curves.easeOutCubic,
       offset: isSelected ? const Offset(-0.012, 0) : Offset.zero,
       child: Padding(
         padding: EdgeInsets.symmetric(horizontal: 10.w),
         child: ClipRRect(
           borderRadius: rowRadius,
           child: Material(
             color: rowColor,
             shape: RoundedRectangleBorder(
               borderRadius: rowRadius,
             ),
             child: GestureDetector(
               behavior: HitTestBehavior.opaque,
               onSecondaryTapDown: (details) => _handleSecondaryTap(
                 context,
                 details.globalPosition,
               ),
               child: InkWell(
                 onTap: selectionMode ? onSelectionToggle : onTap,
                 onLongPress: () => _startSelectionOrMenu(context),
                 child: SizedBox(
                   height: rowExtent,
                   child: Column(
                     children: [
                       Expanded(
                         child: Padding(
                           padding: EdgeInsets.only(left: 10.w, right: 4.w),
                           child: Row(
                             children: [
                               AnimatedSwitcher(
                                 duration: const Duration(milliseconds: 160),
                                 switchInCurve: Curves.easeOutCubic,
                                 switchOutCurve: Curves.easeInCubic,
                                 child: selectionMode
                                     ? Padding(
                                         key: const ValueKey('selection-mark'),
                                         padding: EdgeInsets.only(right: 8.w),
                                         child: _SelectionMark(
                                           isSelected: isSelected,
                                         ),
                                       )
                                     : const SizedBox(
                                         key: ValueKey('selection-empty'),
                                       ),
                                 ),
                                 ClipRRect(
                                   borderRadius: BorderRadius.circular(
                                     Responsive.listArtRadius,
                                   ),
                                   child: _maybeHero(
                                     context,
                                     SizedBox(
                                       width: Responsive.listArtSize,
                                       height: Responsive.listArtSize,
                                       child: LanczosCoverArt(
                                         coverArtPath: music.coverPath,
                                         width: Responsive.listArtSize,
                                         height: Responsive.listArtSize,
                                         borderRadius: BorderRadius.circular(
                                           Responsive.listArtRadius,
                                         ),
                                         coverArtDisplayMode:
                                             Provider.of<SettingsModel>(context)
                                                 .coverArtDisplayMode,
                                       ),
                                     ),
                                   ),
                                 ),
                                 SizedBox(width: 10.w),
                                 Expanded(
                                   child: Column(
                                     mainAxisAlignment: MainAxisAlignment.center,
                                     crossAxisAlignment:
                                         CrossAxisAlignment.start,
                                     children: [
                                        Row(
                                          children: [
                                            if (isVideoTrack) ...[
                                             Icon(
                                               Icons.videocam_rounded,
                                               size: (13 * scale)
                                                   .clamp(12.0, 16.0)
                                                   .s,
                                               color: theme.colorScheme.primary,
                                             ),
                                             SizedBox(width: 4.w),
                                           ],
                                           Expanded(
                                             child: Text(
                                               music.title,
                                               style: TextStyle(
                                                 color:
                                                     theme.colorScheme.onSurface,
                                                 fontSize: (12.5 * scale)
                                                     .clamp(11.5, 15.5)
                                                     .sp,
                                                 fontWeight: FontWeight.w800,
                                               ),
                                               maxLines: 1,
                                               overflow: TextOverflow.ellipsis,
                                             ),
                                           ),
                                         ],
                                       ),
                                       SizedBox(height: 1.h),
                                       Text(
                                         music.artist,
                                         style: TextStyle(
                                           color: theme.colorScheme.onSurface
                                               .withOpacity(0.58),
                                           fontSize: (10.8 * scale)
                                               .clamp(10.0, 13.5)
                                               .sp,
                                           fontWeight: FontWeight.w600,
                                         ),
                                         maxLines: 1,
                                         overflow: TextOverflow.ellipsis,
                                       ),
                                     ],
                                   ),
                                 ),
                                 _buildListIconButton(
                                   icon: isFavorite
                                       ? Icons.favorite
                                       : Icons.favorite_border,
                                   color: isFavorite
                                       ? settings.accentColor
                                       : theme.colorScheme.onSurfaceVariant,
                                   iconSize: iconSize,
                                   onPressed: () =>
                                       musicService.toggleFavorite(music.id),
                                 ),
                                 _buildListIconButton(
                                   icon: Icons.more_vert,
                                   color: theme.colorScheme.onSurfaceVariant,
                                   iconSize: iconSize,
                                   onPressed: () =>
                                       _showGlassContextMenuFromLongPress(
                                           context),
                                 ),
                               ],
                             ),
                           ),
                         ),
                         if (!isLast) SizedBox(height: 0.6.h),
                       ],
                     ),
                   ),
                 ),
               ),
             ),
           ),
         ),
       );
  }

  Widget _buildListIconButton({
    required IconData icon,
    required Color color,
    required double iconSize,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 38, height: 38),
      icon: Icon(icon, color: color, size: iconSize),
      onPressed: onPressed,
    );
  }

  Widget _maybeHero(BuildContext context, Widget child) {
    if (kIsWeb) return child;
    final policy = PerformancePolicy.of(context);
    if (policy.isAndroid) return child;
    return Hero(
      tag: _heroTag,
      child: RepaintBoundary(child: child),
    );
  }

  Widget _buildCardView(BuildContext context, SettingsModel settings) {
    final musicService = Provider.of<MusicService>(context, listen: false);
    final isFavorite = context
        .select<MusicService, bool>((service) => service.isFavorite(music.id));

    return PressableScale(
      onTap: selectionMode ? onSelectionToggle : onTap,
      child: AnimatedSlide(
      duration: const Duration(milliseconds: 170),
      curve: Curves.easeOutCubic,
      offset: isSelected ? const Offset(-0.018, 0) : Offset.zero,
      child: GestureDetector(
        onTap: selectionMode ? onSelectionToggle : onTap,
        onSecondaryTapDown: (details) => _handleSecondaryTap(
          context,
          details.globalPosition,
        ),
        onLongPress: () => _startSelectionOrMenu(context),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16.s),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16.s),
            child: AspectRatio(
              aspectRatio: 1.0,
              child: Stack(
                 fit: StackFit.expand,
                 children: [
                   _maybeHero(
                     context,
                     CoverArtTexture(
                       coverArtPath: music.coverPath,
                       width: double.infinity,
                       height: double.infinity,
                       coverArtDisplayMode:
                           Provider.of<SettingsModel>(context).coverArtDisplayMode,
                     ),
                   ),
                   Container(
                     decoration: BoxDecoration(
                       gradient: LinearGradient(
                         begin: Alignment.topCenter,
                         end: Alignment.bottomCenter,
                         colors: [
                           Colors.transparent,
                           Colors.black.withOpacity(0.62)
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
                         padding: EdgeInsets.all(Responsive.isPhone ? 6.s : 4.s),
                         color: Colors.black.withOpacity(0.22),
                         borderRadius: BorderRadius.circular(6.s),
                         blur: 0.0,
                         child: Icon(
                           isFavorite ? Icons.favorite : Icons.favorite_border,
                           color:
                               isFavorite ? settings.accentColor : Colors.white,
                           size: (Responsive.isPhone ? 17 : 14).s,
                         ),
                       ),
                     ),
                   ),
                  if (isVideoTrack && !selectionMode)
                    Positioned(
                      top: 6.s,
                      left: 6.s,
                      child: GlassContainer(
                        padding: EdgeInsets.all(Responsive.isPhone ? 6.s : 4.s),
                        color: Colors.black.withOpacity(0.22),
                        borderRadius: BorderRadius.circular(6.s),
                        blur: 0.0,
                        child: Icon(
                          Icons.videocam_rounded,
                          color: Colors.white,
                          size: (Responsive.isPhone ? 17 : 14).s,
                        ),
                      ),
                    ),
                  if (selectionMode)
                    Positioned(
                      top: 8.s,
                      left: 8.s,
                      child: _SelectionMark(isSelected: isSelected),
                    ),
                  if (isSelected)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: settings.accentColor.withOpacity(0.95),
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(
                            8.s,
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
                              fontSize: (Responsive.isPhone ? 11.5 : 10).sp,
                              fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          music.artist,
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: (Responsive.isPhone ? 9.5 : 8).sp),
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

  void _handleSecondaryTap(BuildContext context, Offset position) {
    if (selectionMode || onSelectionStart != null) {
      _startSelectionOrToggle();
      return;
    }
    _showGlassContextMenu(context, position);
  }

  void _startSelectionOrMenu(BuildContext context) {
    if (selectionMode || onSelectionStart != null) {
      _startSelectionOrToggle();
      return;
    }
    _showGlassContextMenuFromLongPress(context);
  }

  void _startSelectionOrToggle() {
    if (selectionMode) {
      onSelectionToggle?.call();
      return;
    }
    onSelectionStart?.call();
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
      builder: (menuContext) => SizedBox.expand(
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: EdgeInsets.only(left: left, top: top),
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
                        deleteRemovesFile ? 'Delete File' : 'Delete',
                        Icons.delete_outline_rounded,
                        Colors.redAccent,
                        () => _confirmAndDelete(actionContext)),
                  ],
                ),
              ),
            ),
          ),
        ),
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
        action();
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
    final isFavorite = musicService.isFavorite(music.id);
    showDialog(
      context: context,
      builder: (dialogContext) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Material(
            type: MaterialType.transparency,
            child: GlassContainer(
          width: Responsive.wp(94).clamp(300.0, 480.0),
          padding: EdgeInsets.all(Responsive.s(22)),
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
                      coverArtDisplayMode:
                          Provider.of<SettingsModel>(context).coverArtDisplayMode,
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
              _buildInfoRow(
                  'Year', music.year.trim().isEmpty ? 'Unknown' : music.year),
              _buildInfoRow('Duration', _formatTrackDuration(music.duration)),
              _buildInfoRow('File', music.filePath),
              _SpotifyLinkRow(music: music),
              const SizedBox(height: 18),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildInfoAction(
                      icon: Icons.play_arrow_rounded,
                      label: 'Play',
                      onPressed: () => _closeDialogAndRun(dialogContext, onTap),
                    ),
                    const SizedBox(width: 8),
                    _buildInfoAction(
                      icon: Icons.open_in_full_rounded,
                      label: 'Open',
                      onPressed: () =>
                          _closeDialogAndRun(dialogContext, _openTrack),
                    ),
                    const SizedBox(width: 8),
                    _buildInfoAction(
                      icon: isFavorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      label: isFavorite ? 'Unfavorite' : 'Favorite',
                      onPressed: () {
                        musicService.toggleFavorite(music.id);
                        _showSnack(
                          context,
                          isFavorite
                              ? 'Removed from favorites.'
                              : 'Added to favorites.',
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildInfoAction(
                      icon: Icons.auto_fix_high_rounded,
                      label: 'Auto Tag',
                      onPressed: () => _closeDialogAndRun(
                        dialogContext,
                        () => _autoTagWithMusicBrainz(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildInfoAction(
                      icon: Icons.manage_search_rounded,
                      label: 'Manual Tag',
                      onPressed: () => _closeDialogAndRun(
                        dialogContext,
                        () => _showManualMusicBrainzTagDialog(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildInfoAction(
                      icon: Icons.edit_note_rounded,
                      label: 'Edit Info',
                      onPressed: () => _closeDialogAndRun(
                        dialogContext,
                        () => _showEditMetadataDialog(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildInfoAction(
                      icon: Icons.image_rounded,
                      label: 'Cover',
                      onPressed: () => _closeDialogAndRun(
                        dialogContext,
                        () => _pickCoverArt(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildInfoAction(
                      icon: Icons.playlist_add_rounded,
                      label: 'Playlist',
                      onPressed: () => _closeDialogAndRun(
                        dialogContext,
                        () => _showAddToPlaylistDialog(context),
                      ),
                    ),
                    if (onDelete != null) ...[
                      const SizedBox(width: 8),
                      _buildInfoAction(
                        icon: Icons.delete_outline_rounded,
                        label: deleteRemovesFile ? 'Delete File' : 'Delete',
                        onPressed: () => _closeDialogAndRun(
                          dialogContext,
                          () => _confirmAndDelete(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
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

  Future<void> _confirmAndDelete(BuildContext context) async {
    if (onDelete == null) return;

    if (deleteRemovesFile) {
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Delete file?'),
              content: Text(
                'This will permanently delete "${music.title}" from this device. This cannot be undone.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Delete'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(dialogContext).colorScheme.error,
                    foregroundColor:
                        Theme.of(dialogContext).colorScheme.onError,
                  ),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return;
    }

    final deleted = await onDelete!();
    if (!context.mounted) return;
    if (deleteRemovesFile) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              deleted
                  ? 'Deleted "${music.title}" from this device.'
                  : 'Could not delete "${music.title}".',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
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

  Future<void> _showEditMetadataDialog(BuildContext context) async {
    final musicService = Provider.of<MusicService>(context, listen: false);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _EditMetadataDialog(
        music: music,
        onSave: ({
          required title,
          required artist,
          required album,
          required genre,
          required year,
          String? coverPath,
        }) async {
          await musicService.updateMusicMetadata(
            music.id,
            title,
            artist,
            album,
            genre,
            year: year,
          );
          if (coverPath != null && coverPath != music.coverPath) {
            await musicService.updateMusicCover(music.id, coverPath);
          }
        },
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
    final request = await showDialog<_MusicBrainzManualTagRequest>(
      context: context,
      builder: (_) => _ManualMusicBrainzTagDialog(
        title: music.title,
        artist: music.artist,
        album: music.album,
      ),
    );

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
    final path = await pickFilePathSafely(
      context,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (path == null || path.trim().isEmpty) return;

    await musicService.updateMusicCover(music.id, path);
  }

  void _showAddToPlaylistDialog(BuildContext context) {
    final musicService = Provider.of<MusicService>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Material(
            type: MaterialType.transparency,
            child: GlassContainer(
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

typedef _SaveMetadata = Future<void> Function({
  required String title,
  required String artist,
  required String album,
  required String genre,
  required String year,
  String? coverPath,
});

class _EditMetadataDialog extends StatefulWidget {
  final Music music;
  final _SaveMetadata onSave;

  const _EditMetadataDialog({
    required this.music,
    required this.onSave,
  });

  @override
  State<_EditMetadataDialog> createState() => _EditMetadataDialogState();
}

class _EditMetadataDialogState extends State<_EditMetadataDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;
  late final TextEditingController _albumController;
  late final TextEditingController _genreController;
  late final TextEditingController _yearController;
  bool _isSaving = false;
  String? _selectedCoverPath;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.music.title);
    _artistController = TextEditingController(text: widget.music.artist);
    _albumController = TextEditingController(text: widget.music.album);
    _genreController = TextEditingController(text: widget.music.genre);
    _yearController = TextEditingController(text: widget.music.year);
    _selectedCoverPath = widget.music.coverPath;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    _genreController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await widget.onSave(
        title: _cleanMetadataText(_titleController.text, 'Unknown title'),
        artist: _cleanMetadataText(_artistController.text, 'Unknown Artist'),
        album: _cleanMetadataText(_albumController.text, 'Unknown Album'),
        genre: _cleanMetadataText(_genreController.text, 'Unknown'),
        year: _cleanYear(_yearController.text),
        coverPath: _selectedCoverPath,
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  static String _cleanMetadataText(String value, String fallback) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }

  static String _cleanYear(String value) {
    final match = RegExp(r'\d{4}').firstMatch(value);
    return match?.group(0) ?? value.trim();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.transparent,
      contentPadding: EdgeInsets.zero,
      content: GlassContainer(
        width: 320,
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 620),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Edit Info',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _buildCoverArtSection(context),
                const SizedBox(height: 16),
                _GlassTextField(label: 'Title', controller: _titleController),
                const SizedBox(height: 12),
                _GlassTextField(label: 'Artist', controller: _artistController),
                const SizedBox(height: 12),
                _GlassTextField(label: 'Album', controller: _albumController),
                const SizedBox(height: 12),
                _GlassTextField(label: 'Genre', controller: _genreController),
                const SizedBox(height: 12),
                _GlassTextField(
                  label: 'Year',
                  controller: _yearController,
                  keyboardType: TextInputType.number,
                ),
                if (_isSaving) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(minHeight: 2),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed:
                          _isSaving ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCoverArtSection(BuildContext context) {
    final theme = Theme.of(context);
    final coverPath = _selectedCoverPath ?? widget.music.coverPath;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 100,
            height: 100,
            child: coverPath.isNotEmpty
                ? (coverPath.startsWith('http')
                    ? Image.network(coverPath, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _coverFallback(theme))
                    : CoverArtTexture(coverArtPath: coverPath, width: 100, height: 100))
                : _coverFallback(theme),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: () => _pickNewCover(context),
              icon: const Icon(Icons.image_rounded, size: 18),
              label: const Text('Change Cover'),
            ),
            if (_selectedCoverPath != null && _selectedCoverPath != widget.music.coverPath)
              TextButton.icon(
                onPressed: () => setState(() => _selectedCoverPath = null),
                icon: const Icon(Icons.restore_rounded, size: 18),
                label: const Text('Reset'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _coverFallback(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(Icons.music_note_rounded, size: 40, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
    );
  }

  Future<void> _pickNewCover(BuildContext context) async {
    final path = await pickFilePathSafely(
      context,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (path != null && path.trim().isNotEmpty) {
      setState(() => _selectedCoverPath = path.trim());
    }
  }
}

class _ManualMusicBrainzTagDialog extends StatefulWidget {
  final String title;
  final String artist;
  final String album;

  const _ManualMusicBrainzTagDialog({
    required this.title,
    required this.artist,
    required this.album,
  });

  @override
  State<_ManualMusicBrainzTagDialog> createState() =>
      _ManualMusicBrainzTagDialogState();
}

class _ManualMusicBrainzTagDialogState
    extends State<_ManualMusicBrainzTagDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;
  late final TextEditingController _albumController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.title);
    _artistController = TextEditingController(text: widget.artist);
    _albumController = TextEditingController(text: widget.album);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.pop(
      context,
      _MusicBrainzManualTagRequest(
        title: _titleController.text,
        artist: _artistController.text,
        album: _albumController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Material(
          type: MaterialType.transparency,
          child: GlassContainer(
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
                _GlassTextField(label: 'Title', controller: _titleController),
                const SizedBox(height: 12),
                _GlassTextField(label: 'Artist', controller: _artistController),
                const SizedBox(height: 12),
                _GlassTextField(label: 'Album', controller: _albumController),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                      child: const Text('Search'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;

  const _GlassTextField({
    required this.label,
    required this.controller,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          border: InputBorder.none,
          labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ),
    );
  }
}

class _SelectionMark extends StatelessWidget {
  final bool isSelected;

  const _SelectionMark({required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: isSelected
            ? theme.colorScheme.primary
            : theme.colorScheme.surface.withOpacity(0.88),
        border: Border.all(
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: 1.4,
        ),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 130),
        child: isSelected
            ? Icon(
                Icons.check_rounded,
                key: const ValueKey('selected'),
                color: theme.colorScheme.onPrimary,
                size: 18,
              )
            : const SizedBox(key: ValueKey('empty')),
      ),
    );
  }
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

class _SpotifyLinkRow extends StatelessWidget {
  final Music music;
  const _SpotifyLinkRow({required this.music});

  @override
  Widget build(BuildContext context) {
    return Selector<MusicService, Music?>(
      selector: (_, svc) => svc.musicList.where((m) => m.id == music.id).firstOrNull,
      builder: (context, freshMusic, _) {
        final m = freshMusic ?? music;
        if (m.spotifyUrl != null && m.spotifyUrl!.isNotEmpty) {
          return _SpotifyLinkFound(music: m);
        }
        return _SpotifyLinkSearch(music: m);
      },
    );
  }
}

class _SpotifyLinkFound extends StatelessWidget {
  final Music music;
  const _SpotifyLinkFound({required this.music});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(
            width: 72,
            child: Text('Spotify', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () async {
                final url = Uri.parse(music.spotifyUrl!);
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
              child: Text(
                music.spotifyUrl!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Colors.lightBlueAccent,
                  decoration: TextDecoration.underline),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit, size: 16, color: Colors.white54),
            onPressed: () => _showEditLinkDialog(context, music),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditLinkDialog(BuildContext context, Music music) async {
    final TextEditingController controller = TextEditingController(text: music.spotifyUrl ?? '');
    final newUrl = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Spotify Link'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'https://open.spotify.com/track/...',
              labelText: 'Spotify URL',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save')),
          ],
        );
      },
    );
    if (newUrl != null && newUrl.isNotEmpty && context.mounted) {
      final musicService = Provider.of<MusicService>(context, listen: false);
      await musicService.updateMusicMetadata(
        music.id, music.title, music.artist, music.album, music.genre,
        year: music.year, spotifyUrl: newUrl,
      );
    }
  }
}

class _SpotifyLinkSearch extends StatefulWidget {
  final Music music;
  const _SpotifyLinkSearch({required this.music});

  @override
  State<_SpotifyLinkSearch> createState() => _SpotifyLinkSearchState();
}

class _SpotifyLinkSearchState extends State<_SpotifyLinkSearch> {
  bool _isLoading = false;

  Future<void> _fetchSpotifyLink() async {
    setState(() => _isLoading = true);
    try {
      final spotifyService = Provider.of<SpotifyService>(context, listen: false);
      final url = await spotifyService.getTrackSpotifyUrl(widget.music);
      if (url != null && mounted) {
        final musicService = Provider.of<MusicService>(context, listen: false);
        await musicService.updateMusicMetadata(
          widget.music.id, widget.music.title, widget.music.artist,
          widget.music.album, widget.music.genre,
          year: widget.music.year, spotifyUrl: url,
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Song not found on Spotify. Tap edit to add manually.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showEditLinkDialog() async {
    final TextEditingController controller = TextEditingController(text: widget.music.spotifyUrl ?? '');
    final newUrl = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Spotify Link'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'https://open.spotify.com/track/...',
              labelText: 'Spotify URL',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save')),
          ],
        );
      },
    );
    if (newUrl != null && newUrl.isNotEmpty && mounted) {
      final musicService = Provider.of<MusicService>(context, listen: false);
      await musicService.updateMusicMetadata(
        widget.music.id, widget.music.title, widget.music.artist,
        widget.music.album, widget.music.genre,
        year: widget.music.year, spotifyUrl: newUrl,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(
            width: 72,
            child: Text('Spotify', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          Expanded(
            child: _isLoading
                ? const SizedBox(height: 14, width: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : GestureDetector(
                    onTap: _fetchSpotifyLink,
                    child: const Text('Search on Spotify',
                      style: TextStyle(fontSize: 13, color: Colors.amberAccent,
                        fontWeight: FontWeight.bold)),
                  ),
          ),
          IconButton(
            icon: const Icon(Icons.edit, size: 16, color: Colors.white54),
            onPressed: _showEditLinkDialog,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}
