import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/music_model.dart';
import '../models/settings_model.dart';
import '../services/music_service.dart';
import '../services/responsive.dart';
import '../services/youtube_music_service.dart';
import '../widgets/glass_container.dart';

class YoutubeMusicPage extends StatefulWidget {
  final VoidCallback? onOpenPlayer;

  const YoutubeMusicPage({super.key, this.onOpenPlayer});

  @override
  State<YoutubeMusicPage> createState() => _YoutubeMusicPageState();
}

class _YoutubeMusicPageState extends State<YoutubeMusicPage> {
  final YoutubeMusicService _service = YoutubeMusicService();
  final TextEditingController _controller = TextEditingController();

  final List<String> _filters = const [
    'songs',
    'videos',
    'albums',
    'playlists'
  ];
  String _selectedFilter = 'songs';
  List<YoutubeMusicResult> _results = [];
  String? _message;
  bool _isSearching = false;
  final Set<String> _downloadingIds = {};
  final Set<String> _streamingIds = {};
  final Map<String, double?> _downloadProgress = {};
  final Map<String, String> _downloadMessages = {};

  @override
  void initState() {
    super.initState();
    _runBridgeSmokeTest();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _runBridgeSmokeTest() async {
    if (!YoutubeMusicService.isSupported) {
      setState(() =>
          _message = 'YouTube Music is not available on this platform yet.');
      return;
    }

    try {
      final sum = await _service.add(5, 10);
      if (sum != 15 && mounted) {
        setState(
            () => _message = 'Python bridge test returned $sum instead of 15.');
      }
    } on MissingPluginException {
      if (mounted) {
        setState(() =>
            _message = 'Python channel is not available on this platform.');
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'Python bridge is not ready: $e');
    }
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty || _isSearching) {
      setState(
          () => _message = 'Type a song, artist, album, or playlist name.');
      return;
    }

    setState(() {
      _isSearching = true;
      _message = null;
    });

    try {
      final results = await _service.search(
          query: query, filter: _selectedFilter, limit: 20);
      if (!mounted) return;
      setState(() {
        _results = results;
        _message = results.isEmpty ? 'No YouTube Music results found.' : null;
      });
    } on UnsupportedError catch (e) {
      if (mounted) setState(() => _message = e.message);
    } on MissingPluginException {
      if (mounted) {
        setState(() =>
            _message = 'Python channel is not available on this platform.');
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'Search failed: $e');
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _download(YoutubeMusicResult item) async {
    final key = _resultKey(item);
    if (_downloadingIds.contains(key)) return;

    setState(() {
      _downloadingIds.add(key);
      _downloadProgress[key] = null;
      _downloadMessages[key] = 'Starting download...';
      _message = 'Downloading ${item.title}...';
    });

    try {
      final download = await _service.download(
        item,
        onProgress: (progress, message) {
          if (!mounted) return;
          setState(() {
            _downloadProgress[key] = progress;
            _downloadMessages[key] = message;
            _message = message;
          });
        },
      );
      if (!mounted) return;

      final paths =
          download.downloadDir.isEmpty ? null : [download.downloadDir];
      await context
          .read<MusicService>()
          .loadSystemMusic(customPaths: paths, clearExisting: false);

      if (!mounted) return;
      setState(() {
        _message = download.files.isEmpty
            ? (download.message.isEmpty
                ? 'Download finished.'
                : download.message)
            : 'Downloaded ${download.files.length} file${download.files.length == 1 ? '' : 's'}.';
      });
    } on UnsupportedError catch (e) {
      if (mounted) setState(() => _message = e.message);
    } on MissingPluginException {
      if (mounted) {
        setState(() =>
            _message = 'Python channel is not available on this platform.');
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'Download failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _downloadingIds.remove(key);
          _downloadProgress.remove(key);
          _downloadMessages.remove(key);
        });
      }
    }
  }

