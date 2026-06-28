import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../models/music_model.dart';
import '../services/cover_color_service.dart';
import '../services/music_service.dart';
import '../services/performance_policy.dart';
import '../services/responsive.dart';
import '../services/safe_file_picker.dart';
import '../services/youtube_music_service.dart';
import '../widgets/audio_effects_menu.dart';
import '../widgets/blurred_cover_background.dart';
import '../widgets/lanczos_cover_art.dart';
import '../widgets/cover_art_texture.dart';
import '../widgets/glass_container.dart';
import '../widgets/playback_progress_control.dart';
import '../widgets/stable_video_surface.dart';
import '../models/settings_model.dart';
import '../utils/duration_format.dart';

class _VideoTogglePlayIntent extends Intent {
  const _VideoTogglePlayIntent();
}

class _VideoSeekIntent extends Intent {
  final int direction;

  const _VideoSeekIntent(this.direction);
}

class _VideoFullscreenIntent extends Intent {
  const _VideoFullscreenIntent();
}

class _VideoSubtitlesIntent extends Intent {
  const _VideoSubtitlesIntent();
}

class _VideoQualityIntent extends Intent {
  const _VideoQualityIntent();
}

class _VideoNextIntent extends Intent {
  const _VideoNextIntent();
}

class _VideoPreviousIntent extends Intent {
  const _VideoPreviousIntent();
}

class _VideoRestartIntent extends Intent {
  const _VideoRestartIntent();
}

class _VideoVolumeIntent extends Intent {
  final double delta;

  const _VideoVolumeIntent(this.delta);
}

class _VideoMuteIntent extends Intent {
  const _VideoMuteIntent();
}

Future<void> openVideoFullscreenOverlay({
  required BuildContext context,
  required MusicService musicService,
  required String surfaceKey,
  YoutubeMusicStream? youtubeStream,
  String? youtubeMessage,
  bool isLoadingYoutubeDetails = false,
  bool isChangingYoutubeQuality = false,
  void Function(BuildContext context)? onShowQualityChoices,
  void Function(BuildContext context)? onShowSubtitleChoices,
}) async {
  if (musicService.videoController == null) return;
  if (!kIsWeb && Platform.isLinux) return;

  await Navigator.of(context).push(
    PageRouteBuilder(
      opaque: true,
      barrierColor: Colors.black,
      pageBuilder: (context, animation, secondaryAnimation) {
        return FadeTransition(
          opacity: animation,
          child: _FullscreenVideoPage(
            musicService: musicService,
            youtubeStream: youtubeStream,
            youtubeMessage: youtubeMessage,
            surfaceKey: surfaceKey,
            isLoadingYoutubeDetails: isLoadingYoutubeDetails,
            isChangingYoutubeQuality: isChangingYoutubeQuality,
            onShowQualityChoices: onShowQualityChoices,
            onShowSubtitleChoices: onShowSubtitleChoices,
          ),
        );
      },
    ),
  );
}

class VideoPage extends StatefulWidget {
  final VoidCallback onClose;

