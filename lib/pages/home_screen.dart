import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/music_model.dart';
import '../models/playlist_model.dart';
import '../models/settings_model.dart';
import '../services/local_share_service.dart';
import '../services/music_service.dart';
import '../services/performance_policy.dart';
import '../services/responsive.dart';
import '../widgets/cover_art_texture.dart';
import '../widgets/music_card.dart';
import '../widgets/glass_container.dart';
import 'playlist_detail_page.dart';

enum _HomeRowStyle { cards, lines, mixed }

class HomeScreen extends StatefulWidget {
  final String searchQuery;
  final VoidCallback? onOpenPlayer;

  const HomeScreen({
    super.key,
    this.searchQuery = '',
    this.onOpenPlayer,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final LocalShareService _shareService = LocalShareService();
  final Set<String> _selectedIds = <String>{};
  _HomeRowStyle _rowStyle = _HomeRowStyle.mixed;
  List<Music>? _cachedLibrary;
  int _cachedLibraryLength = -1;
  String _cachedQuery = '';
  List<Music> _cachedFilteredMusic = const [];

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery &&
        _selectedIds.isNotEmpty) {
      setState(_selectedIds.clear);
    }
  }

  @override
  void dispose() {
    unawaited(_shareService.stopSharing());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<MusicService, SettingsModel>(
      builder: (context, musicService, settings, child) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: _buildResponsiveLayout(context, musicService, settings),
        );
      },
    );
  }

  Widget _buildResponsiveLayout(
      BuildContext context, MusicService musicService, SettingsModel settings) {
    final theme = Theme.of(context);
    final performance = PerformancePolicy.of(context);

    if (musicService.isLoadingSystemMusic && musicService.musicList.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: Colors.teal));
    }

    final allMusic = musicService.musicList;
    final normalizedQuery = widget.searchQuery.trim().toLowerCase();
    final filteredMusic = _filteredMusic(allMusic, normalizedQuery);

    final isSearching = normalizedQuery.isNotEmpty;

    _removeMissingSelections(allMusic);
    final mediaPadding = MediaQuery.paddingOf(context);
    final safeTop = mediaPadding.top;
    final safeBottom = mediaPadding.bottom;
    final selectionPanelHeight = 62.h.clamp(56.0, 74.0).toDouble();
    final selectionPanelWidth = 76.w.clamp(68.0, 88.0).toDouble();
    final selectionTop = safeTop + 8.h;
    const effectivePanelPosition = NavPosition.top;
    final selectedTopGap =
        _selectedIds.isNotEmpty && effectivePanelPosition == NavPosition.top
            ? selectionPanelHeight + 24.h
            : 0.0;
    final selectedBottomGap =
        _selectedIds.isNotEmpty && effectivePanelPosition == NavPosition.bottom
            ? selectionPanelHeight + safeBottom + 24.h
            : 0.0;

    return Stack(
      children: [
        CustomScrollView(
          cacheExtent: performance.listCacheExtent,
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(
                height: _selectedIds.isEmpty
                    ? (isSearching ? 40 : 60)
                    : effectivePanelPosition == NavPosition.top
                        ? selectedTopGap
                        : (isSearching ? 40 : 60),
              ),
            ),
            if (allMusic.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildEmptyState(context, musicService, false),
              )
            else if (isSearching) ...[
              SliverToBoxAdapter(
                child: _buildHomeStyleSelector(context, settings),
              ),
              SliverToBoxAdapter(
                child: _buildTrackRow(
                  context,
                  musicService,
                  settings,
                  'Search matches',
                  filteredMusic,
                  Icons.search_rounded,
                  rowIndex: 0,
                  maxItems: settings.homeRecommendedCount,
                ),
              ),
            ] else ...[
              SliverToBoxAdapter(
                child: _buildHomeStyleSelector(context, settings),
              ),
              SliverToBoxAdapter(
                child: _buildUserPlaylistRow(context, musicService, theme),
              ),
              SliverToBoxAdapter(
                child: _buildTrackRow(
                  context,
                  musicService,
                  settings,
                  'Recommended to listen',
                  musicService.recommendedMusicList,
                  Icons.auto_awesome_rounded,
                  rowIndex: 0,
                  maxItems: settings.homeRecommendedCount,
                ),
              ),
              if (musicService.earlyListenedMusicList.isNotEmpty)
                SliverToBoxAdapter(
                  child: _buildTrackRow(
                    context,
                    musicService,
                    settings,
                    'Early listened',
                    musicService.earlyListenedMusicList,
                    Icons.access_time_rounded,
                    rowIndex: 1,
                    maxItems: settings.homeEarlyListenedCount,
                  ),
                ),
              if (musicService.recentlyAddedMusicList.isNotEmpty)
                SliverToBoxAdapter(
                  child: _buildTrackRow(
                    context,
                    musicService,
                    settings,
                    'Recently added',
                    musicService.recentlyAddedMusicList,
                    Icons.new_releases_rounded,
                    rowIndex: 2,
                    maxItems: settings.homeRecentlyAddedCount,
                  ),
                ),
            ],
            SliverToBoxAdapter(child: SizedBox(height: 100.h)),
            if (selectedBottomGap > 0)
              SliverToBoxAdapter(child: SizedBox(height: selectedBottomGap)),
          ],
        ),
        if (_selectedIds.isNotEmpty)
          _buildPositionedSelectionPanel(
            context: context,
            musicService: musicService,
            filteredMusic: filteredMusic,
            navPosition: effectivePanelPosition,
            top: selectionTop,
            bottom: safeBottom + 12.h,
            panelHeight: selectionPanelHeight,
            panelWidth: selectionPanelWidth,
          ),
      ],
    );
  }

  Widget _buildPositionedSelectionPanel({
    required BuildContext context,
    required MusicService musicService,
    required List<Music> filteredMusic,
    required NavPosition navPosition,
    required double top,
    required double bottom,
    required double panelHeight,
    required double panelWidth,
  }) {
    final isVertical =
        navPosition == NavPosition.left || navPosition == NavPosition.right;
    final panel = _buildSelectionBar(
      context,
      musicService,
      filteredMusic,
      isVertical: isVertical,
    );
    switch (navPosition) {
      case NavPosition.bottom:
        return Positioned(
          left: 12.w,
          right: 12.w,
          bottom: bottom,
          child: SizedBox(height: panelHeight, child: panel),
        );
      case NavPosition.left:
        return Positioned(
          top: top,
          bottom: bottom,
          left: 10.w,
          child: SizedBox(width: panelWidth, child: panel),
        );
      case NavPosition.right:
        return Positioned(
          top: top,
          bottom: bottom,
          right: 10.w,
          child: SizedBox(width: panelWidth, child: panel),
        );
      case NavPosition.top:
        return Positioned(
          top: top,
          left: 12.w,
          right: 12.w,
          child: SizedBox(height: panelHeight, child: panel),
        );
    }
  }

  Widget _buildSelectionBar(
      BuildContext context, MusicService musicService, List<Music> visibleMusic,
      {bool isVertical = false}) {
    final theme = Theme.of(context);
    final selected = _selectedTracks(musicService.musicList);
    final controls = <Widget>[
      IconButton(
        tooltip: 'Clear selection',
        icon: const Icon(Icons.close_rounded),
        onPressed: () => setState(_selectedIds.clear),
      ),
      if (isVertical)
        Padding(
          padding: EdgeInsets.symmetric(vertical: 4.h),
          child: Text(
            '${selected.length}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 15.sp,
            ),
          ),
        )
      else
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
        tooltip: 'Select visible',
        icon: const Icon(Icons.select_all_rounded),
        onPressed: () => _selectVisible(visibleMusic),
      ),
      IconButton(
        tooltip: 'Share selected',
        icon: const Icon(Icons.ios_share_rounded),
        onPressed: selected.isEmpty ? null : () => _shareSelected(selected),
      ),
      IconButton(
        tooltip: 'Listen together',
        icon: const Icon(Icons.groups_rounded),
        onPressed: selected.isEmpty ? null : () => _shareSelected(selected),
      ),
      IconButton(
        tooltip: 'Add selected to queue',
        icon: const Icon(Icons.queue_music_rounded),
        onPressed: selected.isEmpty
            ? null
            : () => _addSelectedToQueue(musicService, selected),
      ),
      IconButton(
        tooltip: 'Add to playlist',
        icon: const Icon(Icons.playlist_add_rounded),
        onPressed: selected.isEmpty
            ? null
            : () => _showAddSelectedToPlaylistDialog(
                  context,
                  musicService,
                  selected,
                ),
      ),
      IconButton(
        tooltip: 'Delete selected files',
        icon: Icon(
          Icons.delete_outline_rounded,
          color: theme.colorScheme.error,
        ),
        onPressed: selected.isEmpty
            ? null
            : () => _confirmDeleteSelected(context, musicService, selected),
      ),
    ];

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withOpacity(
            theme.brightness == Brightness.dark ? 0.96 : 0.98,
          ),
          borderRadius: BorderRadius.circular(8.s),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withOpacity(0.52),
          ),
        ),
        child: isVertical
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: controls,
              )
            : Row(children: controls),
      ),
    );
  }

  void _selectVisible(List<Music> visibleMusic) {
    setState(() {
      if (_selectedIds.length == visibleMusic.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(visibleMusic.map((music) => music.id));
      }
    });
  }

  void _removeMissingSelections(List<Music> library) {
    if (_selectedIds.isEmpty) return;
    final libraryIds = library.map((music) => music.id).toSet();
    final staleIds = _selectedIds.where((id) => !libraryIds.contains(id));
    if (staleIds.isEmpty) return;
    _selectedIds.removeAll(staleIds);
  }

  List<Music> _selectedTracks(List<Music> library) {
    return library.where((music) => _selectedIds.contains(music.id)).toList();
  }

  void _addSelectedToQueue(MusicService musicService, List<Music> selected) {
    musicService.addAllToQueue(selected);
    _showSnack('${selected.length} added to current queue.');
    setState(_selectedIds.clear);
  }

  List<Music> _filteredMusic(List<Music> library, String query) {
    if (identical(_cachedLibrary, library) &&
        _cachedLibraryLength == library.length &&
        _cachedQuery == query) {
      return _cachedFilteredMusic;
    }

    _cachedLibrary = library;
    _cachedLibraryLength = library.length;
    _cachedQuery = query;
    if (query.isEmpty) {
      _cachedFilteredMusic = library;
    } else {
      _cachedFilteredMusic = library
          .where((music) => music.searchText.contains(query))
          .toList(growable: false);
    }
    return _cachedFilteredMusic;
  }

  Widget _buildHomeStyleSelector(BuildContext context, SettingsModel settings) {
    final theme = Theme.of(context);
    final options = [
      (_HomeRowStyle.cards, Icons.grid_view_rounded, 'Cards'),
      (_HomeRowStyle.lines, Icons.view_agenda_rounded, 'Lines'),
      (_HomeRowStyle.mixed, Icons.dashboard_customize_rounded, 'Mixed'),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Home',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 28.sp,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.all(3.s),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withOpacity(
                theme.brightness == Brightness.dark ? 0.48 : 0.7,
              ),
              borderRadius: BorderRadius.circular(16.s),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withOpacity(0.32),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in options)
                  Tooltip(
                    message: option.$3,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(7.s),
                      onTap: () => setState(() => _rowStyle = option.$1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        padding: EdgeInsets.symmetric(
                          horizontal: 10.w,
                          vertical: 8.h,
                        ),
                        decoration: BoxDecoration(
                          color: _rowStyle == option.$1
                              ? theme.colorScheme.primaryContainer
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(7.s),
                        ),
                        child: Icon(
                          option.$2,
                          size: 19.s,
                          color: _rowStyle == option.$1
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackRow(
      BuildContext context,
      MusicService musicService,
      SettingsModel settings,
      String title,
      List<Music> tracks,
      IconData emptyIcon,
      {required int rowIndex,
      required int maxItems}) {
    if (tracks.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final effectiveStyle = _rowStyle == _HomeRowStyle.mixed
        ? (rowIndex.isEven ? _HomeRowStyle.cards : _HomeRowStyle.lines)
        : _rowStyle;
    final isLineStyle = effectiveStyle == _HomeRowStyle.lines;
    final cappedTracks = tracks.take(maxItems.clamp(1, 12)).toList();
    final itemCount = isLineStyle
        ? (cappedTracks.length > 6 ? 6 : cappedTracks.length)
        : cappedTracks.length;
    final listItemExtent = MusicCard.listItemExtent(settings);
    final rowHeight = isLineStyle
        ? (62.h + (listItemExtent * itemCount))
        : (Responsive.isTablet ? 248 : 216).h;
    final itemWidth = (Responsive.isTablet ? 180 : 146).s;

    return SizedBox(
      height: rowHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 10.h),
            child: Row(
              children: [
                Icon(
                  emptyIcon,
                  size: 20.s,
                  color: theme.colorScheme.primary.withOpacity(0.9),
                ),
                SizedBox(width: 8.w),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: isLineStyle
                ? Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6.w),
                    child: Column(
                      children: [
                        for (var index = 0; index < itemCount; index++)
                          SizedBox(
                            height: listItemExtent,
                            child: MusicCard(
                              music: cappedTracks[index],
                              viewMode: ViewMode.list,
                              heroPrefix: 'home-row-$title',
                              listIndex: index,
                              listLength: itemCount,
                              isVideoTrack: MusicCard.computeIsVideoTrack(cappedTracks[index]),
                              onTap: () => musicService.playMusicFromQueue(
                                cappedTracks,
                                cappedTracks[index],
                              ),
                              onOpen: widget.onOpenPlayer,
                            ),
                          ),
                      ],
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    cacheExtent: 500,
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    itemBuilder: (context, index) {
                      final music = cappedTracks[index];
                      return RepaintBoundary(
                        key: ValueKey(music.id),
                        child: SizedBox(
                          width: itemWidth,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: MusicCard(
                              music: music,
                              viewMode: ViewMode.card,
                              heroPrefix: 'home-row-$title',
                              listIndex: index,
                              isVideoTrack: MusicCard.computeIsVideoTrack(music),
                              onTap: () => musicService.playMusicFromQueue(
                                  cappedTracks, music),
                              onOpen: widget.onOpenPlayer,
                            ),
                          ),
                        ),
                      );
                    },
                    separatorBuilder: (_, __) => SizedBox(width: 12.w),
                    itemCount: itemCount,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserPlaylistRow(
    BuildContext context,
    MusicService musicService,
    ThemeData theme,
  ) {
    final playlists = musicService.playlists;
    final rowHeight = (Responsive.isTablet ? 278 : 236).h;
    return SizedBox(
      height: rowHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 10.h),
            child: Row(
              children: [
                Icon(
                  Icons.playlist_play_rounded,
                  size: 21.s,
                  color: theme.colorScheme.primary.withOpacity(0.9),
                ),
                SizedBox(width: 8.w),
                Text(
                  'Playlists',
                  style: TextStyle(
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              children: [
                _buildAddPlaylistSquare(context, musicService),
                ...playlists.map(
                  (playlist) => _buildSquarePlaylistCard(
                    context,
                    musicService,
                    playlist,
                    Icons.playlist_play_rounded,
                    theme.colorScheme.onSurface.withOpacity(0.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareSelected(List<Music> selected) async {
    try {
      final info = await _shareService.startSharing(
        library: selected,
        selectedTracks: selected,
        scope: ShareScope.selectedSongs,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Share selected songs'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${info.trackCount} songs are available on this network.'),
              const SizedBox(height: 12),
              for (final url in info.urls)
                SelectableText(
                  url,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Keep Sharing'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                unawaited(_shareService.stopSharing());
              },
              child: const Text('Stop'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _showSnack('No local files available to share.');
    }
  }

  Future<void> _showAddSelectedToPlaylistDialog(
    BuildContext context,
    MusicService musicService,
    List<Music> selected,
  ) async {
    final playlist = await showDialog<Playlist>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add to playlist'),
        content: SizedBox(
          width: 320,
          child: musicService.playlists.isEmpty
              ? const Text('No playlists available.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final playlist in musicService.playlists)
                      ListTile(
                        leading: const Icon(Icons.playlist_play_rounded),
                        title: Text(playlist.name),
                        subtitle: Text('${playlist.musicIds.length} tracks'),
                        onTap: () => Navigator.pop(dialogContext, playlist),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (playlist == null) return;
    for (final music in selected) {
      musicService.addMusicToPlaylist(playlist.id, music.id);
    }
    if (!mounted) return;
    setState(_selectedIds.clear);
    _showSnack('Added ${selected.length} songs to ${playlist.name}.');
  }

  Future<void> _confirmDeleteSelected(
    BuildContext context,
    MusicService musicService,
    List<Music> selected,
  ) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete selected files?'),
            content: Text(
              'This will permanently delete ${selected.length} song files from this device. This cannot be undone.',
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
                  foregroundColor: Theme.of(dialogContext).colorScheme.onError,
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    var deleted = 0;
    for (final music in selected) {
      final index = musicService.musicList.indexWhere(
        (item) => item.id == music.id && item.filePath == music.filePath,
      );
      if (index == -1) continue;
      if (await musicService.deleteMusic(index, deleteFile: true)) {
        deleted++;
      }
    }
    if (!mounted) return;
    setState(_selectedIds.clear);
    _showSnack('Deleted $deleted of ${selected.length} selected songs.');
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Widget _buildSquarePlaylistCard(
      BuildContext context,
      MusicService musicService,
      Playlist playlist,
      IconData icon,
      Color color) {
    final musicList = musicService.getMusicListForPlaylist(playlist.id);
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => PlaylistDetailPage(
                    playlist: playlist,
                    onOpenPlayer: widget.onOpenPlayer,
                  ))),
      child: Container(
        width: (Responsive.isTablet ? 180 : 142).s,
        margin: EdgeInsets.only(right: (Responsive.isTablet ? 16 : 12).w),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final artworkSize = (constraints.maxHeight - 42.h).clamp(
              Responsive.isTablet ? 110.0 : 96.0,
              (Responsive.isTablet ? 180 : 142).s.toDouble(),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GlassContainer(
                  width: artworkSize,
                  height: artworkSize,
                  color: theme.colorScheme.surfaceContainerHighest
                      .withOpacity(0.3),
                  borderRadius: BorderRadius.circular(22.s),
                  blur: 0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.s),
                    child: _buildPlaylistCollage(musicList, icon, color),
                  ),
                ),
                SizedBox(height: 10.h),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.w),
                  child: Text(
                    playlist.name,
                    style:
                        TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPlaylistCollage(
      List<Music> musicList, IconData icon, Color color) {
    final musicWithCovers =
        musicList.where((music) => music.coverPath.isNotEmpty).toList();

    if (musicWithCovers.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: Center(
            child: Icon(icon, color: color.withOpacity(0.5), size: 60.s)),
      );
    }

    if (musicWithCovers.length < 4) {
      return CoverArtTexture(
        coverArtPath: musicWithCovers[0].coverPath,
        width: double.infinity,
        height: double.infinity,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: CoverArtTexture(
                      coverArtPath: musicWithCovers[0].coverPath,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                  Expanded(
                    child: CoverArtTexture(
                      coverArtPath: musicWithCovers[1].coverPath,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: CoverArtTexture(
                      coverArtPath: musicWithCovers[2].coverPath,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                  Expanded(
                    child: CoverArtTexture(
                      coverArtPath: musicWithCovers[3].coverPath,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.08),
          ),
        ),
      ],
    );
  }

  Widget _buildAddPlaylistSquare(
      BuildContext context, MusicService musicService) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => _showCreatePlaylistDialog(context, musicService),
      child: Container(
        width: (Responsive.isTablet ? 180 : 142).s,
        margin: EdgeInsets.only(right: (Responsive.isTablet ? 16 : 12).w),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final artworkSize = (constraints.maxHeight - 42.h).clamp(
              Responsive.isTablet ? 110.0 : 96.0,
              (Responsive.isTablet ? 180 : 142).s.toDouble(),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GlassContainer(
                  width: artworkSize,
                  height: artworkSize,
                  color: theme.colorScheme.surfaceContainerHighest
                      .withOpacity(0.3),
                  borderRadius: BorderRadius.circular(22.s),
                  blur: 0,
                  child: Center(
                      child: Icon(Icons.add_rounded,
                          color: Colors.teal, size: 60.s)),
                ),
                SizedBox(height: 10.h),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.w),
                  child: Text(
                    'New List',
                    style: TextStyle(
                        color: Colors.teal,
                        fontSize: 14.sp,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showCreatePlaylistDialog(
      BuildContext context, MusicService musicService) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Name...',
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.teal)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
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

  Widget _buildEmptyState(
      BuildContext context, MusicService musicService, bool isSearching) {
    final theme = Theme.of(context);
    if (isSearching) {
      return Center(
        child: Padding(
          padding: EdgeInsets.only(top: 50.h),
          child: Column(
            children: [
              Icon(Icons.search_off_rounded,
                  color: theme.colorScheme.onSurface.withOpacity(0.2),
                  size: 64.s),
              SizedBox(height: 16.h),
              Text('No songs found',
                  style: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.2),
                      fontSize: 16.sp)),
            ],
          ),
        ),
      );
    }
    return Center(
      child: ElevatedButton(
          onPressed: musicService.loadSystemMusic,
          child: const Text('Scan Music')),
    );
  }
}
