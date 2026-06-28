import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/music_model.dart';
import '../models/settings_model.dart';
import '../services/cover_color_service.dart';
import '../services/music_service.dart';
import '../services/listen_together_service.dart';
import '../services/performance_policy.dart';
import '../services/responsive.dart';
import '../services/orb_controller.dart';
import '../services/safe_file_picker.dart';
import '../widgets/audio_effects_menu.dart';
import '../widgets/blurred_cover_background.dart';
import '../widgets/cover_art_texture.dart';
import '../widgets/glass_container.dart';
import '../widgets/lanczos_cover_art.dart';
import '../widgets/playback_progress_control.dart';
import '../widgets/stable_video_surface.dart';
import '../widgets/orb_system.dart';
import '../widgets/particle_system.dart';
import 'artist_page.dart';
import '../widgets/listen_together_sheet.dart';
import 'lyrics_sheet_content.dart';
import 'player_controls_widgets.dart';
import 'player_utils.dart';
import 'video_page.dart';

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
    _syncPalette(context.read<MusicService>().currentMusic?.coverPath,
        settings.orbPaletteSize);
  }

  void _syncPalette(String? path, int paletteSize) {
    final normalized = path ?? '';
    final key = '$normalized::$paletteSize';
    if (key == _palettePath) return;
    _palettePath = key;
    CoverColorService.fromPath(normalized, paletteSize: paletteSize).then((p) {
      if (mounted) {
        setState(() => _palette = p);
        context.read<OrbController>().setColors(p.orbColors.isNotEmpty
            ? p.orbColors
            : [
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
        SingleActivator(LogicalKeyboardKey.space): _PlayerTogglePlayIntent(),
        SingleActivator(LogicalKeyboardKey.mediaPlayPause):
            _PlayerTogglePlayIntent(),
        SingleActivator(LogicalKeyboardKey.mediaTrackNext): _PlayerNextIntent(),
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
            context
                .read<ListenTogetherService>()
                .runPartyPlaybackCommand('toggle', musicService);
            return null;
          }),
          _PlayerNextIntent: CallbackAction<_PlayerNextIntent>(onInvoke: (_) {
            context
                .read<ListenTogetherService>()
                .runPartyPlaybackCommand('next', musicService);
            return null;
          }),
          _PlayerPreviousIntent:
              CallbackAction<_PlayerPreviousIntent>(onInvoke: (_) {
            context
                .read<ListenTogetherService>()
                .runPartyPlaybackCommand('previous', musicService);
            return null;
          }),
          _PlayerVolumeIntent:
              CallbackAction<_PlayerVolumeIntent>(onInvoke: (intent) {
            musicService.adjustVolumeBy(intent.delta);
            return null;
          }),
          _PlayerMuteIntent: CallbackAction<_PlayerMuteIntent>(onInvoke: (_) {
            musicService.toggleMute();
            return null;
          }),
        },
        child: Focus(
          autofocus: true,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragUpdate: (details) {
              if (details.primaryDelta == null || details.primaryDelta! <= 0) {
                return;
              }
              _closeDragDistance += details.primaryDelta!;
            },
            onVerticalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              final shouldClose = velocity > 700 || _closeDragDistance > 96.h;
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
                    else if (settings.backgroundMode ==
                            BackgroundMode.customImage &&
                        settings.customBackgroundImage.isNotEmpty)
                      BlurredCoverBackground(
                        coverArtPath: settings.customBackgroundImage,
                        surfaceColor: theme.colorScheme.surface,
                        overlayColor:
                            theme.colorScheme.surface.withOpacity(0.6),
                        blur: policy.backgroundBlur + 20,
                      )
                    else
                      BlurredCoverBackground(
                        coverArtPath: currentMusic?.coverPath ?? '',
                        surfaceColor: theme.colorScheme.surface,
                        overlayColor:
                            theme.colorScheme.surface.withOpacity(0.6),
                        blur: policy.backgroundBlur + 20,
                      ),
                    IgnorePointer(
                      child: const OrbSystem(
                        paused: false,
                        intensity: 1.0,
                      ),
                    ),
                    if (settings.particleEffect != ParticleEffect.none &&
                        settings.particleEffect !=
                            ParticleEffect.coverArtShadowPoints)
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
                                horizontal: isPhone ? 18.w : 24.w,
                                vertical: isShortPhone ? 6.h : 12.h,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(height: isShortPhone ? 2.h : 10.h),
                                  _buildHeroArtwork(currentMusic, palette,
                                      musicService, settings),
                                  SizedBox(height: isShortPhone ? 16.h : 28.h),
                                  _buildMetadata(currentMusic, theme),
                                  SizedBox(height: isShortPhone ? 20.h : 30.h),
                                  _buildControlsSection(
                                      musicService, theme, palette),
                                  SizedBox(height: isShortPhone ? 16.h : 24.h),
                                  _buildQuickQueue(
                                      context, musicService, theme, palette),
                                  SizedBox(height: isShortPhone ? 28.h : 40.h),
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
                    boxShadow: [
                      BoxShadow(
                        color: palette.dominant.withOpacity(0.25),
                        blurRadius: 40,
                        spreadRadius: -4,
                        offset: const Offset(0, 12),
                      ),
                    ],
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
                  fontSize: (isPhone ? 26 : 32).sp,
                  fontWeight: FontWeight.w900,
                  color: theme.colorScheme.onSurface,
                  height: 1.15,
                  letterSpacing: -0.3,
                ),
                softWrap: true,
                overflow: TextOverflow.visible,
                textAlign: TextAlign.left,
              ),
            ),
          ),
          SizedBox(height: 6.h),
          Hero(
            tag: 'artist-${music?.id ?? 'none'}',
            child: Material(
              color: Colors.transparent,
              child: _buildArtistLinks(theme, music, isPhone),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArtistLinks(ThemeData theme, Music? music, bool isPhone) {
    final artist = music?.artist ?? '';
    if (artist.isEmpty) {
      return Text(
        'Unknown Artist',
        style: TextStyle(
          fontSize: (isPhone ? 15 : 18).sp,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.primary.withValues(alpha: 0.8),
        ),
        softWrap: true,
        overflow: TextOverflow.visible,
        textAlign: TextAlign.left,
      );
    }
    final parts = artist.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (parts.length <= 1) {
      return GestureDetector(
        onTap: () => _openArtistPage(artist, music?.coverPath),
        child: Text(
          artist,
          style: TextStyle(
            fontSize: (isPhone ? 15 : 18).sp,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.primary.withValues(alpha: 0.8),
          ),
          softWrap: true,
          overflow: TextOverflow.visible,
          textAlign: TextAlign.left,
        ),
      );
    }
    return Wrap(
      spacing: 0, runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (int i = 0; i < parts.length; i++) ...[
          GestureDetector(
            onTap: () => _openArtistPage(parts[i], music?.coverPath),
            child: Text(
              parts[i],
              style: TextStyle(
                fontSize: (isPhone ? 15 : 18).sp,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary.withValues(alpha: 0.8),
                decoration: TextDecoration.underline,
                decorationColor: theme.colorScheme.primary.withValues(alpha: 0.4),
              ),
              softWrap: true,
              overflow: TextOverflow.visible,
              textAlign: TextAlign.left,
            ),
          ),
          if (i < parts.length - 1)
            Text(
              ', ',
              style: TextStyle(
                fontSize: (isPhone ? 15 : 18).sp,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary.withValues(alpha: 0.8),
              ),
            ),
        ],
      ],
    );
  }

  void _openArtistPage(String artistName, String? coverPath) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, __, ___) => ArtistPage(
          artistName: artistName,
          localCoverPath: coverPath,
        ),
        transitionsBuilder: (_, anim, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: anim,
              curve: Curves.easeOutCubic,
            ),
            child: child,
          );
        },
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
      color: theme.colorScheme.surface.withValues(alpha: 0.42),
      blur: isPhone ? 18 : 22,
      border: Border.all(
        color: theme.colorScheme.outlineVariant.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.58 : 0.72),
        width: 1.15,
      ),
      child: Column(
        children: [
          ValueListenableBuilder<Duration>(
            valueListenable: musicService.songGapRemainingNotifier,
            builder: (context, remaining, _) {
              if (remaining <= Duration.zero) return const SizedBox.shrink();
              return Padding(
                padding: EdgeInsets.only(bottom: 12.h),
                child: SongGapCountdownPill(
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
          _buildSecondaryControls(musicService, theme, palette, isPhone),
          SizedBox(height: isShortPhone ? 12.h : 16.h),
          _buildPrimaryControls(musicService, theme, isPhone),
          SizedBox(height: isShortPhone ? 12.h : 16.h),
          _buildVolumeSlider(musicService, theme, isPhone),
        ],
      ),
    );
  }

  Widget _buildSecondaryControls(
      MusicService musicService, ThemeData theme, CoverArtPalette palette, bool isPhone) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildControlButton(
          icon: musicService.isShuffle
              ? Icons.shuffle_on_rounded
              : Icons.shuffle_rounded,
          color: musicService.isShuffle
              ? palette.accent
              : theme.colorScheme.onSurface.withOpacity(0.4),
          onPressed: musicService.toggleShuffle,
          tooltip: 'Shuffle',
        ),
        Consumer<ListenTogetherService>(
          builder: (context, party, _) {
            final isActive = party.isPartyHosting || party.isPartyJoined;
            return _buildControlButton(
              icon: isActive ? Icons.groups_rounded : Icons.group_add_rounded,
              color: isActive
                  ? palette.accent
                  : theme.colorScheme.onSurface.withOpacity(0.44),
              onPressed: party.isPartyBusy
                  ? null
                  : () => showListenTogetherSheet(context),
              tooltip: 'Listen Together',
            );
          },
        ),
        _buildControlButton(
          icon: Icons.tune_rounded,
          color: theme.colorScheme.onSurface.withOpacity(0.44),
          onPressed: () => showAudioEffectsMenu(context),
          tooltip: 'Audio Effects',
        ),
        _buildControlButton(
          icon: musicService.isRepeatOne
              ? Icons.repeat_one_rounded
              : Icons.repeat_rounded,
          color: (musicService.isRepeatOne || musicService.isRepeatAll)
              ? palette.accent
              : theme.colorScheme.onSurface.withOpacity(0.4),
          onPressed: musicService.toggleRepeatMode,
          tooltip: 'Repeat',
        ),
      ],
    );
  }

  Widget _buildPrimaryControls(
      MusicService musicService, ThemeData theme, bool isPhone) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          iconSize: 32.s,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: const Icon(Icons.skip_previous_rounded),
          onPressed: () => context
              .read<ListenTogetherService>()
              .runPartyPlaybackCommand('previous', musicService),
        ),
        SizedBox(width: 20.w),
        ValueListenableBuilder<bool>(
          valueListenable: musicService.playingNotifier,
          builder: (context, isPlaying, child) {
            return SmoothPlayPauseButton(
              isPlaying: isPlaying,
              onPressed: () => context
                  .read<ListenTogetherService>()
                  .runPartyPlaybackCommand('toggle', musicService),
              size: Size((isPhone ? 66 : 72).s, (isPhone ? 52 : 56).s),
              iconSize: (isPhone ? 31 : 34).s,
            );
          },
        ),
        SizedBox(width: 20.w),
        IconButton(
          iconSize: 32.s,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: const Icon(Icons.skip_next_rounded),
          onPressed: () => context
              .read<ListenTogetherService>()
              .runPartyPlaybackCommand('next', musicService),
        ),
      ],
    );
  }

  Widget _buildVolumeSlider(
      MusicService musicService, ThemeData theme, bool isPhone) {
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          musicService.adjustVolumeBy(event.scrollDelta.dy < 0 ? 3 : -3);
        }
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 4.w),
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
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
    required String tooltip,
  }) {
    return IconButton(
      tooltip: tooltip,
      iconSize: 22.s,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      icon: Icon(icon, color: color),
      onPressed: onPressed,
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
          padding: EdgeInsets.all(24.s),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                  leading: const Icon(Icons.edit_rounded),
                  title: const Text('Edit Metadata'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _showEditMetadataDialog(context);
                    });
                  }),
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

  Future<void> _showEditMetadataDialog(BuildContext context) async {
    final musicService = Provider.of<MusicService>(context, listen: false);
    final music = musicService.currentMusic;
    if (music == null) {
      _showPlayerSnack(context, 'No track selected.');
      return;
    }

    final titleController = TextEditingController(text: music.title);
    final artistController = TextEditingController(text: music.artist);
    final albumController = TextEditingController(text: music.album);
    final genreController = TextEditingController(text: music.genre);
    final yearController = TextEditingController(text: music.year);
    bool isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.transparent,
          contentPadding: EdgeInsets.zero,
          content: GlassContainer(
            width: 320.s,
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 620),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Edit Info',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 100, height: 100,
                        child: music.coverPath.isNotEmpty
                            ? (music.coverPath.startsWith('http')
                                ? Image.network(music.coverPath, fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => _editCoverFallback(context))
                                : CoverArtTexture(coverArtPath: music.coverPath, width: 100, height: 100))
                            : _editCoverFallback(context),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildEditField('Title', titleController),
                    const SizedBox(height: 12),
                    _buildEditField('Artist', artistController),
                    const SizedBox(height: 12),
                    _buildEditField('Album', albumController),
                    const SizedBox(height: 12),
                    _buildEditField('Genre', genreController),
                    const SizedBox(height: 12),
                    _buildEditField('Year', yearController, keyboardType: TextInputType.number),
                    if (isSaving) ...[
                      const SizedBox(height: 16),
                      const LinearProgressIndicator(minHeight: 2),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: isSaving ? null : () async {
                            setDialogState(() => isSaving = true);
                            final cleanedTitle = titleController.text.trim().isEmpty
                                ? 'Unknown title'
                                : titleController.text.trim();
                            final cleanedArtist = artistController.text.trim().isEmpty
                                ? 'Unknown Artist'
                                : artistController.text.trim();
                            final cleanedAlbum = albumController.text.trim().isEmpty
                                ? 'Unknown Album'
                                : albumController.text.trim();
                            final cleanedGenre = genreController.text.trim().isEmpty
                                ? 'Unknown'
                                : genreController.text.trim();
                            final yearMatch = RegExp(r'\d{4}').firstMatch(yearController.text);
                            final cleanedYear = yearMatch?.group(0) ?? yearController.text.trim();

                            await musicService.updateMusicMetadata(
                              music.id,
                              cleanedTitle,
                              cleanedArtist,
                              cleanedAlbum,
                              cleanedGenre,
                              year: cleanedYear,
                            );
                            if (dialogContext.mounted) Navigator.pop(dialogContext);
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    titleController.dispose();
    artistController.dispose();
    albumController.dispose();
    genreController.dispose();
    yearController.dispose();
  }

  Widget _buildEditField(String label, TextEditingController controller,
      {TextInputType keyboardType = TextInputType.text}) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _editCoverFallback(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(Icons.music_note_rounded, size: 40,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
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
          width: 320.s,
          padding: EdgeInsets.all(22.s),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Add to Playlist',
                      style: TextStyle(
                          fontSize: 18.sp, fontWeight: FontWeight.bold),
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
          width: 400.s.clamp(300.0, 480.0),
          padding: EdgeInsets.all(22.s),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16.s),
                    child: AspectRatio(
                      aspectRatio: 1.0,
                      child: CoverArtTexture(
                        coverArtPath: music.coverPath,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    ),
                  ),
                  SizedBox(width: 14.s),
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
                              borderRadius: BorderRadius.circular(
                                  Responsive.listArtRadius),
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
    final initialLyricsKey = lyricsOwnerKey(musicService.currentMusic);
    final lyrics =
        await musicService.loadLyricsDocumentForCurrent(searchOnline: false);
    if (!context.mounted) {
      _isLyricsSheetOpen = false;
      return;
    }
    final currentLyricsKey = lyricsOwnerKey(musicService.currentMusic);
    final initialLyrics = initialLyricsKey == currentLyricsKey ? lyrics : null;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: Responsive.isTablet ? 0.72 : 0.68,
        minChildSize: Responsive.isTablet ? 0.42 : 0.36,
        maxChildSize: Responsive.isTablet ? 0.92 : 0.88,
        builder: (_, controller) => LyricsSheetContent(
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
