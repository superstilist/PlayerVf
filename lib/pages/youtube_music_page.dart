import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/music_model.dart';
import '../models/settings_model.dart';
import '../services/music_service.dart';
import '../services/responsive.dart';
import '../services/youtube_music_service.dart';
import '../utils/duration_format.dart';
import '../widgets/cover_art_texture.dart';
import '../widgets/glass_container.dart';

class YoutubeMusicPage extends StatefulWidget {
  final VoidCallback? onOpenPlayer;

  const YoutubeMusicPage({super.key, this.onOpenPlayer});

  @override
  State<YoutubeMusicPage> createState() => _YoutubeMusicPageState();
}

class _YoutubeDownloadChoice {
  final bool video;
  final int? qualityHeight;
  final List<int> qualityHeights;
  final bool subtitlesOnly;
  final bool includeSubtitles;
  final String? subtitleLanguage;
  final List<String> subtitleLanguages;
  final bool automaticSubtitles;

  const _YoutubeDownloadChoice({
    required this.video,
    this.qualityHeight,
    this.qualityHeights = const [],
    this.subtitlesOnly = false,
    this.includeSubtitles = false,
    this.subtitleLanguage,
    this.subtitleLanguages = const [],
    this.automaticSubtitles = false,
  });

  const _YoutubeDownloadChoice.audio()
      : video = false,
        qualityHeight = null,
        qualityHeights = const [],
        subtitlesOnly = false,
        includeSubtitles = false,
        subtitleLanguage = null,
        subtitleLanguages = const [],
        automaticSubtitles = false;
}

class _DownloadedYoutubeSet {
  final Set<int> qualityHeights;
  final Set<String> subtitleKeys;
  final bool audio;

  const _DownloadedYoutubeSet({
    required this.qualityHeights,
    required this.subtitleKeys,
    this.audio = false,
  });

  bool get hasAny =>
      audio || qualityHeights.isNotEmpty || subtitleKeys.isNotEmpty;

  bool hasQuality(int height) => qualityHeights.contains(height);

  bool hasSubtitle(YoutubeSubtitleOption option) {
    final language = option.language.toLowerCase();
    final exactKey = '$language:${option.automatic}';
    if (subtitleKeys.contains(exactKey)) return true;
    return subtitleKeys.any((key) => key.startsWith(language));
  }
}

