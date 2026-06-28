import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../models/lyrics_model.dart';
import '../models/settings_model.dart';
import '../services/music_service.dart';
import '../services/responsive.dart';
import '../utils/romaji_kana_converter.dart';
import '../widgets/glass_container.dart';
import '../widgets/karaoke_sync_builder.dart';
import 'fullscreen_lyrics_page.dart';
import 'lyrics_sheets.dart';
import 'player_utils.dart';

class LyricsSheetContent extends StatefulWidget {
  final MusicService musicService;
  final LyricsDocument? initialLyrics;
  final String? initialLyricsKey;
  final ScrollController scrollController;
  final Future<String?> Function() pickLyricsFile;

  const LyricsSheetContent({
    super.key,
    required this.musicService,
    required this.initialLyrics,
    required this.initialLyricsKey,
    required this.scrollController,
    required this.pickLyricsFile,
  });

  @override
  State<LyricsSheetContent> createState() => _LyricsSheetContentState();
}

class _LyricsSheetContentState extends State<LyricsSheetContent> {
  late LyricsDocument? _lyrics = widget.initialLyrics;
  String? _trackKey;
  String? _lyricsKey;
  int _lastActiveIndex = -1;
  double _lyricScrollVelocity = 0.0;
  bool _isAutoScrollingLyrics = false;
  DateTime? _lastLyricScrollFrameTime;
  double? _cachedScrollTarget;
  DateTime? _lastManualLyricsInteraction;
  bool _isSearchingLyrics = false;
  final Map<int, GlobalKey> _lineKeys = {};

  static const Duration _manualLyricsBrowseHold = Duration(milliseconds: 2600);

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
      lyricsOwnerKey(widget.musicService.currentMusic);