  const VideoPage({super.key, required this.onClose});

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  final YoutubeMusicService _youtubeService = YoutubeMusicService();
  Future<CoverArtPalette>? _paletteFuture;
  String _palettePath = '';
  String _youtubeVideoId = '';
  YoutubeMusicStream? _youtubeStream;
  String _localManifestTrackPath = '';
  bool _loadingYoutubeDetails = false;
  bool _changingYoutubeQuality = false;
  bool _autoSubtitleApplied = false;
  bool _isFullscreenOpen = false;
  String? _youtubeMessage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final musicService = context.read<MusicService>();
    final settings = context.read<SettingsModel>();
    _syncPalette(musicService.currentMusic?.coverPath, settings.orbPaletteSize);
    _syncYoutubeDetails(musicService);
  }

  void _syncPalette(String? path, int paletteSize) {
    final normalized = path ?? '';
    final key = '$normalized::$paletteSize';
    if (_paletteFuture == null || key != _palettePath) {
      _palettePath = key;
      _paletteFuture = CoverColorService.fromPath(normalized, paletteSize: paletteSize);
    }
  }

  String _extractYoutubeVideoId(Music? music) {
    if (music == null ||
        (music.genre != 'YouTube Music Video' &&
            music.genre != 'YouTube Video')) {
      return '';
    }
    final id = music.id;
    if (id.startsWith('ytm:')) {
      final raw = id.substring(4);
      return raw.split(':').first.trim();
    }
    final uri = Uri.tryParse(music.filePath);
    return uri?.queryParameters['v'] ?? '';
  }

  void _syncYoutubeDetails(MusicService musicService) {
    final current = musicService.currentMusic;
    final videoId = _extractYoutubeVideoId(current);
    if (videoId.isEmpty) {
      if (_youtubeVideoId.isNotEmpty) {
        _youtubeVideoId = '';
        _youtubeStream = null;
        _youtubeMessage = null;
        _autoSubtitleApplied = false;
      }
      _syncLocalVideoManifest(current);
      return;
    }
    if (videoId == _youtubeVideoId) return;
    _youtubeVideoId = videoId;
    _localManifestTrackPath = '';
    _youtubeStream = null;
    _youtubeMessage = null;
    _autoSubtitleApplied = false;
    if (videoId.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && videoId == _youtubeVideoId) {
        unawaited(_loadYoutubeDetails(videoId, musicService));
      }
    });
  }

  void _syncLocalVideoManifest(Music? music) {
    final path = music?.filePath ?? '';
    if (path.isEmpty || path == _localManifestTrackPath) return;
    _localManifestTrackPath = path;
    _youtubeStream = null;
    _youtubeMessage = null;
    if (music == null || !_looksLikeLocalVideo(music)) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && path == _localManifestTrackPath) {
        unawaited(_loadLocalVideoManifest(music));
      }
    });
  }

  bool _looksLikeLocalVideo(Music music) {
    if (music.filePath.startsWith('http://') ||
        music.filePath.startsWith('https://') ||
        music.filePath.startsWith('blob:')) {
      return false;
    }
    final ext = _mediaPathExtension(music.filePath);
    return const {
      '.mp4',
      '.mkv',
      '.webm',
      '.mov',
      '.avi',
      '.m4v',
      '.wmv',
      '.flv',
      '.ts',
      '.m2ts',
      '.3gp',
      '.m3u8',
    }.contains(ext);
  }

  String _mediaPathExtension(String path) {
    final target = path.trim();
    if (target.isEmpty) return '';
    final parsed = Uri.tryParse(target);
    final candidate = parsed != null && parsed.hasScheme
        ? parsed.path
        : target.split('?').first.split('#').first;
    return p.extension(candidate).toLowerCase();
  }

  Future<void> _loadLocalVideoManifest(Music music) async {
    final manifest = await _findLocalVideoManifest(music.filePath);
    if (manifest == null) return;
    try {
      final decoded =
          jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
      final qualities = <YoutubeVideoQuality>[];
      for (final item in decoded['qualities'] as List? ?? const []) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final path = map['path']?.toString() ?? '';
        if (path.isEmpty || !await File(path).exists()) continue;
        final height = (map['height'] as num?)?.toInt() ?? 0;
        qualities.add(YoutubeVideoQuality(
          label:
              map['label']?.toString() ?? (height > 0 ? '${height}p' : 'Auto'),
          height: height,
          url: path,
          formatId: 'local',
          ext: p.extension(path).replaceFirst('.', ''),
          hasAudio: true,
        ));
      }
      final subtitles = <YoutubeSubtitleOption>[];
      for (final item in decoded['subtitles'] as List? ?? const []) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final path = map['path']?.toString() ?? '';
        if (path.isEmpty || !await File(path).exists()) continue;
        subtitles.add(YoutubeSubtitleOption(
          language: map['language']?.toString() ?? '',
          label: map['label']?.toString() ?? p.basename(path),
          url: path,
          automatic: map['automatic'] == true,
        ));
      }
      if (!mounted || music.filePath != _localManifestTrackPath) return;
      final selected = qualities.firstWhere(
        (quality) => p.equals(quality.url, music.filePath),
        orElse: () => qualities.isNotEmpty
            ? qualities.first
            : YoutubeVideoQuality(
                label: 'Local',
                height: 0,
                url: music.filePath,
                formatId: 'local',
                ext: p.extension(music.filePath).replaceFirst('.', ''),
              ),
      );
      setState(() {
        _youtubeStream = YoutubeMusicStream(
          url: music.filePath,
          title: music.title,
          artist: music.artist,
          album: music.album,
          thumbnailUrl: music.coverPath,
          durationSeconds: music.duration?.inSeconds ?? 0,
          videoId: '',
          isVideo: true,
          qualityLabel: selected.label,
          qualities: qualities,
          subtitles: subtitles,
        );
        _youtubeMessage = 'Local qualities loaded';
      });
    } catch (error) {
      if (mounted && music.filePath == _localManifestTrackPath) {
        setState(() => _youtubeMessage = 'Local quality JSON failed: $error');
      }
    }
  }

  Future<File?> _findLocalVideoManifest(String filePath) async {
    final direct = File('${p.withoutExtension(filePath)}.playervf.json');
    if (await direct.exists()) return direct;

    final dir = p.dirname(filePath);
    final stem = p.basenameWithoutExtension(filePath);
    final baseStem =
        stem.replaceFirst(RegExp(r'\.(auto|\d+p)$', caseSensitive: false), '');
    final grouped = File(p.join(dir, '$baseStem.playervf.json'));
    if (await grouped.exists()) return grouped;
    return null;
  }

  Future<void> _loadYoutubeDetails(
      String videoId, MusicService musicService) async {
    if (!YoutubeMusicService.isSupported) return;
    setState(() => _loadingYoutubeDetails = true);
    try {
      final stream = await _youtubeService.streamVideoId(videoId);
      if (!mounted || videoId != _youtubeVideoId) return;
      setState(() {
        _youtubeStream = stream;
        _youtubeMessage = null;
      });
      await _autoLoadYoutubeSubtitle(musicService, stream);
    } catch (e) {
      if (mounted && videoId == _youtubeVideoId) {
        setState(() => _youtubeMessage = 'YouTube details failed: $e');
      }
    } finally {
      if (mounted && videoId == _youtubeVideoId) {
        setState(() => _loadingYoutubeDetails = false);
      }
    }
  }

  Future<void> _autoLoadYoutubeSubtitle(
    MusicService musicService,
    YoutubeMusicStream stream,
  ) async {
    if (_autoSubtitleApplied || stream.subtitles.isEmpty) return;
    final subtitle = stream.subtitles.first;
    try {
      await musicService.loadSubtitleUrl(subtitle.url, title: subtitle.label);
      _autoSubtitleApplied = true;
      if (mounted) {
        setState(() => _youtubeMessage = 'Loaded ${subtitle.label}');
      }
    } catch (e) {
      if (mounted) setState(() => _youtubeMessage = 'Subtitle failed: $e');
    }
  }

  Future<void> _changeYoutubeQuality(
    MusicService musicService,
    YoutubeVideoQuality quality,
  ) async {
    final current = musicService.currentMusic;
    final videoId = _extractYoutubeVideoId(current);
    if (current == null || videoId.isEmpty || _changingYoutubeQuality) return;

    setState(() {
      _changingYoutubeQuality = true;
      _youtubeMessage = 'Switching to ${quality.label}...';
    });
    try {
      final wasPlaying = musicService.isPlaying;
      final position = musicService.position;
      final stream = await _youtubeService.streamVideoId(
        videoId,
        maxHeight: quality.height,
      );
      final updated = Music(
        id: 'ytm:$videoId:q${quality.height}',
        title: stream.displayTitle,
        artist: stream.displayArtist,
        album: stream.album.isEmpty ? current.album : stream.album,
        filePath: stream.url,
        coverPath: stream.thumbnailUrl.isEmpty
            ? current.coverPath
            : stream.thumbnailUrl,
        httpHeaders: stream.httpHeaders,
        genre: 'YouTube Music Video',
        year: current.year,
        duration: stream.durationSeconds > 0
            ? Duration(seconds: stream.durationSeconds)
            : current.duration,
      );
      await musicService.replaceStreamingMusic(
        updated,
        startPosition: position,
        shouldPlay: wasPlaying,
      );
      if (!mounted) return;
      setState(() {
        _youtubeVideoId = videoId;
        _youtubeStream = stream;
        _autoSubtitleApplied = false;
        _youtubeMessage = 'Quality ${stream.qualityLabel}';
      });
      await _autoLoadYoutubeSubtitle(musicService, stream);
    } catch (e) {
      if (mounted) setState(() => _youtubeMessage = 'Quality failed: $e');
    } finally {
      if (mounted) setState(() => _changingYoutubeQuality = false);
    }
  }

  Future<void> _changeLocalVideoQuality(
    MusicService musicService,
    YoutubeVideoQuality quality,
  ) async {
    final current = musicService.currentMusic;
    if (current == null || quality.url.isEmpty || _changingYoutubeQuality) {
      return;
    }
    if (p.equals(
      p.normalize(current.filePath),
      p.normalize(quality.url),
    )) {
      return;
    }
    final file = File(quality.url);
    if (!await file.exists()) return;

    setState(() {
      _changingYoutubeQuality = true;
      _youtubeMessage = 'Switching to ${quality.label}...';
    });
    try {
      final wasPlaying = musicService.isPlaying;
      final position = musicService.position;
      final updated = Music(
        id: 'local-video:${quality.url.hashCode}',
        title: current.title,
        artist: current.artist,
        album: current.album,
        filePath: quality.url,
        coverPath: current.coverPath,
        genre: current.genre,
        year: current.year,
        duration: current.duration,
        isFavorite: current.isFavorite,
        playCount: current.playCount,
        lastPlayed: current.lastPlayed,
        dateAdded: current.dateAdded,
      );
      await musicService.replaceStreamingMusic(
        updated,
        startPosition: position,
        shouldPlay: wasPlaying,
      );
      if (!mounted) return;
      setState(() {
        _localManifestTrackPath = quality.url;
        _youtubeStream = _youtubeStream == null
            ? null
            : YoutubeMusicStream(
                url: quality.url,
                title: updated.title,
                artist: updated.artist,
                album: updated.album,
                thumbnailUrl: updated.coverPath,
                httpHeaders: updated.httpHeaders,
                durationSeconds: updated.duration?.inSeconds ?? 0,
                videoId: '',
                isVideo: true,
                qualityLabel: quality.label,
                qualities: _youtubeStream!.qualities,
                subtitles: _youtubeStream!.subtitles,
              );
        _youtubeMessage = 'Quality ${quality.label}';
      });
    } finally {
      if (mounted) setState(() => _changingYoutubeQuality = false);
    }
  }

  String _videoSurfaceIdentity(Music? music, {String prefix = 'video'}) {
    if (music == null) return '$prefix-none';
    final videoId = _extractYoutubeVideoId(music);
    if (videoId.isNotEmpty) return '$prefix-youtube-$videoId';
    if (_looksLikeLocalVideo(music)) {
      final dir = p.dirname(music.filePath);
      final stem = p.basenameWithoutExtension(music.filePath).replaceFirst(
            RegExp(r'\.(auto|\d+p)$', caseSensitive: false),
            '',
          );
      return '$prefix-local-${p.join(dir, stem).hashCode}';
    }
    return '$prefix-${music.id}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final musicService = Provider.of<MusicService>(context);
    final settings = Provider.of<SettingsModel>(context);
    final currentMusic = musicService.currentMusic;

    return FutureBuilder<CoverArtPalette>(
      future: _paletteFuture,
      builder: (context, snapshot) {
        final palette = snapshot.data ?? CoverColorService.fallbackPalette;

        return Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.space): _VideoTogglePlayIntent(),
            SingleActivator(LogicalKeyboardKey.arrowLeft): _VideoSeekIntent(-1),
            SingleActivator(LogicalKeyboardKey.arrowRight): _VideoSeekIntent(1),
            SingleActivator(LogicalKeyboardKey.keyF): _VideoFullscreenIntent(),
            SingleActivator(LogicalKeyboardKey.keyS): _VideoSubtitlesIntent(),
            SingleActivator(LogicalKeyboardKey.keyQ): _VideoQualityIntent(),
            SingleActivator(LogicalKeyboardKey.keyN): _VideoNextIntent(),
            SingleActivator(LogicalKeyboardKey.keyP): _VideoPreviousIntent(),
            SingleActivator(LogicalKeyboardKey.keyB): _VideoPreviousIntent(),
            SingleActivator(LogicalKeyboardKey.keyR): _VideoRestartIntent(),
            SingleActivator(LogicalKeyboardKey.audioVolumeUp):
                _VideoVolumeIntent(5),
            SingleActivator(LogicalKeyboardKey.audioVolumeDown):
                _VideoVolumeIntent(-5),
            SingleActivator(LogicalKeyboardKey.audioVolumeMute):
                _VideoMuteIntent(),
            SingleActivator(LogicalKeyboardKey.equal): _VideoVolumeIntent(5),
            SingleActivator(LogicalKeyboardKey.minus): _VideoVolumeIntent(-5),
            SingleActivator(LogicalKeyboardKey.keyM): _VideoMuteIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _VideoTogglePlayIntent:
                  CallbackAction<_VideoTogglePlayIntent>(onInvoke: (_) {
                musicService.togglePlayPause();
                return null;
              }),
              _VideoSeekIntent: CallbackAction<_VideoSeekIntent>(
                onInvoke: (intent) {
                  _seekBy(
                    musicService,
                    Duration(
                      seconds: intent.direction * settings.seekStepSeconds,
                    ),
                  );
                  return null;
                },
              ),
              _VideoFullscreenIntent:
                  CallbackAction<_VideoFullscreenIntent>(onInvoke: (_) {
                _openFullscreenVideo(context, musicService);
                return null;
              }),
              _VideoSubtitlesIntent:
                  CallbackAction<_VideoSubtitlesIntent>(onInvoke: (_) {
                _showSubtitleSheet(context, musicService);
                return null;
              }),
              _VideoQualityIntent:
                  CallbackAction<_VideoQualityIntent>(onInvoke: (_) {
                _showQualitySheet(context, musicService);
                return null;
              }),
              _VideoNextIntent: CallbackAction<_VideoNextIntent>(onInvoke: (_) {
                musicService.next();
                return null;
              }),
              _VideoPreviousIntent:
                  CallbackAction<_VideoPreviousIntent>(onInvoke: (_) {
                musicService.previousTrack();
                return null;
              }),
              _VideoRestartIntent:
                  CallbackAction<_VideoRestartIntent>(onInvoke: (_) {
                musicService.restartCurrentTrack();
                return null;
              }),
              _VideoVolumeIntent:
                  CallbackAction<_VideoVolumeIntent>(onInvoke: (intent) {
                musicService.adjustVolumeBy(intent.delta);
                return null;
              }),
              _VideoMuteIntent: CallbackAction<_VideoMuteIntent>(onInvoke: (_) {
                musicService.toggleMute();
                return null;
              }),
            },
            child: Focus(
              autofocus: true,
              child: Scaffold(
                backgroundColor: Colors.transparent,
                body: Stack(
                  children: [
                    Positioned.fill(
                      child: _buildBackground(context, musicService, theme),
                    ),
                    Positioned(
                      left: -20,
                      top: 150.h,
                      child: Opacity(
                        opacity: 0.08,
                        child: RotatedBox(
                          quarterTurns: 1,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 320),
                            child: Text(
                              currentMusic?.title.toUpperCase() ?? 'PLAYERVF',
                              key: ValueKey(currentMusic?.id ?? 'bg-text'),
                              style: TextStyle(
                                fontSize: 120.sp,
                                fontWeight: FontWeight.w900,
                                color: theme.colorScheme.onSurface,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SafeArea(
                      child: Column(
                        children: [
                          _buildTopBar(context, currentMusic, palette),
                          Expanded(
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              padding: EdgeInsets.symmetric(
                                  horizontal: 24.w, vertical: 12.h),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(height: 10.h),
                                  _buildHeroVideo(musicService, settings),
                                  SizedBox(height: 48.h),
                                  _buildMetadata(currentMusic, theme),
                                  SizedBox(height: 40.h),
                                  _buildControlsSection(
                                      musicService, theme, palette),
                                  SizedBox(height: 32.h),
                                  _buildQuickQueue(
                                      context, musicService, theme, palette),
                                  SizedBox(height: 40.h),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_isFullscreenOpen)
                      Positioned.fill(
                        child: _FullscreenVideoPage(
                          musicService: musicService,
                          youtubeStream: _youtubeStream,
                          youtubeMessage: _youtubeMessage,
                          surfaceKey: _videoSurfaceIdentity(currentMusic,
                              prefix: 'linux-full'),
                          isLoadingYoutubeDetails: _loadingYoutubeDetails,
                          isChangingYoutubeQuality: _changingYoutubeQuality,
                          onClose: () =>
                              setState(() => _isFullscreenOpen = false),
                          onShowQualityChoices: (sheetContext) =>
                              _showQualitySheet(sheetContext, musicService),
                          onShowSubtitleChoices: (sheetContext) =>
                              _showSubtitleSheet(sheetContext, musicService),
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
  }

  Widget _buildTopBar(
      BuildContext context, Music? music, CoverArtPalette palette) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
            onPressed: widget.onClose,
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                music?.album.toUpperCase() ?? 'VIDEO',
                key: ValueKey(music?.album ?? 'none'),
                style: TextStyle(
                  fontSize: 10.sp,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: () => _showMoreOptions(context, palette),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground(
      BuildContext context, MusicService musicService, ThemeData theme) {
    final policy = PerformancePolicy.of(context);
    final blur = policy.backgroundBlur;
    final currentMusic = musicService.currentMusic;
    final coverPath = currentMusic?.coverPath ?? '';

    return AnimatedSwitcher(
      duration: policy.animation(const Duration(milliseconds: 520)),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 1.015, end: 1).animate(animation),
            child: child,
          ),
        );
      },
      child: Stack(
        key: ValueKey(_videoSurfaceIdentity(currentMusic, prefix: 'bg')),
        fit: StackFit.expand,
        children: [
          if (coverPath.isNotEmpty)
            BlurredCoverBackground(
              coverArtPath: coverPath,
              surfaceColor: theme.colorScheme.surface,
              overlayColor: theme.colorScheme.surface.withOpacity(
                blur > 0
                    ? (theme.brightness == Brightness.dark ? 0.72 : 0.78)
                    : (theme.brightness == Brightness.dark ? 0.86 : 0.90),
              ),
              blur: blur,
            )
          else
            Container(color: Colors.black),
          if (coverPath.isEmpty && blur > 0)
            ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: blur,
                  sigmaY: blur,
                ),
                child: ColoredBox(
                  color: theme.colorScheme.surface.withOpacity(
                    theme.brightness == Brightness.dark ? 0.72 : 0.78,
                  ),
                ),
              ),
            )
          else if (coverPath.isEmpty)
            ColoredBox(
              color: theme.colorScheme.surface.withOpacity(
                theme.brightness == Brightness.dark ? 0.86 : 0.90,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeroVideo(MusicService musicService, SettingsModel settings) {
    final size = 320.s;
    final controller = musicService.videoController;

    return Center(
      child: Hero(
        tag: _videoSurfaceIdentity(musicService.currentMusic, prefix: 'art'),
        child: GestureDetector(
          onDoubleTap: (controller != null && settings.videoDoubleTapFullscreen)
              ? () => _openFullscreenVideo(context, musicService)
              : null,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28.s),
              color: Colors.black,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28.s),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (controller != null && !_isFullscreenOpen)
                    StableVideoSurface(
                      controller: controller,
                      surfaceKey: _videoSurfaceIdentity(
                          musicService.currentMusic,
                          prefix: 'hero'),
                      fit: BoxFit.cover,
                    )
                  else if (!_isFullscreenOpen)
                    _buildVideoSurfaceUnavailable(),
                  if (_isFullscreenOpen) const ColoredBox(color: Colors.black),
                  _buildQualityTransitionOverlay(compact: true),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQualityTransitionOverlay({bool compact = false}) {
    return AnimatedOpacity(
      opacity: _changingYoutubeQuality ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.32)),
          child: Center(
            child: GlassContainer(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 14.w : 18.w,
                vertical: compact ? 10.h : 12.h,
              ),
              borderRadius: BorderRadius.circular(18.s),
              color: Colors.black.withOpacity(0.48),
              blur: 8,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: compact ? 16.s : 18.s,
                    height: compact ? 16.s : 18.s,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Text(
                    _youtubeMessage ?? 'Switching quality...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 12.sp : 13.sp,
                      fontWeight: FontWeight.w800,
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

  Widget _buildVideoSurfaceUnavailable() {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24.s),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.movie_filter_rounded,
                color: Colors.white70,
                size: 42.s,
              ),
              SizedBox(height: 12.h),
              Text(
                _youtubeMessage ?? 'Preparing video...',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openFullscreenVideo(
      BuildContext context, MusicService musicService) async {
    setState(() => _isFullscreenOpen = true);
    await openVideoFullscreenOverlay(
      context: context,
      musicService: musicService,
      youtubeStream: _youtubeStream,
      youtubeMessage: _youtubeMessage,
      surfaceKey: _videoSurfaceIdentity(
        musicService.currentMusic,
        prefix: 'full',
      ),
      isLoadingYoutubeDetails: _loadingYoutubeDetails,
      isChangingYoutubeQuality: _changingYoutubeQuality,
      onShowQualityChoices: (sheetContext) =>
          _showQualitySheet(sheetContext, musicService),
      onShowSubtitleChoices: (sheetContext) =>
          _showSubtitleSheet(sheetContext, musicService),
    );
    if (mounted) setState(() => _isFullscreenOpen = false);
  }

  void _seekBy(MusicService musicService, Duration delta) {
    final next = musicService.position + delta;
    final clamped = next < Duration.zero
        ? Duration.zero
        : musicService.duration > Duration.zero && next > musicService.duration
            ? musicService.duration
            : next;
    musicService.seekTo(clamped);
  }

  Widget _buildMetadata(Music? music, ThemeData theme) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final offset = Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offset, child: child),
        );
      },
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.centerLeft,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      child: Column(
        key: ValueKey(music?.id ?? 'none'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            music?.title ?? 'Unknown Video',
            style: TextStyle(
              fontSize: 36.sp,
              fontWeight: FontWeight.w900,
              color: theme.colorScheme.onSurface,
              height: 1.1,
              letterSpacing: 0,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 8.h),
          Text(
            music?.artist ?? 'Unknown Artist',
            style: TextStyle(
              fontSize: 20.sp,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withOpacity(0.5),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildControlsSection(
      MusicService musicService, ThemeData theme, CoverArtPalette palette) {
    return GlassContainer(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 18.h),
      borderRadius: BorderRadius.circular(24.s),
      color: null,
      blur: 8,
      child: Column(
        children: [
          PlaybackProgressControl(
            musicService: musicService,
            activeColor: theme.colorScheme.primary,
            inactiveColor: theme.colorScheme.onSurface.withOpacity(0.10),
            timeStyle: _timeStyle(theme),
          ),
          SizedBox(height: 20.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                iconSize: 22.s,
                icon: Icon(
                  musicService.isShuffle
                      ? Icons.shuffle_on_rounded
                      : Icons.shuffle_rounded,
                  color: musicService.isShuffle
                      ? palette.accent
                      : theme.colorScheme.onSurface.withOpacity(0.4),
                ),
                onPressed: musicService.toggleShuffle,
              ),
              IconButton(
                iconSize: 32.s,
                icon: const Icon(Icons.skip_previous_rounded),
                onPressed: musicService.previousTrack,
              ),
              ValueListenableBuilder<bool>(
                valueListenable: musicService.playingNotifier,
                builder: (context, isPlaying, child) {
                  return _SmoothPlayPauseButton(
                    isPlaying: isPlaying,
                    onPressed: musicService.togglePlayPause,
                    size: Size(72.s, 56.s),
                    iconSize: 34.s,
                  );
                },
              ),
              IconButton(
                iconSize: 32.s,
                icon: const Icon(Icons.skip_next_rounded),
                onPressed: musicService.next,
              ),
              IconButton(
                iconSize: 22.s,
                icon: Icon(
                  musicService.isRepeatOne
                      ? Icons.repeat_one_rounded
                      : Icons.repeat_rounded,
                  color: (musicService.isRepeatOne || musicService.isRepeatAll)
                      ? palette.accent
                      : theme.colorScheme.onSurface.withOpacity(0.4),
                ),
                onPressed: musicService.toggleRepeatMode,
              ),
            ],
          ),
          SizedBox(height: 20.h),
          Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                musicService.adjustVolumeBy(event.scrollDelta.dy < 0 ? 3 : -3);
              }
            },
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: ValueListenableBuilder<double>(
                valueListenable: musicService.volumeNotifier,
                builder: (context, volume, child) {
                  return Row(
                    children: [
                      Icon(
                        volume == 0
                            ? Icons.volume_off_rounded
                            : volume < 50
                                ? Icons.volume_down_rounded
                                : Icons.volume_up_rounded,
                        size: 20.s,
                        color: theme.colorScheme.onSurface.withOpacity(0.3),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 6.h,
                            thumbShape:
                                RoundSliderThumbShape(enabledThumbRadius: 6.s),
                            activeTrackColor:
                                theme.colorScheme.onSurface.withOpacity(0.28),
                            inactiveTrackColor:
                                theme.colorScheme.onSurface.withOpacity(0.10),
                            thumbColor:
                                theme.colorScheme.onSurface.withOpacity(0.48),
                            overlayColor:
                                theme.colorScheme.onSurface.withOpacity(0.08),
                          ),
                          child: Slider(
                            value: volume,
                            min: 0,
                            max: 100,
                            onChanged: (val) => musicService.setVolume(val),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 40.w,
                        child: Text(
                          '${volume.toInt()}%',
                          style: TextStyle(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface.withOpacity(0.3),
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          _buildYoutubeVideoTools(context, musicService, theme),
        ],
      ),
    );
  }

  Widget _buildYoutubeVideoTools(
    BuildContext context,
    MusicService musicService,
    ThemeData theme,
  ) {
    if (_youtubeVideoId.isEmpty && _youtubeStream == null) {
      return const SizedBox.shrink();
    }
    final qualityLabel = _youtubeStream?.qualityLabel ?? 'Auto';
    final subtitleCount = _youtubeStream?.subtitles.length ?? 0;

    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 10.h, 8.w, 0),
      child: Wrap(
        spacing: 8.w,
        runSpacing: 8.h,
        alignment: WrapAlignment.center,
        children: [
          ActionChip(
            avatar: _changingYoutubeQuality || _loadingYoutubeDetails
                ? SizedBox.square(
                    dimension: 16.s,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.high_quality_rounded),
            label: Text('Quality $qualityLabel'),
            onPressed: _youtubeStream == null
                ? null
                : () => _showQualitySheet(context, musicService),
          ),
          ActionChip(
            avatar: const Icon(Icons.subtitles_rounded),
            label: Text(
                subtitleCount == 0 ? 'Subtitles' : '$subtitleCount subtitles'),
            onPressed: () => _showSubtitleSheet(context, musicService),
          ),
          if (_youtubeMessage != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 8.h),
              child: Text(
                _youtubeMessage!,
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.62),
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickQueue(BuildContext context, MusicService musicService,
      ThemeData theme, CoverArtPalette palette) {
    final queue = musicService.queueMusicList;
    if (queue.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 8.w),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Next Tracks',
                style: TextStyle(
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface),
              ),
              TextButton(
                onPressed: () =>
                    _showQueueSheet(context, musicService, theme, palette),
                child: Text('Open Queue',
                    style: TextStyle(
                        color: palette.accent, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        SizedBox(height: 12.h),
        ...queue
            .skip(musicService.currentQueuePosition + 1)
            .take(3)
            .map((item) {
          return GlassContainer(
            margin: EdgeInsets.only(bottom: 12.h),
            padding: EdgeInsets.all(16.s),
            borderRadius: BorderRadius.circular(20.s),
            color: theme.colorScheme.onSurface.withOpacity(0.03),
            blur: 4,
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(Responsive.listArtRadius),
                  child: item.coverPath.startsWith('http://') ||
                          item.coverPath.startsWith('https://')
                      ? CoverArtTexture(
                          coverArtPath: item.coverPath,
                          width: Responsive.listArtSize,
                          height: Responsive.listArtSize,
                          borderRadius:
                              BorderRadius.circular(Responsive.listArtRadius),
                        )
                      : LanczosCoverArt(
                    coverArtPath: item.coverPath,
                    width: Responsive.listArtSize,
                    height: Responsive.listArtSize,
                    borderRadius:
                        BorderRadius.circular(Responsive.listArtRadius),
                  ),
                ),
                SizedBox(width: 16.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14.sp),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(item.artist,
                          style: TextStyle(
                              fontSize: 12.sp,
                              color:
                                  theme.colorScheme.onSurface.withOpacity(0.4)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                IconButton(
                    icon: const Icon(Icons.playlist_play_rounded, size: 20),
                    onPressed: () => musicService.playMusicFromQueue(
                        musicService.queueMusicList, item)),
              ],
            ),
          );
        }),
      ],
    );
  }

  TextStyle _timeStyle(ThemeData theme) {
    return TextStyle(
        fontSize: 12.sp,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurface.withOpacity(0.4));
  }

  void _showMoreOptions(BuildContext context, CoverArtPalette palette) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => GlassContainer(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        color: Theme.of(context).colorScheme.surface.withOpacity(0.85),
        blur: 10,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                  leading: const Icon(Icons.equalizer_rounded),
                  title: const Text('Audio Effects'),
                  onTap: () {
                    Navigator.pop(context);
                    showAudioEffectsMenu(context);
                  }),
              ListTile(
                  leading: const Icon(Icons.high_quality_rounded),
                  title: const Text('Video Quality'),
                  onTap: () {
                    Navigator.pop(context);
                    _showQualitySheet(context, context.read<MusicService>());
                  }),
              ListTile(
                  leading: const Icon(Icons.subtitles_rounded),
                  title: const Text('Subtitles'),
                  onTap: () {
                    Navigator.pop(context);
                    _showSubtitleSheet(context, context.read<MusicService>());
                  }),
              ListTile(
                  leading: const Icon(Icons.playlist_add_rounded),
                  title: const Text('Add to Playlist'),
                  onTap: () => Navigator.pop(context)),
              ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('Track Details'),
                  onTap: () => Navigator.pop(context)),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _showQualitySheet(BuildContext context, MusicService musicService) {
    final stream = _youtubeStream;
    if (stream == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('YouTube video quality is loading.')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        return DraggableScrollableSheet(
          initialChildSize: 0.52,
          minChildSize: 0.34,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, controller) => GlassContainer(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            color: theme.colorScheme.surface.withOpacity(0.92),
            blur: 10,
            child: SafeArea(
              top: false,
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const ListTile(
                    leading: Icon(Icons.high_quality_rounded),
                    title: Text('YouTube Quality'),
                    subtitle: Text('Q shortcut opens this menu'),
                  ),
                  ...stream.qualities.map((quality) {
                    final selected = quality.label == stream.qualityLabel;
                    final isYoutubeQuality = _youtubeVideoId.isNotEmpty;
                    final canStream = isYoutubeQuality
                        ? quality.streamable
                        : quality.hasAudio || !quality.url.startsWith('http');
                    return ListTile(
                      leading: Icon(selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded),
                      title: Text(quality.label),
                      subtitle: Text([
                        quality.ext.toUpperCase(),
                        if (isYoutubeQuality && !quality.streamable)
                          'download only'
                        else if (!quality.hasAudio && isYoutubeQuality)
                          'FFmpeg merge'
                        else if (!canStream)
                          'download only'
                      ].join(' - ')),
                      enabled: !_changingYoutubeQuality && canStream,
                      onTap: () {
                        Navigator.pop(context);
                        if (_youtubeVideoId.isEmpty) {
                          unawaited(
                              _changeLocalVideoQuality(musicService, quality));
                        } else {
                          unawaited(
                              _changeYoutubeQuality(musicService, quality));
                        }
                      },
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSubtitleSheet(BuildContext context, MusicService musicService) {
    final stream = _youtubeStream;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        return DraggableScrollableSheet(
          initialChildSize: 0.58,
          minChildSize: 0.36,
          maxChildSize: 0.94,
          expand: false,
          builder: (context, controller) => GlassContainer(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            color: theme.colorScheme.surface.withOpacity(0.92),
            blur: 10,
            child: SafeArea(
              top: false,
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const ListTile(
                    leading: Icon(Icons.subtitles_rounded),
                    title: Text('Subtitles'),
                    subtitle: Text('S shortcut opens this menu'),
                  ),
                  if (stream == null || stream.subtitles.isEmpty)
                    const ListTile(
                      title: Text('No YouTube subtitles found yet'),
                      subtitle: Text('Open a local subtitle file instead.'),
                    )
                  else
                    ...stream.subtitles.map((subtitle) {
                      return ListTile(
                        leading: Icon(subtitle.automatic
                            ? Icons.auto_awesome_rounded
                            : Icons.closed_caption_rounded),
                        title: Text(subtitle.label),
                        onTap: () async {
                          Navigator.pop(context);
                          if (await File(subtitle.url).exists()) {
                            await musicService.loadSubtitleFile(subtitle.url);
                          } else {
                            await musicService.loadSubtitleUrl(
                              subtitle.url,
                              title: subtitle.label,
                            );
                          }
                          if (mounted) {
                            setState(() =>
                                _youtubeMessage = 'Loaded ${subtitle.label}');
                          }
                        },
                      );
                    }),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.folder_open_rounded),
                    title: const Text('Open local subtitles'),
                    onTap: () {
                      Navigator.pop(context);
                      unawaited(_pickSubtitleFileFor(musicService));
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.subtitles_off_rounded),
                    title: const Text('Disable subtitles'),
                    onTap: () {
                      Navigator.pop(context);
                      unawaited(musicService.disableSubtitles());
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickSubtitleFileFor(MusicService musicService) async {
    final path = await pickFilePathSafely(
      context,
      allowedExtensions: const ['srt', 'vtt', 'ass', 'ssa'],
    );
    if (path == null || path.isEmpty) return;
    await musicService.loadSubtitleFile(path);
  }

  void _showQueueSheet(BuildContext context, MusicService musicService,
      ThemeData theme, CoverArtPalette palette) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) => GlassContainer(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          color: theme.colorScheme.surface.withOpacity(0.92),
          blur: 10,
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Up Next',
                            style: TextStyle(
                                fontSize: 24.sp, fontWeight: FontWeight.w900)),
                        Text('Drag tracks to reorder',
                            style: TextStyle(
                                fontSize: 12.sp,
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.5))),
                      ],
                    ),
                    const Spacer(),
                    IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context)),
                  ],
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  scrollController: controller,
                  buildDefaultDragHandles: false,
                  itemCount: musicService.queueMusicList.length,
                  padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 40.h),
                  onReorder: (oldIndex, newIndex) {
                    musicService.moveQueueItem(oldIndex, newIndex);
                  },
                  itemBuilder: (context, index) {
                    final item = musicService.queueMusicList[index];
                    final isCurrent = musicService.currentMusic?.id == item.id;

                    return GlassContainer(
                      key: ValueKey(item.id),
                      margin: EdgeInsets.only(bottom: 8.h),
                      padding:
                          EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                      borderRadius: BorderRadius.circular(16),
                      color: isCurrent
                          ? palette.accent.withOpacity(0.1)
                          : Colors.white.withOpacity(0.02),
                      blur: 2,
                      child: ListTile(
                        contentPadding: EdgeInsets.symmetric(horizontal: 12.w),
                        leading: ClipRRect(
                          borderRadius:
                              BorderRadius.circular(Responsive.listArtRadius),
                          child: SizedBox(
                            width: Responsive.listArtSize,
                            height: Responsive.listArtSize,
                  child: item.coverPath.startsWith('http://') ||
                          item.coverPath.startsWith('https://')
                      ? CoverArtTexture(
                          coverArtPath: item.coverPath,
                          width: Responsive.listArtSize,
                          height: Responsive.listArtSize,
                          borderRadius:
                              BorderRadius.circular(Responsive.listArtRadius),
                        )
                      : LanczosCoverArt(
                              coverArtPath: item.coverPath,
                              width: Responsive.listArtSize,
                              height: Responsive.listArtSize,
                              borderRadius:
                                  BorderRadius.circular(Responsive.listArtRadius),
                            ),
                          ),
                        ),
                        title: Text(
                          item.title,
                          style: TextStyle(
                            fontWeight:
                                isCurrent ? FontWeight.w900 : FontWeight.bold,
                            fontSize: 14.sp,
                            color: isCurrent ? palette.accent : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(item.artist,
                            style: TextStyle(fontSize: 12.sp)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isCurrent)
                              Icon(Icons.graphic_eq_rounded,
                                  color: palette.accent, size: 20),
                            const SizedBox(width: 8),
                            ReorderableDragStartListener(
                              index: index,
                              child: const Icon(Icons.drag_handle_rounded,
                                  color: Colors.white24),
                            ),
                          ],
                        ),
                        onTap: () => musicService.playMusicFromQueue(
                            musicService.queueMusicList, item),
                      ),
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
}

class _FullscreenVideoPage extends StatefulWidget {
  final MusicService musicService;
  final YoutubeMusicStream? youtubeStream;
  final String? youtubeMessage;
  final String surfaceKey;
  final bool isLoadingYoutubeDetails;
  final bool isChangingYoutubeQuality;
  final VoidCallback? onClose;
  final void Function(BuildContext context)? onShowQualityChoices;
  final void Function(BuildContext context)? onShowSubtitleChoices;

  const _FullscreenVideoPage({
    required this.musicService,
    required this.surfaceKey,
    this.youtubeStream,
    this.youtubeMessage,
    this.isLoadingYoutubeDetails = false,
    this.isChangingYoutubeQuality = false,
    this.onClose,
    this.onShowQualityChoices,
    this.onShowSubtitleChoices,
  });

  @override
  State<_FullscreenVideoPage> createState() => _FullscreenVideoPageState();
}

class _FullscreenVideoPageState extends State<_FullscreenVideoPage> {
  static const _overlayIdleDelay = Duration(milliseconds: 2400);

  double? _dragProgress;
  bool _controlsVisible = true;
  Timer? _overlayTimer;

  @override
  void initState() {
    super.initState();
    _scheduleOverlayHide();
  }

  @override
  void dispose() {
    _overlayTimer?.cancel();
    super.dispose();
  }

  void _showOverlay() {
    _overlayTimer?.cancel();
    if (!_controlsVisible && mounted) {
      setState(() => _controlsVisible = true);
    }
    _scheduleOverlayHide();
  }

  void _scheduleOverlayHide() {
    _overlayTimer?.cancel();
    _overlayTimer = Timer(_overlayIdleDelay, () {
      if (!mounted || _dragProgress != null) return;
      setState(() => _controlsVisible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.musicService.videoController;

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.space): _VideoTogglePlayIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft): _VideoSeekIntent(-1),
        SingleActivator(LogicalKeyboardKey.arrowRight): _VideoSeekIntent(1),
        SingleActivator(LogicalKeyboardKey.escape): _VideoFullscreenIntent(),
        SingleActivator(LogicalKeyboardKey.keyF): _VideoFullscreenIntent(),
        SingleActivator(LogicalKeyboardKey.keyQ): _VideoQualityIntent(),
        SingleActivator(LogicalKeyboardKey.keyS): _VideoSubtitlesIntent(),
        SingleActivator(LogicalKeyboardKey.keyN): _VideoNextIntent(),
        SingleActivator(LogicalKeyboardKey.keyP): _VideoPreviousIntent(),
        SingleActivator(LogicalKeyboardKey.keyB): _VideoPreviousIntent(),
        SingleActivator(LogicalKeyboardKey.keyR): _VideoRestartIntent(),
        SingleActivator(LogicalKeyboardKey.audioVolumeUp):
            _VideoVolumeIntent(5),
        SingleActivator(LogicalKeyboardKey.audioVolumeDown):
            _VideoVolumeIntent(-5),
        SingleActivator(LogicalKeyboardKey.audioVolumeMute): _VideoMuteIntent(),
        SingleActivator(LogicalKeyboardKey.equal): _VideoVolumeIntent(5),
        SingleActivator(LogicalKeyboardKey.minus): _VideoVolumeIntent(-5),
        SingleActivator(LogicalKeyboardKey.keyM): _VideoMuteIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _VideoTogglePlayIntent:
              CallbackAction<_VideoTogglePlayIntent>(onInvoke: (_) {
            widget.musicService.togglePlayPause();
            return null;
          }),
          _VideoSeekIntent: CallbackAction<_VideoSeekIntent>(
            onInvoke: (intent) {
              final settings = context.read<SettingsModel>();
              final next = widget.musicService.position +
                  Duration(
                    seconds: intent.direction * settings.seekStepSeconds,
                  );
              widget.musicService.seekTo(next < Duration.zero
                  ? Duration.zero
                  : widget.musicService.duration > Duration.zero &&
                          next > widget.musicService.duration
                      ? widget.musicService.duration
                      : next);
              return null;
            },
          ),
          _VideoFullscreenIntent:
              CallbackAction<_VideoFullscreenIntent>(onInvoke: (_) {
            _close();
            return null;
          }),
          _VideoQualityIntent: CallbackAction<_VideoQualityIntent>(
            onInvoke: (_) {
              widget.onShowQualityChoices?.call(context);
              return null;
            },
          ),
          _VideoSubtitlesIntent: CallbackAction<_VideoSubtitlesIntent>(
            onInvoke: (_) {
              final handler = widget.onShowSubtitleChoices;
              if (handler != null) {
                handler(context);
              } else {
                unawaited(_pickSubtitleFile());
              }
              return null;
            },
          ),
          _VideoNextIntent: CallbackAction<_VideoNextIntent>(onInvoke: (_) {
            widget.musicService.next();
            return null;
          }),
          _VideoPreviousIntent:
              CallbackAction<_VideoPreviousIntent>(onInvoke: (_) {
            widget.musicService.previousTrack();
            return null;
          }),
          _VideoRestartIntent:
              CallbackAction<_VideoRestartIntent>(onInvoke: (_) {
            widget.musicService.restartCurrentTrack();
            return null;
          }),
          _VideoVolumeIntent:
              CallbackAction<_VideoVolumeIntent>(onInvoke: (intent) {
            widget.musicService.adjustVolumeBy(intent.delta);
            return null;
          }),
          _VideoMuteIntent: CallbackAction<_VideoMuteIntent>(onInvoke: (_) {
            widget.musicService.toggleMute();
            return null;
          }),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: MouseRegion(
              cursor: _controlsVisible
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.none,
              onHover: (_) => _showOverlay(),
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => _showOverlay(),
                onPointerSignal: (_) => _showOverlay(),
                child: SafeArea(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (controller != null)
                        Center(
                          child: StableVideoSurface(
                            controller: controller,
                            surfaceKey: widget.surfaceKey,
                            fit: BoxFit.contain,
                          ),
                        ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _showOverlay,
                        onDoubleTap: _close,
                      ),
                      _buildQualityTransitionOverlay(),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: AnimatedOpacity(
                          opacity: _controlsVisible ? 1 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: IgnorePointer(
                            ignoring: !_controlsVisible,
                            child: IconButton(
                              tooltip: 'Close',
                              icon: const Icon(Icons.close_fullscreen_rounded,
                                  color: Colors.white),
                              onPressed: _close,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 12,
                        child: AnimatedSlide(
                          offset: _controlsVisible
                              ? Offset.zero
                              : const Offset(0, 0.18),
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          child: AnimatedOpacity(
                            opacity: _controlsVisible ? 1 : 0,
                            duration: const Duration(milliseconds: 180),
                            child: IgnorePointer(
                              ignoring: !_controlsVisible,
                              child: _buildControls(context),
                            ),
                          ),
                        ),
                      ),
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

  void _close() {
    final handler = widget.onClose;
    if (handler != null) {
      handler();
      return;
    }
    Navigator.of(context).pop();
  }

  Widget _buildControls(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.54),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white24, width: 0.7),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<Duration>(
            valueListenable: widget.musicService.durationNotifier,
            builder: (context, duration, _) {
              return ValueListenableBuilder<Duration>(
                valueListenable: widget.musicService.positionNotifier,
                builder: (context, position, _) {
                  final progress = _dragProgress ??
                      (duration.inMilliseconds <= 0
                          ? 0.0
                          : (position.inMilliseconds / duration.inMilliseconds)
                              .clamp(0.0, 1.0)
                              .toDouble());
                  final preview = Duration(
                    milliseconds: (progress * duration.inMilliseconds).round(),
                  );
                  return Column(
                    children: [
                      ExcludeSemantics(
                        excluding: true,
                        child: SliderTheme(
                          data: const SliderThemeData(
                            trackHeight: 4,
                            thumbShape:
                                RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape:
                                RoundSliderOverlayShape(overlayRadius: 14),
                            activeTrackColor: Colors.white,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: Colors.white,
                          ),
                          child: Slider(
                            value: progress,
                            min: 0,
                            max: 1,
                            onChanged: duration <= Duration.zero
                                ? null
                                : (value) {
                                    _showOverlay();
                                    setState(() {
                                      _dragProgress = value;
                                    });
                                  },
                            onChangeEnd: duration <= Duration.zero
                                ? null
                                : (value) {
                                    widget.musicService.seekTo(Duration(
                                      milliseconds:
                                          (value * duration.inMilliseconds)
                                              .round(),
                                    ));
                                    setState(() => _dragProgress = null);
                                    _scheduleOverlayHide();
                                  },
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Text(formatPlaybackDuration(preview),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                          const Spacer(),
                          Text(formatPlaybackDuration(duration),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
          ),
          Row(
            children: [
              IconButton(
                tooltip: 'Previous',
                icon: const Icon(Icons.skip_previous_rounded,
                    color: Colors.white),
                onPressed: widget.musicService.previousTrack,
              ),
              ValueListenableBuilder<bool>(
                valueListenable: widget.musicService.playingNotifier,
                builder: (context, isPlaying, _) {
                  return IconButton.filled(
                    tooltip: isPlaying ? 'Pause' : 'Play',
                    icon: Icon(isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded),
                    onPressed: widget.musicService.togglePlayPause,
                  );
                },
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Next',
                icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
                onPressed: widget.musicService.next,
              ),
              const SizedBox(width: 8),
              if (widget.youtubeStream != null) ...[
                _FullscreenToolButton(
                  tooltip: 'Quality',
                  icon: Icons.high_quality_rounded,
                  label: widget.isLoadingYoutubeDetails ||
                          widget.isChangingYoutubeQuality
                      ? 'Quality...'
                      : widget.youtubeStream!.qualityLabel,
                  onPressed: widget.onShowQualityChoices == null
                      ? null
                      : () => widget.onShowQualityChoices!(context),
                ),
                const SizedBox(width: 8),
              ],
              IconButton(
                tooltip: widget.youtubeStream == null
                    ? 'Open subtitles'
                    : 'Choose subtitles',
                icon: const Icon(Icons.subtitles_rounded, color: Colors.white),
                onPressed: widget.onShowSubtitleChoices == null
                    ? _pickSubtitleFile
                    : () => widget.onShowSubtitleChoices!(context),
              ),
              const Spacer(),
              Expanded(
                child: Text(
                  widget.youtubeMessage ??
                      widget.musicService.currentMusic?.title ??
                      '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQualityTransitionOverlay() {
    return AnimatedOpacity(
      opacity: widget.isChangingYoutubeQuality ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.28)),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.62),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24, width: 0.7),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    widget.youtubeMessage ?? 'Switching quality...',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
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

  Future<void> _pickSubtitleFile() async {
    final path = await pickFilePathSafely(
      context,
      allowedExtensions: const ['srt', 'vtt', 'ass', 'ssa'],
    );
    if (path == null || path.isEmpty) return;
    await widget.musicService.loadSubtitleFile(path);
  }
}

class _FullscreenToolButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _FullscreenToolButton({
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white.withOpacity(0.14),
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.white10,
          disabledForegroundColor: Colors.white38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: const Size(0, 42),
        ),
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _SmoothPlayPauseButton extends StatefulWidget {
  final bool isPlaying;
  final VoidCallback onPressed;
  final Size size;
  final double iconSize;

  const _SmoothPlayPauseButton({
    required this.isPlaying,
    required this.onPressed,
    required this.size,
    required this.iconSize,
  });

  @override
  State<_SmoothPlayPauseButton> createState() => _SmoothPlayPauseButtonState();
}

class _SmoothPlayPauseButtonState extends State<_SmoothPlayPauseButton> {
  bool? _optimisticIsPlaying;
  Timer? _optimisticTimer;

  bool get _visualIsPlaying => _optimisticIsPlaying ?? widget.isPlaying;

  @override
  void didUpdateWidget(covariant _SmoothPlayPauseButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_optimisticIsPlaying != null &&
        widget.isPlaying == _optimisticIsPlaying) {
      _clearOptimisticState();
    }
  }

  @override
  void dispose() {
    _optimisticTimer?.cancel();
    super.dispose();
  }

  void _clearOptimisticState() {
    _optimisticTimer?.cancel();
    _optimisticTimer = null;
    _optimisticIsPlaying = null;
  }

  void _handlePressed() {
    final nextVisualState = !_visualIsPlaying;
    _optimisticTimer?.cancel();
    setState(() => _optimisticIsPlaying = nextVisualState);
    _optimisticTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() => _optimisticIsPlaying = null);
      }
    });
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visualIsPlaying = _visualIsPlaying;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: visualIsPlaying ? 1 : 0),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.scale(
          scale: 0.98 + (value * 0.02),
          child: FilledButton(
            onPressed: _handlePressed,
            style: FilledButton.styleFrom(
              minimumSize: widget.size,
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20.s),
              ),
              backgroundColor: Color.lerp(
                theme.colorScheme.primaryContainer,
                theme.colorScheme.primary.withOpacity(0.24),
                value,
              ),
              foregroundColor: theme.colorScheme.onPrimaryContainer,
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final scale = Tween<double>(begin: 0.9, end: 1).animate(
                  CurvedAnimation(
                      parent: animation, curve: Curves.easeOutCubic),
                );
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: scale, child: child),
                );
              },
              child: Icon(
                visualIsPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                key: ValueKey(visualIsPlaying),
                size: widget.iconSize,
              ),
            ),
          ),
        );
      },
    );
  }
}
