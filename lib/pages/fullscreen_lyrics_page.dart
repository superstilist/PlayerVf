import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/lyrics_model.dart';
import '../models/music_model.dart';
import '../models/settings_model.dart';
import '../services/music_service.dart';
import '../services/responsive.dart';
import '../services/safe_file_picker.dart';
import '../services/screen_recording_service.dart';
import '../widgets/blurred_cover_background.dart';
import '../widgets/cover_art_texture.dart';
import '../widgets/karaoke_sync_builder.dart';
import '../widgets/playback_progress_control.dart';
import '../utils/romaji_kana_converter.dart';
import 'fullscreen_lyrics_models.dart';
import 'player_utils.dart';

class FullscreenLyricsPage extends StatefulWidget {
  final MusicService musicService;
  final LyricsDocument lyrics;
  final String? lyricsKey;

  const FullscreenLyricsPage({
    required this.musicService,
    required this.lyrics,
    required this.lyricsKey,
  });

  @override
  State<FullscreenLyricsPage> createState() => FullscreenLyricsPageState();
}

class FullscreenLyricsPageState extends State<FullscreenLyricsPage> {
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
  double _lyricScrollVelocity = 0.0;
  bool _isAutoScrollingLyrics = false;
  bool _isLayoutEditing = false;
  bool _editPanelOpen = true;
  bool _fullscreenUiVisible = true;
  double? _cachedScrollTarget;
  bool _recordPanelOpen = false;
  bool _isPreparingRecording = false;
  bool _isRecordingLyrics = false;
  bool _recordTrimMode = false;
  bool _recordFadeVisible = false;
  Timer? _fullscreenUiHideTimer;
  Timer? _recordingWatchTimer;
  Timer? _mobileRecordFrameTimer;
  LyricsLayoutTarget _editTarget = LyricsLayoutTarget.lyrics;
  final LyricsEditHitZone _editHitZone = LyricsEditHitZone.compact;
  LyricsLayoutDraft? _layoutDraft;
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
  DateTime? _lastLyricScrollFrameTime;
  DateTime? _lastManualLyricsInteraction;

  static const Duration _manualLyricsBrowseHold = Duration(milliseconds: 2600);

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
      lyricsOwnerKey(widget.musicService.currentMusic);

