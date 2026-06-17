import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/music_model.dart';
import '../models/settings_model.dart';
import '../services/music_service.dart';
import '../services/performance_policy.dart';
import '../services/responsive.dart';
import '../widgets/music_card.dart';

class FavoritePage extends StatefulWidget {
  final String searchQuery;
  final VoidCallback? onOpenPlayer;

  const FavoritePage({
    super.key,
    this.searchQuery = '',
    this.onOpenPlayer,
  });

  @override
  State<FavoritePage> createState() => _FavoritePageState();
}

class _FavoritePageState extends State<FavoritePage> {
  final Set<String> _selectedIds = <String>{};
  List<Music>? _cachedFavorites;
  int _cachedFavoritesLength = -1;
  String _cachedQuery = '';
  List<Music> _cachedFiltered = const [];

  @override
  void didUpdateWidget(covariant FavoritePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery &&
        _selectedIds.isNotEmpty) {
      setState(_selectedIds.clear);
    }
  }

  @override
  Widget build(BuildContext context) {
    final musicService = Provider.of<MusicService>(context, listen: false);
    final isLoading = context.select<MusicService, bool>((s) => s.isLoadingSystemMusic);
    final musicCount = context.select<MusicService, int>((s) => s.systemMusicCount);
    final musicList = context.select<MusicService, List<Music>>((s) => s.musicList);
    final settings = Provider.of<SettingsModel>(context);

    final performance = PerformancePolicy.of(context);
    final crossAxisCount =
        _calculateAdaptiveCrossAxisCount(Responsive.screenWidth);
    final padding = settings.viewMode == ViewMode.list ? 0.0 : 16.w;
    final listItemExtent = MusicCard.listItemExtent(settings);

    if (isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.teal),
            SizedBox(height: 16.h),
            Text(
              'Scanning music... $musicCount files',
              style: TextStyle(color: Colors.grey[600], fontSize: 14.sp),
            ),
          ],
        ),
      );
    }

    final normalizedQuery = widget.searchQuery.trim().toLowerCase();
    final favoriteMusicList =
        _filteredFavorites(musicList, normalizedQuery);
        final isSearching = normalizedQuery.isNotEmpty;
        _removeMissingSelections(favoriteMusicList);

        if (favoriteMusicList.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isSearching
                      ? Icons.search_off_rounded
                      : Icons.favorite_border,
                  size: 80.s,
                  color: Colors.grey[600],
                ),
                SizedBox(height: 16.h),
                Text(
                  isSearching ? 'No favorite songs found' : 'No favorite songs',
                  style: TextStyle(color: Colors.grey[600], fontSize: 18.sp),
                ),
                SizedBox(height: 8.h),
                if (!isSearching)
                  Text(
                    'Tap the heart icon on songs to add them to favorites',
                    style: TextStyle(color: Colors.grey[700], fontSize: 14.sp),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          );
        }

        if (settings.viewMode == ViewMode.list) {
          return Stack(
            children: [
              ListView.builder(
                cacheExtent: performance.listCacheExtent,
                itemExtent: listItemExtent,
                padding: EdgeInsets.fromLTRB(
                  0,
                  _selectedIds.isEmpty ? 60 : 124,
                  0,
                  100,
                ),
                itemCount: favoriteMusicList.length,
                itemBuilder: (context, index) {
                  final music = favoriteMusicList[index];
                  return _buildFavoriteCard(
                    musicService,
                    settings,
                    favoriteMusicList,
                    music,
                    index,
                    listLength: favoriteMusicList.length,
                  );
                },
              ),
              if (_selectedIds.isNotEmpty)
                _buildSelectionBar(context, musicService, favoriteMusicList),
            ],
          );
        }

        return Stack(
          children: [
            GridView.builder(
              cacheExtent: performance.listCacheExtent,
              padding: EdgeInsets.fromLTRB(
                padding,
                _selectedIds.isEmpty ? 60 : 124,
                padding,
                padding,
              ),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 16.w,
                mainAxisSpacing: 16.h,
                childAspectRatio: 1.0,
              ),
              itemCount: favoriteMusicList.length,
              itemBuilder: (context, index) {
                final music = favoriteMusicList[index];
                return _buildFavoriteCard(
                  musicService,
                  settings,
                  favoriteMusicList,
                  music,
                  index,
                );
              },
            ),
            if (_selectedIds.isNotEmpty)
              _buildSelectionBar(context, musicService, favoriteMusicList),
          ],
        );
  }

  Widget _buildFavoriteCard(
    MusicService musicService,
    SettingsModel settings,
    List<Music> favoriteMusicList,
    Music music,
    int index, {
    int? listLength,
  }) {
    return MusicCard(
      music: music,
      viewMode: settings.viewMode,
      heroPrefix: 'fav',
      listIndex: index,
      listLength: listLength,
      isVideoTrack: MusicCard.computeIsVideoTrack(music),
      selectionMode: _selectedIds.isNotEmpty,
      isSelected: _selectedIds.contains(music.id),
      onSelectionStart: () => _startSelection(music.id),
      onSelectionToggle: () => _toggleSelection(music.id),
      onTap: () => musicService.playMusicFromQueue(
        favoriteMusicList,
        music,
        playlistId: 'favorites',
      ),
      onOpen: widget.onOpenPlayer,
    );
  }

  Widget _buildSelectionBar(
    BuildContext context,
    MusicService musicService,
    List<Music> visible,
  ) {
    final theme = Theme.of(context);
    final selected = visible
        .where((music) => _selectedIds.contains(music.id))
        .toList(growable: false);
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 8.h,
      left: 12.w,
      right: 12.w,
      child: Material(
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
                tooltip: 'Remove from favorites',
                icon: const Icon(Icons.favorite_border_rounded),
                onPressed: selected.isEmpty
                    ? null
                    : () => _removeSelectedFavorites(musicService, selected),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _calculateAdaptiveCrossAxisCount(double screenWidth) {
    if (screenWidth < 330) return 2;
    if (screenWidth < 520) return 3;
    if (screenWidth < 900) return 3;
    if (screenWidth < 1200) return 4;
    return 6;
  }

  List<Music> _filteredFavorites(List<Music> library, String query) {
    if (identical(_cachedFavorites, library) &&
        _cachedFavoritesLength == library.length &&
        _cachedQuery == query) {
      return _cachedFiltered;
    }
    _cachedFavorites = library;
    _cachedFavoritesLength = library.length;
    _cachedQuery = query;
    _cachedFiltered = library.where((music) {
      if (!music.isFavorite) return false;
      return query.isEmpty || music.searchText.contains(query);
    }).toList(growable: false);
    return _cachedFiltered;
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

  Future<void> _removeSelectedFavorites(
    MusicService musicService,
    List<Music> selected,
  ) async {
    await musicService.setFavoriteForMusicIds(
      selected.map((music) => music.id),
      false,
    );
    if (!mounted) return;
    setState(_selectedIds.clear);
  }
}