  Future<void> _stream(YoutubeMusicResult item) async {
    final key = _resultKey(item);
    if (_streamingIds.contains(key)) return;

    setState(() {
      _streamingIds.add(key);
      _message = 'Opening ${item.title}...';
    });

    try {
      final stream = await _service.stream(item);
      if (!mounted) return;
      if (stream.url.isEmpty) {
        setState(() => _message = 'Could not open this YouTube Music stream.');
        return;
      }

      final music = Music(
        id: 'ytm:${stream.videoId.isNotEmpty ? stream.videoId : key}',
        title: stream.title,
        artist: stream.artist,
        album: stream.album.isEmpty ? 'YouTube Music' : stream.album,
        filePath: stream.url,
        coverPath: stream.thumbnailUrl,
        genre: stream.isVideo ? 'YouTube Music Video' : 'YouTube Music',
        duration: stream.durationSeconds > 0
            ? Duration(seconds: stream.durationSeconds)
            : null,
      );

      await context.read<MusicService>().playStreamingMusic(music);
      if (!mounted) return;
      setState(() => _message = 'Playing ${stream.title}');
      widget.onOpenPlayer?.call();
    } on UnsupportedError catch (e) {
      if (mounted) setState(() => _message = e.message);
    } on MissingPluginException {
      if (mounted) {
        setState(() =>
            _message = 'Python channel is not available on this platform.');
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'Stream failed: $e');
    } finally {
      if (mounted) setState(() => _streamingIds.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsModel>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: 44.h)),
          SliverToBoxAdapter(child: _buildHeader(theme)),
          SliverToBoxAdapter(child: SizedBox(height: 18.h)),
          SliverToBoxAdapter(child: _buildSearchPanel(theme, settings)),
          SliverToBoxAdapter(child: SizedBox(height: 12.h)),
          if (_message != null) SliverToBoxAdapter(child: _buildMessage(theme)),
          if (_isSearching)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 80.h),
                child: const Center(
                    child: CircularProgressIndicator(color: Colors.teal)),
              ),
            )
          else if (_results.isEmpty)
            SliverToBoxAdapter(child: _buildEmptyState(theme))
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 120.h),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) =>
                      _buildResultTile(_results[index], theme, settings),
                  childCount: _results.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YouTube Music',
            style: TextStyle(
                fontSize: 30.sp,
                fontWeight: FontWeight.w900,
                color: theme.colorScheme.onSurface),
          ),
          SizedBox(height: 6.h),
          Text(
            'Search, stream, and download music into your PlayerVf library.',
            style: TextStyle(
                fontSize: 13.sp,
                color: theme.colorScheme.onSurface.withOpacity(0.55)),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchPanel(ThemeData theme, SettingsModel settings) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: GlassContainer(
        padding: EdgeInsets.all(14.s),
        borderRadius: BorderRadius.circular(22.s),
        color: theme.colorScheme.onSurface.withOpacity(0.05),
        blur: 12,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: const InputDecoration(
                      hintText: 'Search music...',
                      prefixIcon: Icon(Icons.search_rounded),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                SizedBox(width: 8.w),
                IconButton.filled(
                  onPressed: _isSearching ? null : _search,
                  icon: const Icon(Icons.travel_explore_rounded),
                  tooltip: 'Search',
                  style: IconButton.styleFrom(
                      backgroundColor: settings.accentColor,
                      foregroundColor: Colors.white),
                ),
              ],
            ),
            SizedBox(height: 10.h),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8.w,
                runSpacing: 8.h,
                children: _filters.map((filter) {
                  final selected = filter == _selectedFilter;
                  return ChoiceChip(
                    label: Text(filter),
                    selected: selected,
                    selectedColor: settings.accentColor.withOpacity(0.18),
                    labelStyle: TextStyle(
                      color: selected
                          ? settings.accentColor
                          : theme.colorScheme.onSurface.withOpacity(0.65),
                      fontWeight: FontWeight.w700,
                    ),
                    onSelected: (_) {
                      setState(() => _selectedFilter = filter);
                      if (_controller.text.trim().isNotEmpty) _search();
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessage(ThemeData theme) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 8.h),
      child: Text(
        _message!,
        style: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.65),
            fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Padding(
      padding: EdgeInsets.only(top: 80.h),
      child: Center(
        child: Icon(Icons.library_music_rounded,
            size: 72.s, color: theme.colorScheme.onSurface.withOpacity(0.16)),
      ),
    );
  }

  Widget _buildResultTile(
      YoutubeMusicResult item, ThemeData theme, SettingsModel settings) {
    final key = _resultKey(item);
    final isDownloading = _downloadingIds.contains(key);
    final isStreaming = _streamingIds.contains(key);
    final progress = _downloadProgress[key];
    final progressMessage = _downloadMessages[key];
    final subtitle = [
      if (item.artist.isNotEmpty) item.artist,
      if (item.duration.isNotEmpty) item.duration,
      item.resultType,
    ].join('  -  ');

    return GestureDetector(
      onDoubleTap: isStreaming ? null : () => _stream(item),
      child: GlassContainer(
        margin: EdgeInsets.only(bottom: 10.h),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        borderRadius: BorderRadius.circular(18.s),
        color: theme.colorScheme.onSurface.withOpacity(0.04),
        blur: 10,
        child: Column(
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12.s),
                  child: SizedBox(
                    width: 58.s,
                    height: 58.s,
                    child: item.thumbnailUrl.isEmpty
                        ? Container(
                            color: settings.accentColor.withOpacity(0.12),
                            child: Icon(Icons.music_note_rounded,
                                color: settings.accentColor),
                          )
                        : Image.network(
                            item.thumbnailUrl,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.high,
                            isAntiAlias: true,
                            errorBuilder: (_, __, ___) => Container(
                              color: settings.accentColor.withOpacity(0.12),
                              child: Icon(Icons.music_note_rounded,
                                  color: settings.accentColor),
                            ),
                          ),
                  ),
                ),
                SizedBox(width: 14.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14.sp),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.sp,
                            color:
                                theme.colorScheme.onSurface.withOpacity(0.52)),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8.w),
                IconButton(
                  tooltip: 'Play stream',
                  onPressed: isStreaming ? null : () => _stream(item),
                  icon: isStreaming
                      ? SizedBox(
                          width: 22.s,
                          height: 22.s,
                          child:
                              const CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.play_arrow_rounded),
                  color: settings.accentColor,
                ),
                IconButton(
                  tooltip: 'Download',
                  onPressed: isDownloading ? null : () => _download(item),
                  icon: isDownloading
                      ? SizedBox(
                          width: 22.s,
                          height: 22.s,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, value: progress),
                        )
                      : const Icon(Icons.download_rounded),
                  color: settings.accentColor,
                ),
              ],
            ),
            if (isDownloading) ...[
              SizedBox(height: 8.h),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  minHeight: 4.h,
                  value: progress,
                  backgroundColor:
                      theme.colorScheme.onSurface.withOpacity(0.08),
                  valueColor:
                      AlwaysStoppedAnimation<Color>(settings.accentColor),
                ),
              ),
              if (progressMessage != null) ...[
                SizedBox(height: 5.h),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    progressMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: theme.colorScheme.onSurface.withOpacity(0.48),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _resultKey(YoutubeMusicResult item) {
    return item.videoId.isNotEmpty
        ? item.videoId
        : '${item.resultType}:${item.browseId}:${item.title}';
  }
}
