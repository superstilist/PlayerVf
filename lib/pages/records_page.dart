import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/music_model.dart';
import '../models/settings_model.dart';
import '../services/music_service.dart';
import '../services/responsive.dart';
import '../widgets/music_card.dart';

enum _RecordFilter { all, music, videos, genres }

class RecordsPage extends StatefulWidget {
  final String searchQuery;
  final VoidCallback? onOpenPlayer;

  const RecordsPage({
    super.key,
    this.searchQuery = '',
    this.onOpenPlayer,
  });

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  _RecordFilter _filter = _RecordFilter.all;
  String? _selectedGenre;
  final Set<String> _selectedIds = <String>{};

  @override
  void didUpdateWidget(covariant RecordsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery &&
        _selectedIds.isNotEmpty) {
      setState(_selectedIds.clear);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<MusicService, SettingsModel>(
      builder: (context, musicService, settings, child) {
        final library = musicService.musicList;
        final normalizedQuery = widget.searchQuery.trim().toLowerCase();
        final genres = _genresFor(library);
        final visible = _visibleRecords(
          musicService,
          library,
          normalizedQuery,
        );
        final indexById = <String, int>{
          for (var i = 0; i < library.length; i++) library[i].id: i,
        };

        _removeMissingSelections(library);

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: _selectedIds.isEmpty ? 0 : 72.h,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(24.w, 48.h, 24.w, 10.h),
                      child:
                          _buildHeader(context, musicService, library, visible),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _buildFilterBar(context),
                  ),
                  if (_filter == _RecordFilter.genres)
                    SliverToBoxAdapter(
                      child: _buildGenreBar(context, genres),
                    ),
                  if (visible.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmptyState(context, musicService),
                    )
                  else
                    _buildRecordList(
                      context,
                      musicService,
                      settings,
                      visible,
                      indexById,
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
                    visible,
                    indexById,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(
    BuildContext context,
    MusicService musicService,
    List<Music> library,
    List<Music> visible,
  ) {
    final theme = Theme.of(context);
    final musicCount =
        library.where((music) => !musicService.isVideoMedia(music)).length;
    final videoCount = library.length - musicCount;
    final canFavoriteGenre = _filter == _RecordFilter.genres &&
        _selectedGenre != null &&
        visible.isNotEmpty;
    final allVisibleFavorite =
        canFavoriteGenre && visible.every((music) => music.isFavorite);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Records',
                style: TextStyle(
                  fontSize: 32.sp,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              SizedBox(height: 6.h),
              Text(
                '${library.length} files  |  $musicCount music  |  $videoCount videos',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.sp,
                  color: theme.colorScheme.onSurface.withOpacity(0.58),
                ),
              ),
            ],
          ),
        ),
        if (canFavoriteGenre)
          IconButton.filledTonal(
            tooltip: allVisibleFavorite
                ? 'Unfavorite this genre'
                : 'Favorite this genre',
            onPressed: () => _setGenreFavorite(
              context,
              musicService,
              visible,
              !allVisibleFavorite,
            ),
            icon: Icon(
              allVisibleFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
            ),
          ),
      ],
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
      child: Row(
        children: [
          _filterChip('All', Icons.library_music_rounded, _RecordFilter.all),
          _filterChip('Music', Icons.music_note_rounded, _RecordFilter.music),
          _filterChip('Videos', Icons.videocam_rounded, _RecordFilter.videos),
          _filterChip('Genres', Icons.category_rounded, _RecordFilter.genres),
        ],
      ),
    );
  }

  Widget _filterChip(String label, IconData icon, _RecordFilter filter) {
    final selected = _filter == filter;
    return Padding(
      padding: EdgeInsets.only(right: 8.w),
      child: ChoiceChip(
        selected: selected,
        avatar: Icon(icon, size: 18.s),
        label: Text(label),
        onSelected: (_) => setState(() {
          _filter = filter;
          if (filter != _RecordFilter.genres) _selectedGenre = null;
        }),
      ),
    );
  }

  Widget _buildGenreBar(BuildContext context, List<String> genres) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 12.h),
      child: Row(
        children: [
          _genreChip(null, 'All genres'),
          for (final genre in genres) _genreChip(genre, genre),
        ],
      ),
    );
  }

  Widget _genreChip(String? value, String label) {
    final selected = _selectedGenre == value;
    return Padding(
      padding: EdgeInsets.only(right: 8.w),
      child: ChoiceChip(
        selected: selected,
        label: Text(label),
        onSelected: (_) => setState(() => _selectedGenre = value),
      ),
    );
  }

  Widget _buildRecordList(
    BuildContext context,
    MusicService musicService,
    SettingsModel settings,
    List<Music> visible,
    Map<String, int> indexById,
  ) {
    final listItemExtent = MusicCard.listItemExtent(settings);
    if (settings.viewMode == ViewMode.list) {
      return SliverFixedExtentList(
        itemExtent: listItemExtent,
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildRecordCard(
            musicService,
            settings,
            visible,
            index,
            indexById,
          ),
          childCount: visible.length,
        ),
      );
    }

    final crossAxisCount = _cardColumnCount(settings);
    return SliverPadding(
      padding: EdgeInsets.symmetric(
        horizontal: settings.cardMargins.w,
        vertical: settings.cardMargins.h,
      ),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: settings.cardMargins.w,
          mainAxisSpacing: settings.cardMargins.h,
          childAspectRatio: 1,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildRecordCard(
            musicService,
            settings,
            visible,
            index,
            indexById,
          ),
          childCount: visible.length,
        ),
      ),
    );
  }

  Widget _buildRecordCard(
    MusicService musicService,
    SettingsModel settings,
    List<Music> visible,
    int index,
    Map<String, int> indexById,
  ) {
    final music = visible[index];
    final actualIndex = indexById[music.id] ?? -1;
    return MusicCard(
      music: music,
      viewMode: settings.viewMode,
      heroPrefix: 'records-${settings.viewMode}',
      listIndex: index,
      listLength: settings.viewMode == ViewMode.list ? visible.length : null,
      isVideoTrack: MusicCard.computeIsVideoTrack(music),
      onTap: () => musicService.playMusicFromQueue(visible, music),
      onOpen: widget.onOpenPlayer,
      selectionMode: _selectedIds.isNotEmpty,
      isSelected: _selectedIds.contains(music.id),
      onSelectionStart: () => _startSelection(music.id),
      onSelectionToggle: () => _toggleSelection(music.id),
      deleteRemovesFile: actualIndex != -1,
      onDelete: actualIndex == -1
          ? null
          : () => musicService.deleteMusic(actualIndex, deleteFile: true),
    );
  }

  Widget _buildEmptyState(BuildContext context, MusicService musicService) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.s),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_rounded,
              size: 70.s,
              color: theme.colorScheme.onSurface.withOpacity(0.18),
            ),
            SizedBox(height: 18.h),
            Text(
              'No records found',
              style: TextStyle(
                fontSize: 16.sp,
                color: theme.colorScheme.onSurface.withOpacity(0.48),
              ),
            ),
            SizedBox(height: 18.h),
            FilledButton.icon(
              onPressed: musicService.loadSystemMusic,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Scan Music'),
            ),
          ],
        ),
      ),
    );
  }

  List<Music> _visibleRecords(
    MusicService musicService,
    List<Music> library,
    String query,
  ) {
    Iterable<Music> records = library;
    switch (_filter) {
      case _RecordFilter.music:
        records = records.where((music) => !musicService.isVideoMedia(music));
        break;
      case _RecordFilter.videos:
        records = records.where(musicService.isVideoMedia);
        break;
      case _RecordFilter.genres:
        if (_selectedGenre != null) {
          records =
              records.where((music) => _genreName(music) == _selectedGenre);
        }
        break;
      case _RecordFilter.all:
        break;
    }
    if (query.isNotEmpty) {
      records = records.where((music) => music.searchText.contains(query));
    }
    return records.toList(growable: false);
  }

  Widget _buildSelectionBar(
    BuildContext context,
    MusicService musicService,
    List<Music> visible,
    Map<String, int> indexById,
  ) {
    final theme = Theme.of(context);
    final selected = visible
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
              color: Colors.black.withOpacity(0.14),
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
              tooltip: 'Select visible',
              icon: const Icon(Icons.select_all_rounded),
              onPressed: () => _selectVisible(visible),
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
              tooltip: 'Favorite selected',
              icon: const Icon(Icons.favorite_rounded),
              onPressed: selected.isEmpty
                  ? null
                  : () => _setSelectedFavorite(musicService, selected, true),
            ),
            IconButton(
              tooltip: 'Unfavorite selected',
              icon: const Icon(Icons.favorite_border_rounded),
              onPressed: selected.isEmpty
                  ? null
                  : () => _setSelectedFavorite(musicService, selected, false),
            ),
            IconButton(
              tooltip: 'Delete selected files',
              icon: Icon(
                Icons.delete_outline_rounded,
                color: theme.colorScheme.error,
              ),
              onPressed: selected.isEmpty
                  ? null
                  : () => _confirmDeleteSelected(
                        context,
                        musicService,
                        selected,
                      ),
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

  void _removeMissingSelections(List<Music> library) {
    if (_selectedIds.isEmpty) return;
    final ids = library.map((music) => music.id).toSet();
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

  Future<void> _setSelectedFavorite(
    MusicService musicService,
    List<Music> selected,
    bool favorite,
  ) async {
    await musicService.setFavoriteForMusicIds(
      selected.map((music) => music.id),
      favorite,
    );
    if (!mounted || !context.mounted) return;
    setState(_selectedIds.clear);
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
              'This will permanently delete ${selected.length} files from this device.',
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
      if (index != -1 &&
          await musicService.deleteMusic(index, deleteFile: true)) {
        deleted++;
      }
    }
    if (!mounted || !context.mounted) return;
    setState(_selectedIds.clear);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Deleted $deleted of ${selected.length} records.'),
        ),
      );
  }

  List<String> _genresFor(List<Music> library) {
    final genres = library.map(_genreName).toSet().toList();
    genres.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return genres;
  }

  String _genreName(Music music) {
    final genre = music.genre.trim();
    return genre.isEmpty ? 'Unknown' : genre;
  }

  int _cardColumnCount(SettingsModel settings) {
    if (settings.useAutoCardCount) {
      final availableWidth =
          Responsive.screenWidth - (settings.cardMargins * 2);
      final count =
          (availableWidth / (settings.cardSize + settings.cardMargins)).floor();
      return count < 1 ? 1 : count;
    }
    return settings.cardCount < 1 ? 1 : settings.cardCount;
  }

  Future<void> _setGenreFavorite(
    BuildContext context,
    MusicService musicService,
    List<Music> visible,
    bool favorite,
  ) async {
    await musicService.setFavoriteForMusicIds(
      visible.map((music) => music.id),
      favorite,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            favorite
                ? 'Added ${visible.length} genre records to favorites.'
                : 'Removed ${visible.length} genre records from favorites.',
          ),
        ),
      );
  }
}
