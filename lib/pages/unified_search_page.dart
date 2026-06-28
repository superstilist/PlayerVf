import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/music_model.dart';
import '../services/music_service.dart';
import '../services/responsive.dart';
import '../services/youtube_music_service.dart';
import '../widgets/cover_art_texture.dart';
import '../widgets/glass_container.dart';

enum _YtFilter { songs, artists, albums }

class UnifiedSearchPage extends StatefulWidget {
  const UnifiedSearchPage({super.key});

  @override
  State<UnifiedSearchPage> createState() => _UnifiedSearchPageState();
}

class _UnifiedSearchPageState extends State<UnifiedSearchPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late TabController _tabController;
  Timer? _debounce;

  List<Music> _localResults = [];
  List<YoutubeMusicResult> _ytResults = [];
  bool _isSearchingYt = false;
  bool _hasSearched = false;
  _YtFilter _ytFilter = _YtFilter.songs;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) {
      setState(() {
        _localResults = [];
        _ytResults = [];
        _hasSearched = false;
        _lastQuery = '';
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _lastQuery = trimmed;
      _searchLocal(trimmed);
      _searchYt(trimmed, _ytFilter);
    });
  }

  void _searchLocal(String query) {
    final musicService = context.read<MusicService>();
    final library = musicService.musicList;
    setState(() {
      _localResults = library
          .where((m) => m.searchText.contains(query))
          .toList();
      _hasSearched = true;
    });
  }

  Future<void> _searchYt(String query, _YtFilter filter) async {
    if (!YoutubeMusicService.isSupported) return;
    setState(() => _isSearchingYt = true);
    try {
      final service = YoutubeMusicService();
      final filterStr = switch (filter) {
        _YtFilter.songs => 'songs',
        _YtFilter.artists => 'artists',
        _YtFilter.albums => 'albums',
      };
      final results =
          await service.search(query: query, filter: filterStr, limit: 20);
      if (mounted) {
        setState(() {
          _ytResults = results;
          _isSearchingYt = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isSearchingYt = false);
    }
  }

  void _onFilterChanged(_YtFilter filter) {
    setState(() => _ytFilter = filter);
    if (_lastQuery.isNotEmpty) {
      _searchYt(_lastQuery, filter);
    }
  }

  void _playLocal(Music music) {
    final musicService = context.read<MusicService>();
    musicService.playMusicFromQueue(musicService.musicList, music);
    Navigator.of(context).pop();
  }

  Future<void> _playYt(YoutubeMusicResult result) async {
    if (!YoutubeMusicService.isSupported || result.videoId == null) return;
    final service = YoutubeMusicService();
    try {
      final stream = await service.streamVideoId(result.videoId!);
      if (stream == null || !mounted) return;
      final music = Music(
        id: 'ytm:${stream.videoId}',
        title: stream.displayTitle,
        artist: stream.displayArtist,
        album: stream.album.isEmpty ? 'YouTube Music' : stream.album,
        filePath: stream.url,
        coverPath: stream.thumbnailUrl,
        httpHeaders: stream.httpHeaders,
        genre: 'YouTube Music',
      );
      final musicService = context.read<MusicService>();
      await musicService.playStreamingMusic(music);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.surface,
              theme.colorScheme.surface.withOpacity(0.95),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(theme),
              _buildSearchBar(theme),
              if (_hasSearched) _buildTabBar(theme),
              Expanded(
                child: _hasSearched
                    ? TabBarView(
                        controller: _tabController,
                        children: [
                          _buildLocalResults(theme),
                          _buildYtResultsTab(theme),
                        ],
                      )
                    : _buildEmptyState(theme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.0.w, vertical: 8.0.h),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
          SizedBox(width: 8.0.w),
          Text(
            'Search',
            style: TextStyle(
              fontSize: 20.0.sp,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.0.w, vertical: 4.0.h),
      child: GlassContainer(
        borderRadius: BorderRadius.circular(12.0.s),
        blur: 8,
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          onChanged: _onQueryChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search local library & YouTube Music...',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded),
                    onPressed: () {
                      _controller.clear();
                      _onQueryChanged('');
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding:
                EdgeInsets.symmetric(horizontal: 16.0.w, vertical: 14.0.h),
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar(ThemeData theme) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.0.w, vertical: 4.0.h),
      child: TabBar(
        controller: _tabController,
        labelColor: theme.colorScheme.primary,
        unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(0.6),
        indicatorColor: theme.colorScheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        tabs: [
          Tab(text: 'Library (${_localResults.length})'),
          Tab(text: 'YouTube Music (${_ytResults.length})'),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_rounded,
              size: 64, color: theme.colorScheme.onSurface.withOpacity(0.2)),
          SizedBox(height: 16.0.h),
          Text(
            'Search your library and YouTube Music',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withOpacity(0.5),
              fontSize: 15.0.sp,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalResults(ThemeData theme) {
    if (_localResults.isEmpty) {
      return Center(
        child: Text(
          'No local results found',
          style: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.5),
            fontSize: 14.0.sp,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.symmetric(vertical: 8.0.h),
      itemCount: _localResults.length,
      itemBuilder: (context, index) {
        final music = _localResults[index];
        return _buildLocalResultTile(theme, music);
      },
    );
  }

  Widget _buildLocalResultTile(ThemeData theme, Music music) {
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8.0.s),
        child: SizedBox(
          width: 48.0.s,
          height: 48.0.s,
          child: music.coverPath.isNotEmpty
              ? CoverArtTexture(
                  coverArtPath: music.coverPath,
                  width: 48.0.s,
                  height: 48.0.s,
                )
              : Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(Icons.music_note_rounded,
                      color: theme.colorScheme.onSurface.withOpacity(0.4)),
                ),
        ),
      ),
      title: Text(
        music.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.0.sp),
      ),
      subtitle: Text(
        '${music.artist}${music.album.isNotEmpty ? ' · ${music.album}' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontSize: 12.0.sp,
            color: theme.colorScheme.onSurface.withOpacity(0.6)),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.play_circle_outline_rounded),
        onPressed: () => _playLocal(music),
      ),
      onTap: () => _playLocal(music),
    );
  }

  Widget _buildYtResultsTab(ThemeData theme) {
    return Column(
      children: [
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: 16.0.w, vertical: 4.0.h),
            children: [
              _YtFilterChip(
                icon: Icons.music_note_rounded,
                label: 'Songs',
                isSelected: _ytFilter == _YtFilter.songs,
                onTap: () => _onFilterChanged(_YtFilter.songs),
              ),
              const SizedBox(width: 8),
              _YtFilterChip(
                icon: Icons.person_rounded,
                label: 'Artists',
                isSelected: _ytFilter == _YtFilter.artists,
                onTap: () => _onFilterChanged(_YtFilter.artists),
              ),
              const SizedBox(width: 8),
              _YtFilterChip(
                icon: Icons.album_rounded,
                label: 'Albums',
                isSelected: _ytFilter == _YtFilter.albums,
                onTap: () => _onFilterChanged(_YtFilter.albums),
              ),
            ],
          ),
        ),
        Expanded(child: _buildYtResults(theme)),
      ],
    );
  }

  Widget _buildYtResults(ThemeData theme) {
    if (_isSearchingYt) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            SizedBox(height: 12.0.h),
            Text(
              'Searching YouTube Music...',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.5),
                fontSize: 14.0.sp,
              ),
            ),
          ],
        ),
      );
    }
    if (_ytResults.isEmpty) {
      return Center(
        child: Text(
          'No YouTube Music results found',
          style: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.5),
            fontSize: 14.0.sp,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.symmetric(vertical: 8.0.h),
      itemCount: _ytResults.length,
      itemBuilder: (context, index) {
        final result = _ytResults[index];
        return _buildYtResultTile(theme, result);
      },
    );
  }

  Widget _buildYtResultTile(ThemeData theme, YoutubeMusicResult result) {
    final thumbnailUrl = result.thumbnailUrl ?? '';
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8.0.s),
        child: SizedBox(
          width: 48.0.s,
          height: 48.0.s,
          child: thumbnailUrl.isNotEmpty
              ? CoverArtTexture(
                  coverArtPath: thumbnailUrl,
                  width: 48.0.s,
                  height: 48.0.s,
                )
              : Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(Icons.play_circle_outline_rounded,
                      color: theme.colorScheme.onSurface.withOpacity(0.4)),
                ),
        ),
      ),
      title: Text(
        result.displayTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.0.sp),
      ),
      subtitle: Text(
        '${result.displayArtist}${result.duration != null ? ' · ${result.duration}' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontSize: 12.0.sp,
            color: theme.colorScheme.onSurface.withOpacity(0.6)),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.play_circle_outline_rounded),
        onPressed: () => _playYt(result),
      ),
      onTap: () => _playYt(result),
    );
  }
}

class _YtFilterChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _YtFilterChip({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withOpacity(0.18)
              : theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary.withOpacity(0.5)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withOpacity(0.6),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
