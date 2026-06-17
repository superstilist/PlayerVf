import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/music_model.dart';
import '../models/playlist_model.dart';
import '../models/settings_model.dart';
import '../services/music_service.dart';
import '../services/performance_policy.dart';
import '../services/responsive.dart';
import '../widgets/music_card.dart';
import '../widgets/cover_art_texture.dart';
import '../widgets/glass_container.dart';
import '../widgets/fade_in_up_animation.dart';

class PlaylistDetailPage extends StatefulWidget {
  final Playlist playlist;
  final VoidCallback? onOpenPlayer;

  const PlaylistDetailPage({
    super.key,
    required this.playlist,
    this.onOpenPlayer,
  });

  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> {
  final Set<String> _selectedIds = <String>{};

  @override
  Widget build(BuildContext context) {
    return Consumer2<MusicService, SettingsModel>(
      builder: (context, musicService, settings, child) {
        final playlist = widget.playlist;
        final musicList = musicService.getMusicListForPlaylist(playlist.id);
        final currentMusic = musicService.currentMusic;
        final bgPath = currentMusic?.coverPath ??
            (musicList.isNotEmpty ? musicList.first.coverPath : '');
        final performance = PerformancePolicy.of(context);
        final listItemExtent = MusicCard.listItemExtent(settings);
        _removeMissingSelections(musicList);

        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: Stack(
            children: [
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 360),
                  child: Stack(
                    key: ValueKey(bgPath),
                    children: [
                      CoverArtTexture(
                          coverArtPath: bgPath,
                          width: double.infinity,
                          height: double.infinity,
                          filterQuality: FilterQuality.medium),
                      Container(color: Colors.black.withOpacity(0.85)),
                    ],
                  ),
                ),
              ),
              CustomScrollView(
                cacheExtent: performance.listCacheExtent,
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: _selectedIds.isEmpty ? 0 : 72.h,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(24.w, 100.h, 24.w, 32.h),
                      child: Column(
                        children: [
                          Center(
                            child: Hero(
                              tag: 'playlist-art-${playlist.id}',
                              child: Container(
                                width: 220.s,
                                height: 220.s,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(24.s),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(24.s),
                                  child: _buildPlaylistCollage(musicList),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: 32.h),
                          Text(
                            playlist.name,
                            style: TextStyle(
                                fontSize: 36.sp,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 0),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 8.h),
                          Text(
                            '${musicList.length} Tracks • curated for you',
                            style: TextStyle(
                                fontSize: 14.sp,
                                color: Colors.white54,
                                fontWeight: FontWeight.w500),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 24.h),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton.icon(
                                onPressed: () =>
                                    musicService.playPlaylist(playlist.id),
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: const Text('Play All'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: settings.accentColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 28, vertical: 14),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20)),
                                  elevation: 0,
                                ),
                              ),
                              const SizedBox(width: 12),
                              IconButton(
                                icon: GlassContainer(
                                  padding: const EdgeInsets.all(12),
                                  borderRadius: BorderRadius.circular(20),
                                  color: Colors.white.withOpacity(0.08),
                                  child: const Icon(Icons.edit_note_rounded,
                                      color: Colors.white, size: 24),
                                ),
                                onPressed: () => _showEditPlaylistDialog(
                                    context, musicService),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (musicList.isEmpty)
                    const SliverFillRemaining(
                      child: Center(
                        child: Text('Empty Playlist',
                            style: TextStyle(color: Colors.white24)),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.symmetric(
                        horizontal:
                            settings.viewMode == ViewMode.list ? 0 : 16.w,
                      ),
                      sliver: settings.viewMode == ViewMode.card
                          ? SliverGrid(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: _calculateCrossAxisCount(
                                    Responsive.screenWidth),
                                crossAxisSpacing: 16.w,
                                mainAxisSpacing: 16.h,
                                childAspectRatio: 1.0,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final music = musicList[index];
                                  return FadeInUpAnimation(
                                    delay: index * 0.03,
                                    child: MusicCard(
                                      music: music,
                                      viewMode: ViewMode.card,
                                      heroPrefix: 'playlist-detail',
                                      listIndex: index,
                                      isVideoTrack: MusicCard.computeIsVideoTrack(music),
                                      selectionMode: _selectedIds.isNotEmpty,
                                      isSelected:
                                          _selectedIds.contains(music.id),
                                      onSelectionStart: () =>
                                          _startSelection(music.id),
                                      onSelectionToggle: () =>
                                          _toggleSelection(music.id),
                                      onTap: () => musicService
                                          .playMusicFromQueue(musicList, music,
                                              playlistId: playlist.id),
                                      onOpen: () =>
                                          _openPlayerFromDetail(context),
                                      onDelete: () {
                                        musicService.removeMusicFromPlaylist(
                                            playlist.id, music.id);
                                        return true;
                                      },
                                    ),
                                  );
                                },
                                childCount: musicList.length,
                              ),
                            )
                          : SliverFixedExtentList(
                              itemExtent: listItemExtent,
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final music = musicList[index];
                                  return FadeInUpAnimation(
                                    delay: index * 0.03,
                                    child: MusicCard(
                                      music: music,
                                      viewMode: ViewMode.list,
                                      heroPrefix: 'playlist-detail',
                                      listIndex: index,
                                      listLength: musicList.length,
                                      isVideoTrack: MusicCard.computeIsVideoTrack(music),
                                      selectionMode: _selectedIds.isNotEmpty,
                                      isSelected:
                                          _selectedIds.contains(music.id),
                                      onSelectionStart: () =>
                                          _startSelection(music.id),
                                      onSelectionToggle: () =>
                                          _toggleSelection(music.id),
                                      onTap: () => musicService
                                          .playMusicFromQueue(musicList, music,
                                              playlistId: playlist.id),
                                      onOpen: () =>
                                          _openPlayerFromDetail(context),
                                      onDelete: () {
                                        musicService.removeMusicFromPlaylist(
                                            playlist.id, music.id);
                                        return true;
                                      },
                                    ),
                                  );
                                },
                                childCount: musicList.length,
                              ),
                            ),
                    ),
                  SliverToBoxAdapter(child: SizedBox(height: 120.h)),
                ],
              ),
              if (_selectedIds.isNotEmpty)
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 8.h,
                  left: 12.w,
                  right: 12.w,
                  child: _buildSelectionBar(
                    context,
                    musicService,
                    musicList,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _openPlayerFromDetail(BuildContext context) {
    final open = widget.onOpenPlayer;
    if (open == null) return;
    Navigator.of(context).maybePop();
    WidgetsBinding.instance.addPostFrameCallback((_) => open());
  }

  Widget _buildSelectionBar(
    BuildContext context,
    MusicService musicService,
    List<Music> musicList,
  ) {
    final theme = Theme.of(context);
    final selected = musicList
        .where((music) => _selectedIds.contains(music.id))
        .toList(growable: false);
    return Material(
      color: Colors.transparent,
      child: Container(
        height: 58.h.clamp(54.0, 66.0),
        padding: EdgeInsets.symmetric(horizontal: 10.w),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withOpacity(0.96),
          borderRadius: BorderRadius.circular(18.s),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withOpacity(0.36),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.24),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Clear selection',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(_selectedIds.clear),
            ),
            Expanded(
              child: Text(
                '${selected.length} selected',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15.sp,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Select all',
              icon: const Icon(Icons.select_all_rounded),
              onPressed: () => _selectVisible(musicList),
            ),
            IconButton(
              tooltip: 'Listen together',
              icon: const Icon(Icons.groups_rounded),
              onPressed: selected.isEmpty
                  ? null
                  : () => _listenTogetherSelected(musicService, selected),
            ),
            IconButton(
              tooltip: 'Add selected to queue',
              icon: const Icon(Icons.queue_music_rounded),
              onPressed: selected.isEmpty
                  ? null
                  : () => _addSelectedToQueue(musicService, selected),
            ),
            IconButton(
              tooltip: 'Remove from playlist',
              icon: Icon(
                Icons.playlist_remove_rounded,
                color: theme.colorScheme.error,
              ),
              onPressed: selected.isEmpty
                  ? null
                  : () => _removeSelectedFromPlaylist(musicService, selected),
            ),
          ],
        ),
      ),
    );
  }

  void _startSelection(String id) {
    setState(() => _selectedIds.add(id));
  }

  void _toggleSelection(String id) {
    setState(() {
      if (!_selectedIds.remove(id)) {
        _selectedIds.add(id);
      }
    });
  }

  void _selectVisible(List<Music> visible) {
    setState(() {
      if (_selectedIds.length == visible.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(visible.map((music) => music.id));
      }
    });
  }

  void _removeMissingSelections(List<Music> visible) {
    if (_selectedIds.isEmpty) return;
    final ids = visible.map((music) => music.id).toSet();
    _selectedIds.removeWhere((id) => !ids.contains(id));
  }

  void _addSelectedToQueue(MusicService musicService, List<Music> selected) {
    musicService.addAllToQueue(selected);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('${selected.length} added to current queue.')),
      );
    setState(_selectedIds.clear);
  }

  void _listenTogetherSelected(
      MusicService musicService, List<Music> selected) {
    _addSelectedToQueue(musicService, selected);
    widget.onOpenPlayer?.call();
  }

  Future<void> _removeSelectedFromPlaylist(
    MusicService musicService,
    List<Music> selected,
  ) async {
    for (final music in selected) {
      musicService.removeMusicFromPlaylist(widget.playlist.id, music.id);
    }
    if (!mounted) return;
    setState(_selectedIds.clear);
  }

  Widget _buildPlaylistCollage(List<Music> musicList) {
    if (musicList.isEmpty) {
      return Container(
        color: Colors.white.withOpacity(0.05),
        child: const Icon(Icons.playlist_play_rounded,
            size: 100, color: Colors.white10),
      );
    }

    if (musicList.length < 4) {
      return CoverArtTexture(
          coverArtPath: musicList[0].coverPath,
          width: 220.s,
          height: 220.s,
          filterQuality: FilterQuality.high,
          cacheScale: 2.2);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = constraints.maxWidth / 2;
        final tileHeight = constraints.maxHeight / 2;
        return Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(
                      child: CoverArtTexture(
                          coverArtPath: musicList[0].coverPath,
                          width: tileWidth,
                          height: tileHeight,
                          filterQuality: FilterQuality.high,
                          cacheScale: 2.2)),
                  Expanded(
                      child: CoverArtTexture(
                          coverArtPath: musicList[1].coverPath,
                          width: tileWidth,
                          height: tileHeight,
                          filterQuality: FilterQuality.high,
                          cacheScale: 2.2)),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                      child: CoverArtTexture(
                          coverArtPath: musicList[2].coverPath,
                          width: tileWidth,
                          height: tileHeight,
                          filterQuality: FilterQuality.high,
                          cacheScale: 2.2)),
                  Expanded(
                      child: CoverArtTexture(
                          coverArtPath: musicList[3].coverPath,
                          width: tileWidth,
                          height: tileHeight,
                          filterQuality: FilterQuality.high,
                          cacheScale: 2.2)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  int _calculateCrossAxisCount(double width) {
    if (width < 600) return 2;
    if (width < 900) return 3;
    return 4;
  }

  void _showEditPlaylistDialog(
      BuildContext context, MusicService musicService) {
    final controller = TextEditingController(text: widget.playlist.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: GlassContainer(
          padding: const EdgeInsets.all(24),
          borderRadius: BorderRadius.circular(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Edit Playlist',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12)),
                child: TextField(
                  controller: controller,
                  style: const TextStyle(fontSize: 16),
                  decoration: const InputDecoration(
                      border: InputBorder.none, hintText: 'Playlist Name'),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () {
                      if (controller.text.isNotEmpty) {
                        musicService.renamePlaylist(
                            widget.playlist.id, controller.text);
                        Navigator.pop(context);
                      }
                    },
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                    child: const Text('Rename'),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}
