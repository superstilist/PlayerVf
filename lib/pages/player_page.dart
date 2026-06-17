import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/music_model.dart';
import '../models/lyrics_model.dart';
import '../services/cover_color_service.dart';
import '../services/music_service.dart';
import '../services/listen_together_service.dart';
import '../widgets/listen_together_sheet.dart';
import '../services/performance_policy.dart';
import '../services/responsive.dart';
import '../services/safe_file_picker.dart';
import '../services/orb_controller.dart';
import '../services/screen_recording_service.dart';
import '../widgets/audio_effects_menu.dart';
import '../widgets/blurred_cover_background.dart';
import '../widgets/cover_art_texture.dart';
import '../widgets/lanczos_cover_art.dart';
import '../widgets/glass_container.dart';
import '../widgets/playback_progress_control.dart';
import '../widgets/stable_video_surface.dart';
import '../models/settings_model.dart';
import '../utils/romaji_kana_converter.dart';
import '../widgets/orb_system.dart';
import '../widgets/particle_system.dart';
import 'video_page.dart';

String? _lyricsOwnerKey(Music? music) {
  return music == null ? null : '${music.id}\n${music.filePath}';
}

class _PlayerTogglePlayIntent extends Intent {
  const _PlayerTogglePlayIntent();
}

class _PlayerNextIntent extends Intent {
  const _PlayerNextIntent();
}

class _PlayerPreviousIntent extends Intent {
  const _PlayerPreviousIntent();
}

class _PlayerVolumeIntent extends Intent {
  final double delta;

  const _PlayerVolumeIntent(this.delta);
}

class _PlayerMuteIntent extends Intent {
  const _PlayerMuteIntent();
}

class PlayerPage extends StatefulWidget {
  final VoidCallback onClose;
  final Animation<double>? routeAnimation;