  void _handleMusicServiceChanged() {
    final nextTrackKey = _currentLyricsKey;
    if (nextTrackKey == _trackKey) return;
    _trackKey = nextTrackKey;
    _lastActiveIndex = -1;
    _cachedScrollTarget = null;
    _lyricScrollVelocity = 0.0;
    _lastLyricScrollFrameTime = null;
    _lastManualLyricsInteraction = null;
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
    final settings = context.watch<SettingsModel>();
    final generateKanaLyrics = settings.generateKanaLyrics;
    final baseFontSize = settings.fontSize;
    final enhancedScale = settings.lyricsEnhancedFontScale;
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
                            baseFontSize,
                            enhancedScale,
                          )
                        : SingleChildScrollView(
                            controller: widget.scrollController,
                            child: _buildPlainLyricsText(
                              visibleLyrics,
                              generateKanaLyrics,
                              TextStyle(
                                  fontSize: baseFontSize.sp, height: 1.55),
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
    double baseFontSize,
    double enhancedScale,
  ) {
    final inactiveFont = (baseFontSize * enhancedScale);
    final settings = context.read<SettingsModel>();
    return ExcludeSemantics(
        excluding: true,
        child: KaraokeSyncBuilder(
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
                final verticalPadding = (constraints.maxHeight * 0.34)
                    .clamp(72.0, 150.0)
                    .toDouble();
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
                      controller: widget.scrollController,
                      padding: EdgeInsets.symmetric(vertical: verticalPadding),
                      itemCount: lyrics.lines.length,
                      itemBuilder: (context, index) {
                        final line = lyrics.lines[index];
                        final isActive = index == activeIndex;
                        final isPrev = index == activeIndex - 1;
                        final isNext = index == syncState.lineSync.nextIndex;
                        final distance = activeIndex < 0
                            ? 6
                            : (index - activeIndex).abs().clamp(0, 6);

                        const hPad = 18.0;
                        const vPad = 14.0;

                        final activeColor = theme.colorScheme.primary;
                        final inactiveColor = theme.colorScheme.onSurface;
                        final distanceFade =
                            (1.0 - distance * 0.12).clamp(0.30, 1.0).toDouble();

                        final inactiveOpacity =
                            manualBrowsing ? 0.70 : 0.42 * distanceFade;
                        final kanaOpacity =
                            manualBrowsing ? 0.46 : 0.24 * distanceFade;
                        final mainStyle = TextStyle(
                          color: isActive
                              ? activeColor
                              : inactiveColor.withOpacity(inactiveOpacity),
                          fontSize: (inactiveFont * (isActive ? 1.06 : 1.0)).sp,
                          height: 1.25,
                          fontWeight:
                              isActive ? FontWeight.w900 : FontWeight.w600,
                          shadows: [
                            Shadow(
                              color: Colors.black
                                  .withOpacity(isActive ? 0.42 : 0.18),
                              blurRadius: isActive ? 12 : 4,
                              offset: const Offset(0, 1),
                            ),
                            Shadow(
                              color: (isActive ? activeColor : inactiveColor)
                                  .withOpacity(isActive ? 0.38 : 0.18),
                              blurRadius: isActive ? 28 : 12,
                            ),
                            Shadow(
                              color: Colors.white
                                  .withOpacity(isActive ? 0.18 : 0.08),
                              blurRadius: 2.4,
                              offset: const Offset(0, -0.8),
                            ),
                            if (isActive)
                              Shadow(
                                color: activeColor.withOpacity(0.34),
                                blurRadius: 24,
                              ),
                          ],
                        );
                        final kanaStyle = TextStyle(
                          color: (isActive ? activeColor : inactiveColor)
                              .withOpacity(isActive ? 0.62 : kanaOpacity),
                          fontSize: (inactiveFont * 0.72).sp,
                          height: 1.22,
                          fontWeight: FontWeight.w600,
                        );

                        Widget textWidget;
                        if (_hasParentheses(line.text)) {
                          final mainSpans =
                              _parenthesizedSpans(line.text, mainStyle);
                          textWidget = Text.rich(
                            TextSpan(children: mainSpans),
                            textAlign: TextAlign.center,
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
                                  Text(romaji,
                                      style: kanaStyle,
                                      textAlign: TextAlign.center),
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
                            expandWidth: false,
                          );
                        }

                        if (isActive) {
                          final fill =
                              syncState.lineSync.fillProgress.clamp(0.0, 1.0);
                          final unfilledColor = inactiveColor.withValues(
                            alpha: manualBrowsing ? 0.58 : 0.32,
                          );
                          textWidget = FullscreenLyricsPageState
                              .karaokeFillMaskForLyrics(
                            fill: fill,
                            activeColor: activeColor,
                            highlightColor:
                                Color.lerp(activeColor, Colors.white, 0.32)!,
                            unfilledColor: unfilledColor,
                            child: textWidget,
                          );
                        }

                        final handover = syncState.lineSync.transitionProgress.clamp(0.0, 1.0);
                        final rise = isActive
                            ? activeEntryProgress
                            : isNext
                                ? handover
                                : 1.0;
                        final translateY = isPrev
                            ? 4.0 * _easeInOutCubic(activeEntryProgress)
                            : isActive
                                ? 5.0 * (1.0 - rise)
                                : isNext
                                    ? -3.0 * (1.0 - rise)
                                    : 0.0;
                        final scale = isActive ? 1.04 : 1.0;
                        final opacity = isPrev
                            ? (manualBrowsing ? 0.58 : 0.24)
                            : isActive
                                ? 1.0
                                : isNext
                                    ? (manualBrowsing
                                        ? 0.68
                                        : 0.30 + 0.16 * handover)
                                    : (manualBrowsing
                                            ? 0.54 + 0.22 * distanceFade
                                            : 0.16 + 0.22 * distanceFade)
                                        .clamp(0.0, 1.0);
                        final blurAmount = manualBrowsing ||
                                isActive ||
                                distance <= 2
                            ? 0.0
                            : math
                                .min(3.2, math.pow(distance - 2, 1.55) * 0.62)
                                .toDouble();
                        Widget lineWidget = Container(
                          width: double.infinity,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(
                            horizontal: hPad,
                            vertical: vPad,
                          ),
                          child: textWidget,
                        );
                        if (blurAmount > 0.05) {
                          lineWidget = ImageFiltered(
                            imageFilter: ui.ImageFilter.blur(
                              sigmaX: blurAmount,
                              sigmaY: blurAmount,
                            ),
                            child: lineWidget,
                          );
                        }

                        return Transform.translate(
                          key: _lineKeys.putIfAbsent(index, GlobalKey.new),
                          offset: Offset(0, translateY),
                          child: Transform.scale(
                            scale: scale,
                            child: Opacity(
                              opacity: opacity.clamp(0.0, 1.0).toDouble(),
                              child: RepaintBoundary(child: lineWidget),
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
        ));
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
      if (!mounted || !widget.scrollController.hasClients) return;

      if (_cachedScrollTarget == null || lineChanged) {
        double? revealTarget(int lineIndex) {
          final lineContext = _lineKeys[lineIndex]?.currentContext;
          final renderObject = lineContext?.findRenderObject();
          final viewport = renderObject == null
              ? null
              : RenderAbstractViewport.maybeOf(renderObject);
          if (renderObject == null || viewport == null) return null;
          return viewport.getOffsetToReveal(renderObject, 0.48).offset.clamp(
                widget.scrollController.position.minScrollExtent,
                widget.scrollController.position.maxScrollExtent,
              );
        }

        _cachedScrollTarget = revealTarget(activeIndex);
        if (_cachedScrollTarget == null) {
          final viewportDimension =
              widget.scrollController.position.viewportDimension;
          const estimatedLineExtent = 62.0;
          _cachedScrollTarget = ((activeIndex * estimatedLineExtent) -
                  (viewportDimension / 2) +
                  (estimatedLineExtent / 2))
              .clamp(0.0, widget.scrollController.position.maxScrollExtent);
        }
      }
      _moveLyricsScrollToward(_cachedScrollTarget!, lineChanged: lineChanged);
    });
  }

  void _moveLyricsScrollToward(
    double target, {
    required bool lineChanged,
  }) {
    if (!widget.scrollController.hasClients) return;
    final now = DateTime.now();
    final previousFrame = _lastLyricScrollFrameTime;
    _lastLyricScrollFrameTime = now;
    final dt = previousFrame == null
        ? 1 / 60
        : now.difference(previousFrame).inMicroseconds / 1000000.0;
    final frameSeconds = dt.clamp(1 / 240, 1 / 24).toDouble();
    final position = widget.scrollController.position;
    final boundedTarget = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final current = widget.scrollController.offset;
    final delta = boundedTarget - current;

    if (delta.abs() < 0.18) {
      _lyricScrollVelocity = 0.0;
      return;
    }

    if (delta.abs() < 1.2 && _lyricScrollVelocity.abs() < 8.0) {
      _lyricScrollVelocity = 0.0;
      _isAutoScrollingLyrics = true;
      try {
        widget.scrollController.jumpTo(boundedTarget);
      } finally {
        _isAutoScrollingLyrics = false;
      }
      return;
    }

    if (delta.abs() > position.viewportDimension * 0.92) {
      _lyricScrollVelocity = 0.0;
      _lastLyricScrollFrameTime = now;
    }

    final viewport = math.max(220.0, position.viewportDimension);
    final followRate = lineChanged ? 5.2 : 3.6;
    final targetStep = delta * (1.0 - math.exp(-frameSeconds * followRate));
    final maxVelocity = math.max(360.0, viewport * 1.65);
    final desiredVelocity =
        (targetStep / frameSeconds).clamp(-maxVelocity, maxVelocity).toDouble();
    final smoothing = 1.0 - math.exp(-frameSeconds * 6.4);
    _lyricScrollVelocity +=
        (desiredVelocity - _lyricScrollVelocity) * smoothing;
    final maxStep = maxVelocity * frameSeconds;
    final step = (_lyricScrollVelocity * frameSeconds)
        .clamp(-maxStep, maxStep)
        .toDouble();
    final nextOffset = (current + step)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    _isAutoScrollingLyrics = true;
    try {
      widget.scrollController.jumpTo(nextOffset);
    } finally {
      _isAutoScrollingLyrics = false;
    }
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
    TextStyle? mainStyle,
    required TextStyle generatedStyle,
    bool expandWidth = true,
  }) {
    Widget textBox(String value, TextStyle? style) {
      final textWidget = Text(value, style: style, textAlign: TextAlign.center);
      return expandWidth
          ? SizedBox(width: double.infinity, child: textWidget)
          : textWidget;
    }

    if (!generateKana) return textBox(text, mainStyle);
    final romaji = RomajiKanaConverter.generatedRomajiForLine(text);
    if (romaji.isEmpty) return textBox(text, mainStyle);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        textBox(text, mainStyle),
        const SizedBox(height: 4),
        textBox(romaji, generatedStyle),
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
      _cachedScrollTarget = null;
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
      _cachedScrollTarget = null;
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
      builder: (_) => LyricsTimingShiftSheet(
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
        builder: (_) => FullscreenLyricsPage(
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
    final params = await showModalBottomSheet<LyricsSearchParameters?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LyricsSearchInputSheet(
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
            padding: EdgeInsets.fromLTRB(18.s, 14.s, 18.s, 18.s),
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
                          ].join(' \u2022 '),
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