  void _handleMusicServiceChanged() {
    final nextTrackKey = _currentLyricsKey;
    if (nextTrackKey == _trackKey) return;
    _trackKey = nextTrackKey;
    _lastActiveIndex = -1;
    _cachedScrollTarget = null;
    _lastManualLyricsInteraction = null;
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
    _cachedScrollTarget = null;
    _lyricScrollVelocity = 0.0;
    _lastLyricScrollFrameTime = null;
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
        ? (_layoutDraft ?? LyricsLayoutDraft.fromSettings(settings))
        : LyricsLayoutDraft.fromSettings(settings);
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
                    if (settings.lyricsGifBackgroundEnabled &&
                        settings.lyricsGifBackgroundUrl.isNotEmpty)
                      Positioned.fill(
                        child: Image.network(
                          settings.lyricsGifBackgroundUrl,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    if (settings.lyricsGifBackgroundEnabled &&
                        settings.lyricsGifBackgroundUrl.isNotEmpty)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black.withOpacity(
                              settings.lyricsFullscreenDimBackground),
                        ),
                      ),
                    if (settings.lyricsGifBackgroundUrl.isEmpty ||
                        !settings.lyricsGifBackgroundEnabled)
                      if (settings.lyricsCustomBackgroundColor.isNotEmpty)
                        Positioned.fill(
                          child: Container(
                            color: _parseColorString(
                                settings.lyricsCustomBackgroundColor),
                          ),
                        ),
                    if (settings.lyricsGifBackgroundUrl.isEmpty ||
                        !settings.lyricsGifBackgroundEnabled)
                      if (settings.lyricsCustomBackgroundColor.isEmpty)
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
                          child: FullscreenLyricsParticleField(
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
                            22.s, (14 + topInset * 0.35).s, 22.s, 22.s),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final objects = <LyricsLayeredObject>[
                              if (_isLayoutEditing || layout.hasAnyVisual)
                                for (var visualIndex = 0;
                                    visualIndex < layout.visualItems.length;
                                    visualIndex++)
                                  if (_isLayoutEditing ||
                                      (layout.visualItems[visualIndex].show &&
                                          layout.visualItems[visualIndex].path
                                              .trim()
                                              .isNotEmpty))
                                    LyricsLayeredObject(
                                      layer:
                                          layout.visualItems[visualIndex].layer,
                                      child: Positioned.fill(
                                        child: Align(
                                          alignment: Alignment.center,
                                          child: _layoutEditableObject(
                                            settings: settings,
                                            layout: layout,
                                            target: LyricsLayoutTarget.visual,
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
                                                    LyricsLayoutTarget.visual &&
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
                                LyricsLayeredObject(
                                  layer: layout.headerLayer,
                                  child: Positioned.fill(
                                    child: Align(
                                      alignment:
                                          _fullscreenHeaderSceneAlignment(
                                              layout),
                                      child: _layoutEditableObject(
                                        settings: settings,
                                        layout: layout,
                                        target: LyricsLayoutTarget.header,
                                        offset: layout.headerOffset,
                                        scale: layout.headerScale,
                                        rotation: layout.headerRotation,
                                        child: _buildFullscreenHeader(
                                            theme, music, settings, layout),
                                      ),
                                    ),
                                  ),
                                ),
                              LyricsLayeredObject(
                                layer: layout.lyricsLayer,
                                child: Positioned.fill(
                                  child: Align(
                                    alignment:
                                        _fullscreenLyricsSceneAlignment(layout),
                                    child: SizedBox(
                                      width: constraints.maxWidth,
                                      height: _fullscreenLyricsAutoHeight(
                                        constraints,
                                        layout,
                                      ),
                                      child: _layoutEditableObject(
                                        settings: settings,
                                        layout: layout,
                                        target: LyricsLayoutTarget.lyrics,
                                        offset: _fullscreenLyricsSceneOffset(
                                            layout),
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
                                LyricsLayeredObject(
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
                                                  LyricsLayoutTarget.controls,
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
      _layoutDraft = LyricsLayoutDraft.fromSettings(settings)
        ..customLayout = true;
      _editTarget = LyricsLayoutTarget.lyrics;
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
      textAlign: draft.textAlign,
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
      coverScale: draft.coverScale,
      fadeMode: draft.fadeMode,
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
      lyricsWidth: draft.letterSpacing,
      lyricsHeight: draft.lineHeight,
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
    required LyricsLayoutDraft layout,
    required LyricsLayoutTarget target,
    required Offset offset,
    required double scale,
    required double rotation,
    required Widget child,
    bool? selectedOverride,
    VoidCallback? onSelect,
  }) {
    final selected =
        selectedOverride ?? (_isLayoutEditing && _editTarget == target);
    final editPadSize = target == LyricsLayoutTarget.lyrics ||
            target == LyricsLayoutTarget.header ||
            target == LyricsLayoutTarget.visual
        ? _editPadSizeForTarget(layout, target)
        : null;
    final handleSize = _editHandleSize(scale, target, editPadSize);
    final hitPadding = _editHitPadding(scale, target, editPadSize);
    final handleOffset = -handleSize * 0.42;
    Widget content = child;
    if (_isLayoutEditing) {
      final frameChild =
          target == LyricsLayoutTarget.lyrics ? const SizedBox.expand() : child;
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
                    target == LyricsLayoutTarget.lyrics ? 2 : 6,
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
      if (target == LyricsLayoutTarget.lyrics ||
          target == LyricsLayoutTarget.header ||
          target == LyricsLayoutTarget.visual) {
        final padSize = editPadSize!;
        if (target == LyricsLayoutTarget.lyrics) {
          content = Stack(
            fit: StackFit.expand,
            children: [
              IgnorePointer(child: child),
              Positioned.fill(child: editPad),
            ],
          );
        } else {
          content = Stack(
            fit: StackFit.passthrough,
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
        }
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
    LyricsLayoutDraft layout,
    LyricsLayoutTarget target,
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
    LyricsLayoutTarget target,
    Size? padSize,
  ) {
    final zoneBoost = switch (_editHitZone) {
      LyricsEditHitZone.tiny => -4.0,
      LyricsEditHitZone.compact => 0.0,
      LyricsEditHitZone.touch => 6.0,
    };
    final inverseBoost = ((1.0 - scale) * 14).clamp(0.0, 12.0).toDouble();
    if (padSize != null) {
      final footprint = math.min(padSize.width, padSize.height);
      final dynamicSize =
          footprint * (target == LyricsLayoutTarget.lyrics ? 0.26 : 0.22);
      return (dynamicSize + inverseBoost + zoneBoost)
          .clamp(
            target == LyricsLayoutTarget.lyrics ? 32.0 : 36.0,
            target == LyricsLayoutTarget.lyrics ? 50.0 : 58.0,
          )
          .toDouble();
    }
    return (46 + inverseBoost + zoneBoost).clamp(38.0, 60.0).toDouble();
  }

  double _editHitPadding(
    double scale,
    LyricsLayoutTarget target,
    Size? padSize,
  ) {
    final handleSize = _editHandleSize(scale, target, padSize);
    final multiplier = switch (_editHitZone) {
      LyricsEditHitZone.tiny => 0.72,
      LyricsEditHitZone.compact => 1.0,
      LyricsEditHitZone.touch => 1.35,
    };
    if (target == LyricsLayoutTarget.lyrics) {
      return (handleSize * 0.08 * multiplier).clamp(3.0, 9.0).toDouble();
    }
    if (target == LyricsLayoutTarget.header) {
      return (handleSize * 0.12 * multiplier).clamp(5.0, 12.0).toDouble();
    }
    return (handleSize * 0.24 * multiplier).clamp(10.0, 22.0).toDouble();
  }

  Alignment _editPadAlignment(
    LyricsLayoutDraft layout,
    LyricsLayoutTarget target,
  ) {
    if (target == LyricsLayoutTarget.header) {
      return switch (layout.headerPosition) {
        LyricsFullscreenHeaderPosition.topLeft => Alignment.centerLeft,
        LyricsFullscreenHeaderPosition.topCenter => Alignment.center,
        LyricsFullscreenHeaderPosition.topRight => Alignment.centerRight,
      };
    }
    return Alignment.center;
  }

  Alignment _fullscreenHeaderSceneAlignment(LyricsLayoutDraft layout) {
    return switch (layout.headerPosition) {
      LyricsFullscreenHeaderPosition.topLeft => Alignment.topLeft,
      LyricsFullscreenHeaderPosition.topCenter => Alignment.topCenter,
      LyricsFullscreenHeaderPosition.topRight => Alignment.topRight,
    };
  }

  Alignment _fullscreenLyricsSceneAlignment(LyricsLayoutDraft layout) {
    return switch (layout.position) {
      LyricsFullscreenPosition.top => Alignment.topCenter,
      LyricsFullscreenPosition.center => Alignment.center,
      LyricsFullscreenPosition.bottom => Alignment.bottomCenter,
    };
  }

  Offset _fullscreenLyricsSceneOffset(LyricsLayoutDraft layout) {
    if (layout.customLayout || _isLayoutEditing) {
      return layout.lyricsOffset;
    }
    return Offset.zero;
  }

  Size _editPadSizeForTarget(
    LyricsLayoutDraft layout,
    LyricsLayoutTarget target,
  ) {
    final mediaSize = MediaQuery.sizeOf(context);
    final multiplier = switch (_editHitZone) {
      LyricsEditHitZone.tiny => 0.76,
      LyricsEditHitZone.compact => 1.0,
      LyricsEditHitZone.touch => 1.28,
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
      LyricsLayoutTarget.header => Size(
          (headerBaseWidth * multiplier)
              .clamp(70.0, mediaSize.width.clamp(140.0, 360.0))
              .toDouble(),
          (headerBaseHeight * multiplier).clamp(50.0, 190.0).toDouble(),
        ),
      LyricsLayoutTarget.lyrics => Size(
          (mediaSize.width * 0.28 * multiplier).clamp(120.0, 300.0).toDouble(),
          (mediaSize.height * 0.12 * multiplier).clamp(68.0, 170.0).toDouble(),
        ),
      LyricsLayoutTarget.visual => Size.square(
          (mediaSize.shortestSide * 0.28 * multiplier)
              .clamp(96.0, 240.0)
              .toDouble(),
        ),
      LyricsLayoutTarget.controls => Size.zero,
    };
  }

  Size _estimatedHeaderTextSize(LyricsLayoutDraft layout, double maxWidth) {
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

  LyricsLayoutDraft get _activeDraft {
    final draft = _layoutDraft;
    if (draft == null) {
      throw StateError('Fullscreen lyrics edit draft is not active.');
    }
    return draft;
  }

  void _selectVisual(LyricsLayoutDraft layout, int index) {
    if (layout.visualItems.isEmpty) return;
    layout.selectedVisualIndex = index.clamp(0, layout.visualItems.length - 1);
    _editTarget = LyricsLayoutTarget.visual;
  }

  void _startEditGesture(LyricsLayoutTarget target) {
    final draft = _activeDraft;
    setState(() {
      _editTarget = target;
      _gestureStartScale = _targetScale(draft, target);
      _gestureStartRotation = _targetRotation(draft, target);
    });
  }

  void _updateEditGesture(
      LyricsLayoutTarget target, ScaleUpdateDetails details) {
    setState(() {
      final draft = _activeDraft;
      final moveDelta = details.pointerCount >= 2
          ? details.focalPointDelta * 0.55
          : details.focalPointDelta;
      if (moveDelta != Offset.zero) {
        _applyMoveToDraft(draft, target, moveDelta);
      }
      if (details.pointerCount >= 2) {
        final minScale = target == LyricsLayoutTarget.visual ? 0.35 : 0.55;
        final maxScale = target == LyricsLayoutTarget.visual ? 2.25 : 1.75;
        final rotationLimit =
            target == LyricsLayoutTarget.visual ? 180.0 : 45.0;
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

  double _targetScale(LyricsLayoutDraft draft, LyricsLayoutTarget target) {
    return switch (target) {
      LyricsLayoutTarget.header => draft.headerScale,
      LyricsLayoutTarget.lyrics => draft.lyricsScale,
      LyricsLayoutTarget.controls => draft.controlsScale,
      LyricsLayoutTarget.visual => draft.selectedVisual?.scale ?? 1,
    };
  }

  void _setTargetScale(
    LyricsLayoutDraft draft,
    LyricsLayoutTarget target,
    double value,
  ) {
    switch (target) {
      case LyricsLayoutTarget.header:
        draft.headerScale = value;
      case LyricsLayoutTarget.lyrics:
        draft.lyricsScale = value;
      case LyricsLayoutTarget.controls:
        draft.controlsScale = value;
      case LyricsLayoutTarget.visual:
        draft.selectedVisual?.scale = value.clamp(0.35, 2.25).toDouble();
    }
  }

  double _targetRotation(LyricsLayoutDraft draft, LyricsLayoutTarget target) {
    return switch (target) {
      LyricsLayoutTarget.header => draft.headerRotation,
      LyricsLayoutTarget.lyrics => draft.lyricsRotation,
      LyricsLayoutTarget.controls => draft.controlsRotation,
      LyricsLayoutTarget.visual => draft.selectedVisual?.rotation ?? 0,
    };
  }

  void _setTargetRotation(
    LyricsLayoutDraft draft,
    LyricsLayoutTarget target,
    double value,
  ) {
    switch (target) {
      case LyricsLayoutTarget.header:
        draft.headerRotation = value;
      case LyricsLayoutTarget.lyrics:
        draft.lyricsRotation = value;
      case LyricsLayoutTarget.controls:
        draft.controlsRotation = value;
      case LyricsLayoutTarget.visual:
        draft.selectedVisual?.rotation = value.clamp(-180.0, 180.0).toDouble();
    }
  }

  void _applyMoveToDraft(
    LyricsLayoutDraft draft,
    LyricsLayoutTarget target,
    Offset delta,
  ) {
    final screenSize = MediaQuery.sizeOf(context);
    final xLimit = (screenSize.width * 0.72).clamp(420.0, 1600.0).toDouble();
    final yLimit = (screenSize.height * 0.72).clamp(420.0, 1400.0).toDouble();
    switch (target) {
      case LyricsLayoutTarget.header:
        final next = draft.headerOffset + delta;
        draft.headerOffset = Offset(
          next.dx.clamp(-xLimit, xLimit).toDouble(),
          next.dy.clamp(-yLimit, yLimit).toDouble(),
        );
      case LyricsLayoutTarget.lyrics:
        final next = draft.lyricsOffset + delta;
        draft.lyricsOffset = Offset(
          next.dx.clamp(-xLimit, xLimit).toDouble(),
          next.dy.clamp(-yLimit, yLimit).toDouble(),
        );
      case LyricsLayoutTarget.controls:
        final next = draft.controlsOffset + delta;
        draft.controlsOffset = Offset(
          next.dx.clamp(-xLimit, xLimit).toDouble(),
          next.dy.clamp(-yLimit, yLimit).toDouble(),
        );
      case LyricsLayoutTarget.visual:
        final visual = draft.selectedVisual;
        if (visual == null) return;
        final next = visual.offset + delta;
        visual.offset = Offset(
          next.dx.clamp(-xLimit, xLimit).toDouble(),
          next.dy.clamp(-yLimit, yLimit).toDouble(),
        );
    }
  }

  void _resizeEditTarget(LyricsLayoutTarget target, Offset delta) {
    setState(() {
      final draft = _activeDraft;
      final current = _targetScale(draft, target);
      final minScale = target == LyricsLayoutTarget.visual ? 0.35 : 0.55;
      final maxScale = target == LyricsLayoutTarget.visual ? 2.25 : 1.75;
      final next = (current + ((delta.dx + delta.dy) / 170))
          .clamp(minScale, maxScale)
          .toDouble();
      _setTargetScale(draft, target, next);
    });
  }

  void _rotateEditTarget(LyricsLayoutTarget target, Offset delta) {
    setState(() {
      final draft = _activeDraft;
      final current = _targetRotation(draft, target);
      final limit = target == LyricsLayoutTarget.visual ? 180.0 : 45.0;
      final next =
          (current + (delta.dx * 0.72)).clamp(-limit, limit).toDouble();
      _setTargetRotation(draft, target, next);
    });
  }

  Widget _buildEditPanel(
    BuildContext context,
    ThemeData theme,
    SettingsModel settings,
    LyricsLayoutDraft layout,
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
                      if (value) _editTarget = LyricsLayoutTarget.visual;
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
                _segmentedLyricsTextAlign(theme, layout),
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
                _editSectionLabel(theme, 'Cover art size'),
                _draftSlider(
                  theme: theme,
                  label: 'Cover size',
                  value: layout.coverScale,
                  min: 0.2,
                  max: 3.0,
                  display: '${(layout.coverScale * 100).round()}%',
                  onChanged: (value) =>
                      setState(() => layout.coverScale = value),
                ),
                _draftSlider(
                  theme: theme,
                  label: 'Track/artist text size',
                  value: layout.headerTextScale,
                  min: 0.5,
                  max: 2.5,
                  display: '${(layout.headerTextScale * 100).round()}%',
                  onChanged: (value) =>
                      setState(() => layout.headerTextScale = value),
                ),
                const Divider(height: 24),
                _editSectionLabel(theme, 'Lyrics fade'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      selected:
                          layout.fadeMode == LyricsFullscreenFadeMode.none,
                      avatar: const Icon(Icons.crop_square_rounded, size: 17),
                      label: const Text('None'),
                      onSelected: (_) => setState(() =>
                          layout.fadeMode = LyricsFullscreenFadeMode.none),
                    ),
                    FilterChip(
                      selected: layout.fadeMode == LyricsFullscreenFadeMode.top,
                      avatar: const Icon(Icons.border_top_rounded, size: 17),
                      label: const Text('Fade top'),
                      onSelected: (_) => setState(
                          () => layout.fadeMode = LyricsFullscreenFadeMode.top),
                    ),
                    FilterChip(
                      selected:
                          layout.fadeMode == LyricsFullscreenFadeMode.bottom,
                      avatar: const Icon(Icons.border_bottom_rounded, size: 17),
                      label: const Text('Fade bottom'),
                      onSelected: (_) => setState(() =>
                          layout.fadeMode = LyricsFullscreenFadeMode.bottom),
                    ),
                    FilterChip(
                      selected:
                          layout.fadeMode == LyricsFullscreenFadeMode.both,
                      avatar: const Icon(Icons.gradient_rounded, size: 17),
                      label: const Text('Fade both'),
                      onSelected: (_) => setState(() =>
                          layout.fadeMode = LyricsFullscreenFadeMode.both),
                    ),
                  ],
                ),
                const Divider(height: 24),
                _editSectionLabel(theme, 'Font'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _fontPresetChip(layout, LyricsFullscreenFontPreset.system,
                        Icons.text_fields_rounded, 'System'),
                    _fontPresetChip(layout, LyricsFullscreenFontPreset.robot,
                        Icons.android, 'Robot'),
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
                    _fontPresetChip(layout, LyricsFullscreenFontPreset.arial,
                        Icons.text_fields_rounded, 'Arial'),
                    _fontPresetChip(
                        layout,
                        LyricsFullscreenFontPreset.helvetica,
                        Icons.text_fields_rounded,
                        'Helvetica'),
                    _fontPresetChip(layout, LyricsFullscreenFontPreset.georgia,
                        Icons.text_fields_rounded, 'Georgia'),
                    _fontPresetChip(
                        layout,
                        LyricsFullscreenFontPreset.timesNewRoman,
                        Icons.text_fields_rounded,
                        'Times'),
                    _fontPresetChip(
                        layout,
                        LyricsFullscreenFontPreset.courierNew,
                        Icons.text_fields_rounded,
                        'Courier'),
                    _fontPresetChip(layout, LyricsFullscreenFontPreset.verdana,
                        Icons.text_fields_rounded, 'Verdana'),
                    _fontPresetChip(
                        layout,
                        LyricsFullscreenFontPreset.trebuchetMS,
                        Icons.text_fields_rounded,
                        'Trebuchet'),
                    _fontPresetChip(layout, LyricsFullscreenFontPreset.impact,
                        Icons.text_fields_rounded, 'Impact'),
                    _fontPresetChip(
                        layout,
                        LyricsFullscreenFontPreset.comicSans,
                        Icons.text_fields_rounded,
                        'Comic'),
                    _fontPresetChip(layout, LyricsFullscreenFontPreset.tahoma,
                        Icons.text_fields_rounded, 'Tahoma'),
                    _fontPresetChip(
                        layout,
                        LyricsFullscreenFontPreset.centuryGothic,
                        Icons.text_fields_rounded,
                        'Century'),
                    _fontPresetChip(
                        layout,
                        LyricsFullscreenFontPreset.lucidaConsole,
                        Icons.text_fields_rounded,
                        'Lucida'),
                    _fontPresetChip(layout, LyricsFullscreenFontPreset.segoeUI,
                        Icons.text_fields_rounded, 'Segoe'),
                    _fontPresetChip(layout, LyricsFullscreenFontPreset.calibri,
                        Icons.text_fields_rounded, 'Calibri'),
                    _fontPresetChip(layout, LyricsFullscreenFontPreset.cambria,
                        Icons.text_fields_rounded, 'Cambria'),
                    _fontPresetChip(layout, LyricsFullscreenFontPreset.consolas,
                        Icons.text_fields_rounded, 'Consolas'),
                    _fontPresetChip(
                        layout,
                        LyricsFullscreenFontPreset.constantia,
                        Icons.text_fields_rounded,
                        'Constantia'),
                    _fontPresetChip(layout, LyricsFullscreenFontPreset.corbel,
                        Icons.text_fields_rounded, 'Corbel'),
                    _fontPresetChip(
                        layout,
                        LyricsFullscreenFontPreset.franklinGothic,
                        Icons.text_fields_rounded,
                        'Franklin'),
                    _fontPresetChip(layout, LyricsFullscreenFontPreset.gabriola,
                        Icons.text_fields_rounded, 'Gabriola'),
                    _fontPresetChip(layout, LyricsFullscreenFontPreset.palatino,
                        Icons.text_fields_rounded, 'Palatino'),
                    _fontPresetChip(layout, LyricsFullscreenFontPreset.garamond,
                        Icons.text_fields_rounded, 'Garamond'),
                    _fontPresetChip(
                        layout,
                        LyricsFullscreenFontPreset.bookAntiqua,
                        Icons.text_fields_rounded,
                        'Book A.'),
                    _fontPresetChip(
                        layout,
                        LyricsFullscreenFontPreset.lucidaSans,
                        Icons.text_fields_rounded,
                        'Lucida S.'),
                    _fontPresetChip(
                        layout,
                        LyricsFullscreenFontPreset.arialBlack,
                        Icons.text_fields_rounded,
                        'Arial B.'),
                    _fontPresetChip(
                        layout,
                        LyricsFullscreenFontPreset.bookmanOldStyle,
                        Icons.text_fields_rounded,
                        'Bookman'),
                  ],
                ),
                const Divider(height: 24),
                _editSectionLabel(theme, 'Letter spacing & line height'),
                _draftSlider(
                  theme: theme,
                  label: 'Letter spacing',
                  value: layout.letterSpacing,
                  min: -2.0,
                  max: 5.0,
                  display: layout.letterSpacing == 0
                      ? 'Normal'
                      : layout.letterSpacing < 0
                          ? '${layout.letterSpacing.toStringAsFixed(1)} tight'
                          : '${layout.letterSpacing.toStringAsFixed(1)} loose',
                  onChanged: (value) =>
                      setState(() => layout.letterSpacing = value),
                ),
                _draftSlider(
                  theme: theme,
                  label: 'Line height',
                  value: layout.lineHeight,
                  min: 0.5,
                  max: 2.0,
                  display: layout.lineHeight == 1.2
                      ? 'Normal'
                      : layout.lineHeight < 1.2
                          ? '${layout.lineHeight.toStringAsFixed(1)}x compact'
                          : '${layout.lineHeight.toStringAsFixed(1)}x spacious',
                  onChanged: (value) =>
                      setState(() => layout.lineHeight = value),
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

  Widget _editHint(ThemeData theme, LyricsLayoutDraft layout) {
    final scale = switch (_editTarget) {
      LyricsLayoutTarget.header => layout.headerScale,
      LyricsLayoutTarget.lyrics => layout.lyricsScale,
      LyricsLayoutTarget.controls => layout.controlsScale,
      LyricsLayoutTarget.visual => layout.selectedVisual?.scale ?? 1,
    };
    final rotation = switch (_editTarget) {
      LyricsLayoutTarget.header => layout.headerRotation,
      LyricsLayoutTarget.lyrics => layout.lyricsRotation,
      LyricsLayoutTarget.controls => layout.controlsRotation,
      LyricsLayoutTarget.visual => layout.selectedVisual?.rotation ?? 0,
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

  Widget _sizePresetChip(LyricsLayoutDraft layout, double scale, String label) {
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

  Widget _segmentedPosition(ThemeData theme, LyricsLayoutDraft layout) {
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

  Widget _segmentedHeaderPosition(ThemeData theme, LyricsLayoutDraft layout) {
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

  Widget _segmentedLyricsTextAlign(ThemeData theme, LyricsLayoutDraft layout) {
    return SegmentedButton<LyricsFullscreenTextAlign>(
      showSelectedIcon: false,
      selected: {layout.textAlign},
      onSelectionChanged: (selection) =>
          setState(() => layout.textAlign = selection.first),
      segments: const [
        ButtonSegment(
          value: LyricsFullscreenTextAlign.left,
          icon: Icon(Icons.format_align_left_rounded),
          label: Text('Left'),
        ),
        ButtonSegment(
          value: LyricsFullscreenTextAlign.center,
          icon: Icon(Icons.format_align_center_rounded),
          label: Text('Center'),
        ),
        ButtonSegment(
          value: LyricsFullscreenTextAlign.right,
          icon: Icon(Icons.format_align_right_rounded),
          label: Text('Right'),
        ),
      ],
    );
  }

  Widget _coverStyleChip(
    LyricsLayoutDraft layout,
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
    LyricsLayoutDraft layout,
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
    LyricsLayoutDraft layout,
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
    LyricsLayoutDraft layout,
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
    LyricsLayoutDraft layout,
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
    LyricsLayoutDraft layout,
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

  Future<void> _pickLyricsVisual(LyricsLayoutDraft layout) async {
    final path = await pickFilePathSafely(
      context,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'],
    );
    if (!mounted || path == null || path.trim().isEmpty) return;
    setState(() {
      final index = layout.visualItems.length;
      layout.visualItems.add(LyricsVisualDraftItem(
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
      _editTarget = LyricsLayoutTarget.visual;
    });
  }

  void _removeSelectedVisual(LyricsLayoutDraft layout) {
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
        _editTarget == LyricsLayoutTarget.visual) {
      _editTarget = LyricsLayoutTarget.lyrics;
    }
  }

  int _selectedLayer(LyricsLayoutDraft layout) {
    return switch (_editTarget) {
      LyricsLayoutTarget.header => layout.headerLayer,
      LyricsLayoutTarget.lyrics => layout.lyricsLayer,
      LyricsLayoutTarget.controls => layout.controlsLayer,
      LyricsLayoutTarget.visual => layout.selectedVisual?.layer ?? 4,
    };
  }

  void _changeSelectedLayer(LyricsLayoutDraft layout, int delta) {
    final next = (_selectedLayer(layout) + delta).clamp(0, 9);
    switch (_editTarget) {
      case LyricsLayoutTarget.header:
        layout.headerLayer = next;
      case LyricsLayoutTarget.lyrics:
        layout.lyricsLayer = next;
      case LyricsLayoutTarget.controls:
        layout.controlsLayer = next;
      case LyricsLayoutTarget.visual:
        layout.selectedVisual?.layer = next;
    }
  }

  Widget _buildFullscreenVisualOverlay(
    ThemeData theme,
    LyricsVisualDraftItem visual,
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
    LyricsLayoutDraft layout,
  ) {
    final showCover = layout.showCover;
    final showName = layout.showTrackName;
    final isDesktop = MediaQuery.sizeOf(context).width >= 720;
    final preferredCoverSize = switch (layout.headerStyle) {
      LyricsFullscreenHeaderStyle.bigCover => 300.s,
      LyricsFullscreenHeaderStyle.coverAbove => 250.s,
      LyricsFullscreenHeaderStyle.fullCover => isDesktop ? 800.s : 500.s,
      _ => 150.s,
    };
    final alignment = switch (layout.headerPosition) {
      LyricsFullscreenHeaderPosition.topLeft => MainAxisAlignment.start,
      LyricsFullscreenHeaderPosition.topCenter => MainAxisAlignment.center,
      LyricsFullscreenHeaderPosition.topRight => MainAxisAlignment.end,
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackWidth = MediaQuery.sizeOf(context).width - 44;
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : fallbackWidth.toDouble();
        final coverSizeRatio = switch (layout.headerStyle) {
          LyricsFullscreenHeaderStyle.fullCover => 0.95,
          LyricsFullscreenHeaderStyle.coverAbove => 0.85,
          _ => 0.65,
        };
        final coverSize =
            (maxWidth * coverSizeRatio * layout.coverScale).toDouble();
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
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    textAlign: layout.headerStyle ==
                            LyricsFullscreenHeaderStyle.coverAbove
                        ? TextAlign.center
                        : TextAlign.start,
                    style: TextStyle(
                      color: layout.textColor,
                      fontFamily: _fontFamilyFor(layout),
                      fontSize: (layout.headerStyle ==
                                  LyricsFullscreenHeaderStyle.bigCover
                              ? 24.sp
                              : 21.sp) *
                          layout.headerTextScale,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                    ),
                  ),
                  Text(
                    music?.artist ?? '',
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    textAlign: layout.headerStyle ==
                            LyricsFullscreenHeaderStyle.coverAbove
                        ? TextAlign.center
                        : TextAlign.start,
                    style: TextStyle(
                      color: layout.textColor.withOpacity(0.68),
                      fontFamily: _fontFamilyFor(layout),
                      fontSize: 13.sp * layout.headerTextScale,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ],
              )
            : null;
        Widget? fittedTitle({
          required double width,
        }) {
          if (titleCore == null) return null;
          return SizedBox(
            width: width,
            child: titleCore,
          );
        }

        final content =
            layout.headerStyle == LyricsFullscreenHeaderStyle.coverAbove
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
                              child: fittedTitle(
                            width: double.infinity,
                          )!),
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

  String? _fontFamilyFor(LyricsLayoutDraft layout) {
    return switch (layout.fontPreset) {
      LyricsFullscreenFontPreset.system => null,
      LyricsFullscreenFontPreset.robot => 'Roboto',
      LyricsFullscreenFontPreset.serif => 'serif',
      LyricsFullscreenFontPreset.mono => 'monospace',
      LyricsFullscreenFontPreset.rounded => 'sans-serif',
      LyricsFullscreenFontPreset.notoSans => 'NotoSans',
      LyricsFullscreenFontPreset.notoJapanese => 'NotoSansJP',
      LyricsFullscreenFontPreset.notoChinese => 'NotoSansSC',
      LyricsFullscreenFontPreset.display => 'serif',
      LyricsFullscreenFontPreset.handwritten => 'cursive',
      LyricsFullscreenFontPreset.arial => 'Arial',
      LyricsFullscreenFontPreset.helvetica => 'Helvetica',
      LyricsFullscreenFontPreset.georgia => 'Georgia',
      LyricsFullscreenFontPreset.timesNewRoman => 'Times New Roman',
      LyricsFullscreenFontPreset.courierNew => 'Courier New',
      LyricsFullscreenFontPreset.verdana => 'Verdana',
      LyricsFullscreenFontPreset.trebuchetMS => 'Trebuchet MS',
      LyricsFullscreenFontPreset.impact => 'Impact',
      LyricsFullscreenFontPreset.comicSans => 'Comic Sans MS',
      LyricsFullscreenFontPreset.tahoma => 'Tahoma',
      LyricsFullscreenFontPreset.centuryGothic => 'Century Gothic',
      LyricsFullscreenFontPreset.lucidaConsole => 'Lucida Console',
      LyricsFullscreenFontPreset.segoeUI => 'Segoe UI',
      LyricsFullscreenFontPreset.calibri => 'Calibri',
      LyricsFullscreenFontPreset.cambria => 'Cambria',
      LyricsFullscreenFontPreset.consolas => 'Consolas',
      LyricsFullscreenFontPreset.constantia => 'Constantia',
      LyricsFullscreenFontPreset.corbel => 'Corbel',
      LyricsFullscreenFontPreset.franklinGothic => 'Franklin Gothic Medium',
      LyricsFullscreenFontPreset.gabriola => 'Gabriola',
      LyricsFullscreenFontPreset.palatino => 'Palatino Linotype',
      LyricsFullscreenFontPreset.garamond => 'Garamond',
      LyricsFullscreenFontPreset.bookAntiqua => 'Book Antiqua',
      LyricsFullscreenFontPreset.lucidaSans => 'Lucida Sans Unicode',
      LyricsFullscreenFontPreset.arialBlack => 'Arial Black',
      LyricsFullscreenFontPreset.bookmanOldStyle => 'Bookman Old Style',
    };
  }

  Widget _buildFullscreenCover(
    ThemeData theme,
    Music? music,
    SettingsModel settings,
    LyricsLayoutDraft layout,
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
                    layout.coverStyle == LyricsFullscreenCoverStyle.glow
                        ? 2
                        : 0,
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
    LyricsLayoutDraft layout,
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
                      EdgeInsets.symmetric(horizontal: 10.s, vertical: 6.s),
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
            padding: EdgeInsets.symmetric(horizontal: 14.s, vertical: 8.s),
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
                return ExcludeSemantics(
                  excluding: true,
                  child: Semantics(
                    label: 'Playback progress',
                    value: '${(progress * 100).round()}%',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) =>
                          seekFromDx(details.localPosition.dx, width),
                      onHorizontalDragUpdate: (details) =>
                          seekFromDx(details.localPosition.dx, width),
                      child: CustomPaint(
                        painter: FullscreenCompactProgressPainter(
                          progress: progress,
                          activeColor: settings.accentColor,
                          inactiveColor: Colors.white.withOpacity(0.16),
                          enabled: enabled,
                        ),
                        child: const SizedBox.expand(),
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
        return ExcludeSemantics(
            excluding: true,
            child: ValueListenableBuilder<Duration>(
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
            ));
      },
    );
  }

  Widget _buildPlainLyrics(
    LyricsDocument lyrics,
    bool generateKanaLyrics,
    LyricsLayoutDraft layout,
  ) {
    final fontScale = context.read<SettingsModel>().lyricsFullscreenFontScale;
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
                fontSize: (25.0 * fontScale).sp,
                height: 1.45,
                fontWeight: FontWeight.w800,
              ),
              textAlign: _lyricsTextAlign(layout.textAlign),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyLyrics(LyricsLayoutDraft layout) {
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
    LyricsLayoutDraft layout, {
    required double opacity,
    required double fontSize,
    required double height,
    required FontWeight fontWeight,
  }) {
    return TextStyle(
      color: _fullscreenLyricsColor(context, opacity),
      fontFamily: _fontFamilyFor(layout),
      fontSize: fontSize * layout.fontScale,
      height: height * layout.lineHeight,
      fontWeight: fontWeight,
      letterSpacing: layout.letterSpacing,
    );
  }

  double _fullscreenVerticalPadding(
    double height,
    bool timed,
    LyricsLayoutDraft layout,
  ) {
    final position = layout.position;
    if (timed) {
      return switch (position) {
        LyricsFullscreenPosition.top =>
          (height * 0.18).clamp(40.0.s, 150.0.s).toDouble(),
        LyricsFullscreenPosition.center =>
          (height * 0.42).clamp(90.0.s, 280.0.s).toDouble(),
        LyricsFullscreenPosition.bottom =>
          (height * 0.58).clamp(130.0.s, 360.0.s).toDouble(),
      };
    }
    return switch (position) {
      LyricsFullscreenPosition.top =>
        (height * 0.05).clamp(12.0.s, 56.0.s).toDouble(),
      LyricsFullscreenPosition.center =>
        (height * 0.18).clamp(28.0.s, 120.0.s).toDouble(),
      LyricsFullscreenPosition.bottom =>
        (height * 0.34).clamp(64.0.s, 220.0.s).toDouble(),
    };
  }

  Color _parseColorString(String value) {
    final v = value.trim();
    if (v.isEmpty) return Colors.black;
    if (v.startsWith('#')) {
      final hex = v.substring(1);
      if (hex.length == 6) return Color(int.parse('FF$hex', radix: 16));
      if (hex.length == 8) return Color(int.parse(hex, radix: 16));
    }
    return Colors.black;
  }

  double _fullscreenLyricsAutoHeight(
    BoxConstraints constraints,
    LyricsLayoutDraft layout,
  ) {
    final maxHeight = constraints.maxHeight.isFinite
        ? constraints.maxHeight
        : MediaQuery.sizeOf(context).height;
    if (maxHeight <= 0) return 160.0.s;

    final safeInsets = _fullscreenLyricsSafeInsets(constraints, layout);
    final reservedHeight = safeInsets.top + safeInsets.bottom;
    final freeHeight = (maxHeight - reservedHeight)
        .clamp(maxHeight * 0.34, maxHeight)
        .toDouble();
    final minimum = maxHeight < 420 ? 140.0.s : 200.0.s;
    final oldCap = switch (layout.position) {
      LyricsFullscreenPosition.top => maxHeight * 0.56,
      LyricsFullscreenPosition.center => maxHeight * 0.74,
      LyricsFullscreenPosition.bottom => maxHeight * 0.56,
    };

    final expandedHeight = freeHeight + reservedHeight * 0.78;
    final targetHeight = layout.customLayout
        ? math.max(oldCap, expandedHeight)
        : oldCap + reservedHeight * 0.35;
    return targetHeight.clamp(minimum, maxHeight).toDouble();
  }

  EdgeInsets _fullscreenLyricsSafeInsets(
    BoxConstraints constraints,
    LyricsLayoutDraft layout,
  ) {
    final width = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : MediaQuery.sizeOf(context).width;
    final horizontal = (width * 0.065).clamp(16.0, 82.0).toDouble();
    final headerVisible = layout.showCover || layout.showTrackName;
    final headerNearTop = headerVisible && layout.headerOffset.dy < 180;
    final headerAvoidance = !headerNearTop
        ? 0.0
        : switch (layout.headerStyle) {
            LyricsFullscreenHeaderStyle.bigCover => 178.0.s,
            LyricsFullscreenHeaderStyle.coverAbove => 138.0.s,
            LyricsFullscreenHeaderStyle.nameOnly => 64.0.s,
            LyricsFullscreenHeaderStyle.compact => 96.0.s,
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
            LyricsFullscreenControlsStyle.panel43 => 48.0.s,
            LyricsFullscreenControlsStyle.minimal => 52.0.s,
            LyricsFullscreenControlsStyle.pill => 74.0.s,
            LyricsFullscreenControlsStyle.glow => 82.0.s,
            LyricsFullscreenControlsStyle.classic => 76.0.s,
          }
        : 14.0.s;
    final bottom = (controlsAvoidance * layout.controlsScale)
        .clamp(14.0.s, constraints.maxHeight * 0.26)
        .toDouble();
    return EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom);
  }

  Widget _buildTimedLyrics(
    LyricsDocument lyrics,
    bool generateKanaLyrics,
    LyricsLayoutDraft layout,
  ) {
    final settings = context.read<SettingsModel>();
    final baseColor = _isLayoutEditing
        ? _activeDraft.textColor
        : settings.lyricsFullscreenTextColor;
    final activeColor = baseColor;
    final fontScale = settings.lyricsFullscreenFontScale;
    final baseFontSize = 22.0 * fontScale;
    final baseKanaSize = 15.0 * fontScale;
    return ExcludeSemantics(
      excluding: true,
      child: KaraokeSyncBuilder(
        key: ValueKey('timed-${_trackKey ?? 'none'}'),
        musicService: widget.musicService,
        lyrics: lyrics,
        transitionGapMs: settings.karaokeTransitionGapMs,
        builder: (context, syncState) {
          final activeIndex = syncState.activeIndex;
          final manualBrowsing = _isManualLyricsBrowsing;
          _scrollActiveLineIntoView(activeIndex);
          final activeEntryProgress = _easeOutCubic(
            ((syncState.position - syncState.lineSync.lineStart)
                        .inMilliseconds /
                    760.0)
                .clamp(0.0, 1.0),
          );
          return LayoutBuilder(
            builder: (context, constraints) {
              final verticalPadding = _fullscreenVerticalPadding(
                  constraints.maxHeight, true, layout);
              final safeInsets =
                  _fullscreenLyricsSafeInsets(constraints, layout);
              final lineTextAlign = _lyricsTextAlign(layout.textAlign);
              return Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _markManualLyricsBrowsing(),
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    _markManualLyricsBrowsing();
                  }
                },
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (_isAutoScrollingLyrics) return false;
                    if (notification is ScrollStartNotification ||
                        (notification is ScrollUpdateNotification &&
                            notification.dragDetails != null)) {
                      _markManualLyricsBrowsing();
                    }
                    return false;
                  },
                  child: ListView.builder(
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
                      final isPrev = index == activeIndex - 1;
                      final isNext = index == syncState.lineSync.nextIndex;
                      final isSideLine = isPrev || isNext;
                      final distance = activeIndex < 0
                          ? 6
                          : (index - activeIndex).abs().clamp(0, 6);

                      const vPad = 4.0;
                      final edgePad = switch (layout.textAlign) {
                        LyricsFullscreenTextAlign.left => 24.0,
                        LyricsFullscreenTextAlign.right => 24.0,
                        LyricsFullscreenTextAlign.center => 12.0,
                      };
                      final distanceFade =
                          (1.0 - distance * 0.12).clamp(0.28, 1.0).toDouble();
                      final inactiveMainOpacity =
                          manualBrowsing ? 0.72 : 0.34 * distanceFade;
                      final inactiveKanaOpacity =
                          manualBrowsing ? 0.48 : 0.24 * distanceFade;
                       final textEdgeShadows = [
                        Shadow(
                          color: Colors.black.withOpacity(isActive
                              ? 0.82
                              : isSideLine
                                  ? 0.48
                                  : 0.58),
                          blurRadius: isActive
                              ? 3.4
                              : isSideLine
                                  ? 1.8
                                  : 2.4,
                          offset: const Offset(0, 1.4),
                        ),
                        Shadow(
                          color: Colors.black.withOpacity(isActive
                              ? 0.68
                              : isSideLine
                                  ? 0.26
                                  : 0.42),
                          blurRadius: isActive
                              ? 5.8
                              : isSideLine
                                  ? 2.2
                                  : 3.6,
                        ),
                        if (!isActive && !isSideLine)
                          Shadow(
                            color: baseColor.withOpacity(
                              manualBrowsing ? 0.18 : 0.18 * distanceFade,
                            ),
                            blurRadius:
                                manualBrowsing ? 8.0 : 11.0 + distance * 1.8,
                          ),
                        Shadow(
                          color: Colors.black.withOpacity(
                            isActive
                                ? 0.18
                                : manualBrowsing
                                    ? 0.08
                                    : 0.04,
                          ),
                          blurRadius: 2.4,
                          offset: const Offset(0, -0.8),
                        ),
                      ];

                      final mainStyle = _fullscreenLyricsTextStyle(
                        context,
                        layout,
                        opacity: isActive
                            ? 1.0
                            : isSideLine
                                ? 0.32
                                : 0.42 * distanceFade,
                        fontSize: baseFontSize.sp,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                      ).copyWith(
                        color: isActive
                            ? activeColor
                            : isSideLine
                                ? baseColor.withOpacity(
                                    manualBrowsing ? 0.68 : 0.32,
                                  )
                                : baseColor.withOpacity(inactiveMainOpacity),
                        fontFamily: _fontFamilyFor(layout),
                        fontWeight:
                            isActive ? FontWeight.w900 : FontWeight.w500,
                        shadows: textEdgeShadows,
                      );
                      final kanaStyle = _fullscreenLyricsTextStyle(
                        context,
                        layout,
                        opacity: isActive
                            ? 0.68
                            : isSideLine
                                ? 0.18
                                : 0.22 * distanceFade,
                        fontSize: baseKanaSize.sp,
                        height: 1.18,
                        fontWeight: FontWeight.w600,
                      ).copyWith(
                        color: isActive
                            ? Color.lerp(activeColor, Colors.white, 0.28)
                            : isSideLine
                                ? baseColor.withOpacity(
                                    manualBrowsing ? 0.44 : 0.20,
                                  )
                                : baseColor.withOpacity(inactiveKanaOpacity),
                      );

                      Widget textWidget;
                      if (_hasParentheses(line.text)) {
                        final mainSpans =
                            _parenthesizedSpans(line.text, mainStyle);
                        textWidget = Text.rich(
                          TextSpan(children: mainSpans),
                          textAlign: lineTextAlign,
                        );
                        if (generateKanaLyrics) {
                          final romaji =
                              RomajiKanaConverter.generatedRomajiForLine(
                                  line.text);
                          if (romaji.isNotEmpty) {
                            textWidget = Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                textWidget,
                                const SizedBox(height: 4),
                                Text(
                                  romaji,
                                  style: kanaStyle,
                                  textAlign: lineTextAlign,
                                ),
                              ],
                            );
                          }
                        }
                      } else {
                        textWidget = _buildGeneratedKanaLine(
                          text: line.text,
                          generateKana: generateKanaLyrics,
                          mainStyle: mainStyle,
                          generatedStyle: kanaStyle,
                          textAlign: lineTextAlign,
                          expandWidth: true,
                        );
                      }

                      if (isActive) {
                        final fill =
                            syncState.lineSync.fillProgress.clamp(0.0, 1.0);
                        final unfilledColor = baseColor.withValues(
                          alpha: manualBrowsing ? 0.48 : 0.34,
                        );
                        textWidget = karaokeFillMaskForLyrics(
                          fill: fill,
                          activeColor: activeColor,
                          highlightColor:
                              Color.lerp(activeColor, Colors.white, 0.34)!,
                          unfilledColor: unfilledColor,
                          child: textWidget,
                        );
                      }

                      final handover = syncState.lineSync.transitionProgress.clamp(0.0, 1.0);
                      final drop =
                          isPrev ? _easeInOutCubic(activeEntryProgress) : 0.0;
                      final rise = isActive
                          ? activeEntryProgress
                          : isNext
                              ? handover
                              : 1.0;
                      final translateY = isPrev
                          ? 4.0 * drop
                          : isActive
                              ? 5.0 * (1.0 - rise)
                              : isNext
                                  ? -3.0 * (1.0 - rise)
                                  : 0.0;
                      final opacity = isPrev
                          ? (manualBrowsing ? 0.58 : 0.22)
                          : isActive
                              ? 0.94 + 0.06 * rise
                              : isNext
                                  ? (manualBrowsing ? 0.64 : 0.22)
                                  : (manualBrowsing
                                          ? 0.52 + 0.24 * distanceFade
                                          : 0.12 + 0.16 * distanceFade)
                                      .clamp(0.0, 1.0);
                      final scale = isActive ? 1.04 : 1.0;
                      final safeOpacity = opacity.clamp(0.0, 1.0).toDouble();
                      final paddedText = Container(
                        width: double.infinity,
                        alignment: _lyricsLineAlignment(layout.textAlign),
                        padding: EdgeInsets.only(
                          left: layout.textAlign == LyricsFullscreenTextAlign.left
                              ? edgePad
                              : edgePad * 0.5,
                          right: layout.textAlign == LyricsFullscreenTextAlign.right
                              ? edgePad
                              : edgePad * 0.5,
                          top: vPad,
                          bottom: vPad,
                        ),
                        child: textWidget,
                      );
                      final blurAmount = manualBrowsing
                          ? 0.0
                          : isActive
                              ? (0.28 * (1.0 - rise))
                                  .clamp(0.0, 0.28)
                                  .toDouble()
                              : isPrev || isNext
                                  ? 0.0
                                  : _backgroundLyricBlur(
                                      index - activeIndex,
                                      distance,
                                    );

                      return Transform.translate(
                        key: _lineKeys.putIfAbsent(index, GlobalKey.new),
                        offset: Offset(
                          0,
                          _snapToPixel(context, translateY),
                        ),
                        child: Transform.scale(
                          scale: scale,
                          child: RepaintBoundary(
                            child: Opacity(
                              opacity: safeOpacity,
                              child: blurAmount > 0.05
                                  ? ImageFiltered(
                                      imageFilter: ui.ImageFilter.blur(
                                        sigmaX: blurAmount,
                                        sigmaY: blurAmount,
                                      ),
                                      child: paddedText,
                                    )
                                  : paddedText,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  static bool _hasParentheses(String text) {
    return text.contains('(') || text.contains('（');
  }

  static List<InlineSpan> _parenthesizedSpans(
    String text,
    TextStyle baseStyle,
  ) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'(\([^)]*\)|（[^）]*）)');
    int lastEnd = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      spans.add(TextSpan(
        text: match.group(0),
        style: baseStyle.copyWith(
          fontSize: (baseStyle.fontSize ?? 16) * 0.72,
          fontWeight: FontWeight.w400,
        ),
      ));
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }
    return spans;
  }

  static double _easeOutCubic(double t) {
    final v = t.clamp(0.0, 1.0);
    return 1.0 - math.pow(1.0 - v, 3.0).toDouble();
  }

  static double _easeInOutCubic(double t) {
    final v = t.clamp(0.0, 1.0);
    return v < 0.5
        ? 4.0 * v * v * v
        : 1.0 - math.pow(-2.0 * v + 2.0, 3.0).toDouble() / 2.0;
  }

  static Widget karaokeFillMaskForLyrics({
    required double fill,
    required Color activeColor,
    required Color highlightColor,
    required Color unfilledColor,
    required Widget child,
  }) {
    final progress = fill.clamp(0.0, 1.0).toDouble();
    if (progress >= 0.995) {
      return ShaderMask(
        shaderCallback: (bounds) => LinearGradient(
          colors: [activeColor, activeColor],
        ).createShader(bounds),
        blendMode: BlendMode.srcIn,
        child: child,
      );
    }

    if (progress < 0.008) {
      return ShaderMask(
        shaderCallback: (bounds) => LinearGradient(
          colors: [unfilledColor, unfilledColor],
        ).createShader(bounds),
        blendMode: BlendMode.srcIn,
        child: child,
      );
    }

    const feather = 0.055;
    const epsilon = 0.001;
    final edgeStart = (progress - feather).clamp(0.0, 1.0 - epsilon);
    final edgeEnd = math.max(edgeStart + epsilon,
        (progress + feather).clamp(epsilon, 1.0).toDouble());
    return ShaderMask(
      shaderCallback: (bounds) {
        return LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          stops: [0.0, edgeStart, edgeEnd, 1.0],
          colors: [
            activeColor,
            highlightColor,
            unfilledColor,
            unfilledColor,
          ],
        ).createShader(bounds);
      },
      blendMode: BlendMode.srcIn,
      child: child,
    );
  }

  static double _backgroundLyricBlur(int signedDistance, int distance) {
    if (distance <= 0) return 0.0;
    if (distance <= 3) return 0.0;

    final afterActive = signedDistance > 0;
    final edgeDepth = math.pow((distance - 3) / 3.0, 1.9).toDouble();
    final directionBias = afterActive ? 0.04 : 0.12;
    final blur = edgeDepth * 2.85 + directionBias;
    return blur.clamp(0.0, 3.85).toDouble();
  }

  static TextAlign _lyricsTextAlign(LyricsFullscreenTextAlign align) {
    return switch (align) {
      LyricsFullscreenTextAlign.left => TextAlign.left,
      LyricsFullscreenTextAlign.center => TextAlign.center,
      LyricsFullscreenTextAlign.right => TextAlign.right,
    };
  }

  static Alignment _lyricsLineAlignment(LyricsFullscreenTextAlign align) {
    return switch (align) {
      LyricsFullscreenTextAlign.left => Alignment.centerLeft,
      LyricsFullscreenTextAlign.center => Alignment.center,
      LyricsFullscreenTextAlign.right => Alignment.centerRight,
    };
  }

  static double _snapToPixel(BuildContext context, double value) {
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    if (devicePixelRatio <= 0) return value;
    return (value * devicePixelRatio).roundToDouble() / devicePixelRatio;
  }

  bool get _isManualLyricsBrowsing {
    final lastInteraction = _lastManualLyricsInteraction;
    if (lastInteraction == null) return false;
    return DateTime.now().difference(lastInteraction) < _manualLyricsBrowseHold;
  }

  void _markManualLyricsBrowsing() {
    _lastManualLyricsInteraction = DateTime.now();
    _lyricScrollVelocity = 0.0;
    if (mounted) setState(() {});
  }

  void _scrollActiveLineIntoView(int activeIndex) {
    if (activeIndex < 0) return;
    if (_isManualLyricsBrowsing) return;
    final lineChanged = activeIndex != _lastActiveIndex;
    _lastActiveIndex = activeIndex;
    if (lineChanged) {
      _cachedScrollTarget = null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      if (_cachedScrollTarget == null || lineChanged) {
        double? revealTarget(int lineIndex) {
          final lineContext = _lineKeys[lineIndex]?.currentContext;
          final renderObject = lineContext?.findRenderObject();
          final viewport = renderObject == null
              ? null
              : RenderAbstractViewport.maybeOf(renderObject);
          if (renderObject == null || viewport == null) return null;
          return viewport.getOffsetToReveal(renderObject, 0.5).offset.clamp(
                _scrollController.position.minScrollExtent,
                _scrollController.position.maxScrollExtent,
              );
        }

        _cachedScrollTarget = revealTarget(activeIndex);
        if (_cachedScrollTarget == null) {
          final viewportDimension =
              _scrollController.position.viewportDimension;
          const estimatedLineExtent = 78.0;
          _cachedScrollTarget = ((activeIndex * estimatedLineExtent) -
                  (viewportDimension / 2) +
                  (estimatedLineExtent / 2))
              .clamp(0.0, _scrollController.position.maxScrollExtent);
        }
      }
      _moveLyricsScrollToward(_cachedScrollTarget!, lineChanged: lineChanged);
    });
  }

  int _nextTimedLineIndex(int activeIndex) {
    for (var i = activeIndex + 1; i < _lyrics.lines.length; i++) {
      if (_lyrics.lines[i].timestamp != null) return i;
    }
    return activeIndex + 1;
  }

  void _moveLyricsScrollToward(
    double target, {
    required bool lineChanged,
  }) {
    if (!_scrollController.hasClients) return;
    final now = DateTime.now();
    final previousFrame = _lastLyricScrollFrameTime;
    _lastLyricScrollFrameTime = now;
    final dt = previousFrame == null
        ? 1 / 60
        : now.difference(previousFrame).inMicroseconds / 1000000.0;
    final frameSeconds = dt.clamp(1 / 240, 1 / 24).toDouble();
    final position = _scrollController.position;
    final boundedTarget = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final current = _scrollController.offset;
    final delta = boundedTarget - current;

    if (delta.abs() < 0.18) {
      _lyricScrollVelocity = 0.0;
      return;
    }

    if (delta.abs() < 1.2 && _lyricScrollVelocity.abs() < 8.0) {
      _lyricScrollVelocity = 0.0;
      _isAutoScrollingLyrics = true;
      try {
        _scrollController.jumpTo(boundedTarget);
      } finally {
        _isAutoScrollingLyrics = false;
      }
      return;
    }

    if (delta.abs() > position.viewportDimension * 0.92) {
      _lyricScrollVelocity = 0.0;
      _lastLyricScrollFrameTime = now;
    }

    final viewport = math.max(240.0, position.viewportDimension);
    final followRate = lineChanged ? 5.0 : 3.4;
    final targetStep = delta * (1.0 - math.exp(-frameSeconds * followRate));
    final maxVelocity = math.max(380.0, viewport * 1.6);
    final desiredVelocity =
        (targetStep / frameSeconds).clamp(-maxVelocity, maxVelocity).toDouble();
    final smoothing = 1.0 - math.exp(-frameSeconds * 6.2);
    _lyricScrollVelocity = _lyricScrollVelocity +
        (desiredVelocity - _lyricScrollVelocity) * smoothing;
    final maxStep = maxVelocity * frameSeconds;
    final step = (_lyricScrollVelocity * frameSeconds)
        .clamp(-maxStep, maxStep)
        .toDouble();
    final nextOffset = _snapToPixel(
      context,
      (current + step)
          .clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          )
          .toDouble(),
    ).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _isAutoScrollingLyrics = true;
    try {
      _scrollController.jumpTo(nextOffset);
    } finally {
      _isAutoScrollingLyrics = false;
    }
  }

  Widget _buildPlainLyricsText(
    LyricsDocument lyrics,
    bool generateKanaLyrics,
    TextStyle style, {
    TextAlign? textAlign,
  }) {
    if (!generateKanaLyrics) {
      return SizedBox(
        width: double.infinity,
        child: Text(
          lyrics.plainText,
          textAlign: textAlign,
          style: style,
          softWrap: true,
          overflow: TextOverflow.visible,
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: Text.rich(
        TextSpan(
          style: style,
          children: _plainLyricsKanaSpans(lyrics, style),
        ),
        textAlign: textAlign,
        softWrap: true,
        overflow: TextOverflow.visible,
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
    TextStyle? mainStyle,
    required TextStyle generatedStyle,
    TextAlign textAlign = TextAlign.center,
    bool expandWidth = true,
  }) {
    Widget textBox(String value, TextStyle? style) {
      final textWidget = Text(
        value,
        style: style,
        softWrap: true,
        overflow: TextOverflow.visible,
        textAlign: textAlign,
      );
      return expandWidth
          ? SizedBox(width: double.infinity, child: textWidget)
          : textWidget;
    }

    if (!generateKana) {
      return textBox(text, mainStyle);
    }
    final romaji = RomajiKanaConverter.generatedRomajiForLine(text);
    if (romaji.isEmpty) {
      return textBox(text, mainStyle);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: expandWidth
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.start,
      children: [
        textBox(text, mainStyle),
        SizedBox(height: 5.s),
        textBox(romaji, generatedStyle),
      ],
    );
  }
}

class FullscreenLyricsParticleField extends StatefulWidget {
  final Color accentColor;
  final Color textColor;
  final LyricsFullscreenParticlePack pack;
  final String customPack;

  const FullscreenLyricsParticleField({
    required this.accentColor,
    required this.textColor,
    required this.pack,
    required this.customPack,
  });

  @override
  State<FullscreenLyricsParticleField> createState() =>
      FullscreenLyricsParticleFieldState();
}

class FullscreenLyricsParticleFieldState
    extends State<FullscreenLyricsParticleField> {
  int _cycle = 0;
  final Map<String, TextPainter> _painterCache = {};

  @override
  void didUpdateWidget(covariant FullscreenLyricsParticleField oldWidget) {
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
            painter: FullscreenLyricsParticlePainter(
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

class FullscreenLyricsParticlePainter extends CustomPainter {
  final double progress;
  final Color accentColor;
  final Color textColor;
  final LyricsFullscreenParticlePack pack;
  final String customPack;
  final Map<String, TextPainter> painterCache;

  const FullscreenLyricsParticlePainter({
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
  bool shouldRepaint(covariant FullscreenLyricsParticlePainter oldDelegate) {
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
    path.cubicTo(-size * 0.45, -size * 0.8, -size * 0.95, -size * 0.45,
        -size * 0.95, size * 0.05);
    path.cubicTo(
        -size * 0.95, size * 0.5, -size * 0.5, size * 0.8, 0, size * 1.05);
    path.cubicTo(size * 0.5, size * 0.8, size * 0.95, size * 0.5, size * 0.95,
        size * 0.05);
    path.cubicTo(
        size * 0.95, -size * 0.45, size * 0.45, -size * 0.8, 0, -size * 0.35);
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

class FullscreenCompactProgressPainter extends CustomPainter {
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final bool enabled;

  const FullscreenCompactProgressPainter({
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
  bool shouldRepaint(covariant FullscreenCompactProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.enabled != enabled;
  }
}