  const PlayerPage({
    super.key,
    required this.onClose,
    this.routeAnimation,
  });

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  String _palettePath = '';
  bool _isLyricsSheetOpen = false;
  bool _isFullscreenVideoOpen = false;
  double _closeDragDistance = 0;
  CoverArtPalette _palette = CoverColorService.fallbackPalette;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = context.read<SettingsModel>();
    _syncPalette(context.read<MusicService>().currentMusic?.coverPath, settings.orbPaletteSize);
  }

  void _syncPalette(String? path, int paletteSize) {
    final normalized = path ?? '';
    final key = '$normalized::$paletteSize';
    if (key == _palettePath) return;
    _palettePath = key;
    CoverColorService.fromPath(normalized, paletteSize: paletteSize).then((p) {
      if (mounted) {
        setState(() => _palette = p);
        context.read<OrbController>().setColors(p.orbColors.isNotEmpty ? p.orbColors : [
          p.dominant,
          p.vibrant,
          p.accent,
          p.darkVibrant,
          p.lightVibrant,
        ]);
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final musicService = Provider.of<MusicService>(context);
    final settings = Provider.of<SettingsModel>(context);
    final policy = PerformancePolicy.of(context);
    final currentMusic = musicService.currentMusic;
    final isPhone = !Responsive.isTablet;
    final isShortPhone = isPhone && Responsive.screenHeight < 720;
    _syncPalette(currentMusic?.coverPath, settings.orbPaletteSize);

    final palette = _palette;

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.space):
            _PlayerTogglePlayIntent(),
        SingleActivator(LogicalKeyboardKey.mediaPlayPause):
            _PlayerTogglePlayIntent(),
        SingleActivator(LogicalKeyboardKey.mediaTrackNext):
            _PlayerNextIntent(),
        SingleActivator(LogicalKeyboardKey.mediaTrackPrevious):
            _PlayerPreviousIntent(),
        SingleActivator(LogicalKeyboardKey.audioVolumeUp):
            _PlayerVolumeIntent(5),
        SingleActivator(LogicalKeyboardKey.audioVolumeDown):
            _PlayerVolumeIntent(-5),
        SingleActivator(LogicalKeyboardKey.audioVolumeMute):
            _PlayerMuteIntent(),
        SingleActivator(LogicalKeyboardKey.equal): _PlayerVolumeIntent(5),
        SingleActivator(LogicalKeyboardKey.minus): _PlayerVolumeIntent(-5),
        SingleActivator(LogicalKeyboardKey.keyM): _PlayerMuteIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _PlayerTogglePlayIntent:
              CallbackAction<_PlayerTogglePlayIntent>(onInvoke: (_) {
            context.read<ListenTogetherService>().runPartyPlaybackCommand('toggle', musicService);
            return null;
          }),
          _PlayerNextIntent:
              CallbackAction<_PlayerNextIntent>(onInvoke: (_) {
            context.read<ListenTogetherService>().runPartyPlaybackCommand('next', musicService);
            return null;
          }),
          _PlayerPreviousIntent:
              CallbackAction<_PlayerPreviousIntent>(onInvoke: (_) {
            context.read<ListenTogetherService>().runPartyPlaybackCommand('previous', musicService);
            return null;
          }),
              _PlayerVolumeIntent:
                  CallbackAction<_PlayerVolumeIntent>(onInvoke: (intent) {
                musicService.adjustVolumeBy(intent.delta);
                return null;
              }),
              _PlayerMuteIntent:
                  CallbackAction<_PlayerMuteIntent>(onInvoke: (_) {
                musicService.toggleMute();
                return null;
              }),
            },
            child: Focus(
              autofocus: true,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragUpdate: (details) {
                  if (details.primaryDelta == null ||
                      details.primaryDelta! <= 0) {
                    return;
                  }
                  _closeDragDistance += details.primaryDelta!;
                },
                onVerticalDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  final shouldClose =
                      velocity > 700 || _closeDragDistance > 96.h;
                  _closeDragDistance = 0;
                  if (shouldClose) widget.onClose();
                },
                onVerticalDragCancel: () => _closeDragDistance = 0,
                  child: (() {
                    Widget scaffold = Scaffold(
                      backgroundColor: Colors.transparent,
                      body: Stack(
                        children: [
                          if (settings.backgroundMode == BackgroundMode.solidColor)
                            Container(color: theme.colorScheme.surface)
                          else if (settings.backgroundMode == BackgroundMode.customImage && settings.customBackgroundImage.isNotEmpty)
                            BlurredCoverBackground(
                              coverArtPath: settings.customBackgroundImage,
                              surfaceColor: theme.colorScheme.surface,
                              overlayColor: theme.colorScheme.surface.withOpacity(0.6),
                              blur: policy.backgroundBlur + 20,
                            )
                          else
                            BlurredCoverBackground(
                              coverArtPath: currentMusic?.coverPath ?? '',
                              surfaceColor: theme.colorScheme.surface,
                              overlayColor: theme.colorScheme.surface.withOpacity(0.6),
                              blur: policy.backgroundBlur + 20,
                            ),
                          IgnorePointer(
                            child: const OrbSystem(
                              paused: false,
                              intensity: 1.0,
                            ),
                          ),
                          if (settings.particleEffect != ParticleEffect.none &&
                              settings.particleEffect != ParticleEffect.coverArtShadowPoints)
                            IgnorePointer(
                              child: ValueListenableBuilder<bool>(
                                valueListenable: musicService.playingNotifier,
                                builder: (context, isPlaying, child) {
                                  return ParticleSystem(
                                    effect: settings.particleEffect,
                                    customPack: settings.customParticlePack,
                                    paused: !isPlaying,
                                    intensity: isPlaying ? 1.0 : 0.0,
                                  );
                                },
                              ),
                            ),
                      if (!isPhone)
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
                                  currentMusic?.title.toUpperCase() ??
                                      'PLAYERVF',
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
                                  horizontal: isPhone ? 18.w : 24.w,
                                  vertical: isShortPhone ? 6.h : 12.h,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(height: isShortPhone ? 2.h : 10.h),
                                    _buildHeroArtwork(currentMusic, palette,
                                        musicService, settings),
                                    SizedBox(
                                        height: isShortPhone ? 22.h : 42.h),
                                    _buildMetadata(currentMusic, theme),
                                    SizedBox(
                                        height: isShortPhone ? 24.h : 36.h),
                                    _buildControlsSection(
                                        musicService, theme, palette),
                                    SizedBox(
                                        height: isShortPhone ? 22.h : 32.h),
                                    _buildQuickQueue(
                                        context, musicService, theme, palette),
                                    SizedBox(
                                        height: isShortPhone ? 28.h : 40.h),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  );
                  if (widget.routeAnimation != null) {
                    scaffold = FadeTransition(
                      opacity: CurvedAnimation(
                        parent: widget.routeAnimation!,
                        curve: Curves.easeOutCubic,
                      ),
                      child: scaffold,
                    );
                  }
                  return scaffold;
                })(),
              ),
            ),
          ),
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
                music?.album.toUpperCase() ?? 'SINGLE',
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



  Widget _buildHeroArtwork(Music? music, CoverArtPalette palette,
      MusicService musicService, SettingsModel settings) {
    final mediaSize = MediaQuery.sizeOf(context);
    final maxByWidth = mediaSize.width - 48.w;
    final maxByHeight = mediaSize.height * (Responsive.isCompact ? 0.34 : 0.40);
    final size =
        320.s.clamp(210.0, maxByWidth.clamp(210.0, maxByHeight)).toDouble();
    final videoController = musicService.videoController;
    final shouldShowVideo =
        musicService.isCurrentMediaVideo && videoController != null;
    final canOpenFullscreen =
        shouldShowVideo && musicService.videoControllerReady;

    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 340),
            width: size * 0.9,
            height: size * 0.9,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 460),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale:
                      Tween<double>(begin: 0.96, end: 1.0).animate(animation),
                  child: child,
                ),
              );
            },
            child: Hero(
              key: ValueKey(music?.id ?? 'none'),
              tag: 'cover-art-${music?.id ?? 'none'}',
              child: GestureDetector(
                onTap: music == null || shouldShowVideo
                    ? null
                    : () => _showLyricsSheet(context, musicService),
                onDoubleTap: canOpenFullscreen
                    ? () => _openFullscreenVideo(musicService, music)
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
                    child: shouldShowVideo
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              if (!_isFullscreenVideoOpen)
                                StableVideoSurface(
                                  controller: videoController,
                                  surfaceKey:
                                      'player-video-${music?.id ?? 'current'}',
                                  fit: BoxFit.cover,
                                )
                              else
                                const ColoredBox(color: Colors.black),
                              if (!musicService.videoControllerReady)
                                CoverArtTexture(
                                  coverArtPath: music?.coverPath ?? '',
                                  width: double.infinity,
                                  height: double.infinity,
                                ),
                              if (canOpenFullscreen)
                                Positioned(
                                  right: 10.s,
                                  top: 10.s,
                                  child: IconButton.filled(
                                    tooltip: 'Fullscreen',
                                    icon: const Icon(
                                      Icons.fullscreen_rounded,
                                    ),
                                    onPressed: () => _openFullscreenVideo(
                                      musicService,
                                      music,
                                    ),
                                  ),
                                ),
                            ],
                          )
                        : CoverArtTexture(
                            coverArtPath: music?.coverPath ?? '',
                            width: double.infinity,
                            height: double.infinity,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openFullscreenVideo(
    MusicService musicService,
    Music? music,
  ) async {
    if (_isFullscreenVideoOpen || musicService.videoController == null) return;
    setState(() => _isFullscreenVideoOpen = true);
    await openVideoFullscreenOverlay(
      context: context,
      musicService: musicService,
      surfaceKey: 'player-full-${music?.id ?? 'current'}',
    );
    if (mounted) setState(() => _isFullscreenVideoOpen = false);
  }

  Widget _buildMetadata(Music? music, ThemeData theme) {
    final isPhone = !Responsive.isTablet;
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
          Hero(
            tag: 'title-${music?.id ?? 'none'}',
            child: Material(
              color: Colors.transparent,
              child: Text(
                music?.title ?? 'Unknown Track',
                style: TextStyle(
                  fontSize: (isPhone ? 30 : 36).sp,
                  fontWeight: FontWeight.w900,
                  color: theme.colorScheme.onSurface,
                  height: 1.1,
                  letterSpacing: 0,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.left,
              ),
            ),
          ),
          SizedBox(height: 8.h),
          Hero(
            tag: 'artist-${music?.id ?? 'none'}',
            child: Material(
              color: Colors.transparent,
              child: Text(
                music?.artist ?? 'Unknown Artist',
                style: TextStyle(
                  fontSize: (isPhone ? 17 : 20).sp,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.left,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsSection(
      MusicService musicService, ThemeData theme, CoverArtPalette palette) {
    final isPhone = !Responsive.isTablet;
    final isShortPhone = isPhone && Responsive.screenHeight < 720;
    return GlassContainer(
      padding: EdgeInsets.symmetric(
        horizontal: isPhone ? 10.w : 14.w,
        vertical: isShortPhone ? 12.h : 18.h,
      ),
      borderRadius: BorderRadius.circular(isPhone ? 20.s : 24.s),
      color: null,
      blur: isPhone ? 5 : 8,
      child: Column(
        children: [
          ValueListenableBuilder<Duration>(
            valueListenable: musicService.songGapRemainingNotifier,
            builder: (context, remaining, _) {
              if (remaining <= Duration.zero) return const SizedBox.shrink();
              return Padding(
                padding: EdgeInsets.only(bottom: 12.h),
                child: _SongGapCountdownPill(
                  remaining: remaining,
                  foreground: theme.colorScheme.onSurface,
                  background: theme.colorScheme.surfaceContainerHighest,
                ),
              );
            },
          ),
          PlaybackProgressControl(
            musicService: musicService,
            activeColor: theme.colorScheme.primary,
            inactiveColor: theme.colorScheme.onSurface.withOpacity(0.10),
            timeStyle: _timeStyle(theme),
          ),
          SizedBox(height: isShortPhone ? 12.h : 20.h),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  iconSize: 22.s,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
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
                Consumer<ListenTogetherService>(
                  builder: (context, party, _) {
                    final isActive = party.isPartyHosting || party.isPartyJoined;
                    return IconButton(
                      tooltip: 'Listen Together',
                      iconSize: 22.s,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        isActive ? Icons.groups_rounded : Icons.group_add_rounded,
                        color: isActive
                            ? palette.accent
                            : theme.colorScheme.onSurface.withOpacity(0.44),
                      ),
                      onPressed: party.isPartyBusy
                          ? null
                          : () => showListenTogetherSheet(context),
                    );
                  },
                ),
                IconButton(
                  iconSize: 32.s,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.skip_previous_rounded),
                  onPressed: () =>
                      context.read<ListenTogetherService>().runPartyPlaybackCommand('previous', musicService),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: musicService.playingNotifier,
                  builder: (context, isPlaying, child) {
                    return _SmoothPlayPauseButton(
                      isPlaying: isPlaying,
                      onPressed: () =>
                          context.read<ListenTogetherService>().runPartyPlaybackCommand('toggle', musicService),
                      size: Size((isPhone ? 66 : 72).s, (isPhone ? 52 : 56).s),
                      iconSize: (isPhone ? 31 : 34).s,
                    );
                  },
                ),
                IconButton(
                  iconSize: 32.s,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.skip_next_rounded),
                  onPressed: () => context.read<ListenTogetherService>().runPartyPlaybackCommand('next', musicService),
                ),
                IconButton(
                  iconSize: 22.s,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
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
                IconButton(
                  tooltip: 'Audio Effects',
                  iconSize: 22.s,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    Icons.tune_rounded,
                    color: theme.colorScheme.onSurface.withOpacity(0.44),
                  ),
                  onPressed: () => showAudioEffectsMenu(context),
                ),
              ],
            ),
          ),
          SizedBox(height: isShortPhone ? 8.h : 20.h),
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
        ],
      ),
    );
  }

  Widget _buildQuickQueue(BuildContext context, MusicService musicService,
      ThemeData theme, CoverArtPalette palette) {
    final queue = musicService.queueMusicList;
    if (queue.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
            .take(!Responsive.isTablet ? 3 : 5)
            .map((item) {
          return GlassContainer(
            margin: EdgeInsets.only(bottom: 8.h),
            padding: EdgeInsets.symmetric(horizontal: 12.s, vertical: 8.s),
            borderRadius: BorderRadius.circular(16.s),
            color: theme.colorScheme.onSurface.withOpacity(0.03),
            blur: 4,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(Responsive.listArtRadius),
                  child: SizedBox(
                    width: Responsive.listArtSize,
                    height: Responsive.listArtSize,
                    child: LanczosCoverArt(
                      coverArtPath: item.coverPath,
                      width: Responsive.listArtSize,
                      height: Responsive.listArtSize,
                      borderRadius:
                          BorderRadius.circular(Responsive.listArtRadius),
                    ),
                  ),
                ),
                SizedBox(width: 14.w),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14.sp),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      SizedBox(height: 2.h),
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
                SizedBox(width: 6.w),
                IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
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
    final musicService = context.read<MusicService>();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => GlassContainer(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        color: Theme.of(sheetContext).colorScheme.surface.withOpacity(0.85),
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
                    Navigator.pop(sheetContext);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) showAudioEffectsMenu(context);
                    });
                  }),
              ListTile(
                  leading: const Icon(Icons.playlist_add_rounded),
                  title: const Text('Add to Playlist'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        _showAddCurrentTrackToPlaylistDialog(
                            context, musicService);
                      }
                    });
                  }),
              ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('Track Details'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _showCurrentTrackDetails(context);
                    });
                  }),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddCurrentTrackToPlaylistDialog(
      BuildContext context, MusicService musicService) {
    final music = musicService.currentMusic;
    if (music == null) {
      _showPlayerSnack(context, 'No track selected.');
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: GlassContainer(
          width: 320,
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Add to Playlist',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (musicService.playlists.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Text('No playlists available.'),
                )
              else
                ...musicService.playlists.map(
                  (playlist) => ListTile(
                    leading: const Icon(Icons.playlist_play_rounded),
                    title: Text(playlist.name),
                    subtitle: Text('${playlist.musicIds.length} tracks'),
                    onTap: () {
                      musicService.addMusicToPlaylist(playlist.id, music.id);
                      Navigator.pop(dialogContext);
                      _showPlayerSnack(context, 'Added to ${playlist.name}.');
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCurrentTrackDetails(BuildContext context) {
    final music = context.read<MusicService>().currentMusic;
    if (music == null) {
      _showPlayerSnack(context, 'No track selected.');
      return;
    }

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
                    child: AspectRatio(
                      aspectRatio: 1.0,
                      child: CoverArtTexture(
                        coverArtPath: music.coverPath,
                        width: double.infinity,
                        height: double.infinity,
                      ),
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
              _buildTrackDetailRow('Album', music.album),
              _buildTrackDetailRow('Genre', music.genre),
              _buildTrackDetailRow(
                'Year',
                music.year.trim().isEmpty ? 'Unknown' : music.year,
              ),
              _buildTrackDetailRow(
                  'Duration', _formatTrackDuration(music.duration)),
              _buildTrackDetailRow('Play count', music.playCount.toString()),
              _buildTrackDetailRow('File', music.filePath, maxLines: 2),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrackDetailRow(
    String label,
    String value, {
    int maxLines = 1,
  }) {
    final cleanValue = value.trim().isEmpty ? 'Unknown' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              cleanValue,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
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

  void _showPlayerSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
                            child: LanczosCoverArt(
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

  Future<void> _showLyricsSheet(
      BuildContext context, MusicService musicService) async {
    if (_isLyricsSheetOpen) return;
    _isLyricsSheetOpen = true;
    final initialLyricsKey = _lyricsOwnerKey(musicService.currentMusic);
    final lyrics =
        await musicService.loadLyricsDocumentForCurrent(searchOnline: false);
    if (!context.mounted) {
      _isLyricsSheetOpen = false;
      return;
    }
    final currentLyricsKey = _lyricsOwnerKey(musicService.currentMusic);
    final initialLyrics = initialLyricsKey == currentLyricsKey ? lyrics : null;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: Responsive.isTablet ? 0.72 : 0.68,
        minChildSize: Responsive.isTablet ? 0.42 : 0.36,
        maxChildSize: Responsive.isTablet ? 0.92 : 0.88,
        builder: (_, controller) => _LyricsSheetContent(
          musicService: musicService,
          initialLyrics: initialLyrics,
          initialLyricsKey: initialLyrics == null ? null : initialLyricsKey,
          scrollController: controller,
          pickLyricsFile: _pickLyricsFile,
        ),
      ),
    );
    if (mounted) _isLyricsSheetOpen = false;
  }

  Future<String?> _pickLyricsFile() async {
    return pickFilePathSafely(
      context,
      allowedExtensions: const ['lrc', 'txt', 'lyrics'],
    );
  }
}

class _LyricsSheetContent extends StatefulWidget {
  final MusicService musicService;
  final LyricsDocument? initialLyrics;
  final String? initialLyricsKey;
  final ScrollController scrollController;
  final Future<String?> Function() pickLyricsFile;

  const _LyricsSheetContent({
    required this.musicService,
    required this.initialLyrics,
    required this.initialLyricsKey,
    required this.scrollController,
    required this.pickLyricsFile,
  });

  @override
  State<_LyricsSheetContent> createState() => _LyricsSheetContentState();
}

class _LyricsSheetContentState extends State<_LyricsSheetContent> {
  late LyricsDocument? _lyrics = widget.initialLyrics;
  String? _trackKey;
  String? _lyricsKey;
  int _lastActiveIndex = -1;
  bool _isSearchingLyrics = false;
  final Map<int, GlobalKey> _lineKeys = {};

  @override
  void initState() {
    super.initState();
    _trackKey = _currentLyricsKey;
    _lyricsKey =
        widget.initialLyricsKey == _trackKey ? widget.initialLyricsKey : null;
    if (_lyricsKey == null) _lyrics = null;
    widget.musicService.addListener(_handleMusicServiceChanged);
    if (_lyrics == null || _lyrics!.lines.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchLyrics(showResultMessage: false);
      });
    }
  }

  @override
  void dispose() {
    widget.musicService.removeListener(_handleMusicServiceChanged);
    super.dispose();
  }

  String? get _currentLyricsKey =>
      _lyricsOwnerKey(widget.musicService.currentMusic);

  void _handleMusicServiceChanged() {
    final nextTrackKey = _currentLyricsKey;
    if (nextTrackKey == _trackKey) return;
    _trackKey = nextTrackKey;
    _lastActiveIndex = -1;
    _lineKeys.clear();
    setState(() {
      _lyrics = null;
      _lyricsKey = null;
    });
    unawaited(_reloadLyricsForCurrentTrack());
  }

  Future<void> _reloadLyricsForCurrentTrack() async {
    final expectedTrackKey = _currentLyricsKey;
    final loaded = await widget.musicService
        .loadLyricsDocumentForCurrent(searchOnline: false);
    if (!mounted || expectedTrackKey != _currentLyricsKey) {
      return;
    }
    setState(() {
      _lyrics = loaded;
      _lyricsKey = loaded == null ? null : expectedTrackKey;
    });
    if (loaded == null || loaded.lines.isEmpty) {
      await _searchLyrics(showResultMessage: false, trackKey: expectedTrackKey);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleLyrics = _lyricsKey == _trackKey ? _lyrics : null;
    final generateKanaLyrics =
        context.watch<SettingsModel>().generateKanaLyrics;
    final isPhone = !Responsive.isTablet;
    final sheetColor = theme.colorScheme.surface.withOpacity(
      theme.brightness == Brightness.dark
          ? (isPhone ? 0.98 : 0.92)
          : (isPhone ? 0.99 : 0.94),
    );

    return SafeArea(
      top: true,
      bottom: true,
      child: GlassContainer(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        color: sheetColor,
        blur: isPhone ? 6 : 10,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            isPhone ? 16.w : 22,
            14,
            isPhone ? 16.w : 22,
            isPhone ? 16 : 24,
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              if (isPhone)
                _buildCompactLyricsHeader(theme, visibleLyrics)
              else
                _buildWideLyricsHeader(theme, visibleLyrics),
              const SizedBox(height: 8),
              Expanded(
                child: visibleLyrics == null || visibleLyrics.lines.isEmpty
                    ? Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10.w),
                          child: Text(
                            'No lyrics found. Edit lyrics, open an .lrc/.txt file, or let auto search try online.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ),
                      )
                    : visibleLyrics.hasTimedLines
                        ? _buildTimedLyrics(
                            theme,
                            visibleLyrics,
                            generateKanaLyrics,
                          )
                        : SingleChildScrollView(
                            controller: widget.scrollController,
                            child: _buildPlainLyricsText(
                              visibleLyrics,
                              generateKanaLyrics,
                              TextStyle(fontSize: 18.sp, height: 1.55),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWideLyricsHeader(ThemeData theme, LyricsDocument? lyrics) {
    return Row(
      children: [
        Expanded(
          child: Text(
            widget.musicService.currentMusic?.title ?? 'Lyrics',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 22.sp,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        _buildLyricsActions(theme, lyrics),
      ],
    );
  }

  Widget _buildCompactLyricsHeader(ThemeData theme, LyricsDocument? lyrics) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.musicService.currentMusic?.title ?? 'Lyrics',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 20.sp,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 8.h),
        Align(
          alignment: Alignment.centerRight,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: _buildLyricsActions(theme, lyrics),
          ),
        ),
      ],
    );
  }

  Widget _buildLyricsActions(ThemeData theme, LyricsDocument? lyrics) {
    final hasLyrics = lyrics != null && lyrics.lines.isNotEmpty;
    final iconSize = Responsive.isTablet ? 24.0 : 22.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Edit timed lyrics',
          icon: Icon(Icons.edit_note_rounded, size: iconSize),
          onPressed: _editLyrics,
        ),
        IconButton(
          tooltip: 'Open fullscreen lyrics',
          icon: Icon(Icons.fullscreen_rounded, size: iconSize),
          onPressed: hasLyrics ? _openFullscreenLyrics : null,
        ),
        IconButton(
          tooltip: 'Shift lyric timing',
          icon: Icon(Icons.more_time_rounded, size: iconSize),
          onPressed:
              hasLyrics && lyrics.hasTimedLines ? _shiftLyricsTiming : null,
        ),
        IconButton(
          tooltip: 'Search lyrics',
          icon: _isSearchingLyrics
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                )
              : Icon(Icons.manage_search_rounded, size: iconSize),
          onPressed: _isSearchingLyrics ? null : _searchLyrics,
        ),
        IconButton(
          tooltip: 'Custom lyrics search',
          icon: Icon(Icons.tune_rounded, size: iconSize),
          onPressed: _isSearchingLyrics ? null : _searchLyricsWithCustomInput,
        ),
        IconButton(
          tooltip: 'Open lyrics file',
          icon: Icon(Icons.file_open_rounded, size: iconSize),
          onPressed: _openLyricsFile,
        ),
      ],
    );
  }

  Widget _buildTimedLyrics(
    ThemeData theme,
    LyricsDocument lyrics,
    bool generateKanaLyrics,
  ) {
    return ValueListenableBuilder<Duration>(
      valueListenable: widget.musicService.positionNotifier,
      builder: (context, position, _) {
        final activeIndex = lyrics.activeIndexAt(position);
        _scrollActiveLineIntoView(activeIndex);
        return LayoutBuilder(
          builder: (context, constraints) {
            final verticalPadding =
                (constraints.maxHeight * 0.34).clamp(72.0, 150.0).toDouble();
            return ListView.builder(
              controller: widget.scrollController,
              padding: EdgeInsets.symmetric(vertical: verticalPadding),
              itemCount: lyrics.lines.length,
              itemBuilder: (context, index) {
                final line = lyrics.lines[index];
                final isActive = index == activeIndex;
                final isNear = (index - activeIndex).abs() == 1;
                final color = isActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface
                        .withOpacity(isNear ? 0.72 : 0.38);
                return AnimatedContainer(
                  key: _lineKeys.putIfAbsent(index, GlobalKey.new),
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.symmetric(
                    horizontal: isActive ? 6.w : 0,
                    vertical: isActive ? 14.h : 9.h,
                  ),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: color,
                      fontSize: isActive ? 23.sp : 18.sp,
                      height: 1.25,
                      fontWeight: isActive ? FontWeight.w900 : FontWeight.w600,
                    ),
                    child: _buildGeneratedKanaLine(
                      text: line.text,
                      generateKana: generateKanaLyrics,
                      generatedStyle: TextStyle(
                        color: color.withOpacity(isActive ? 0.76 : 0.62),
                        fontSize: isActive ? 15.sp : 13.sp,
                        height: 1.22,
                        fontWeight:
                            isActive ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _scrollActiveLineIntoView(int activeIndex) {
    if (activeIndex < 0 || activeIndex == _lastActiveIndex) return;
    _lastActiveIndex = activeIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.scrollController.hasClients) return;
      final lineContext = _lineKeys[activeIndex]?.currentContext;
      if (lineContext != null) {
        Scrollable.ensureVisible(
          lineContext,
          alignment: 0.48,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
        );
        return;
      }
      final viewport = widget.scrollController.position.viewportDimension;
      const estimatedLineExtent = 62.0;
      final target = ((activeIndex * estimatedLineExtent) -
              (viewport / 2) +
              (estimatedLineExtent / 2))
          .clamp(0.0, widget.scrollController.position.maxScrollExtent);
      widget.scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Widget _buildPlainLyricsText(
    LyricsDocument lyrics,
    bool generateKanaLyrics,
    TextStyle style,
  ) {
    if (!generateKanaLyrics) {
      return Text(lyrics.plainText, style: style);
    }

    return Text.rich(
      TextSpan(
        style: style,
        children: _plainLyricsKanaSpans(lyrics, style),
      ),
    );
  }

  List<InlineSpan> _plainLyricsKanaSpans(
      LyricsDocument lyrics, TextStyle style) {
    final spans = <InlineSpan>[];
    for (final line in lyrics.lines) {
      final text = line.text.trim();
      if (text.isEmpty) continue;
      final romaji = RomajiKanaConverter.generatedRomajiForLine(text);
      spans.add(TextSpan(text: text));
      if (romaji.isNotEmpty) {
        spans.add(TextSpan(
          text: '\n$romaji',
          style: style.copyWith(
            fontSize: (style.fontSize ?? 18) * 0.76,
            fontWeight: FontWeight.w600,
            color: (style.color ?? Theme.of(context).colorScheme.onSurface)
                .withOpacity(0.68),
          ),
        ));
      }
      spans.add(const TextSpan(text: '\n'));
    }
    if (spans.isNotEmpty) spans.removeLast();
    return spans;
  }

  Widget _buildGeneratedKanaLine({
    required String text,
    required bool generateKana,
    required TextStyle generatedStyle,
  }) {
    if (!generateKana) return Text(text);
    final romaji = RomajiKanaConverter.generatedRomajiForLine(text);
    if (romaji.isEmpty) return Text(text);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text),
        const SizedBox(height: 4),
        Text(romaji, style: generatedStyle),
      ],
    );
  }

  Future<void> _openLyricsFile() async {
    final picked = await widget.pickLyricsFile();
    if (picked == null) return;
    final expectedTrackKey = _currentLyricsKey;
    final loaded = await widget.musicService
        .loadLyricsDocumentForCurrent(explicitPath: picked);
    if (!mounted || expectedTrackKey != _currentLyricsKey) {
      return;
    }
    setState(() {
      _lyrics = loaded;
      _lyricsKey = loaded == null ? null : expectedTrackKey;
    });
  }

  Future<void> _shiftLyricsTiming() async {
    final visibleLyrics = _lyricsKey == _trackKey ? _lyrics : null;
    if (visibleLyrics == null || !visibleLyrics.hasTimedLines) return;

    await _showLyricsTimingShiftSheet();
  }

  Future<bool> _applyLyricsTimingOffset(Duration offset) async {
    if (offset == Duration.zero) return false;
    final visibleLyrics = _lyricsKey == _trackKey ? _lyrics : null;
    if (visibleLyrics == null || !visibleLyrics.hasTimedLines) return false;

    final expectedTrackKey = _currentLyricsKey;
    await widget.musicService.keepOriginalLyricsTimingForCurrent(
      visibleLyrics.rawText,
    );
    final shiftedRaw = LyricsDocument.shiftRawTimestamps(
      visibleLyrics.rawText,
      offset,
    );
    final saved = await widget.musicService.saveLyricsForCurrent(shiftedRaw);
    if (!mounted || expectedTrackKey != _currentLyricsKey || saved == null) {
      return false;
    }

    setState(() {
      _lyrics = saved;
      _lyricsKey = expectedTrackKey;
      _lastActiveIndex = -1;
      _lineKeys.clear();
    });
    _showLyricsShiftMessage(offset);
    return true;
  }

  Future<bool> _resetOriginalLyricsTiming() async {
    final expectedTrackKey = _currentLyricsKey;
    final restored =
        await widget.musicService.restoreOriginalLyricsTimingForCurrent();
    if (!mounted || expectedTrackKey != _currentLyricsKey || restored == null) {
      return false;
    }

    setState(() {
      _lyrics = restored;
      _lyricsKey = expectedTrackKey;
      _lastActiveIndex = -1;
      _lineKeys.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Original lyric timing restored.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return true;
  }

  Future<void> _showLyricsTimingShiftSheet() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LyricsTimingShiftSheet(
        onShift: _applyLyricsTimingOffset,
        onReset: _resetOriginalLyricsTiming,
      ),
    );
  }

  void _showLyricsShiftMessage(Duration offset) {
    final milliseconds = offset.inMilliseconds;
    final direction = milliseconds >= 0 ? 'forward' : 'back';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Lyrics moved $direction ${milliseconds.abs()} ms.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openFullscreenLyrics() {
    final lyrics = _lyrics;
    if (lyrics == null || lyrics.lines.isEmpty || _lyricsKey != _trackKey) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullscreenLyricsPage(
          musicService: widget.musicService,
          lyrics: lyrics,
          lyricsKey: _lyricsKey,
        ),
      ),
    );
  }

  Future<void> _searchLyrics({
    bool showResultMessage = true,
    String? trackKey,
  }) async {
    final expectedTrackKey = trackKey ?? _currentLyricsKey;
    setState(() => _isSearchingLyrics = true);
    final found = await widget.musicService.searchLyricsForCurrentOnline();
    if (!mounted || expectedTrackKey != _currentLyricsKey) {
      if (mounted) setState(() => _isSearchingLyrics = false);
      return;
    }
    setState(() {
      _lyrics = found;
      _lyricsKey = found == null ? null : expectedTrackKey;
      _isSearchingLyrics = false;
    });
    if (showResultMessage) _showLyricsSearchMessage(found != null);
  }

  Future<void> _searchLyricsWithCustomInput() async {
    final music = widget.musicService.currentMusic;
    final duration = music?.duration ?? widget.musicService.duration;
    final params = await showModalBottomSheet<_LyricsSearchParameters?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LyricsSearchInputSheet(
        title: music?.title ?? '',
        artist: music?.artist ?? '',
        album: music?.album ?? '',
        durationSeconds: duration > Duration.zero ? duration.inSeconds : null,
      ),
    );

    if (params == null) return;

    setState(() => _isSearchingLyrics = true);
    final results = await widget.musicService.searchLyricsResultsForCurrent(
      title: params.title,
      artist: params.artist,
      album: params.album,
      durationSeconds: params.durationSeconds,
    );
    if (!mounted) {
      return;
    }
    setState(() => _isSearchingLyrics = false);
    if (results.isEmpty) {
      _showLyricsSearchMessage(false);
      return;
    }

    final selected = await _showLyricsSearchResults(results);
    if (selected == null) return;

    final expectedTrackKey = _currentLyricsKey;
    setState(() => _isSearchingLyrics = true);
    final found =
        await widget.musicService.saveLyricsResultForCurrent(selected);
    if (!mounted || expectedTrackKey != _currentLyricsKey) {
      if (mounted) setState(() => _isSearchingLyrics = false);
      return;
    }
    setState(() {
      _lyrics = found;
      _lyricsKey = found == null ? null : expectedTrackKey;
      _isSearchingLyrics = false;
    });
    _showLyricsSearchMessage(found != null);
  }

  Future<LrclibLyrics?> _showLyricsSearchResults(
    List<LrclibLyrics> results,
  ) {
    return showModalBottomSheet<LrclibLyrics>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.62,
        minChildSize: 0.38,
        maxChildSize: 0.88,
        builder: (_, controller) => GlassContainer(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          color: Theme.of(context).colorScheme.surface.withOpacity(0.96),
          blur: 8,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Choose Lyrics',
                        style: TextStyle(
                          fontSize: 20.sp,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    controller: controller,
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final result = results[index];
                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        tileColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withOpacity(0.42),
                        title: Text(
                          result.trackName ?? 'Unknown title',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          [
                            result.artistName ?? 'Unknown artist',
                            if (result.albumName?.trim().isNotEmpty == true)
                              result.albumName!,
                            if (result.durationSeconds != null)
                              _formatLyricsDuration(result.durationSeconds!),
                          ].join(' • '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Wrap(
                          spacing: 6,
                          children: [
                            if (result.hasSyncedLyrics)
                              const Chip(
                                label: Text('Sync'),
                                visualDensity: VisualDensity.compact,
                              ),
                            if (result.hasPlainLyrics)
                              const Chip(
                                label: Text('Plain'),
                                visualDensity: VisualDensity.compact,
                              ),
                          ],
                        ),
                        onTap: () => Navigator.pop(context, result),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatLyricsDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }

  void _showLyricsSearchMessage(bool found) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(found ? 'Lyrics saved.' : 'No lyrics found.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _editLyrics() async {
    final expectedTrackKey = _currentLyricsKey;
    final visibleLyrics = _lyricsKey == _trackKey ? _lyrics : null;
    final controller = TextEditingController(
      text: visibleLyrics?.rawText ??
          await widget.musicService.editableLyricsForCurrent(),
    );
    if (!mounted) return;
    final saved = await showModalBottomSheet<LyricsDocument?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: GlassContainer(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          color: Theme.of(context).colorScheme.surface.withOpacity(0.96),
          blur: 8,
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.78,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Edit Lyrics',
                          style: TextStyle(
                            fontSize: 20.sp,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () async {
                          final document = await widget.musicService
                              .saveLyricsForCurrent(controller.text);
                          if (context.mounted) {
                            Navigator.pop(context, document);
                          }
                        },
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        hintText:
                            '[00:12.50] First lyric line\n[00:18.00] Next lyric line',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    controller.dispose();
    if (saved != null && mounted && expectedTrackKey == _currentLyricsKey) {
      setState(() {
        _lyrics = saved;
        _lyricsKey = expectedTrackKey;
      });
    }
  }
}

class _FullscreenLyricsPage extends StatefulWidget {
  final MusicService musicService;
  final LyricsDocument lyrics;
  final String? lyricsKey;

  const _FullscreenLyricsPage({
    required this.musicService,
    required this.lyrics,
    required this.lyricsKey,
  });

  @override
  State<_FullscreenLyricsPage> createState() => _FullscreenLyricsPageState();
}

enum _LyricsLayoutTarget { header, lyrics, controls, visual }

enum _LyricsEditHitZone { tiny, compact, touch }

class _LyricsLayeredObject {
  final int layer;
  final Widget child;

  const _LyricsLayeredObject({
    required this.layer,
    required this.child,
  });
}

class _LyricsVisualDraftItem {
  String id;
  String path;
  bool show;
  Offset offset;
  double scale;
  double rotation;
  int layer;
  double opacity;

  _LyricsVisualDraftItem({
    required this.id,
    required this.path,
    required this.show,
    required this.offset,
    required this.scale,
    required this.rotation,
    required this.layer,
    required this.opacity,
  });

  factory _LyricsVisualDraftItem.fromSettings(
    LyricsFullscreenVisualItem item,
  ) {
    return _LyricsVisualDraftItem(
      id: item.id,
      path: item.path,
      show: item.show,
      offset: Offset(item.offsetX, item.offsetY),
      scale: item.scale,
      rotation: item.rotation,
      layer: item.layer,
      opacity: item.opacity,
    );
  }

  LyricsFullscreenVisualItem toSettingsItem() {
    return LyricsFullscreenVisualItem(
      id: id,
      path: path,
      show: show,
      offsetX: offset.dx,
      offsetY: offset.dy,
      scale: scale,
      rotation: rotation,
      layer: layer,
      opacity: opacity,
    ).sanitized();
  }
}

class _LyricsLayoutDraft {
  Color textColor;
  LyricsFullscreenPosition position;
  bool showCover;
  bool showTrackName;
  bool showControls;
  bool showProgress;
  double fontScale;
  double dimBackground;
  LyricsFullscreenHeaderPosition headerPosition;
  LyricsFullscreenCoverStyle coverStyle;
  bool customLayout;
  Offset lyricsOffset;
  Offset headerOffset;
  Offset controlsOffset;
  double headerScale;
  double lyricsScale;
  double controlsScale;
  double headerRotation;
  double lyricsRotation;
  double controlsRotation;
  LyricsFullscreenFontPreset fontPreset;
  LyricsFullscreenHeaderStyle headerStyle;
  LyricsFullscreenControlsStyle controlsStyle;
  LyricsFullscreenSpecialEffect specialEffect;
  LyricsFullscreenParticlePack particlePack;
  String customParticlePack;
  int headerLayer;
  int lyricsLayer;
  int controlsLayer;
  List<_LyricsVisualDraftItem> visualItems;
  int selectedVisualIndex;

  _LyricsLayoutDraft({
    required this.textColor,
    required this.position,
    required this.showCover,
    required this.showTrackName,
    required this.showControls,
    required this.showProgress,
    required this.fontScale,
    required this.dimBackground,
    required this.headerPosition,
    required this.coverStyle,
    required this.customLayout,
    required this.lyricsOffset,
    required this.headerOffset,
    required this.controlsOffset,
    required this.headerScale,
    required this.lyricsScale,
    required this.controlsScale,
    required this.headerRotation,
    required this.lyricsRotation,
    required this.controlsRotation,
    required this.fontPreset,
    required this.headerStyle,
    required this.controlsStyle,
    required this.specialEffect,
    required this.particlePack,
    required this.customParticlePack,
    required this.headerLayer,
    required this.lyricsLayer,
    required this.controlsLayer,
    required this.visualItems,
    required this.selectedVisualIndex,
  });

  factory _LyricsLayoutDraft.fromSettings(SettingsModel settings) {
    return _LyricsLayoutDraft(
      textColor: settings.lyricsFullscreenTextColor,
      position: settings.lyricsFullscreenPosition,
      showCover: settings.lyricsFullscreenShowCover,
      showTrackName: settings.lyricsFullscreenShowTrackName,
      showControls: settings.lyricsFullscreenShowControls,
      showProgress: settings.lyricsFullscreenShowProgress,
      fontScale: settings.lyricsFullscreenFontScale,
      dimBackground: settings.lyricsFullscreenDimBackground,
      headerPosition: settings.lyricsFullscreenHeaderPosition,
      coverStyle: settings.lyricsFullscreenCoverStyle,
      customLayout: settings.lyricsFullscreenCustomLayout,
      lyricsOffset: Offset(settings.lyricsFullscreenLyricsOffsetX,
          settings.lyricsFullscreenLyricsOffsetY),
      headerOffset: Offset(settings.lyricsFullscreenHeaderOffsetX,
          settings.lyricsFullscreenHeaderOffsetY),
      controlsOffset: Offset(settings.lyricsFullscreenControlsOffsetX,
          settings.lyricsFullscreenControlsOffsetY),
      headerScale: settings.lyricsFullscreenHeaderScale,
      lyricsScale: settings.lyricsFullscreenLyricsScale,
      controlsScale: settings.lyricsFullscreenControlsScale,
      headerRotation: settings.lyricsFullscreenHeaderRotation,
      lyricsRotation: settings.lyricsFullscreenLyricsRotation,
      controlsRotation: settings.lyricsFullscreenControlsRotation,
      fontPreset: settings.lyricsFullscreenFontPreset,
      headerStyle: settings.lyricsFullscreenHeaderStyle,
      controlsStyle: settings.lyricsFullscreenControlsStyle,
      specialEffect: settings.lyricsFullscreenSpecialEffect,
      particlePack: settings.lyricsFullscreenParticlePack,
      customParticlePack: settings.lyricsFullscreenCustomParticlePack,
      headerLayer: settings.lyricsFullscreenHeaderLayer,
      lyricsLayer: settings.lyricsFullscreenLyricsLayer,
      controlsLayer: settings.lyricsFullscreenControlsLayer,
      visualItems: _visualDraftItemsFromSettings(settings),
      selectedVisualIndex: 0,
    );
  }

  void resetTransforms() {
    customLayout = true;
    lyricsOffset = Offset.zero;
    headerOffset = Offset.zero;
    controlsOffset = Offset.zero;
    headerScale = 1;
    lyricsScale = 1;
    controlsScale = 1;
    headerRotation = 0;
    lyricsRotation = 0;
    controlsRotation = 0;
    for (final item in visualItems) {
      item.scale = 1;
      item.rotation = 0;
      item.offset = const Offset(0, -40);
    }
  }

  bool get hasAnyVisual =>
      visualItems.any((item) => item.show && item.path.trim().isNotEmpty);

  _LyricsVisualDraftItem? get selectedVisual {
    if (visualItems.isEmpty) return null;
    selectedVisualIndex = selectedVisualIndex.clamp(0, visualItems.length - 1);
    return visualItems[selectedVisualIndex];
  }

  static List<_LyricsVisualDraftItem> _visualDraftItemsFromSettings(
    SettingsModel settings,
  ) {
    final items = settings.lyricsFullscreenVisualItems
        .map(_LyricsVisualDraftItem.fromSettings)
        .toList(growable: true);
    if (items.isEmpty &&
        settings.lyricsFullscreenVisualPath.trim().isNotEmpty) {
      items.add(_LyricsVisualDraftItem(
        id: 'visual_legacy',
        path: settings.lyricsFullscreenVisualPath,
        show: settings.lyricsFullscreenShowVisual,
        offset: Offset(settings.lyricsFullscreenVisualOffsetX,
            settings.lyricsFullscreenVisualOffsetY),
        scale: settings.lyricsFullscreenVisualScale,
        rotation: settings.lyricsFullscreenVisualRotation,
        layer: settings.lyricsFullscreenVisualLayer,
        opacity: settings.lyricsFullscreenVisualOpacity,
      ));
    }
    return items;
  }
}

class _FullscreenLyricsPageState extends State<_FullscreenLyricsPage> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _lineKeys = {};
  final GlobalKey _recordCanvasKey = GlobalKey();
  final ScreenRecordingService _recordingService = ScreenRecordingService();
  final TextEditingController _recordTrimStartController =
      TextEditingController(text: '0:00');
  final TextEditingController _recordTrimEndController =
      TextEditingController();
  late LyricsDocument _lyrics = widget.lyrics;
  String? _trackKey;
  String? _lyricsKey;
  int _lastActiveIndex = -1;
  bool _isLayoutEditing = false;
  bool _editPanelOpen = true;
  bool _fullscreenUiVisible = true;
  bool _recordPanelOpen = false;
  bool _isPreparingRecording = false;
  bool _isRecordingLyrics = false;
  bool _recordTrimMode = false;
  bool _recordFadeVisible = false;
  Timer? _fullscreenUiHideTimer;
  Timer? _recordingWatchTimer;
  Timer? _mobileRecordFrameTimer;
  _LyricsLayoutTarget _editTarget = _LyricsLayoutTarget.lyrics;
  final _LyricsEditHitZone _editHitZone = _LyricsEditHitZone.compact;
  _LyricsLayoutDraft? _layoutDraft;
  double _gestureStartScale = 1.0;
  double _gestureStartRotation = 0.0;
  int _recordCountdown = 0;
  Duration _recordTrimStart = Duration.zero;
  Duration? _recordTrimEnd;
  Duration? _activeRecordEnd;
  String? _recordStatus;
  String? _lastRecordingPath;
  double? _recordOriginalVolume;
  int _recordVolumeFadeGeneration = 0;
  bool _isCapturingRecordFrame = false;
  bool _recordingOrientationLocked = false;

  static const List<Color> _lyricsTextColors = [
    Colors.white,
    Color(0xFFE0F2FE),
    Color(0xFFD1FAE5),
    Color(0xFFFEF3C7),
    Color(0xFFFCE7F3),
    Color(0xFFEDE9FE),
    Color(0xFFFFEDD5),
    Color(0xFFCBD5E1),
  ];

  @override
  void initState() {
    super.initState();
    _trackKey = _currentLyricsKey;
    _lyricsKey = widget.lyricsKey == _trackKey ? widget.lyricsKey : null;
    if (_lyricsKey == null) _lyrics = LyricsDocument.parse('', source: 'empty');
    widget.musicService.addListener(_handleMusicServiceChanged);
    _allowFullscreenAutoOrientation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleFullscreenUiHide();
    });
  }

  @override
  void dispose() {
    _fullscreenUiHideTimer?.cancel();
    _recordingWatchTimer?.cancel();
    _mobileRecordFrameTimer?.cancel();
    _restoreSystemOrientation();
    _restoreRecordingVolume();
    unawaited(_recordingService.stop());
    widget.musicService.removeListener(_handleMusicServiceChanged);
    _recordTrimStartController.dispose();
    _recordTrimEndController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String? get _currentLyricsKey =>
      _lyricsOwnerKey(widget.musicService.currentMusic);

  void _handleMusicServiceChanged() {
    final nextTrackKey = _currentLyricsKey;
    if (nextTrackKey == _trackKey) return;
    _trackKey = nextTrackKey;
    _lastActiveIndex = -1;
    setState(() {
      _lyrics = LyricsDocument.parse('', source: 'empty');
      _lyricsKey = null;
    });
    _revealFullscreenUi();
    _jumpLyricsToTop();
    unawaited(_reloadLyricsForCurrentTrack(nextTrackKey));
  }

  Future<void> _reloadLyricsForCurrentTrack(String? expectedTrackKey) async {
    final loaded = await widget.musicService
        .loadLyricsDocumentForCurrent(searchOnline: false);
    if (!mounted || expectedTrackKey != _currentLyricsKey) {
      return;
    }
    if (loaded != null && loaded.lines.isNotEmpty) {
      setState(() {
        _lyrics = loaded;
        _lyricsKey = expectedTrackKey;
      });
      _jumpLyricsToTop();
      return;
    }

    final searched = await widget.musicService.searchLyricsForCurrentOnline();
    if (!mounted || expectedTrackKey != _currentLyricsKey) {
      return;
    }
    setState(() {
      _lyrics = searched ?? LyricsDocument.parse('', source: 'empty');
      _lyricsKey = searched == null ? null : expectedTrackKey;
    });
    _jumpLyricsToTop();
  }

  void _jumpLyricsToTop() {
    _lineKeys.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(0);
    });
  }

  void _revealFullscreenUi() {
    if (!mounted) return;
    if (!_fullscreenUiVisible) {
      setState(() => _fullscreenUiVisible = true);
    }
    _scheduleFullscreenUiHide();
  }

  void _scheduleFullscreenUiHide() {
    _fullscreenUiHideTimer?.cancel();
    if (_isLayoutEditing) return;
    _fullscreenUiHideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _isLayoutEditing) return;
      setState(() => _fullscreenUiVisible = false);
    });
  }

  void _allowFullscreenAutoOrientation() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    unawaited(SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]));
  }

  Future<void> _lockRecordingOrientationForCurrentScreen() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final size = MediaQuery.sizeOf(context);
    final orientations = size.height > size.width
        ? const [
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
          ]
        : const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ];
    await SystemChrome.setPreferredOrientations(orientations);
    _recordingOrientationLocked = true;
  }

  Future<void> _restoreFullscreenOrientation() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _recordingOrientationLocked = false;
  }

  void _restoreSystemOrientation() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    unawaited(SystemChrome.setPreferredOrientations(const []));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final music = widget.musicService.currentMusic;
    final visibleLyrics = _lyricsKey == _trackKey
        ? _lyrics
        : LyricsDocument.parse('', source: 'empty');
    final settings = context.watch<SettingsModel>();
    final layout = _isLayoutEditing
        ? (_layoutDraft ?? _LyricsLayoutDraft.fromSettings(settings))
        : _LyricsLayoutDraft.fromSettings(settings);
    final generateKanaLyrics = settings.generateKanaLyrics;
    final mediaPadding = MediaQuery.paddingOf(context);
    final topInset = mediaPadding.top.clamp(0.0, 42.0).toDouble();

    return Scaffold(
      backgroundColor: Colors.black,
      body: MouseRegion(
        onHover: (_) => _revealFullscreenUi(),
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _revealFullscreenUi(),
          onPointerMove: (_) => _revealFullscreenUi(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              RepaintBoundary(
                key: _recordCanvasKey,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    BlurredCoverBackground(
                      coverArtPath: music?.coverPath ?? '',
                      surfaceColor: Colors.black,
                      overlayColor:
                          Colors.black.withOpacity(layout.dimBackground),
                      blur: 34,
                    ),
                    if (layout.specialEffect ==
                        LyricsFullscreenSpecialEffect.particles)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: _FullscreenLyricsParticleField(
                            accentColor: settings.accentColor,
                            textColor: layout.textColor,
                            pack: layout.particlePack,
                            customPack: layout.customParticlePack,
                          ),
                        ),
                      ),
                    SafeArea(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                            22, 14 + topInset * 0.35, 22, 22),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final objects = <_LyricsLayeredObject>[
                              if (_isLayoutEditing || layout.hasAnyVisual)
                                for (var visualIndex = 0;
                                    visualIndex < layout.visualItems.length;
                                    visualIndex++)
                                  if (_isLayoutEditing ||
                                      (layout.visualItems[visualIndex].show &&
                                          layout.visualItems[visualIndex].path
                                              .trim()
                                              .isNotEmpty))
                                    _LyricsLayeredObject(
                                      layer:
                                          layout.visualItems[visualIndex].layer,
                                      child: Positioned.fill(
                                        child: Align(
                                          alignment: Alignment.center,
                                          child: _layoutEditableObject(
                                            settings: settings,
                                            layout: layout,
                                            target: _LyricsLayoutTarget.visual,
                                            offset: layout
                                                .visualItems[visualIndex]
                                                .offset,
                                            scale: layout
                                                .visualItems[visualIndex].scale,
                                            rotation: layout
                                                .visualItems[visualIndex]
                                                .rotation,
                                            selectedOverride: _isLayoutEditing &&
                                                _editTarget ==
                                                    _LyricsLayoutTarget
                                                        .visual &&
                                                layout.selectedVisualIndex ==
                                                    visualIndex,
                                            onSelect: () => _selectVisual(
                                                layout, visualIndex),
                                            child:
                                                _buildFullscreenVisualOverlay(
                                              theme,
                                              layout.visualItems[visualIndex],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                              if (layout.showCover || layout.showTrackName)
                                _LyricsLayeredObject(
                                  layer: layout.headerLayer,
                                  child: Positioned.fill(
                                    child: Align(
                                      alignment:
                                          _fullscreenHeaderSceneAlignment(
                                              layout),
                                      child: _layoutEditableObject(
                                        settings: settings,
                                        layout: layout,
                                        target: _LyricsLayoutTarget.header,
                                        offset: layout.headerOffset,
                                        scale: layout.headerScale,
                                        rotation: layout.headerRotation,
                                        child: _buildFullscreenHeader(
                                            theme, music, settings, layout),
                                      ),
                                    ),
                                  ),
                                ),
                              _LyricsLayeredObject(
                                layer: layout.lyricsLayer,
                                child: Positioned.fill(
                                  child: Align(
                                    alignment: Alignment.center,
                                    child: SizedBox(
                                      width: constraints.maxWidth,
                                      height: _fullscreenLyricsAutoHeight(
                                        constraints,
                                        layout,
                                      ),
                                      child: _layoutEditableObject(
                                        settings: settings,
                                        layout: layout,
                                        target: _LyricsLayoutTarget.lyrics,
                                        offset: layout.lyricsOffset,
                                        scale: layout.lyricsScale,
                                        rotation: layout.lyricsRotation,
                                        child: AnimatedSwitcher(
                                          duration:
                                              const Duration(milliseconds: 260),
                                          child: visibleLyrics.lines.isEmpty
                                              ? _buildEmptyLyrics(layout)
                                              : visibleLyrics.hasTimedLines
                                                  ? _buildTimedLyrics(
                                                      visibleLyrics,
                                                      generateKanaLyrics,
                                                      layout,
                                                    )
                                                  : _buildPlainLyrics(
                                                      visibleLyrics,
                                                      generateKanaLyrics,
                                                      layout,
                                                    ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (layout.showProgress || layout.showControls)
                                _LyricsLayeredObject(
                                  layer: layout.controlsLayer,
                                  child: Positioned.fill(
                                    child: Align(
                                      alignment: Alignment.bottomCenter,
                                      child: IgnorePointer(
                                        ignoring: !_isLayoutEditing &&
                                            !_fullscreenUiVisible,
                                        child: AnimatedSlide(
                                          duration:
                                              const Duration(milliseconds: 260),
                                          curve: Curves.easeOutCubic,
                                          offset: (_isLayoutEditing ||
                                                  _fullscreenUiVisible)
                                              ? Offset.zero
                                              : const Offset(0, 0.32),
                                          child: AnimatedOpacity(
                                            duration: const Duration(
                                                milliseconds: 220),
                                            curve: Curves.easeOutCubic,
                                            opacity: (_isLayoutEditing ||
                                                    _fullscreenUiVisible)
                                                ? 1
                                                : 0,
                                            child: _layoutEditableObject(
                                              settings: settings,
                                              layout: layout,
                                              target:
                                                  _LyricsLayoutTarget.controls,
                                              offset: layout.controlsOffset,
                                              scale: layout.controlsScale,
                                              rotation: layout.controlsRotation,
                                              child:
                                                  _buildFullscreenBottomControls(
                                                      theme, settings, layout),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ]..sort((a, b) => a.layer.compareTo(b.layer));
                            return Stack(
                              clipBehavior: Clip.none,
                              fit: StackFit.expand,
                              children: [
                                for (final object in objects) object.child
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                    _buildRecordingFadeOverlay(),
                  ],
                ),
              ),
              if (!_isLayoutEditing && !_isRecordingLyrics)
                _buildFullscreenChrome(settings),
              if (_recordPanelOpen && !_isLayoutEditing && !_isRecordingLyrics)
                _buildLyricsRecordingPanel(theme, settings),
              if (_recordCountdown > 0)
                _buildLyricsRecordingHud(theme, settings),
              if (_isLayoutEditing)
                _buildEditPanel(context, theme, settings, layout),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFullscreenChrome(SettingsModel settings) {
    return Positioned(
      top: 10,
      right: 12,
      child: SafeArea(
        child: IgnorePointer(
          ignoring: !_fullscreenUiVisible,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            offset: _fullscreenUiVisible ? Offset.zero : const Offset(0, -0.42),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              opacity: _fullscreenUiVisible ? 1 : 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Record lyrics video',
                    iconSize: 18,
                    style: IconButton.styleFrom(
                      backgroundColor: _isRecordingLyrics
                          ? Colors.redAccent.withOpacity(0.90)
                          : Colors.black.withOpacity(0.34),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(34, 34),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () => setState(() {
                      _recordPanelOpen = !_recordPanelOpen;
                      _fullscreenUiVisible = true;
                    }),
                    icon: Icon(_isRecordingLyrics
                        ? Icons.stop_circle_rounded
                        : Icons.fiber_manual_record_rounded),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Edit fullscreen lyrics',
                    iconSize: 18,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withOpacity(0.34),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(34, 34),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () => _enterLayoutEdit(settings),
                    icon: const Icon(Icons.edit_rounded),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Close',
                    iconSize: 20,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withOpacity(0.34),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(34, 34),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLyricsRecordingPanel(
    ThemeData theme,
    SettingsModel settings,
  ) {
    final music = widget.musicService.currentMusic;
    final duration = _recordingDuration;
    final position = widget.musicService.positionNotifier.value;
    final trimEnd = _recordTrimEnd ?? duration;
    final hasDuration = duration > Duration.zero;

    return Positioned(
      left: 14,
      top: 62,
      child: SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: ColoredBox(
              color: theme.colorScheme.surface.withOpacity(0.92),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.video_camera_back_rounded,
                          color: settings.accentColor,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Record Mode',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () =>
                              setState(() => _recordPanelOpen = false),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      music == null
                          ? 'No song loaded.'
                          : '${music.title} - ${music.artist}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.72),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FutureBuilder<String?>(
                      future: _recordingService.availabilityMessage(),
                      builder: (context, snapshot) {
                        final message = snapshot.data;
                        if (message == null) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _recordInfoBox(theme, message),
                        );
                      },
                    ),
                    _buildRecordSavePathRow(theme, settings),
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Record only trim episode',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      value: _recordTrimMode,
                      onChanged: _isPreparingRecording || _isRecordingLyrics
                          ? null
                          : (value) => setState(() => _recordTrimMode = value),
                    ),
                    if (_recordTrimMode) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: _recordTimeField(
                              theme: theme,
                              controller: _recordTrimStartController,
                              label: 'Start time',
                              enabled:
                                  !_isPreparingRecording && !_isRecordingLyrics,
                              onSubmitted: (value) =>
                                  _applyRecordTimecode(value, isStart: true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _recordTimeField(
                              theme: theme,
                              controller: _recordTrimEndController,
                              label: 'End time',
                              hint: _formatRecordDuration(duration),
                              enabled:
                                  !_isPreparingRecording && !_isRecordingLyrics,
                              onSubmitted: (value) =>
                                  _applyRecordTimecode(value, isStart: false),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: hasDuration &&
                                      !_isPreparingRecording &&
                                      !_isRecordingLyrics
                                  ? () => setState(() {
                                        _recordTrimStart =
                                            _boundedRecordPosition(position);
                                        _recordTrimStartController.text =
                                            _formatRecordDuration(
                                                _recordTrimStart);
                                        if (_recordTrimEnd != null &&
                                            _recordTrimEnd! <=
                                                _recordTrimStart) {
                                          _recordTrimEnd = duration;
                                          _recordTrimEndController.text =
                                              _formatRecordDuration(duration);
                                        }
                                      })
                                  : null,
                              icon: const Icon(Icons.first_page_rounded),
                              label: Text(
                                  'Start ${_formatRecordDuration(_recordTrimStart)}'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: hasDuration &&
                                      !_isPreparingRecording &&
                                      !_isRecordingLyrics
                                  ? () => setState(() {
                                        final next =
                                            _boundedRecordPosition(position);
                                        _recordTrimEnd =
                                            next <= _recordTrimStart
                                                ? duration
                                                : next;
                                        _recordTrimEndController.text =
                                            _formatRecordDuration(
                                                _recordTrimEnd!);
                                      })
                                  : null,
                              icon: const Icon(Icons.last_page_rounded),
                              label:
                                  Text('End ${_formatRecordDuration(trimEnd)}'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Current ${_formatRecordDuration(position)} / ${_formatRecordDuration(duration)}',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withOpacity(0.62),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (_recordStatus != null) ...[
                      const SizedBox(height: 10),
                      _recordInfoBox(theme, _recordStatus!),
                    ],
                    if (_lastRecordingPath != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _lastRecordingPath!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isPreparingRecording
                            ? null
                            : _isRecordingLyrics
                                ? _stopLyricsRecording
                                : () => _startLyricsRecording(
                                    trim: _recordTrimMode),
                        icon: Icon(_isRecordingLyrics
                            ? Icons.stop_rounded
                            : Icons.fiber_manual_record_rounded),
                        label: Text(_isRecordingLyrics
                            ? 'Stop recording'
                            : _recordTrimMode
                                ? 'Record trim'
                                : 'Record full song'),
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

  Widget _buildRecordSavePathRow(
    ThemeData theme,
    SettingsModel settings,
  ) {
    final path = settings.recordingSavePath.trim();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.46),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.10)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
        child: Row(
          children: [
            Icon(
              Icons.folder_rounded,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                path.isEmpty ? 'Default recording folder' : path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.74),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TextButton(
              onPressed: _isPreparingRecording || _isRecordingLyrics
                  ? null
                  : () => _pickRecordingSavePathFromLyrics(settings),
              child: const Text('Change'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recordInfoBox(ThemeData theme, String message) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.68),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(
          message,
          style: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.72),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _recordTimeField({
    required ThemeData theme,
    required TextEditingController controller,
    required String label,
    required bool enabled,
    required ValueChanged<String> onSubmitted,
    String? hint,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.datetime,
      textInputAction: TextInputAction.done,
      onSubmitted: onSubmitted,
      onEditingComplete: () => onSubmitted(controller.text),
      style: const TextStyle(fontWeight: FontWeight.w800),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        hintText: hint ?? '0:00',
        helperText: 'm:ss',
        prefixIcon: const Icon(Icons.timer_rounded),
        suffixIcon: IconButton(
          tooltip: 'Apply time',
          icon: const Icon(Icons.check_rounded),
          onPressed: enabled ? () => onSubmitted(controller.text) : null,
        ),
      ),
    );
  }

  Widget _buildLyricsRecordingHud(
    ThemeData theme,
    SettingsModel settings,
  ) {
    final label = _recordCountdown > 0
        ? 'Starting in $_recordCountdown'
        : 'REC ${_formatRecordDuration(widget.musicService.positionNotifier.value)}';
    return Positioned(
      top: 74,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: EdgeInsets.symmetric(
              horizontal: _recordCountdown > 0 ? 24 : 14,
              vertical: _recordCountdown > 0 ? 14 : 8,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.56),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: (_recordCountdown > 0
                        ? settings.accentColor
                        : Colors.redAccent)
                    .withOpacity(0.72),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.32),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: _recordCountdown > 0 ? 24 : 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecordingFadeOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _recordFadeVisible ? 1 : 0,
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeInOutCubic,
          child: const ColoredBox(color: Colors.black),
        ),
      ),
    );
  }

  Duration get _recordingDuration {
    final notifierDuration = widget.musicService.durationNotifier.value;
    final musicDuration = widget.musicService.currentMusic?.duration;
    if (notifierDuration > Duration.zero) return notifierDuration;
    return musicDuration ?? Duration.zero;
  }

  Duration _boundedRecordPosition(Duration value) {
    final duration = _recordingDuration;
    if (duration <= Duration.zero) return value;
    return Duration(
      milliseconds: value.inMilliseconds.clamp(0, duration.inMilliseconds),
    );
  }

  void _applyRecordTimecode(String value, {required bool isStart}) {
    final parsed = _parseRecordTimecode(value);
    if (parsed == null) {
      setState(() => _recordStatus =
          'Use time like 1:23, 01:02:03, 83s, or milliseconds.');
      return;
    }
    final duration = _recordingDuration;
    final bounded = _boundedRecordPosition(parsed);
    setState(() {
      if (isStart) {
        _recordTrimStart = bounded;
        _recordTrimStartController.text = _formatRecordDuration(bounded);
        if (_recordTrimEnd != null && _recordTrimEnd! <= _recordTrimStart) {
          _recordTrimEnd = duration > bounded ? duration : null;
          _recordTrimEndController.text = _recordTrimEnd == null
              ? ''
              : _formatRecordDuration(_recordTrimEnd!);
        }
      } else {
        _recordTrimEnd =
            bounded <= _recordTrimStart && duration > _recordTrimStart
                ? duration
                : bounded;
        _recordTrimEndController.text = _formatRecordDuration(_recordTrimEnd!);
      }
      _recordStatus = null;
    });
  }

  bool _applyRecordTrimFields() {
    final startText = _recordTrimStartController.text.trim();
    final endText = _recordTrimEndController.text.trim();
    final parsedStart =
        startText.isEmpty ? Duration.zero : _parseRecordTimecode(startText);
    final parsedEnd =
        endText.isEmpty ? _recordingDuration : _parseRecordTimecode(endText);
    if (parsedStart == null || parsedEnd == null) {
      setState(() => _recordStatus =
          'Trim time is invalid. Use 1:23, 01:02:03, 83s, or milliseconds.');
      return false;
    }
    final start = _boundedRecordPosition(parsedStart);
    final end = _boundedRecordPosition(parsedEnd);
    if (end <= start + const Duration(seconds: 1)) {
      setState(() => _recordStatus = 'Trim end must be after start.');
      return false;
    }
    setState(() {
      _recordTrimStart = start;
      _recordTrimEnd = end;
      _recordTrimStartController.text = _formatRecordDuration(start);
      _recordTrimEndController.text = _formatRecordDuration(end);
      _recordStatus = null;
    });
    return true;
  }

  Duration? _parseRecordTimecode(String raw) {
    final value = raw.trim().toLowerCase().replaceAll(',', '.');
    if (value.isEmpty) return null;

    final suffixMatch = RegExp(r'^(\d+(?:\.\d+)?)(ms|s|m)$').firstMatch(value);
    if (suffixMatch != null) {
      final number = double.tryParse(suffixMatch.group(1)!);
      if (number == null) return null;
      return switch (suffixMatch.group(2)) {
        'ms' => Duration(milliseconds: number.round()),
        's' => Duration(milliseconds: (number * 1000).round()),
        'm' => Duration(milliseconds: (number * 60000).round()),
        _ => null,
      };
    }

    if (!value.contains(':')) {
      final number = double.tryParse(value);
      if (number == null) return null;
      if (number >= 1000 && !value.contains('.')) {
        return Duration(milliseconds: number.round());
      }
      return Duration(milliseconds: (number * 1000).round());
    }

    final parts = value.split(':');
    if (parts.length < 2 || parts.length > 3) return null;
    final seconds = double.tryParse(parts.last);
    final minutes = int.tryParse(parts[parts.length - 2]);
    final hours = parts.length == 3 ? int.tryParse(parts.first) : 0;
    if (seconds == null || minutes == null || hours == null) return null;
    if (minutes < 0 || seconds < 0 || seconds >= 60) return null;
    return Duration(
      hours: hours,
      minutes: minutes,
      milliseconds: (seconds * 1000).round(),
    );
  }

  void _captureRecordingVolume() {
    _recordOriginalVolume ??= widget.musicService.volumeNotifier.value;
  }

  Future<void> _fadeRecordingVolumeTo(
    double target, {
    Duration duration = const Duration(milliseconds: 600),
  }) async {
    final generation = ++_recordVolumeFadeGeneration;
    final from = widget.musicService.volumeNotifier.value;
    final to = target.clamp(0.0, 100.0).toDouble();
    if ((from - to).abs() < 0.5 || duration <= Duration.zero) {
      widget.musicService.setVolume(to);
      return;
    }

    const steps = 14;
    final stepDelay = Duration(
      milliseconds: math.max(12, duration.inMilliseconds ~/ steps),
    );
    for (var i = 1; i <= steps; i++) {
      if (!mounted || generation != _recordVolumeFadeGeneration) return;
      final t = i / steps;
      final eased = t * t * (3 - (2 * t));
      widget.musicService.setVolume(from + ((to - from) * eased));
      await Future<void>.delayed(stepDelay);
    }
  }

  void _restoreRecordingVolume() {
    final original = _recordOriginalVolume;
    _recordOriginalVolume = null;
    _recordVolumeFadeGeneration++;
    if (original != null) {
      widget.musicService.setVolume(original);
    }
  }

  bool get _usesMobileFrameRecorder => Platform.isAndroid || Platform.isIOS;
  bool get _usesFlutterFrameRecorder => Platform.isIOS;

  double _mobileNativeRefreshRate() {
    if (!_usesMobileFrameRecorder) return 60.0;
    final refreshRate = View.of(context).display.refreshRate;
    if (!refreshRate.isFinite || refreshRate <= 0) return 60.0;
    return refreshRate.clamp(24.0, 120.0).toDouble();
  }

  void _startMobileFrameCapture(double nativeFrameRate) {
    if (!_usesFlutterFrameRecorder) return;
    _mobileRecordFrameTimer?.cancel();
    final safeFrameRate = nativeFrameRate.clamp(24.0, 120.0).toDouble();
    final frameDelay = Duration(
      microseconds: math.max(8000, (1000000 / safeFrameRate).round()),
    );
    _mobileRecordFrameTimer = Timer.periodic(frameDelay, (_) {
      unawaited(_captureMobileRecordFrame());
    });
    unawaited(_captureMobileRecordFrame());
  }

  Future<void> _captureMobileRecordFrame() async {
    if (_isCapturingRecordFrame || !_usesFlutterFrameRecorder) return;
    _isCapturingRecordFrame = true;
    try {
      await _recordingService.captureMobileFrame(_recordCanvasKey);
    } finally {
      _isCapturingRecordFrame = false;
    }
  }

  Future<void> _stopMobileFrameCapture() async {
    _mobileRecordFrameTimer?.cancel();
    _mobileRecordFrameTimer = null;
    if (_usesFlutterFrameRecorder) {
      await _captureMobileRecordFrame();
    }
  }

  Future<void> _pickRecordingSavePathFromLyrics(
    SettingsModel settings,
  ) async {
    final path = await pickDirectorySafely(context);
    if (!mounted || path == null || path.trim().isEmpty) return;
    await settings.setRecordingSavePath(path);
    if (!mounted) return;
    setState(() => _recordStatus = 'Recording folder saved.');
  }

  Future<void> _startLyricsRecording({required bool trim}) async {
    if (_isPreparingRecording || _isRecordingLyrics) return;
    final music = widget.musicService.currentMusic;
    final duration = _recordingDuration;
    if (music == null || duration <= Duration.zero) {
      setState(() => _recordStatus = 'Load a song with duration first.');
      return;
    }

    if (trim && !_applyRecordTrimFields()) return;

    final unavailable = await _recordingService.availabilityMessage();
    if (unavailable != null) {
      if (!mounted) return;
      setState(() => _recordStatus = unavailable);
      return;
    }

    final start = trim ? _recordTrimStart : Duration.zero;
    final end = trim ? (_recordTrimEnd ?? duration) : duration;
    if (end <= start + const Duration(seconds: 1)) {
      setState(() => _recordStatus = 'Trim must be longer than 1 second.');
      return;
    }

    setState(() {
      _isPreparingRecording = true;
      _recordStatus = 'Resetting song and preparing 3 second countdown.';
      _lastRecordingPath = null;
      _activeRecordEnd = end;
      _recordFadeVisible = true;
      _recordPanelOpen = false;
      _fullscreenUiVisible = false;
    });

    if (_usesMobileFrameRecorder) {
      await _lockRecordingOrientationForCurrentScreen();
    }
    if (!mounted) return;
    final screenSize = MediaQuery.sizeOf(context);
    final settings = context.read<SettingsModel>();
    final recordingSavePath = settings.recordingSavePath;
    final mobileNativeFrameRate = _mobileNativeRefreshRate();
    _captureRecordingVolume();
    widget.musicService.seekTo(start);
    if (widget.musicService.isPlaying) {
      widget.musicService.togglePlayPause();
    }
    await Future<void>.delayed(const Duration(milliseconds: 360));

    for (var value = 3; value >= 1; value--) {
      if (!mounted) return;
      setState(() => _recordCountdown = value);
      await Future<void>.delayed(const Duration(seconds: 1));
    }

    if (!mounted) return;
    setState(() {
      _recordCountdown = 0;
      _recordStatus = 'Recording...';
    });

    try {
      await _fadeRecordingVolumeTo(
        0,
        duration: const Duration(milliseconds: 220),
      );
      if (!mounted) return;
      setState(() {
        _recordCountdown = 0;
        _recordStatus = 'Starting clean recording view.';
        _recordPanelOpen = false;
        _fullscreenUiVisible = false;
        _isRecordingLyrics = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 320));
      if (!mounted) return;
      final output = _usesMobileFrameRecorder
          ? await _recordingService.startMobileRecording(
              music: music,
              start: start,
              end: end,
              screenWidth: screenSize.width,
              screenHeight: screenSize.height,
              nativeFrameRate: mobileNativeFrameRate,
              saveDirectory: recordingSavePath,
            )
          : await _recordingService.start(
              music: music,
              start: start,
              end: end,
              saveDirectory: recordingSavePath,
            );
      if (!mounted) return;
      setState(() {
        _isPreparingRecording = false;
        _lastRecordingPath = output;
      });
      _startMobileFrameCapture(mobileNativeFrameRate);
      widget.musicService.seekTo(start);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await widget.musicService.play();
      _recordingService.markPlaybackStarted();
      _startRecordingWatcher(end);
      setState(() => _recordFadeVisible = false);
      unawaited(_fadeRecordingVolumeTo(
        _recordOriginalVolume ?? widget.musicService.volumeNotifier.value,
        duration: const Duration(milliseconds: 900),
      ));
    } catch (error) {
      if (!mounted) return;
      await _stopMobileFrameCapture();
      if (_recordingOrientationLocked) {
        await _restoreFullscreenOrientation();
      }
      _restoreRecordingVolume();
      setState(() {
        _isPreparingRecording = false;
        _isRecordingLyrics = false;
        _recordFadeVisible = false;
        _recordPanelOpen = true;
        _fullscreenUiVisible = true;
        _recordStatus = error.toString();
      });
    }
  }

  void _startRecordingWatcher(Duration end) {
    _recordingWatchTimer?.cancel();
    var endingFadeStarted = false;
    _recordingWatchTimer =
        Timer.periodic(const Duration(milliseconds: 180), (_) {
      if (!mounted || !_isRecordingLyrics) return;
      final position = widget.musicService.positionNotifier.value;
      final remaining = end - position;
      if (!endingFadeStarted &&
          remaining <= const Duration(milliseconds: 700)) {
        endingFadeStarted = true;
        setState(() => _recordFadeVisible = true);
        unawaited(_fadeRecordingVolumeTo(
          0,
          duration: const Duration(milliseconds: 680),
        ));
      }
      if (position >= end || remaining <= Duration.zero) {
        unawaited(_stopLyricsRecording(auto: true));
      }
    });
  }

  Future<void> _stopLyricsRecording({bool auto = false}) async {
    _recordingWatchTimer?.cancel();
    if (!_isRecordingLyrics && !_isPreparingRecording) return;
    setState(() {
      _recordFadeVisible = true;
      _recordStatus = auto ? 'Finishing recording...' : 'Stopping recording...';
      _isPreparingRecording = false;
      _recordCountdown = 0;
    });
    await _fadeRecordingVolumeTo(
      0,
      duration: const Duration(milliseconds: 620),
    );
    await Future<void>.delayed(const Duration(milliseconds: 90));
    await _stopMobileFrameCapture();
    final result = await _recordingService.stop();
    if (!mounted) return;
    if (widget.musicService.isPlaying && _activeRecordEnd != null) {
      final position = widget.musicService.positionNotifier.value;
      if (position >= _activeRecordEnd! - const Duration(milliseconds: 250)) {
        widget.musicService.togglePlayPause();
      }
    }
    if (_recordingOrientationLocked) {
      await _restoreFullscreenOrientation();
    }
    _restoreRecordingVolume();
    setState(() {
      _isRecordingLyrics = false;
      _recordPanelOpen = true;
      _recordFadeVisible = false;
      _recordStatus = result?.message ?? 'Recording stopped.';
      _lastRecordingPath = result?.path ?? _lastRecordingPath;
      _activeRecordEnd = null;
    });
  }

  String _formatRecordDuration(Duration duration) {
    if (duration < Duration.zero) duration = Duration.zero;
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _enterLayoutEdit(SettingsModel settings) {
    _fullscreenUiHideTimer?.cancel();
    setState(() {
      _fullscreenUiVisible = true;
      _layoutDraft = _LyricsLayoutDraft.fromSettings(settings)
        ..customLayout = true;
      _editTarget = _LyricsLayoutTarget.lyrics;
      _editPanelOpen = true;
      _isLayoutEditing = true;
    });
  }

  void _cancelLayoutEdit() {
    setState(() {
      _isLayoutEditing = false;
      _layoutDraft = null;
      _editPanelOpen = true;
    });
    _scheduleFullscreenUiHide();
  }

  Future<void> _acceptLayoutEdit(SettingsModel settings) async {
    final draft = _layoutDraft;
    if (draft == null) return;
    await settings.applyLyricsFullscreenCustomization(
      textColor: draft.textColor,
      position: draft.position,
      showCover: draft.showCover,
      showTrackName: draft.showTrackName,
      showControls: draft.showControls,
      showProgress: draft.showProgress,
      fontScale: draft.fontScale,
      dimBackground: draft.dimBackground,
      headerPosition: draft.headerPosition,
      coverStyle: draft.coverStyle,
      customLayout: true,
      lyricsOffsetX: draft.lyricsOffset.dx,
      lyricsOffsetY: draft.lyricsOffset.dy,
      headerOffsetX: draft.headerOffset.dx,
      headerOffsetY: draft.headerOffset.dy,
      controlsOffsetX: draft.controlsOffset.dx,
      controlsOffsetY: draft.controlsOffset.dy,
      headerScale: draft.headerScale,
      lyricsScale: draft.lyricsScale,
      controlsScale: draft.controlsScale,
      headerRotation: draft.headerRotation,
      lyricsRotation: draft.lyricsRotation,
      controlsRotation: draft.controlsRotation,
      fontPreset: draft.fontPreset,
      headerStyle: draft.headerStyle,
      controlsStyle: draft.controlsStyle,
      specialEffect: draft.specialEffect,
      headerLayer: draft.headerLayer,
      lyricsLayer: draft.lyricsLayer,
      controlsLayer: draft.controlsLayer,
      visualPath: draft.selectedVisual?.path ?? '',
      showVisual: draft.selectedVisual?.show ?? false,
      visualOffsetX: draft.selectedVisual?.offset.dx ?? 0,
      visualOffsetY: draft.selectedVisual?.offset.dy ?? -40,
      visualScale: draft.selectedVisual?.scale ?? 1,
      visualRotation: draft.selectedVisual?.rotation ?? 0,
      visualLayer: draft.selectedVisual?.layer ?? 4,
      visualOpacity: draft.selectedVisual?.opacity ?? 0.82,
      visualItems: draft.visualItems
          .map((item) => item.toSettingsItem())
          .toList(growable: false),
      particlePack: draft.particlePack,
      customParticlePack: draft.customParticlePack,
    );
    if (!mounted) return;
    setState(() {
      _isLayoutEditing = false;
      _layoutDraft = null;
      _editPanelOpen = true;
    });
    _scheduleFullscreenUiHide();
  }

  Widget _layoutEditableObject({
    required SettingsModel settings,
    required _LyricsLayoutDraft layout,
    required _LyricsLayoutTarget target,
    required Offset offset,
    required double scale,
    required double rotation,
    required Widget child,
    bool? selectedOverride,
    VoidCallback? onSelect,
  }) {
    final selected =
        selectedOverride ?? (_isLayoutEditing && _editTarget == target);
    final editPadSize = target == _LyricsLayoutTarget.lyrics ||
            target == _LyricsLayoutTarget.header ||
            target == _LyricsLayoutTarget.visual
        ? _editPadSizeForTarget(layout, target)
        : null;
    final handleSize = _editHandleSize(scale, target, editPadSize);
    final hitPadding = _editHitPadding(scale, target, editPadSize);
    final handleOffset = -handleSize * 0.42;
    Widget content = child;
    if (_isLayoutEditing) {
      final frameChild = target == _LyricsLayoutTarget.lyrics
          ? const SizedBox.expand()
          : child;
      final editPad = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          onSelect?.call();
          _editTarget = target;
        }),
        onScaleStart: (_) {
          onSelect?.call();
          _startEditGesture(target);
        },
        onScaleUpdate: (details) => _updateEditGesture(target, details),
        child: Padding(
          padding: EdgeInsets.all(hitPadding),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(selected ? 0.20 : 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected
                        ? settings.accentColor.withOpacity(0.92)
                        : Colors.white.withOpacity(0.16),
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.all(
                    target == _LyricsLayoutTarget.lyrics ? 2 : 6,
                  ),
                  child: frameChild,
                ),
              ),
              if (selected) ...[
                Positioned(
                  right: handleOffset,
                  bottom: handleOffset,
                  child: _editHandle(
                    settings: settings,
                    icon: Icons.open_in_full_rounded,
                    size: handleSize,
                    onPanUpdate: (delta) => _resizeEditTarget(target, delta),
                  ),
                ),
                Positioned(
                  right: handleOffset,
                  top: -handleSize * 1.12,
                  child: _editHandle(
                    settings: settings,
                    icon: Icons.rotate_right_rounded,
                    size: handleSize,
                    onPanUpdate: (delta) => _rotateEditTarget(target, delta),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
      if (target == _LyricsLayoutTarget.lyrics ||
          target == _LyricsLayoutTarget.header ||
          target == _LyricsLayoutTarget.visual) {
        final padSize = editPadSize!;
        content = Stack(
          fit: target == _LyricsLayoutTarget.lyrics
              ? StackFit.expand
              : StackFit.passthrough,
          children: [
            IgnorePointer(child: child),
            Positioned.fill(
              child: Align(
                alignment: _editPadAlignment(layout, target),
                child: SizedBox(
                  width: padSize.width,
                  height: padSize.height,
                  child: editPad,
                ),
              ),
            ),
          ],
        );
      } else {
        content = editPad;
      }
    }
    return Transform.translate(
      offset: offset,
      child: Transform.rotate(
        angle: rotation * math.pi / 180,
        alignment: Alignment.center,
        child: Transform.scale(
          scale: scale,
          alignment: Alignment.center,
          child: _effectWrapper(layout, target, content),
        ),
      ),
    );
  }

  Widget _effectWrapper(
    _LyricsLayoutDraft layout,
    _LyricsLayoutTarget target,
    Widget child,
  ) {
    if (layout.specialEffect == LyricsFullscreenSpecialEffect.none ||
        layout.specialEffect == LyricsFullscreenSpecialEffect.particles) {
      return child;
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1400),
      curve: Curves.easeInOut,
      builder: (context, value, _) {
        final phase = math.sin(value * math.pi * 2);
        final glow =
            layout.specialEffect == LyricsFullscreenSpecialEffect.softGlow ||
                layout.specialEffect == LyricsFullscreenSpecialEffect.pulse;
        final float =
            layout.specialEffect == LyricsFullscreenSpecialEffect.float;
        return Transform.translate(
          offset: float ? Offset(0, phase * 5) : Offset.zero,
          child: Transform.scale(
            scale: layout.specialEffect == LyricsFullscreenSpecialEffect.pulse
                ? 1 + (phase.abs() * 0.025)
                : 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                boxShadow: glow
                    ? [
                        BoxShadow(
                          color: layout.textColor
                              .withOpacity(0.18 + phase.abs() * 0.12),
                          blurRadius: 18 + phase.abs() * 12,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: child,
            ),
          ),
        );
      },
      onEnd: () {
        if (mounted) setState(() {});
      },
      child: child,
    );
  }

  Widget _editHandle({
    required SettingsModel settings,
    required IconData icon,
    required double size,
    required ValueChanged<Offset> onPanUpdate,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (details) => onPanUpdate(details.delta),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: settings.accentColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: size * 0.48,
            color: ThemeData.estimateBrightnessForColor(settings.accentColor) ==
                    Brightness.dark
                ? Colors.white
                : Colors.black,
          ),
        ),
      ),
    );
  }

  double _editHandleSize(
    double scale,
    _LyricsLayoutTarget target,
    Size? padSize,
  ) {
    final zoneBoost = switch (_editHitZone) {
      _LyricsEditHitZone.tiny => -4.0,
      _LyricsEditHitZone.compact => 0.0,
      _LyricsEditHitZone.touch => 6.0,
    };
    final inverseBoost = ((1.0 - scale) * 14).clamp(0.0, 12.0).toDouble();
    if (padSize != null) {
      final footprint = math.min(padSize.width, padSize.height);
      final dynamicSize =
          footprint * (target == _LyricsLayoutTarget.lyrics ? 0.26 : 0.22);
      return (dynamicSize + inverseBoost + zoneBoost)
          .clamp(
            target == _LyricsLayoutTarget.lyrics ? 32.0 : 36.0,
            target == _LyricsLayoutTarget.lyrics ? 50.0 : 58.0,
          )
          .toDouble();
    }
    return (46 + inverseBoost + zoneBoost).clamp(38.0, 60.0).toDouble();
  }

  double _editHitPadding(
    double scale,
    _LyricsLayoutTarget target,
    Size? padSize,
  ) {
    final handleSize = _editHandleSize(scale, target, padSize);
    final multiplier = switch (_editHitZone) {
      _LyricsEditHitZone.tiny => 0.72,
      _LyricsEditHitZone.compact => 1.0,
      _LyricsEditHitZone.touch => 1.35,
    };
    if (target == _LyricsLayoutTarget.lyrics) {
      return (handleSize * 0.08 * multiplier).clamp(3.0, 9.0).toDouble();
    }
    if (target == _LyricsLayoutTarget.header) {
      return (handleSize * 0.12 * multiplier).clamp(5.0, 12.0).toDouble();
    }
    return (handleSize * 0.24 * multiplier).clamp(10.0, 22.0).toDouble();
  }

  Alignment _editPadAlignment(
    _LyricsLayoutDraft layout,
    _LyricsLayoutTarget target,
  ) {
    if (target == _LyricsLayoutTarget.header) {
      return switch (layout.headerPosition) {
        LyricsFullscreenHeaderPosition.topLeft => Alignment.centerLeft,
        LyricsFullscreenHeaderPosition.topCenter => Alignment.center,
        LyricsFullscreenHeaderPosition.topRight => Alignment.centerRight,
      };
    }
    return Alignment.center;
  }

  Alignment _fullscreenHeaderSceneAlignment(_LyricsLayoutDraft layout) {
    return switch (layout.headerPosition) {
      LyricsFullscreenHeaderPosition.topLeft => Alignment.topLeft,
      LyricsFullscreenHeaderPosition.topCenter => Alignment.topCenter,
      LyricsFullscreenHeaderPosition.topRight => Alignment.topRight,
    };
  }

  Size _editPadSizeForTarget(
    _LyricsLayoutDraft layout,
    _LyricsLayoutTarget target,
  ) {
    final mediaSize = MediaQuery.sizeOf(context);
    final multiplier = switch (_editHitZone) {
      _LyricsEditHitZone.tiny => 0.76,
      _LyricsEditHitZone.compact => 1.0,
      _LyricsEditHitZone.touch => 1.28,
    };
    final isDesktop = MediaQuery.sizeOf(context).width >= 720;
    final coverSize = switch (layout.headerStyle) {
      LyricsFullscreenHeaderStyle.bigCover => 112.s,
      LyricsFullscreenHeaderStyle.coverAbove => 82.s,
      LyricsFullscreenHeaderStyle.fullCover => isDesktop ? 360.s : 240.s,
      _ => 58.s,
    };
    final coverVisible = layout.showCover &&
        layout.headerStyle != LyricsFullscreenHeaderStyle.nameOnly;
    final titleVisible = layout.showTrackName;
    final titleSize = titleVisible
        ? _estimatedHeaderTextSize(layout, mediaSize.width)
        : Size.zero;
    final titleWidth = titleSize.width;
    final headerBaseWidth =
        layout.headerStyle == LyricsFullscreenHeaderStyle.coverAbove
            ? math.max(coverVisible ? coverSize : 0.0, titleWidth)
            : (coverVisible ? coverSize : 0.0) +
                (coverVisible && titleVisible ? 14.0 : 0.0) +
                titleWidth;
    final headerBaseHeight =
        layout.headerStyle == LyricsFullscreenHeaderStyle.coverAbove
            ? (coverVisible ? coverSize : 0.0) +
                (coverVisible && titleVisible ? 10.0 : 0.0) +
                (titleVisible ? titleSize.height : 0.0)
            : math.max(coverVisible ? coverSize : 0.0,
                titleVisible ? titleSize.height : 0.0);
    return switch (target) {
      _LyricsLayoutTarget.header => Size(
          (headerBaseWidth * multiplier)
              .clamp(70.0, mediaSize.width.clamp(140.0, 360.0))
              .toDouble(),
          (headerBaseHeight * multiplier).clamp(50.0, 190.0).toDouble(),
        ),
      _LyricsLayoutTarget.lyrics => Size(
          (mediaSize.width * 0.28 * multiplier).clamp(120.0, 300.0).toDouble(),
          (mediaSize.height * 0.12 * multiplier).clamp(68.0, 170.0).toDouble(),
        ),
      _LyricsLayoutTarget.visual => Size.square(
          (mediaSize.shortestSide * 0.28 * multiplier)
              .clamp(96.0, 240.0)
              .toDouble(),
        ),
      _LyricsLayoutTarget.controls => Size.zero,
    };
  }

  Size _estimatedHeaderTextSize(_LyricsLayoutDraft layout, double maxWidth) {
    final music = widget.musicService.currentMusic;
    final title = (music?.title.trim().isNotEmpty == true)
        ? music!.title.trim()
        : 'Lyrics';
    final artist = music?.artist.trim() ?? '';
    final titleFontSize =
        layout.headerStyle == LyricsFullscreenHeaderStyle.bigCover
            ? 24.sp
            : 21.sp;
    final artistFontSize = 13.sp;
    final maxTextWidth = maxWidth
        .clamp(
            120.0,
            layout.headerStyle == LyricsFullscreenHeaderStyle.bigCover
                ? 360.0
                : 280.0)
        .toDouble();

    double measure(String text, TextStyle style) {
      if (text.isEmpty) return 0;
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxTextWidth);
      return painter.size.width;
    }

    final titleWidth = measure(
      title,
      TextStyle(
        fontFamily: _fontFamilyFor(layout),
        fontSize: titleFontSize,
        fontWeight: FontWeight.w900,
      ),
    );
    final artistWidth = measure(
      artist,
      TextStyle(
        fontFamily: _fontFamilyFor(layout),
        fontSize: artistFontSize,
        fontWeight: FontWeight.w700,
      ),
    );
    final rawWidth = math.max(titleWidth, artistWidth);
    final width = rawWidth
        .clamp(
          layout.headerStyle == LyricsFullscreenHeaderStyle.nameOnly
              ? 86.0
              : 96.0,
          maxTextWidth,
        )
        .toDouble();
    final titleLineCount =
        layout.headerStyle == LyricsFullscreenHeaderStyle.bigCover ? 2 : 1;
    final height = ((titleFontSize * 1.18 * titleLineCount) +
            (artist.isEmpty ? 0 : artistFontSize * 1.24))
        .clamp(34.0, 88.0)
        .toDouble();
    return Size(width, height);
  }

  _LyricsLayoutDraft get _activeDraft {
    final draft = _layoutDraft;
    if (draft == null) {
      throw StateError('Fullscreen lyrics edit draft is not active.');
    }
    return draft;
  }

  void _selectVisual(_LyricsLayoutDraft layout, int index) {
    if (layout.visualItems.isEmpty) return;
    layout.selectedVisualIndex = index.clamp(0, layout.visualItems.length - 1);
    _editTarget = _LyricsLayoutTarget.visual;
  }

  void _startEditGesture(_LyricsLayoutTarget target) {
    final draft = _activeDraft;
    setState(() {
      _editTarget = target;
      _gestureStartScale = _targetScale(draft, target);
      _gestureStartRotation = _targetRotation(draft, target);
    });
  }

  void _updateEditGesture(
      _LyricsLayoutTarget target, ScaleUpdateDetails details) {
    setState(() {
      final draft = _activeDraft;
      final moveDelta = details.pointerCount >= 2
          ? details.focalPointDelta * 0.55
          : details.focalPointDelta;
      if (moveDelta != Offset.zero) {
        _applyMoveToDraft(draft, target, moveDelta);
      }
      if (details.pointerCount >= 2) {
        final minScale = target == _LyricsLayoutTarget.visual ? 0.35 : 0.55;
        final maxScale = target == _LyricsLayoutTarget.visual ? 2.25 : 1.75;
        final rotationLimit =
            target == _LyricsLayoutTarget.visual ? 180.0 : 45.0;
        _setTargetScale(
          draft,
          target,
          (_gestureStartScale * details.scale)
              .clamp(minScale, maxScale)
              .toDouble(),
        );
        _setTargetRotation(
          draft,
          target,
          (_gestureStartRotation + details.rotation * 180 / math.pi)
              .clamp(-rotationLimit, rotationLimit)
              .toDouble(),
        );
      }
    });
  }

  double _targetScale(_LyricsLayoutDraft draft, _LyricsLayoutTarget target) {
    return switch (target) {
      _LyricsLayoutTarget.header => draft.headerScale,
      _LyricsLayoutTarget.lyrics => draft.lyricsScale,
      _LyricsLayoutTarget.controls => draft.controlsScale,
      _LyricsLayoutTarget.visual => draft.selectedVisual?.scale ?? 1,
    };
  }

  void _setTargetScale(
    _LyricsLayoutDraft draft,
    _LyricsLayoutTarget target,
    double value,
  ) {
    switch (target) {
      case _LyricsLayoutTarget.header:
        draft.headerScale = value;
      case _LyricsLayoutTarget.lyrics:
        draft.lyricsScale = value;
      case _LyricsLayoutTarget.controls:
        draft.controlsScale = value;
      case _LyricsLayoutTarget.visual:
        draft.selectedVisual?.scale = value.clamp(0.35, 2.25).toDouble();
    }
  }

  double _targetRotation(_LyricsLayoutDraft draft, _LyricsLayoutTarget target) {
    return switch (target) {
      _LyricsLayoutTarget.header => draft.headerRotation,
      _LyricsLayoutTarget.lyrics => draft.lyricsRotation,
      _LyricsLayoutTarget.controls => draft.controlsRotation,
      _LyricsLayoutTarget.visual => draft.selectedVisual?.rotation ?? 0,
    };
  }

  void _setTargetRotation(
    _LyricsLayoutDraft draft,
    _LyricsLayoutTarget target,
    double value,
  ) {
    switch (target) {
      case _LyricsLayoutTarget.header:
        draft.headerRotation = value;
      case _LyricsLayoutTarget.lyrics:
        draft.lyricsRotation = value;
      case _LyricsLayoutTarget.controls:
        draft.controlsRotation = value;
      case _LyricsLayoutTarget.visual:
        draft.selectedVisual?.rotation = value.clamp(-180.0, 180.0).toDouble();
    }
  }

  void _applyMoveToDraft(
    _LyricsLayoutDraft draft,
    _LyricsLayoutTarget target,
    Offset delta,
  ) {
    final screenSize = MediaQuery.sizeOf(context);
    final xLimit = (screenSize.width * 0.72).clamp(420.0, 1600.0).toDouble();
    final yLimit = (screenSize.height * 0.72).clamp(420.0, 1400.0).toDouble();
    switch (target) {
      case _LyricsLayoutTarget.header:
        final next = draft.headerOffset + delta;
        draft.headerOffset = Offset(
          next.dx.clamp(-xLimit, xLimit).toDouble(),
          next.dy.clamp(-yLimit, yLimit).toDouble(),
        );
      case _LyricsLayoutTarget.lyrics:
        final next = draft.lyricsOffset + delta;
        draft.lyricsOffset = Offset(
          next.dx.clamp(-xLimit, xLimit).toDouble(),
          next.dy.clamp(-yLimit, yLimit).toDouble(),
        );
      case _LyricsLayoutTarget.controls:
        final next = draft.controlsOffset + delta;
        draft.controlsOffset = Offset(
          next.dx.clamp(-xLimit, xLimit).toDouble(),
          next.dy.clamp(-yLimit, yLimit).toDouble(),
        );
      case _LyricsLayoutTarget.visual:
        final visual = draft.selectedVisual;
        if (visual == null) return;
        final next = visual.offset + delta;
        visual.offset = Offset(
          next.dx.clamp(-xLimit, xLimit).toDouble(),
          next.dy.clamp(-yLimit, yLimit).toDouble(),
        );
    }
  }

  void _resizeEditTarget(_LyricsLayoutTarget target, Offset delta) {
    setState(() {
      final draft = _activeDraft;
      final current = _targetScale(draft, target);
      final minScale = target == _LyricsLayoutTarget.visual ? 0.35 : 0.55;
      final maxScale = target == _LyricsLayoutTarget.visual ? 2.25 : 1.75;
      final next = (current + ((delta.dx + delta.dy) / 170))
          .clamp(minScale, maxScale)
          .toDouble();
      _setTargetScale(draft, target, next);
    });
  }

  void _rotateEditTarget(_LyricsLayoutTarget target, Offset delta) {
    setState(() {
      final draft = _activeDraft;
      final current = _targetRotation(draft, target);
      final limit = target == _LyricsLayoutTarget.visual ? 180.0 : 45.0;
      final next =
          (current + (delta.dx * 0.72)).clamp(-limit, limit).toDouble();
      _setTargetRotation(draft, target, next);
    });
  }

  Widget _buildEditPanel(
    BuildContext context,
    ThemeData theme,
    SettingsModel settings,
    _LyricsLayoutDraft layout,
  ) {
    final mediaSize = MediaQuery.sizeOf(context);
    final compact = mediaSize.width < 700;
    if (!_editPanelOpen) {
      return Positioned(
        right: 10,
        top: 64,
        child: SafeArea(
          child: Column(
            children: [
              _editRailButton(
                settings,
                Icons.tune_rounded,
                () => setState(() => _editPanelOpen = true),
                'Open edit panel',
              ),
              const SizedBox(height: 8),
              _editRailButton(
                settings,
                Icons.check_rounded,
                () => _acceptLayoutEdit(settings),
                'Accept',
              ),
              const SizedBox(height: 8),
              _editRailButton(
                settings,
                Icons.close_rounded,
                _cancelLayoutEdit,
                'Cancel',
              ),
            ],
          ),
        ),
      );
    }
    final panelWidth = compact ? math.min(mediaSize.width - 24, 330.0) : 330.0;
    return Positioned(
      right: 12,
      top: compact ? 58 : 70,
      bottom: 12,
      width: panelWidth,
      child: SafeArea(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: ColoredBox(
            color: theme.colorScheme.surface.withOpacity(0.90),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Edit Lyrics',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Collapse panel',
                      onPressed: () => setState(() => _editPanelOpen = false),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _acceptLayoutEdit(settings),
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Accept'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _cancelLayoutEdit,
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('Cancel'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () =>
                        setState(() => _activeDraft.resetTransforms()),
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('Reset move, size, rotation'),
                  ),
                ),
                const Divider(height: 24),
                _editHint(theme, layout),
                const SizedBox(height: 12),
                _editSectionLabel(theme, 'Size presets'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _sizePresetChip(layout, 0.75, 'Small'),
                    _sizePresetChip(layout, 1.0, 'Normal'),
                    _sizePresetChip(layout, 1.25, 'Big'),
                    _sizePresetChip(layout, 1.55, 'Huge'),
                  ],
                ),
                const Divider(height: 24),
                _editSectionLabel(theme, 'Visible parts'),
                _draftSwitch(
                  theme,
                  'Cover art',
                  layout.showCover,
                  (value) => setState(() => layout.showCover = value),
                ),
                _draftSwitch(
                  theme,
                  'Song name and artist',
                  layout.showTrackName,
                  (value) => setState(() => layout.showTrackName = value),
                ),
                _draftSwitch(
                  theme,
                  'Playback controls',
                  layout.showControls,
                  (value) => setState(() => layout.showControls = value),
                ),
                _draftSwitch(
                  theme,
                  'Progress bar',
                  layout.showProgress,
                  (value) => setState(() => layout.showProgress = value),
                ),
                _draftSwitch(
                  theme,
                  'Photo/GIF overlays',
                  layout.hasAnyVisual,
                  (value) {
                    if (value && layout.visualItems.isEmpty) {
                      _pickLyricsVisual(layout);
                      return;
                    }
                    setState(() {
                      for (final item in layout.visualItems) {
                        item.show = value;
                      }
                      if (value) _editTarget = _LyricsLayoutTarget.visual;
                    });
                  },
                ),
                const SizedBox(height: 8),
                _editSectionLabel(theme, 'Photos and GIFs'),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickLyricsVisual(layout),
                        icon: const Icon(Icons.add_photo_alternate_rounded),
                        label: const Text('Add GIF/photo'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Remove selected visual',
                      onPressed: layout.visualItems.isEmpty
                          ? null
                          : () => setState(() => _removeSelectedVisual(layout)),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
                if (layout.visualItems.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var index = 0;
                          index < layout.visualItems.length;
                          index++)
                        FilterChip(
                          selected: layout.selectedVisualIndex == index,
                          avatar: Icon(
                            layout.visualItems[index].show
                                ? Icons.image_rounded
                                : Icons.visibility_off_rounded,
                            size: 17,
                          ),
                          label: Text('Visual ${index + 1}'),
                          onSelected: (_) =>
                              setState(() => _selectVisual(layout, index)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'Hide or show selected visual',
                        onPressed: layout.selectedVisual == null
                            ? null
                            : () => setState(() {
                                  final visual = layout.selectedVisual;
                                  if (visual != null) {
                                    visual.show = !visual.show;
                                  }
                                }),
                        icon: Icon(
                          layout.selectedVisual?.show == true
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          layout.selectedVisual?.path ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color:
                                theme.colorScheme.onSurface.withOpacity(0.62),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _draftSlider(
                    theme: theme,
                    label: 'Selected opacity',
                    value: layout.selectedVisual?.opacity ?? 0.82,
                    min: 0.12,
                    max: 1,
                    display:
                        '${((layout.selectedVisual?.opacity ?? 0.82) * 100).round()}%',
                    onChanged: (value) => setState(() {
                      final visual = layout.selectedVisual;
                      if (visual != null) visual.opacity = value;
                    }),
                  ),
                ],
                const Divider(height: 24),
                _editSectionLabel(theme, 'Text color'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final color in _lyricsTextColors)
                      _draftColorChip(
                        color: color,
                        selected: layout.textColor.value == color.value,
                        onTap: () => setState(() => layout.textColor = color),
                      ),
                    _draftColorChip(
                      color: settings.accentColor,
                      selected:
                          layout.textColor.value == settings.accentColor.value,
                      onTap: () => setState(
                          () => layout.textColor = settings.accentColor),
                    ),
                  ],
                ),
                const Divider(height: 24),
                _draftSlider(
                  theme: theme,
                  label: 'Text size',
                  value: layout.fontScale,
                  min: 0.75,
                  max: 1.35,
                  display: '${(layout.fontScale * 100).round()}%',
                  onChanged: (value) =>
                      setState(() => layout.fontScale = value),
                ),
                _draftSlider(
                  theme: theme,
                  label: 'Dim background',
                  value: layout.dimBackground,
                  min: 0.25,
                  max: 0.85,
                  display: '${(layout.dimBackground * 100).round()}%',
                  onChanged: (value) =>
                      setState(() => layout.dimBackground = value),
                ),
                const Divider(height: 24),
                _editSectionLabel(theme, 'Base position'),
                _segmentedPosition(theme, layout),
                const SizedBox(height: 10),
                _segmentedHeaderPosition(theme, layout),
                const Divider(height: 24),
                _editSectionLabel(theme, 'Cover style'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _coverStyleChip(layout, LyricsFullscreenCoverStyle.rounded,
                        Icons.rounded_corner_rounded, 'Rounded'),
                    _coverStyleChip(layout, LyricsFullscreenCoverStyle.circle,
                        Icons.circle_outlined, 'Circle'),
                    _coverStyleChip(layout, LyricsFullscreenCoverStyle.shadow,
                        Icons.layers_rounded, 'Shadow'),
                    _coverStyleChip(layout, LyricsFullscreenCoverStyle.glow,
                        Icons.auto_awesome_rounded, 'Glow'),
                  ],
                ),
                const Divider(height: 24),
                _editSectionLabel(theme, 'Font'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _fontPresetChip(layout, LyricsFullscreenFontPreset.system,
                        Icons.text_fields_rounded, 'System'),
                    _fontPresetChip(layout, LyricsFullscreenFontPreset.serif,
                        Icons.menu_book_rounded, 'Serif'),
                    _fontPresetChip(layout, LyricsFullscreenFontPreset.mono,
                        Icons.code_rounded, 'Mono'),
                    _fontPresetChip(layout, LyricsFullscreenFontPreset.rounded,
                        Icons.circle_rounded, 'Round'),
                    _fontPresetChip(layout, LyricsFullscreenFontPreset.notoSans,
                        Icons.text_format_rounded, 'Noto'),
                    _fontPresetChip(
                        layout,
                        LyricsFullscreenFontPreset.notoJapanese,
                        Icons.translate_rounded,
                        'JP'),
                    _fontPresetChip(
                        layout,
                        LyricsFullscreenFontPreset.notoChinese,
                        Icons.language_rounded,
                        'SC'),
                    _fontPresetChip(layout, LyricsFullscreenFontPreset.display,
                        Icons.title_rounded, 'Display'),
                    _fontPresetChip(
                        layout,
                        LyricsFullscreenFontPreset.handwritten,
                        Icons.draw_rounded,
                        'Hand'),
                  ],
                ),
                const Divider(height: 24),
                _editSectionLabel(theme, 'Cover and name style'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _headerStyleChip(
                        layout,
                        LyricsFullscreenHeaderStyle.compact,
                        Icons.view_compact_rounded,
                        'Compact'),
                    _headerStyleChip(
                        layout,
                        LyricsFullscreenHeaderStyle.bigCover,
                        Icons.photo_size_select_large_rounded,
                        'Big cover'),
                    _headerStyleChip(
                        layout,
                        LyricsFullscreenHeaderStyle.coverAbove,
                        Icons.vertical_align_top_rounded,
                        'Stacked'),
                    _headerStyleChip(
                        layout,
                        LyricsFullscreenHeaderStyle.nameOnly,
                        Icons.title_rounded,
                        'Name only'),
                  ],
                ),
                const Divider(height: 24),
                _editSectionLabel(theme, 'Control style'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _controlsStyleChip(
                        layout,
                        LyricsFullscreenControlsStyle.classic,
                        Icons.tune_rounded,
                        'Classic'),
                    _controlsStyleChip(
                        layout,
                        LyricsFullscreenControlsStyle.pill,
                        Icons.horizontal_rule_rounded,
                        'Pill'),
                    _controlsStyleChip(
                        layout,
                        LyricsFullscreenControlsStyle.minimal,
                        Icons.remove_rounded,
                        'Minimal'),
                    _controlsStyleChip(
                        layout,
                        LyricsFullscreenControlsStyle.glow,
                        Icons.auto_awesome_rounded,
                        'Glow'),
                    _controlsStyleChip(
                        layout,
                        LyricsFullscreenControlsStyle.panel43,
                        Icons.aspect_ratio_rounded,
                        '6:1'),
                  ],
                ),
                const Divider(height: 24),
                _editSectionLabel(theme, 'Special effect'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _effectChip(layout, LyricsFullscreenSpecialEffect.none,
                        Icons.block_rounded, 'None'),
                    _effectChip(layout, LyricsFullscreenSpecialEffect.softGlow,
                        Icons.blur_on_rounded, 'Glow'),
                    _effectChip(layout, LyricsFullscreenSpecialEffect.pulse,
                        Icons.radio_button_checked_rounded, 'Pulse'),
                    _effectChip(layout, LyricsFullscreenSpecialEffect.float,
                        Icons.waves_rounded, 'Float'),
                    _effectChip(layout, LyricsFullscreenSpecialEffect.particles,
                        Icons.grain_rounded, 'Particles'),
                  ],
                ),
                if (layout.specialEffect ==
                    LyricsFullscreenSpecialEffect.particles) ...[
                  const SizedBox(height: 12),
                  _editSectionLabel(theme, 'Particle pack'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _particlePackChip(layout,
                          LyricsFullscreenParticlePack.sparkles, 'Spark'),
                      _particlePackChip(
                          layout, LyricsFullscreenParticlePack.stars, 'Stars'),
                      _particlePackChip(
                          layout, LyricsFullscreenParticlePack.snow, 'Snow'),
                      _particlePackChip(layout,
                          LyricsFullscreenParticlePack.bubbles, 'Bubbles'),
                      _particlePackChip(
                          layout, LyricsFullscreenParticlePack.hearts, 'Heart'),
                      _particlePackChip(layout,
                          LyricsFullscreenParticlePack.sakura, 'Sakura'),
                      _particlePackChip(layout,
                          LyricsFullscreenParticlePack.fireflies, 'Firefly'),
                      _particlePackChip(layout,
                          LyricsFullscreenParticlePack.confetti, 'Confetti'),
                      _particlePackChip(layout,
                          LyricsFullscreenParticlePack.custom, 'Custom'),
                    ],
                  ),
                  if (layout.particlePack ==
                      LyricsFullscreenParticlePack.custom) ...[
                    const SizedBox(height: 10),
                    TextFormField(
                      initialValue: layout.customParticlePack,
                      decoration: const InputDecoration(
                        labelText: 'Custom lyric particles',
                        helperText: 'Separate symbols with spaces',
                        prefixIcon: Icon(Icons.auto_awesome_rounded),
                      ),
                      onChanged: (value) => setState(() {
                        layout.customParticlePack =
                            value.trim().isEmpty ? '* + .' : value.trim();
                      }),
                    ),
                  ],
                ],
                const Divider(height: 24),
                _editSectionLabel(theme, 'Layer'),
                Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Send back',
                      onPressed: () =>
                          setState(() => _changeSelectedLayer(layout, -1)),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Layer ${_selectedLayer(layout)}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Bring front',
                      onPressed: () =>
                          setState(() => _changeSelectedLayer(layout, 1)),
                      icon: const Icon(Icons.keyboard_arrow_up_rounded),
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

  Widget _editRailButton(
    SettingsModel settings,
    IconData icon,
    VoidCallback onPressed,
    String tooltip,
  ) {
    return IconButton.filledTonal(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withOpacity(0.46),
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _editSectionLabel(ThemeData theme, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: theme.colorScheme.primary,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }

  Widget _editHint(ThemeData theme, _LyricsLayoutDraft layout) {
    final scale = switch (_editTarget) {
      _LyricsLayoutTarget.header => layout.headerScale,
      _LyricsLayoutTarget.lyrics => layout.lyricsScale,
      _LyricsLayoutTarget.controls => layout.controlsScale,
      _LyricsLayoutTarget.visual => layout.selectedVisual?.scale ?? 1,
    };
    final rotation = switch (_editTarget) {
      _LyricsLayoutTarget.header => layout.headerRotation,
      _LyricsLayoutTarget.lyrics => layout.lyricsRotation,
      _LyricsLayoutTarget.controls => layout.controlsRotation,
      _LyricsLayoutTarget.visual => layout.selectedVisual?.rotation ?? 0,
    };
    return Text(
      'Tap an object on the canvas, then drag it. Corner resizes. '
      'Round handle rotates. ${(scale * 100).round()}%  ${rotation.round()} deg',
      style: TextStyle(
        color: theme.colorScheme.onSurface.withOpacity(0.66),
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _sizePresetChip(
      _LyricsLayoutDraft layout, double scale, String label) {
    final selected = (_targetScale(layout, _editTarget) - scale).abs() < 0.04;
    return ChoiceChip(
      selected: selected,
      avatar: const Icon(Icons.open_in_full_rounded, size: 16),
      label: Text(label),
      onSelected: (_) => setState(
        () => _setTargetScale(layout, _editTarget, scale),
      ),
    );
  }

  Widget _draftSwitch(
    ThemeData theme,
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return SwitchListTile.adaptive(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: TextStyle(
          color: theme.colorScheme.onSurface.withOpacity(0.78),
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _draftColorChip({
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? Colors.white : Colors.white.withOpacity(0.30),
            width: selected ? 3 : 1,
          ),
        ),
        child: selected
            ? Icon(
                Icons.check_rounded,
                size: 18,
                color: ThemeData.estimateBrightnessForColor(color) ==
                        Brightness.dark
                    ? Colors.white
                    : Colors.black,
              )
            : null,
      ),
    );
  }

  Widget _draftSlider({
    required ThemeData theme,
    required String label,
    required double value,
    required double min,
    required double max,
    required String display,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              display,
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _segmentedPosition(ThemeData theme, _LyricsLayoutDraft layout) {
    return SegmentedButton<LyricsFullscreenPosition>(
      showSelectedIcon: false,
      selected: {layout.position},
      onSelectionChanged: (selection) =>
          setState(() => layout.position = selection.first),
      segments: const [
        ButtonSegment(
          value: LyricsFullscreenPosition.top,
          icon: Icon(Icons.vertical_align_top_rounded),
          label: Text('Top'),
        ),
        ButtonSegment(
          value: LyricsFullscreenPosition.center,
          icon: Icon(Icons.vertical_align_center_rounded),
          label: Text('Mid'),
        ),
        ButtonSegment(
          value: LyricsFullscreenPosition.bottom,
          icon: Icon(Icons.vertical_align_bottom_rounded),
          label: Text('Low'),
        ),
      ],
    );
  }

  Widget _segmentedHeaderPosition(ThemeData theme, _LyricsLayoutDraft layout) {
    return SegmentedButton<LyricsFullscreenHeaderPosition>(
      showSelectedIcon: false,
      selected: {layout.headerPosition},
      onSelectionChanged: (selection) =>
          setState(() => layout.headerPosition = selection.first),
      segments: const [
        ButtonSegment(
          value: LyricsFullscreenHeaderPosition.topLeft,
          icon: Icon(Icons.align_horizontal_left_rounded),
          label: Text('Left'),
        ),
        ButtonSegment(
          value: LyricsFullscreenHeaderPosition.topCenter,
          icon: Icon(Icons.align_horizontal_center_rounded),
          label: Text('Mid'),
        ),
        ButtonSegment(
          value: LyricsFullscreenHeaderPosition.topRight,
          icon: Icon(Icons.align_horizontal_right_rounded),
          label: Text('Right'),
        ),
      ],
    );
  }

  Widget _coverStyleChip(
    _LyricsLayoutDraft layout,
    LyricsFullscreenCoverStyle style,
    IconData icon,
    String label,
  ) {
    return ChoiceChip(
      selected: layout.coverStyle == style,
      avatar: Icon(icon, size: 17),
      label: Text(label),
      onSelected: (_) => setState(() => layout.coverStyle = style),
    );
  }

  Widget _fontPresetChip(
    _LyricsLayoutDraft layout,
    LyricsFullscreenFontPreset preset,
    IconData icon,
    String label,
  ) {
    return ChoiceChip(
      selected: layout.fontPreset == preset,
      avatar: Icon(icon, size: 17),
      label: Text(label),
      onSelected: (_) => setState(() => layout.fontPreset = preset),
    );
  }

  Widget _headerStyleChip(
    _LyricsLayoutDraft layout,
    LyricsFullscreenHeaderStyle style,
    IconData icon,
    String label,
  ) {
    return ChoiceChip(
      selected: layout.headerStyle == style,
      avatar: Icon(icon, size: 17),
      label: Text(label),
      onSelected: (_) => setState(() => layout.headerStyle = style),
    );
  }

  Widget _controlsStyleChip(
    _LyricsLayoutDraft layout,
    LyricsFullscreenControlsStyle style,
    IconData icon,
    String label,
  ) {
    return ChoiceChip(
      selected: layout.controlsStyle == style,
      avatar: Icon(icon, size: 17),
      label: Text(label),
      onSelected: (_) => setState(() => layout.controlsStyle = style),
    );
  }

  Widget _effectChip(
    _LyricsLayoutDraft layout,
    LyricsFullscreenSpecialEffect effect,
    IconData icon,
    String label,
  ) {
    return ChoiceChip(
      selected: layout.specialEffect == effect,
      avatar: Icon(icon, size: 17),
      label: Text(label),
      onSelected: (_) => setState(() => layout.specialEffect = effect),
    );
  }

  Widget _particlePackChip(
    _LyricsLayoutDraft layout,
    LyricsFullscreenParticlePack pack,
    String label,
  ) {
    return ChoiceChip(
      selected: layout.particlePack == pack,
      avatar: const Icon(Icons.auto_awesome_rounded, size: 17),
      label: Text(label),
      onSelected: (_) => setState(() => layout.particlePack = pack),
    );
  }

  Future<void> _pickLyricsVisual(_LyricsLayoutDraft layout) async {
    final path = await pickFilePathSafely(
      context,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'],
    );
    if (!mounted || path == null || path.trim().isEmpty) return;
    setState(() {
      final index = layout.visualItems.length;
      layout.visualItems.add(_LyricsVisualDraftItem(
        id: 'visual_${DateTime.now().microsecondsSinceEpoch}_$index',
        path: path.trim(),
        show: true,
        offset: Offset(index * 24.0, -40 + index * 18.0),
        scale: 1,
        rotation: 0,
        layer: 4 + (index % 3),
        opacity: 0.82,
      ));
      layout.selectedVisualIndex = layout.visualItems.length - 1;
      layout.customLayout = true;
      _editTarget = _LyricsLayoutTarget.visual;
    });
  }

  void _removeSelectedVisual(_LyricsLayoutDraft layout) {
    if (layout.visualItems.isEmpty) return;
    final index = layout.selectedVisualIndex.clamp(
      0,
      layout.visualItems.length - 1,
    );
    layout.visualItems.removeAt(index);
    layout.selectedVisualIndex = layout.visualItems.isEmpty
        ? 0
        : index.clamp(0, layout.visualItems.length - 1);
    if (layout.visualItems.isEmpty &&
        _editTarget == _LyricsLayoutTarget.visual) {
      _editTarget = _LyricsLayoutTarget.lyrics;
    }
  }

  int _selectedLayer(_LyricsLayoutDraft layout) {
    return switch (_editTarget) {
      _LyricsLayoutTarget.header => layout.headerLayer,
      _LyricsLayoutTarget.lyrics => layout.lyricsLayer,
      _LyricsLayoutTarget.controls => layout.controlsLayer,
      _LyricsLayoutTarget.visual => layout.selectedVisual?.layer ?? 4,
    };
  }

  void _changeSelectedLayer(_LyricsLayoutDraft layout, int delta) {
    final next = (_selectedLayer(layout) + delta).clamp(0, 9);
    switch (_editTarget) {
      case _LyricsLayoutTarget.header:
        layout.headerLayer = next;
      case _LyricsLayoutTarget.lyrics:
        layout.lyricsLayer = next;
      case _LyricsLayoutTarget.controls:
        layout.controlsLayer = next;
      case _LyricsLayoutTarget.visual:
        layout.selectedVisual?.layer = next;
    }
  }

  Widget _buildFullscreenVisualOverlay(
    ThemeData theme,
    _LyricsVisualDraftItem visual,
  ) {
    final path = visual.path.trim();
    final hasVisual = path.isNotEmpty && File(path).existsSync();
    final mediaSize = MediaQuery.sizeOf(context);
    final baseSize =
        (mediaSize.shortestSide * 0.30).clamp(110.0, 260.0).toDouble();

    if (!hasVisual) {
      if (!_isLayoutEditing) return const SizedBox.shrink();
      return SizedBox(
        width: baseSize,
        height: baseSize,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.20),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.18)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_photo_alternate_rounded,
                color: theme.colorScheme.primary,
                size: 42,
              ),
              const SizedBox(height: 8),
              Text(
                'Choose GIF or photo',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.72),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Opacity(
      opacity: visual.show ? visual.opacity.clamp(0.12, 1.0).toDouble() : 0.18,
      child: SizedBox(
        width: baseSize,
        height: baseSize,
        child: Image.file(
          File(path),
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) {
            return DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.20),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.16)),
              ),
              child: const Center(
                child: Icon(Icons.broken_image_rounded, color: Colors.white70),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFullscreenHeader(
    ThemeData theme,
    Music? music,
    SettingsModel settings,
    _LyricsLayoutDraft layout,
  ) {
    final showCover = layout.showCover;
    final showName = layout.showTrackName;
    final isDesktop = MediaQuery.sizeOf(context).width >= 720;
    final preferredCoverSize = switch (layout.headerStyle) {
      LyricsFullscreenHeaderStyle.bigCover => 112.s,
      LyricsFullscreenHeaderStyle.coverAbove => 82.s,
      LyricsFullscreenHeaderStyle.fullCover => isDesktop ? 360.s : 240.s,
      _ => 58.s,
    };
    final alignment = switch (layout.headerPosition) {
      LyricsFullscreenHeaderPosition.topLeft => MainAxisAlignment.start,
      LyricsFullscreenHeaderPosition.topCenter => MainAxisAlignment.center,
      LyricsFullscreenHeaderPosition.topRight => MainAxisAlignment.end,
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackWidth =
            (MediaQuery.sizeOf(context).width - 44).clamp(160.0, 720.0);
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : fallbackWidth.toDouble();
        final coverSizeRatio = switch (layout.headerStyle) {
          LyricsFullscreenHeaderStyle.fullCover => 0.85,
          LyricsFullscreenHeaderStyle.coverAbove => 0.58,
          _ => 0.42,
        };
        final coverSize = math
            .min(preferredCoverSize, maxWidth * coverSizeRatio)
            .clamp(42.0, preferredCoverSize)
            .toDouble();
        final coverVisible = showCover &&
            layout.headerStyle != LyricsFullscreenHeaderStyle.nameOnly;
        final gapWidth = coverVisible && showName ? 14.0 : 0.0;
        final measuredTextSize =
            showName ? _estimatedHeaderTextSize(layout, maxWidth) : Size.zero;
        final remainingRowWidth =
            (maxWidth - (coverVisible ? coverSize : 0.0) - gapWidth)
                .clamp(72.0, maxWidth)
                .toDouble();
        final rowTextWidth = math
            .min(remainingRowWidth, math.max(96.0, measuredTextSize.width + 8))
            .toDouble();
        final rowTextHeight =
            (coverVisible ? coverSize : 72.0).clamp(44.0, 132.0).toDouble();
        final stackedTextWidth =
            math.min(maxWidth, math.max(112.0, measuredTextSize.width + 8));
        final stackedTextHeight =
            (layout.headerStyle == LyricsFullscreenHeaderStyle.coverAbove
                    ? math.max(44.0, measuredTextSize.height)
                    : rowTextHeight)
                .toDouble();

        final titleCore = showName
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment:
                    layout.headerStyle == LyricsFullscreenHeaderStyle.coverAbove
                        ? CrossAxisAlignment.center
                        : CrossAxisAlignment.start,
                children: [
                  Text(
                    music?.title ?? 'Lyrics',
                    maxLines: layout.headerStyle ==
                            LyricsFullscreenHeaderStyle.bigCover
                        ? 2
                        : 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: layout.headerStyle ==
                            LyricsFullscreenHeaderStyle.coverAbove
                        ? TextAlign.center
                        : TextAlign.start,
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: _fontFamilyFor(layout),
                      fontSize: layout.headerStyle ==
                              LyricsFullscreenHeaderStyle.bigCover
                          ? 24.sp
                          : 21.sp,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    music?.artist ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: layout.headerStyle ==
                            LyricsFullscreenHeaderStyle.coverAbove
                        ? TextAlign.center
                        : TextAlign.start,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.68),
                      fontFamily: _fontFamilyFor(layout),
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              )
            : null;
        Widget? fittedTitle({
          required double width,
          required double maxHeight,
          required Alignment alignment,
        }) {
          if (titleCore == null) return null;
          return SizedBox(
            width: width,
            height: maxHeight,
            child: ClipRect(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: alignment,
                child: SizedBox(
                  width: width,
                  child: titleCore,
                ),
              ),
            ),
          );
        }

        final content = layout.headerStyle ==
                LyricsFullscreenHeaderStyle.coverAbove
            ? SizedBox(
                width: stackedTextWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showCover)
                      _buildFullscreenCover(
                          theme, music, settings, layout, coverSize),
                    if (showCover && showName) const SizedBox(height: 10),
                    if (titleCore != null)
                      fittedTitle(
                        width: stackedTextWidth,
                        maxHeight: stackedTextHeight,
                        alignment: Alignment.topCenter,
                      )!,
                  ],
                ),
              )
            : ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (coverVisible)
                      _buildFullscreenCover(
                          theme, music, settings, layout, coverSize),
                    if (coverVisible && showName) SizedBox(width: gapWidth),
                    if (titleCore != null)
                      Flexible(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: rowTextWidth),
                          child: fittedTitle(
                            width: rowTextWidth,
                            maxHeight: rowTextHeight,
                            alignment: Alignment.centerLeft,
                          )!,
                        ),
                      ),
                  ],
                ),
              );
        final styledContent = layout.headerStyle ==
                LyricsFullscreenHeaderStyle.bigCover
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.32),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                  boxShadow: [
                    BoxShadow(
                      color: settings.accentColor.withOpacity(0.16),
                      blurRadius: 28,
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.30),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: content,
                ),
              )
            : content;

        return Row(
          mainAxisAlignment: alignment,
          children: [
            Flexible(child: styledContent),
          ],
        );
      },
    );
  }

  String? _fontFamilyFor(_LyricsLayoutDraft layout) {
    return switch (layout.fontPreset) {
      LyricsFullscreenFontPreset.system => null,
      LyricsFullscreenFontPreset.serif => 'serif',
      LyricsFullscreenFontPreset.mono => 'monospace',
      LyricsFullscreenFontPreset.rounded => 'sans-serif',
      LyricsFullscreenFontPreset.notoSans => 'NotoSans',
      LyricsFullscreenFontPreset.notoJapanese => 'NotoSansJP',
      LyricsFullscreenFontPreset.notoChinese => 'NotoSansSC',
      LyricsFullscreenFontPreset.display => 'serif',
      LyricsFullscreenFontPreset.handwritten => 'cursive',
    };
  }

  Widget _buildFullscreenCover(
    ThemeData theme,
    Music? music,
    SettingsModel settings,
    _LyricsLayoutDraft layout,
    double size,
  ) {
    final radius = switch (layout.coverStyle) {
      LyricsFullscreenCoverStyle.circle => BorderRadius.circular(999),
      LyricsFullscreenCoverStyle.rounded => BorderRadius.circular(14),
      LyricsFullscreenCoverStyle.shadow => BorderRadius.circular(16),
      LyricsFullscreenCoverStyle.glow => BorderRadius.circular(18),
    };
    final shadowColor = layout.coverStyle == LyricsFullscreenCoverStyle.glow
        ? settings.accentColor.withOpacity(0.54)
        : Colors.black.withOpacity(
            layout.coverStyle == LyricsFullscreenCoverStyle.shadow ? 0.42 : 0,
          );
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            if (layout.coverStyle != LyricsFullscreenCoverStyle.rounded)
              BoxShadow(
                color: shadowColor,
                blurRadius: layout.coverStyle == LyricsFullscreenCoverStyle.glow
                    ? 24
                    : 16,
                spreadRadius:
                    layout.coverStyle == LyricsFullscreenCoverStyle.glow ? 2 : 0,
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: AspectRatio(
            aspectRatio: 1.0,
            child: music == null
                ? ColoredBox(color: theme.colorScheme.surface)
                : CoverArtTexture(
                    coverArtPath: music.coverPath,
                    width: double.infinity,
                    height: double.infinity,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildFullscreenBottomControls(
    ThemeData theme,
    SettingsModel settings,
    _LyricsLayoutDraft layout,
  ) {
    final isMinimal =
        layout.controlsStyle == LyricsFullscreenControlsStyle.minimal;
    final isPanel61 =
        layout.controlsStyle == LyricsFullscreenControlsStyle.panel43;
    final mediaSize = MediaQuery.sizeOf(context);
    final buttonExtent = (isMinimal ? 48.s : (isPanel61 ? 34.s : 54.s))
        .clamp(isPanel61 ? 30.0 : 46.0, isPanel61 ? 38.0 : 58.0)
        .toDouble();
    final playExtent = (isMinimal ? 54.s : (isPanel61 ? 40.s : 62.s))
        .clamp(isPanel61 ? 36.0 : 52.0, isPanel61 ? 44.0 : 66.0)
        .toDouble();
    final sideIconSize = (isMinimal ? 30.s : (isPanel61 ? 22.s : 36.s))
        .clamp(20.0, isPanel61 ? 25.0 : 40.0)
        .toDouble();
    final playIconSize = (isMinimal ? 34.s : (isPanel61 ? 27.s : 42.s))
        .clamp(24.0, isPanel61 ? 30.0 : 46.0)
        .toDouble();

    final progress = PlaybackProgressControl(
      musicService: widget.musicService,
      activeColor: settings.accentColor,
      inactiveColor: Colors.white.withOpacity(0.16),
      timeStyle: TextStyle(
        color: Colors.white.withOpacity(0.68),
        fontSize: isPanel61 ? 10.sp : 11.sp,
        fontWeight: FontWeight.w700,
      ),
    );
    final compactProgressWithTime =
        _buildFullscreenCompactProgressWithTime(settings);

    final playbackButtons = ValueListenableBuilder<bool>(
      valueListenable: widget.musicService.playingNotifier,
      builder: (context, isPlaying, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Previous',
              color: Colors.white.withOpacity(0.84),
              iconSize: sideIconSize,
              style: IconButton.styleFrom(
                minimumSize: Size(buttonExtent, buttonExtent),
                tapTargetSize: MaterialTapTargetSize.padded,
                padding: EdgeInsets.zero,
              ),
              icon: const Icon(Icons.skip_previous_rounded),
              onPressed: widget.musicService.previousTrack,
            ),
            SizedBox(width: isPanel61 ? 4.w : 12.w),
            IconButton.filled(
              tooltip: isPlaying ? 'Pause' : 'Play',
              style: IconButton.styleFrom(
                minimumSize: Size(playExtent, playExtent),
                tapTargetSize: MaterialTapTargetSize.padded,
                padding: EdgeInsets.zero,
                backgroundColor: isMinimal
                    ? Colors.white.withOpacity(0.10)
                    : settings.accentColor,
                foregroundColor: ThemeData.estimateBrightnessForColor(
                            settings.accentColor) ==
                        Brightness.dark
                    ? Colors.white
                    : Colors.black,
              ),
              iconSize: playIconSize,
              icon: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
              onPressed: widget.musicService.togglePlayPause,
            ),
            SizedBox(width: isPanel61 ? 4.w : 12.w),
            IconButton(
              tooltip: 'Next',
              color: Colors.white.withOpacity(0.84),
              iconSize: sideIconSize,
              style: IconButton.styleFrom(
                minimumSize: Size(buttonExtent, buttonExtent),
                tapTargetSize: MaterialTapTargetSize.padded,
                padding: EdgeInsets.zero,
              ),
              icon: const Icon(Icons.skip_next_rounded),
              onPressed: widget.musicService.next,
            ),
          ],
        );
      },
    );

    final controls = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (layout.showProgress) progress,
        if (layout.showControls) playbackButtons,
      ],
    );
    final decorated = switch (layout.controlsStyle) {
      LyricsFullscreenControlsStyle.panel43 => LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : mediaSize.width;
            final preferredWidth =
                mediaSize.width * (mediaSize.width < 640 ? 0.80 : 0.38);
            final panelMaxWidth =
                math.max(1.0, math.min(430.0, availableWidth));
            final panelMinWidth = math.min(240.0, panelMaxWidth);
            final panelWidth =
                preferredWidth.clamp(panelMinWidth, panelMaxWidth).toDouble();
            final panelHeight = (panelWidth / 6).clamp(42.0, 64.0).toDouble();
            final buttonLaneWidth = (panelWidth *
                    (layout.showProgress && layout.showControls ? 0.34 : 0.56))
                .clamp(74.0, 132.0)
                .toDouble();
            final progressLaneHeight =
                (panelHeight - 16).clamp(24.0, 36.0).toDouble();

            Widget panelChild;
            if (layout.showProgress && layout.showControls) {
              panelChild = Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: progressLaneHeight,
                      child: compactProgressWithTime,
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: buttonLaneWidth,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: playbackButtons,
                    ),
                  ),
                ],
              );
            } else if (layout.showProgress) {
              panelChild = SizedBox(
                height: progressLaneHeight,
                child: compactProgressWithTime,
              );
            } else {
              panelChild = Center(
                child: SizedBox(
                  width: buttonLaneWidth,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: playbackButtons,
                  ),
                ),
              );
            }

            return SizedBox(
              width: panelWidth,
              height: panelHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.38),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.14)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.30),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: panelChild,
                ),
              ),
            );
          },
        ),
      LyricsFullscreenControlsStyle.pill => DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.34),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: controls,
          ),
        ),
      LyricsFullscreenControlsStyle.glow => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: settings.accentColor.withOpacity(0.34),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: controls,
        ),
      _ => controls,
    };
    return Padding(
      padding: EdgeInsets.only(top: 12.h),
      child: Align(
        widthFactor: 1,
        heightFactor: 1,
        child: decorated,
      ),
    );
  }

  Widget _buildFullscreenCompactProgress(SettingsModel settings) {
    return ValueListenableBuilder<Duration>(
      valueListenable: widget.musicService.durationNotifier,
      builder: (context, duration, _) {
        return ValueListenableBuilder<Duration>(
          valueListenable: widget.musicService.positionNotifier,
          builder: (context, position, _) {
            final enabled = duration.inMilliseconds > 0;
            final boundedPosition = !enabled
                ? Duration.zero
                : Duration(
                    milliseconds: position.inMilliseconds
                        .clamp(0, duration.inMilliseconds),
                  );
            final progress = enabled
                ? (boundedPosition.inMilliseconds / duration.inMilliseconds)
                    .clamp(0.0, 1.0)
                    .toDouble()
                : 0.0;

            void seekFromDx(double dx, double width) {
              if (!enabled || width <= 0) return;
              final next = (dx / width).clamp(0.0, 1.0).toDouble();
              widget.musicService.seekTo(
                Duration(
                  milliseconds: (duration.inMilliseconds * next).round(),
                ),
              );
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth.isFinite
                    ? constraints.maxWidth
                    : MediaQuery.sizeOf(context).width;
                return Semantics(
                  label: 'Playback progress',
                  value: '${(progress * 100).round()}%',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) =>
                        seekFromDx(details.localPosition.dx, width),
                    onHorizontalDragUpdate: (details) =>
                        seekFromDx(details.localPosition.dx, width),
                    child: CustomPaint(
                      painter: _FullscreenCompactProgressPainter(
                        progress: progress,
                        activeColor: settings.accentColor,
                        inactiveColor: Colors.white.withOpacity(0.16),
                        enabled: enabled,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildFullscreenCompactProgressWithTime(SettingsModel settings) {
    final textStyle = TextStyle(
      color: Colors.white.withOpacity(0.72),
      fontSize: 10,
      fontWeight: FontWeight.w900,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return ValueListenableBuilder<Duration>(
      valueListenable: widget.musicService.durationNotifier,
      builder: (context, duration, _) {
        return ValueListenableBuilder<Duration>(
          valueListenable: widget.musicService.positionNotifier,
          builder: (context, position, _) {
            final boundedPosition = duration > Duration.zero
                ? Duration(
                    milliseconds: position.inMilliseconds
                        .clamp(0, duration.inMilliseconds),
                  )
                : position;
            return Row(
              children: [
                SizedBox(
                  width: 37,
                  child: Text(
                    _formatRecordDuration(boundedPosition),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: textStyle,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: _buildFullscreenCompactProgress(settings),
                  ),
                ),
                SizedBox(
                  width: 37,
                  child: Text(
                    duration > Duration.zero
                        ? _formatRecordDuration(duration)
                        : '--:--',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    textAlign: TextAlign.right,
                    style: textStyle,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPlainLyrics(
    LyricsDocument lyrics,
    bool generateKanaLyrics,
    _LyricsLayoutDraft layout,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final verticalPadding =
            _fullscreenVerticalPadding(constraints.maxHeight, false, layout);
        final safeInsets = _fullscreenLyricsSafeInsets(constraints, layout);
        return SingleChildScrollView(
          key: ValueKey('plain-${_trackKey ?? 'none'}'),
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(
            safeInsets.left,
            verticalPadding + safeInsets.top,
            safeInsets.right,
            verticalPadding + safeInsets.bottom,
          ),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 18 * (1 - value)),
                  child: child,
                ),
              );
            },
            child: _buildPlainLyricsText(
              lyrics,
              generateKanaLyrics,
              _fullscreenLyricsTextStyle(
                context,
                layout,
                opacity: 0.9,
                fontSize: 25.sp,
                height: 1.45,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyLyrics(_LyricsLayoutDraft layout) {
    return SizedBox.expand(
      key: ValueKey('empty-${_trackKey ?? 'none'}'),
    );
  }

  Color _fullscreenLyricsColor(BuildContext context, double opacity) {
    final color = _isLayoutEditing
        ? _activeDraft.textColor
        : context.watch<SettingsModel>().lyricsFullscreenTextColor;
    return color.withOpacity(opacity.clamp(0.0, 1.0).toDouble());
  }

  TextStyle _fullscreenLyricsTextStyle(
    BuildContext context,
    _LyricsLayoutDraft layout, {
    required double opacity,
    required double fontSize,
    required double height,
    required FontWeight fontWeight,
  }) {
    final shadowOpacity = (opacity * 0.58).clamp(0.0, 0.58).toDouble();
    return TextStyle(
      color: _fullscreenLyricsColor(context, opacity),
      fontFamily: _fontFamilyFor(layout),
      fontSize: fontSize * layout.fontScale,
      height: height,
      fontWeight: fontWeight,
      shadows: [
        Shadow(
          color: Colors.black.withOpacity(shadowOpacity),
          blurRadius: 12,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  double _fullscreenVerticalPadding(
    double height,
    bool timed,
    _LyricsLayoutDraft layout,
  ) {
    final position = layout.position;
    if (timed) {
      return switch (position) {
        LyricsFullscreenPosition.top =>
          (height * 0.18).clamp(56.0, 150.0).toDouble(),
        LyricsFullscreenPosition.center =>
          (height * 0.42).clamp(130.0, 280.0).toDouble(),
        LyricsFullscreenPosition.bottom =>
          (height * 0.58).clamp(180.0, 360.0).toDouble(),
      };
    }
    return switch (position) {
      LyricsFullscreenPosition.top =>
        (height * 0.05).clamp(16.0, 56.0).toDouble(),
      LyricsFullscreenPosition.center =>
        (height * 0.18).clamp(36.0, 120.0).toDouble(),
      LyricsFullscreenPosition.bottom =>
        (height * 0.34).clamp(86.0, 220.0).toDouble(),
    };
  }

  double _fullscreenLyricsAutoHeight(
    BoxConstraints constraints,
    _LyricsLayoutDraft layout,
  ) {
    final maxHeight = constraints.maxHeight.isFinite
        ? constraints.maxHeight
        : MediaQuery.sizeOf(context).height;
    if (maxHeight <= 0) return 180.0;

    final safeInsets = _fullscreenLyricsSafeInsets(constraints, layout);
    final reservedHeight = safeInsets.top + safeInsets.bottom;
    final freeHeight = (maxHeight - reservedHeight)
        .clamp(maxHeight * 0.34, maxHeight)
        .toDouble();
    final minimum = maxHeight < 420 ? 150.0 : 220.0;
    final oldCap = maxHeight * 0.72;

    // The lyric viewport should grow with real free territory, while still
    // leaving the internal padding to steer text away from cover/controls.
    final expandedHeight = freeHeight + reservedHeight * 0.78;
    return math
        .max(oldCap, expandedHeight)
        .clamp(minimum, maxHeight)
        .toDouble();
  }

  EdgeInsets _fullscreenLyricsSafeInsets(
    BoxConstraints constraints,
    _LyricsLayoutDraft layout,
  ) {
    final width = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : MediaQuery.sizeOf(context).width;
    final horizontal = (width * 0.065).clamp(20.0, 82.0).toDouble();
    final headerVisible = layout.showCover || layout.showTrackName;
    final headerNearTop = headerVisible && layout.headerOffset.dy < 180;
    final headerAvoidance = !headerNearTop
        ? 0.0
        : switch (layout.headerStyle) {
            LyricsFullscreenHeaderStyle.bigCover => 178.0,
            LyricsFullscreenHeaderStyle.coverAbove => 138.0,
            LyricsFullscreenHeaderStyle.nameOnly => 64.0,
            LyricsFullscreenHeaderStyle.compact => 96.0,
            LyricsFullscreenHeaderStyle.fullCover => 0.0,
          };
    final top = (headerAvoidance * layout.headerScale)
        .clamp(0.0, constraints.maxHeight * 0.42)
        .toDouble();
    final controlsVisible = (layout.showProgress || layout.showControls) &&
        (_isLayoutEditing || _fullscreenUiVisible);
    final controlsNearBottom =
        controlsVisible && layout.controlsOffset.dy > -180;
    final controlsAvoidance = controlsNearBottom
        ? switch (layout.controlsStyle) {
            LyricsFullscreenControlsStyle.panel43 => 48.0,
            LyricsFullscreenControlsStyle.minimal => 52.0,
            LyricsFullscreenControlsStyle.pill => 74.0,
            LyricsFullscreenControlsStyle.glow => 82.0,
            LyricsFullscreenControlsStyle.classic => 76.0,
          }
        : 18.0;
    final bottom = (controlsAvoidance * layout.controlsScale)
        .clamp(16.0, constraints.maxHeight * 0.26)
        .toDouble();
    return EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom);
  }

  Widget _buildTimedLyrics(
    LyricsDocument lyrics,
    bool generateKanaLyrics,
    _LyricsLayoutDraft layout,
  ) {
    return ValueListenableBuilder<Duration>(
      key: ValueKey('timed-${_trackKey ?? 'none'}'),
      valueListenable: widget.musicService.positionNotifier,
      builder: (context, position, _) {
        final activeIndex = lyrics.activeIndexAt(position);
        _scrollActiveLineIntoView(activeIndex);
        return LayoutBuilder(
          builder: (context, constraints) {
            final verticalPadding =
                _fullscreenVerticalPadding(constraints.maxHeight, true, layout);
            final safeInsets = _fullscreenLyricsSafeInsets(constraints, layout);
            return ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.fromLTRB(
                safeInsets.left,
                verticalPadding + safeInsets.top,
                safeInsets.right,
                verticalPadding + safeInsets.bottom,
              ),
              itemCount: lyrics.lines.length,
              itemBuilder: (context, index) {
                final line = lyrics.lines[index];
                final isActive = index == activeIndex;
                final distance = (index - activeIndex).abs();
                final opacity = isActive
                    ? 1.0
                    : distance == 1
                        ? 0.62
                        : 0.28;
                return AnimatedContainer(
                  key: _lineKeys.putIfAbsent(index, GlobalKey.new),
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.symmetric(
                    horizontal: isActive ? 14.w : 0,
                    vertical: isActive ? 18.h : 10.h,
                  ),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    textAlign: TextAlign.center,
                    style: _fullscreenLyricsTextStyle(
                      context,
                      layout,
                      opacity: opacity,
                      fontSize: isActive ? 31.sp : 22.sp,
                      height: 1.2,
                      fontWeight: isActive ? FontWeight.w900 : FontWeight.w700,
                    ),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(end: isActive ? 1 : 0),
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) {
                        return Opacity(
                          opacity: (0.86 + value * 0.14).clamp(0.0, 1.0),
                          child: Transform.translate(
                            offset: Offset(0, (1 - value) * 6),
                            child: Transform.scale(
                              scale: 1 + value * 0.035,
                              child: child,
                            ),
                          ),
                        );
                      },
                      child: _buildGeneratedKanaLine(
                        text: line.text,
                        generateKana: generateKanaLyrics,
                        generatedStyle: _fullscreenLyricsTextStyle(
                          context,
                          layout,
                          opacity: opacity * 0.74,
                          fontSize: isActive ? 19.sp : 15.sp,
                          height: 1.18,
                          fontWeight:
                              isActive ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _scrollActiveLineIntoView(int activeIndex) {
    if (activeIndex < 0 || activeIndex == _lastActiveIndex) return;
    _lastActiveIndex = activeIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final lineContext = _lineKeys[activeIndex]?.currentContext;
      if (lineContext != null) {
        Scrollable.ensureVisible(
          lineContext,
          alignment: 0.48,
          duration: const Duration(milliseconds: 460),
          curve: Curves.easeOutCubic,
        );
        return;
      }
      final viewport = _scrollController.position.viewportDimension;
      const estimatedLineExtent = 78.0;
      final target = ((activeIndex * estimatedLineExtent) -
              (viewport / 2) +
              (estimatedLineExtent / 2))
          .clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 460),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Widget _buildPlainLyricsText(
    LyricsDocument lyrics,
    bool generateKanaLyrics,
    TextStyle style, {
    TextAlign? textAlign,
  }) {
    if (!generateKanaLyrics) {
      return Text(
        lyrics.plainText,
        textAlign: textAlign,
        style: style,
        softWrap: true,
        overflow: TextOverflow.visible,
      );
    }

    return Text.rich(
      TextSpan(
        style: style,
        children: _plainLyricsKanaSpans(lyrics, style),
      ),
      textAlign: textAlign,
      softWrap: true,
      overflow: TextOverflow.visible,
    );
  }

  List<InlineSpan> _plainLyricsKanaSpans(
      LyricsDocument lyrics, TextStyle style) {
    final spans = <InlineSpan>[];
    for (final line in lyrics.lines) {
      final text = line.text.trim();
      if (text.isEmpty) continue;
      final romaji = RomajiKanaConverter.generatedRomajiForLine(text);
      spans.add(TextSpan(text: text));
      if (romaji.isNotEmpty) {
        spans.add(TextSpan(
          text: '\n$romaji',
          style: style.copyWith(
            fontSize: (style.fontSize ?? 25) * 0.72,
            fontWeight: FontWeight.w600,
            color: (style.color ?? Colors.white).withOpacity(0.68),
          ),
        ));
      }
      spans.add(const TextSpan(text: '\n'));
    }
    if (spans.isNotEmpty) spans.removeLast();
    return spans;
  }

  Widget _buildGeneratedKanaLine({
    required String text,
    required bool generateKana,
    required TextStyle generatedStyle,
  }) {
    if (!generateKana) {
      return Text(
        text,
        softWrap: true,
        overflow: TextOverflow.visible,
        textAlign: TextAlign.center,
      );
    }
    final romaji = RomajiKanaConverter.generatedRomajiForLine(text);
    if (romaji.isEmpty) {
      return Text(
        text,
        softWrap: true,
        overflow: TextOverflow.visible,
        textAlign: TextAlign.center,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          softWrap: true,
          overflow: TextOverflow.visible,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 5),
        Text(
          romaji,
          style: generatedStyle,
          softWrap: true,
          overflow: TextOverflow.visible,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _FullscreenLyricsParticleField extends StatefulWidget {
  final Color accentColor;
  final Color textColor;
  final LyricsFullscreenParticlePack pack;
  final String customPack;

  const _FullscreenLyricsParticleField({
    required this.accentColor,
    required this.textColor,
    required this.pack,
    required this.customPack,
  });

  @override
  State<_FullscreenLyricsParticleField> createState() =>
      _FullscreenLyricsParticleFieldState();
}

class _FullscreenLyricsParticleFieldState
    extends State<_FullscreenLyricsParticleField> {
  int _cycle = 0;
  final Map<String, TextPainter> _painterCache = {};

  @override
  void didUpdateWidget(covariant _FullscreenLyricsParticleField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accentColor != widget.accentColor ||
        oldWidget.textColor != widget.textColor ||
        oldWidget.pack != widget.pack ||
        oldWidget.customPack != widget.customPack) {
      _painterCache.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        key: ValueKey(_cycle),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(seconds: 14),
        curve: Curves.linear,
        onEnd: () {
          if (mounted) setState(() => _cycle++);
        },
        builder: (context, progress, _) {
          return CustomPaint(
            painter: _FullscreenLyricsParticlePainter(
              progress: progress,
              accentColor: widget.accentColor,
              textColor: widget.textColor,
              pack: widget.pack,
              customPack: widget.customPack,
              painterCache: _painterCache,
            ),
          );
        },
      ),
    );
  }
}

class _FullscreenLyricsParticlePainter extends CustomPainter {
  final double progress;
  final Color accentColor;
  final Color textColor;
  final LyricsFullscreenParticlePack pack;
  final String customPack;
  final Map<String, TextPainter> painterCache;

  const _FullscreenLyricsParticlePainter({
    required this.progress,
    required this.accentColor,
    required this.textColor,
    required this.pack,
    required this.customPack,
    required this.painterCache,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final area = size.width * size.height;
    final count = (area / _particleDensityDivisor).clamp(24, 100).round();
    final glowPaint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);

    for (var i = 0; i < count; i++) {
      final seedA = ((i * 73) % 997) / 997.0;
      final seedB = ((i * 191) % 991) / 991.0;
      final seedC = ((i * 43) % 983) / 983.0;
      final speed = 0.36 + seedC * 0.72;
      final loop = (progress * speed + seedB) % 1.0;
      final sway = math.sin((loop * math.pi * 2) + seedA * math.pi * 2);
      final direction = _rises ? -1.0 : 1.0;
      final x = (seedA * size.width + sway * (18 + seedB * 42))
          .clamp(0.0, size.width)
          .toDouble();
      final y = _rises
          ? (size.height + 24) - loop * (size.height + 64)
          : -24 + loop * (size.height + 64);
      final radius = _baseRadius(seedC);
      final opacity =
          (math.sin(loop * math.pi).clamp(0.0, 1.0) * (0.20 + seedB * 0.42))
              .toDouble();
      final color = Color.lerp(accentColor, textColor, seedB)!
          .withOpacity(opacity.clamp(0.0, 0.66));
      final center = Offset(x, y);

      glowPaint.color = color.withOpacity(opacity * 0.38);
      canvas.drawCircle(center, radius * 2.2, glowPaint);
      _drawPackParticle(
        canvas,
        center,
        radius,
        color,
        i,
        seedB,
        direction,
      );

      if (i % 5 == 0) {
        final sparkle = Paint()
          ..color = color.withOpacity(opacity * 0.82)
          ..strokeWidth = 1.1
          ..strokeCap = StrokeCap.round;
        final arm = radius * 2.1;
        canvas.drawLine(
            center.translate(-arm, 0), center.translate(arm, 0), sparkle);
        canvas.drawLine(
            center.translate(0, -arm), center.translate(0, arm), sparkle);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FullscreenLyricsParticlePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.textColor != textColor ||
        oldDelegate.pack != pack ||
        oldDelegate.customPack != customPack;
  }

  bool get _rises {
    return pack != LyricsFullscreenParticlePack.snow &&
        pack != LyricsFullscreenParticlePack.sakura &&
        pack != LyricsFullscreenParticlePack.confetti;
  }

  double get _particleDensityDivisor {
    return switch (pack) {
      LyricsFullscreenParticlePack.fireflies => 21000,
      LyricsFullscreenParticlePack.confetti => 15500,
      LyricsFullscreenParticlePack.stars => 16500,
      LyricsFullscreenParticlePack.custom => 18500,
      _ => 18000,
    };
  }

  double _baseRadius(double seed) {
    return switch (pack) {
      LyricsFullscreenParticlePack.bubbles => 3.0 + seed * 7.0,
      LyricsFullscreenParticlePack.hearts => 5.0 + seed * 8.0,
      LyricsFullscreenParticlePack.sakura => 4.0 + seed * 7.0,
      LyricsFullscreenParticlePack.confetti => 3.0 + seed * 6.0,
      LyricsFullscreenParticlePack.custom => 7.0 + seed * 9.0,
      _ => 1.4 + seed * 3.6,
    };
  }

  void _drawHeart(Canvas canvas, double size, Paint paint) {
    final path = Path();
    path.moveTo(0, -size * 0.35);
    path.cubicTo(-size * 0.45, -size * 0.8, -size * 0.95, -size * 0.45, -size * 0.95, size * 0.05);
    path.cubicTo(-size * 0.95, size * 0.5, -size * 0.5, size * 0.8, 0, size * 1.05);
    path.cubicTo(size * 0.5, size * 0.8, size * 0.95, size * 0.5, size * 0.95, size * 0.05);
    path.cubicTo(size * 0.95, -size * 0.45, size * 0.45, -size * 0.8, 0, -size * 0.35);
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawPackParticle(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    int index,
    double seedB,
    double direction,
  ) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate((seedB - 0.5) * math.pi * 0.9 * direction);
    switch (pack) {
      case LyricsFullscreenParticlePack.sparkles:
      case LyricsFullscreenParticlePack.stars:
      case LyricsFullscreenParticlePack.fireflies:
        canvas.drawCircle(Offset.zero, radius, paint);
      case LyricsFullscreenParticlePack.snow:
        canvas.drawCircle(Offset.zero, radius * 0.82, paint);
      case LyricsFullscreenParticlePack.bubbles:
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        canvas.drawCircle(Offset.zero, radius, paint);
      case LyricsFullscreenParticlePack.hearts:
        _drawHeart(canvas, radius * 2.35, paint);
      case LyricsFullscreenParticlePack.sakura:
        final path = Path()
          ..moveTo(0, -radius)
          ..quadraticBezierTo(radius, -radius * 0.2, 0, radius)
          ..quadraticBezierTo(-radius, -radius * 0.2, 0, -radius);
        canvas.drawPath(path, paint);
      case LyricsFullscreenParticlePack.confetti:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: radius * 1.1,
              height: radius * 2.2,
            ),
            const Radius.circular(2),
          ),
          paint,
        );
      case LyricsFullscreenParticlePack.custom:
        _drawParticleText(
            canvas, _customSymbolFor(index), radius * 1.75, color);
    }
    canvas.restore();
  }

  void _drawParticleText(
    Canvas canvas,
    String symbol,
    double size,
    Color color,
  ) {
    final opacity = color.opacity;
    final roundedOpacity = (opacity * 10).round() / 10;
    final displayColor = color.withOpacity(roundedOpacity);
    final key = '$symbol-${size.toStringAsFixed(1)}-${displayColor.value}';

    final painter = painterCache.putIfAbsent(key, () {
      return TextPainter(
        text: TextSpan(
          text: symbol,
          style: TextStyle(
            color: displayColor,
            fontSize: size,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
  }

  String _customSymbolFor(int index) {
    final symbols = customPack
        .trim()
        .split(RegExp(r'\s+'))
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (symbols.isEmpty) return '*';
    return symbols[index % symbols.length];
  }
}

class _FullscreenCompactProgressPainter extends CustomPainter {
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final bool enabled;

  const _FullscreenCompactProgressPainter({
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    required this.enabled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final trackHeight = math.min(10.0, size.height * 0.42);
    final centerY = size.height / 2;
    final radius = Radius.circular(trackHeight / 2);
    final trackRect = Rect.fromLTWH(
      0,
      centerY - trackHeight / 2,
      size.width,
      trackHeight,
    );
    final activeWidth =
        (trackRect.width * progress).clamp(0.0, trackRect.width).toDouble();

    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, radius),
      Paint()
        ..color = inactiveColor.withOpacity(enabled ? 0.88 : 0.42)
        ..style = PaintingStyle.fill,
    );

    if (activeWidth > 0) {
      final activeRect = Rect.fromLTWH(
          trackRect.left, trackRect.top, activeWidth, trackHeight);
      canvas.drawRRect(
        RRect.fromRectAndRadius(activeRect, radius),
        Paint()
          ..shader = LinearGradient(
            colors: [
              activeColor.withOpacity(enabled ? 0.76 : 0.38),
              activeColor.withOpacity(enabled ? 1.0 : 0.50),
            ],
          ).createShader(trackRect)
          ..style = PaintingStyle.fill,
      );
    }

    final thumbX = (trackRect.left + activeWidth)
        .clamp(trackRect.left, trackRect.right)
        .toDouble();
    canvas.drawCircle(
      Offset(thumbX, centerY),
      math.min(7.0, size.height * 0.34),
      Paint()
        ..color = enabled ? activeColor : activeColor.withOpacity(0.45)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _FullscreenCompactProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.enabled != enabled;
  }
}

class _LyricsSearchParameters {
  final String title;
  final String artist;
  final String? album;
  final int? durationSeconds;

  _LyricsSearchParameters({
    required this.title,
    required this.artist,
    required String album,
    required this.durationSeconds,
  }) : album = album.trim().isEmpty ? null : album;
}

class _LyricsTimingShiftSheet extends StatefulWidget {
  final Future<bool> Function(Duration offset) onShift;
  final Future<bool> Function() onReset;

  const _LyricsTimingShiftSheet({
    required this.onShift,
    required this.onReset,
  });

  @override
  State<_LyricsTimingShiftSheet> createState() =>
      _LyricsTimingShiftSheetState();
}

class _LyricsTimingShiftSheetState extends State<_LyricsTimingShiftSheet> {
  late final TextEditingController _controller;
  bool _isApplying = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '500');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Duration _customOffset(int direction) {
    final milliseconds = int.tryParse(_controller.text.trim()) ?? 0;
    return Duration(milliseconds: milliseconds.abs() * direction);
  }

  Future<void> _shift(Duration offset) async {
    if (_isApplying || offset == Duration.zero) return;
    setState(() => _isApplying = true);
    await widget.onShift(offset);
    if (mounted) setState(() => _isApplying = false);
  }

  Future<void> _reset() async {
    if (_isApplying) return;
    setState(() => _isApplying = true);
    await widget.onReset();
    if (mounted) setState(() => _isApplying = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget presetButton({
      required IconData icon,
      required int milliseconds,
    }) {
      final isForward = milliseconds > 0;
      return FilledButton.tonalIcon(
        onPressed: _isApplying
            ? null
            : () => _shift(Duration(milliseconds: milliseconds)),
        icon: Icon(icon),
        label: Text('${isForward ? '+' : '-'}${milliseconds.abs()} ms'),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: GlassContainer(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        color: theme.colorScheme.surface.withOpacity(0.96),
        blur: 8,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Shift Lyric Timing',
                      style: TextStyle(
                        fontSize: 20.sp,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Move every timed lyric row while playback keeps running.',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.68),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_isApplying) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(minHeight: 2),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  presetButton(
                    icon: Icons.fast_rewind_rounded,
                    milliseconds: -1000,
                  ),
                  presetButton(
                    icon: Icons.keyboard_arrow_left_rounded,
                    milliseconds: -500,
                  ),
                  presetButton(
                    icon: Icons.keyboard_arrow_right_rounded,
                    milliseconds: 500,
                  ),
                  presetButton(
                    icon: Icons.fast_forward_rounded,
                    milliseconds: 1000,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Custom shift milliseconds',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.timer_rounded),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          _isApplying ? null : () => _shift(_customOffset(-1)),
                      icon: const Icon(Icons.remove_rounded),
                      label: const Text('Back'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed:
                          _isApplying ? null : () => _shift(_customOffset(1)),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Forward'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _isApplying ? null : _reset,
                  icon: const Icon(Icons.restore_rounded),
                  label: const Text('Reset original timing'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LyricsSearchInputSheet extends StatefulWidget {
  final String title;
  final String artist;
  final String album;
  final int? durationSeconds;

  const _LyricsSearchInputSheet({
    required this.title,
    required this.artist,
    required this.album,
    required this.durationSeconds,
  });

  @override
  State<_LyricsSearchInputSheet> createState() =>
      _LyricsSearchInputSheetState();
}

class _LyricsSearchInputSheetState extends State<_LyricsSearchInputSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;
  late final TextEditingController _albumController;
  late final TextEditingController _durationController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.title);
    _artistController = TextEditingController(text: widget.artist);
    _albumController = TextEditingController(text: widget.album);
    _durationController = TextEditingController(
      text: widget.durationSeconds?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.pop(
      context,
      _LyricsSearchParameters(
        title: _titleController.text,
        artist: _artistController.text,
        album: _albumController.text,
        durationSeconds: int.tryParse(_durationController.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: GlassContainer(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        color: theme.colorScheme.surface.withOpacity(0.96),
        blur: 8,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Search Lyrics',
                      style: TextStyle(
                        fontSize: 20.sp,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: _submit,
                    child: const Text('Search'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _artistController,
                decoration: const InputDecoration(
                  labelText: 'Artist',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _albumController,
                decoration: const InputDecoration(
                  labelText: 'Album',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _durationController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Duration seconds',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SongGapCountdownPill extends StatelessWidget {
  final Duration remaining;
  final Color foreground;
  final Color background;

  const _SongGapCountdownPill({
    required this.remaining,
    required this.foreground,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    final seconds = (remaining.inMilliseconds / 1000).ceil().clamp(1, 99);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background.withOpacity(0.42),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: foreground.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                foreground.withOpacity(0.72),
              ),
            ),
          ),
          const SizedBox(width: 9),
          Text(
            'next track: $seconds sec',
            style: TextStyle(
              color: foreground.withOpacity(0.72),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
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