class _YoutubeMusicPageState extends State<YoutubeMusicPage>
    with AutomaticKeepAliveClientMixin {
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
  final Map<String, _DownloadedYoutubeSet> _downloadedCache = {};

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
      _service.warmStreams(results);
      unawaited(_refreshDownloadedCache(results));
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

    final choice = await _chooseDownloadOptions(item);
    if (choice == null) return;
    if (!mounted) return;

    setState(() {
      _downloadingIds.add(key);
      _downloadProgress[key] = null;
      _downloadMessages[key] = 'Starting download...';
      _message = 'Downloading ${item.title}...';
    });

    try {
      final download = await _service.download(
        item,
        video: choice.video,
        qualityHeight: choice.qualityHeight,
        qualityHeights: choice.qualityHeights,
        subtitlesOnly: choice.subtitlesOnly,
        includeSubtitles: choice.includeSubtitles,
        subtitleLanguage: choice.subtitleLanguage,
        subtitleLanguages: choice.subtitleLanguages,
        automaticSubtitles: choice.automaticSubtitles,
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
        final visibleCount = download.libraryFiles.isNotEmpty
            ? download.libraryFiles.length
            : download.files.length;
        _message = download.files.isEmpty
            ? (download.message.isEmpty
                ? 'Download finished.'
                : download.message)
            : download.message.isNotEmpty
                ? download.message
                : 'Downloaded $visibleCount item${visibleCount == 1 ? '' : 's'}.';
      });
      unawaited(_refreshDownloadedCache(_results));
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

  Future<_YoutubeDownloadChoice?> _chooseDownloadOptions(
      YoutubeMusicResult item) async {
    if (item.resultType.toLowerCase() != 'video') {
      return const _YoutubeDownloadChoice.audio();
    }

    setState(() => _message = 'Loading video download options...');
    YoutubeMusicStream stream;
    try {
      stream = await _service.stream(item);
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'Could not load video options: $error');
      }
      return null;
    }
    if (!mounted) return null;

    final qualities = stream.qualities;
    final downloadedSet = await _loadDownloadedYoutubeSet(item);
    if (!mounted) return null;
    bool video = qualities.isNotEmpty;
    final selectedHeights = <int>{
      if (qualities.isNotEmpty) qualities.first.height,
    };
    List<int> sortedSelectedHeights() =>
        selectedHeights.toList()..sort((a, b) => b.compareTo(a));
    bool includeSubtitles = false;
    final selectedSubtitleKeys = <String>{};
    if (stream.subtitles.isNotEmpty) {
      selectedSubtitleKeys.add(_subtitleKey(stream.subtitles.first));
    }

    return showModalBottomSheet<_YoutubeDownloadChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return GlassContainer(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              color: theme.colorScheme.surface.withOpacity(0.94),
              blur: 12,
              child: SafeArea(
                top: false,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.88,
                  ),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 22.h),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 38,
                            height: 4,
                            decoration: BoxDecoration(
                              color:
                                  theme.colorScheme.onSurface.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        SizedBox(height: 12.h),
                        ListTile(
                          leading: const Icon(Icons.download_rounded),
                          title: const Text('Download video'),
                          subtitle: Text(item.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        Wrap(
                          spacing: 8.w,
                          runSpacing: 8.h,
                          children: [
                            ChoiceChip(
                              avatar: const Icon(Icons.music_note_rounded),
                              label: const Text('Audio MP3'),
                              selected: !video,
                              onSelected: (_) =>
                                  setSheetState(() => video = false),
                            ),
                            ...qualities.map((quality) {
                              final selected = video &&
                                  selectedHeights.contains(quality.height);
                              final saved =
                                  downloadedSet?.hasQuality(quality.height) ??
                                      false;
                              return ChoiceChip(
                                avatar: Icon(saved
                                    ? Icons.download_done_rounded
                                    : Icons.high_quality_rounded),
                                label: Text(saved
                                    ? '${quality.label} saved'
                                    : quality.label),
                                selected: selected,
                                onSelected: (_) => setSheetState(() {
                                  video = true;
                                  if (selected && selectedHeights.length > 1) {
                                    selectedHeights.remove(quality.height);
                                  } else {
                                    selectedHeights.add(quality.height);
                                  }
                                }),
                              );
                            }),
                          ],
                        ),
                        if (qualities.length > 1)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              icon: const Icon(Icons.done_all_rounded),
                              label: const Text('Select all qualities'),
                              onPressed: () => setSheetState(() {
                                video = true;
                                selectedHeights
                                  ..clear()
                                  ..addAll(qualities
                                      .map((quality) => quality.height));
                              }),
                            ),
                          ),
                        SizedBox(height: 10.h),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.subtitles_rounded),
                          title: const Text('Download subtitles'),
                          subtitle: Text(stream.subtitles.isEmpty
                              ? 'No subtitles found for this video'
                              : 'Choose a subtitle track or turn this off'),
                          value:
                              includeSubtitles && stream.subtitles.isNotEmpty,
                          onChanged: stream.subtitles.isEmpty
                              ? null
                              : (value) =>
                                  setSheetState(() => includeSubtitles = value),
                        ),
                        if (includeSubtitles && stream.subtitles.isNotEmpty)
                          ConstrainedBox(
                            constraints: BoxConstraints(maxHeight: 220.h),
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: stream.subtitles.map((option) {
                                  final key = _subtitleKey(option);
                                  final saved =
                                      downloadedSet?.hasSubtitle(option) ??
                                          false;
                                  return CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    secondary: Icon(option.automatic
                                        ? Icons.auto_awesome_rounded
                                        : Icons.closed_caption_rounded),
                                    title: Text(saved
                                        ? '${option.label} saved'
                                        : option.label),
                                    value: selectedSubtitleKeys.contains(key),
                                    onChanged: (value) => setSheetState(() {
                                      if (value == true) {
                                        selectedSubtitleKeys.add(key);
                                      } else if (selectedSubtitleKeys.length >
                                          1) {
                                        selectedSubtitleKeys.remove(key);
                                      }
                                    }),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        if (includeSubtitles && stream.subtitles.length > 1)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              icon: const Icon(Icons.done_all_rounded),
                              label: const Text('Select all subtitles'),
                              onPressed: () => setSheetState(() {
                                selectedSubtitleKeys
                                  ..clear()
                                  ..addAll(stream.subtitles.map(_subtitleKey));
                              }),
                            ),
                          ),
                        if ((downloadedSet?.hasAny ?? false) &&
                            stream.subtitles.isNotEmpty)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              icon: const Icon(Icons.subtitles_rounded),
                              label: const Text('Download subtitles only'),
                              onPressed: () => setSheetState(() {
                                video = false;
                                includeSubtitles = true;
                              }),
                            ),
                          ),
                        SizedBox(height: 12.h),
                        FilledButton.icon(
                          icon: const Icon(Icons.download_done_rounded),
                          label: Text(video
                              ? 'Download ${selectedHeights.length} quality${selectedHeights.length == 1 ? '' : 'ies'}'
                              : includeSubtitles &&
                                      selectedSubtitleKeys.isNotEmpty
                                  ? 'Download subtitles only'
                                  : 'Download audio MP3'),
                          onPressed: () => Navigator.pop(
                            context,
                            _YoutubeDownloadChoice(
                              video: video,
                              subtitlesOnly: !video &&
                                  includeSubtitles &&
                                  selectedSubtitleKeys.isNotEmpty,
                              qualityHeight: video && selectedHeights.isNotEmpty
                                  ? selectedHeights.first
                                  : null,
                              qualityHeights:
                                  video ? sortedSelectedHeights() : const [],
                              includeSubtitles: includeSubtitles &&
                                  selectedSubtitleKeys.isNotEmpty,
                              subtitleLanguage: null,
                              subtitleLanguages: stream.subtitles
                                  .where((option) => selectedSubtitleKeys
                                      .contains(_subtitleKey(option)))
                                  .map((option) => option.language)
                                  .toSet()
                                  .toList(),
                              automaticSubtitles: stream.subtitles.any(
                                  (option) =>
                                      selectedSubtitleKeys
                                          .contains(_subtitleKey(option)) &&
                                      option.automatic),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _subtitleKey(YoutubeSubtitleOption option) =>
      '${option.language}:${option.automatic}';

  Future<_DownloadedYoutubeSet?> _loadDownloadedYoutubeSet(
      YoutubeMusicResult item) async {
    final cached = _downloadedCache[_resultKey(item)];
    if (cached != null) return cached;
    if (kIsWeb || item.videoId.isEmpty) return null;
    try {
      final downloadDir = Directory(await _service.resolvedDownloadDirectory());
      if (!await downloadDir.exists()) return null;
      final manifests = await downloadDir
          .list(recursive: true, followLinks: false)
          .where((entity) =>
              entity is File &&
              entity.path.toLowerCase().endsWith('.playervf.json'))
          .cast<File>()
          .toList();
      manifests.sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      for (final file in manifests) {
        final data = jsonDecode(await file.readAsString());
        if (data is! Map || data['type'] != 'playervf.youtubeVideoSet') {
          continue;
        }
        if ((data['videoId'] ?? '').toString() != item.videoId) continue;
        final qualities = <int>{};
        for (final quality in (data['qualities'] as List? ?? const [])) {
          if (quality is! Map) continue;
          final path = quality['path']?.toString() ?? '';
          final height =
              int.tryParse((quality['height'] ?? '').toString()) ?? 0;
          if (height > 0 && path.isNotEmpty && await File(path).exists()) {
            qualities.add(height);
          }
        }
        final subtitles = <String>{};
        for (final subtitle in (data['subtitles'] as List? ?? const [])) {
          if (subtitle is! Map) continue;
          final path = subtitle['path']?.toString() ?? '';
          if (path.isNotEmpty && !await File(path).exists()) continue;
          final language =
              (subtitle['language'] ?? '').toString().toLowerCase();
          if (language.isEmpty) continue;
          subtitles.add('$language:${subtitle['automatic'] == true}');
        }
        return _DownloadedYoutubeSet(
          qualityHeights: qualities,
          subtitleKeys: subtitles,
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> _refreshDownloadedCache(List<YoutubeMusicResult> items) async {
    if (kIsWeb || items.isEmpty) return;
    try {
      final downloadDir = Directory(await _service.resolvedDownloadDirectory());
      if (!await downloadDir.exists()) return;
      final next = <String, _DownloadedYoutubeSet>{};
      await _readVideoDownloadMarks(downloadDir, next);
      await _readAudioDownloadMarks(downloadDir, items, next);
      if (!mounted) return;
      setState(() {
        _downloadedCache
          ..clear()
          ..addAll(next);
      });
    } catch (_) {
      // Download markers are a UI hint; failures should not block search.
    }
  }

  Future<void> _readVideoDownloadMarks(
    Directory downloadDir,
    Map<String, _DownloadedYoutubeSet> marks,
  ) async {
    final manifests = await downloadDir
        .list(recursive: true, followLinks: false)
        .where((entity) =>
            entity is File &&
            entity.path.toLowerCase().endsWith('.playervf.json'))
        .cast<File>()
        .toList();
    for (final file in manifests) {
      final data = jsonDecode(await file.readAsString());
      if (data is! Map || data['type'] != 'playervf.youtubeVideoSet') {
        continue;
      }
      final videoId = (data['videoId'] ?? '').toString();
      if (videoId.isEmpty) continue;
      final qualities = <int>{};
      for (final quality in (data['qualities'] as List? ?? const [])) {
        if (quality is! Map) continue;
        final path = quality['path']?.toString() ?? '';
        final height = int.tryParse((quality['height'] ?? '').toString()) ?? 0;
        if (height > 0 && path.isNotEmpty && await File(path).exists()) {
          qualities.add(height);
        }
      }
      final subtitles = <String>{};
      for (final subtitle in (data['subtitles'] as List? ?? const [])) {
        if (subtitle is! Map) continue;
        final path = subtitle['path']?.toString() ?? '';
        if (path.isNotEmpty && !await File(path).exists()) continue;
        final language = (subtitle['language'] ?? '').toString().toLowerCase();
        if (language.isEmpty) continue;
        subtitles.add('$language:${subtitle['automatic'] == true}');
      }
      marks[videoId] = _mergeDownloadedSet(
        marks[videoId],
        _DownloadedYoutubeSet(
          qualityHeights: qualities,
          subtitleKeys: subtitles,
        ),
      );
    }
  }

  Future<void> _readAudioDownloadMarks(
    Directory downloadDir,
    List<YoutubeMusicResult> items,
    Map<String, _DownloadedYoutubeSet> marks,
  ) async {
    final mediaNames = <String>[];
    await for (final entity
        in downloadDir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final lower = entity.path.toLowerCase();
      if (!lower.endsWith('.mp3') &&
          !lower.endsWith('.m4a') &&
          !lower.endsWith('.flac') &&
          !lower.endsWith('.wav') &&
          !lower.endsWith('.opus') &&
          !lower.endsWith('.ogg')) {
        continue;
      }
      mediaNames
          .add(_downloadMarkText(entity.path.split(RegExp(r'[\\/]')).last));
    }

    for (final item in items) {
      if (item.resultType.toLowerCase() == 'video' &&
          marks[_resultKey(item)]?.qualityHeights.isNotEmpty == true) {
        continue;
      }
      final title = _downloadMarkText(item.title);
      final artist = _downloadMarkText(item.artist);
      if (title.isEmpty) continue;
      final matched = mediaNames.any((name) =>
          name.contains(title) && (artist.isEmpty || name.contains(artist)));
      if (!matched) continue;
      final key = _resultKey(item);
      marks[key] = _mergeDownloadedSet(
        marks[key],
        const _DownloadedYoutubeSet(
          qualityHeights: <int>{},
          subtitleKeys: <String>{},
          audio: true,
        ),
      );
    }
  }

  _DownloadedYoutubeSet _mergeDownloadedSet(
    _DownloadedYoutubeSet? existing,
    _DownloadedYoutubeSet next,
  ) {
    if (existing == null) return next;
    return _DownloadedYoutubeSet(
      qualityHeights: {...existing.qualityHeights, ...next.qualityHeights},
      subtitleKeys: {...existing.subtitleKeys, ...next.subtitleKeys},
      audio: existing.audio || next.audio,
    );
  }

  String _downloadMarkText(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
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

      final playFuture = context.read<MusicService>().playStreamingMusic(music);
      widget.onOpenPlayer?.call();
      if (!mounted) return;
      setState(() => _message = 'Playing ${stream.title}');
      await playFuture;
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
    super.build(context);
    final theme = Theme.of(context);
    final settings = context.watch<SettingsModel>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        cacheExtent: 900,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
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
                child: Center(
                  child: CircularProgressIndicator(
                    color: theme.colorScheme.primary,
                    strokeWidth: 3,
                  ),
                ),
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
        ],
      ),
    );
  }

  Widget _buildSearchPanel(ThemeData theme, SettingsModel settings) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: GlassContainer(
        padding: EdgeInsets.all(14.s),
        borderRadius: BorderRadius.circular(18.s),
        color: null,
        blur: 16,
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
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    foregroundColor: theme.colorScheme.onPrimaryContainer,
                  ),
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
                    label: Text(
                      filter,
                      style: TextStyle(fontSize: 12.sp),
                    ),
                    selected: selected,
                    selectedColor:
                        theme.colorScheme.primaryContainer.withOpacity(0.68),
                    backgroundColor: theme.colorScheme.surfaceContainerHighest
                        .withOpacity(0.34),
                    padding:
                        EdgeInsets.symmetric(horizontal: 8.w, vertical: 5.h),
                    visualDensity: VisualDensity.compact,
                    labelStyle: TextStyle(
                      color: selected
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurface.withOpacity(0.68),
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
    final downloadedSet = _downloadedCache[key];
    final isDownloaded = downloadedSet?.hasAny ?? false;
    final progress = _downloadProgress[key];
    final progressMessage = _downloadMessages[key];
    final subtitle = [
      if (item.artist.isNotEmpty) item.artist,
      if (item.duration.isNotEmpty)
        normalizePlaybackDurationText(item.duration),
      item.resultType,
      if (isDownloaded) 'saved',
    ].join('  -  ');

    return GestureDetector(
      onTap: isStreaming ? null : () => _stream(item),
      child: GlassContainer(
        margin: EdgeInsets.only(bottom: 10.h),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        borderRadius: BorderRadius.circular(16.s),
        color: null,
        blur: 14,
        child: Column(
          children: [
            Row(
              children: [
                RepaintBoundary(
                  child: SizedBox.square(
                    dimension: 58.s,
                    child: CoverArtTexture(
                      coverArtPath: item.thumbnailUrl,
                      width: 58.s,
                      height: 58.s,
                      borderRadius: BorderRadius.circular(12.s),
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
                  onPressed: isStreaming ? null : () => _stream(item),
                  icon: isStreaming
                      ? SizedBox(
                          width: 20.s,
                          height: 20.s,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ))
                      : const Icon(Icons.play_arrow_rounded),
                  color: theme.colorScheme.primary,
                ),
                IconButton(
                  onPressed: isDownloading ? null : () => _download(item),
                  icon: isDownloading
                      ? SizedBox(
                          width: 22.s,
                          height: 22.s,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            value: progress,
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : Icon(isDownloaded
                          ? Icons.download_done_rounded
                          : Icons.download_rounded),
                  color: isDownloaded
                      ? theme.colorScheme.tertiary
                      : theme.colorScheme.primary,
                ),
              ],
            ),
            if (isDownloading) ...[
              SizedBox(height: 8.h),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  minHeight: 6.h,
                  value: progress,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest
                      .withOpacity(0.8),
                  valueColor:
                      AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
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

  @override
  bool get wantKeepAlive => true;
}
