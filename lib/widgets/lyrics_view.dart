import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:player_vf/controllers/lyrics_controller.dart';
import 'package:player_vf/models/lyrics_model.dart';
import 'package:player_vf/services/lyrics_sync_engine.dart';
import 'package:player_vf/services/responsive.dart';

class KaraokeLyricsView extends StatefulWidget {
  final LyricsController controller;
  final TextStyle? activeWordStyle;
  final TextStyle? inactiveWordStyle;
  final Color activeWordColor;
  final Color inactiveWordColor;
  final Color activeLineColor;
  final Color inactiveLineColor;
  final double activeWordScale;
  final double inactiveWordScale;
  final Duration animationDuration;
  final bool enableWordLevelHighlight;

  const KaraokeLyricsView({
    Key? key,
    required this.controller,
    this.activeWordStyle,
    this.inactiveWordStyle,
    this.activeWordColor = Colors.white,
    this.inactiveWordColor = Colors.white70,
    this.activeLineColor = Colors.white,
    this.inactiveLineColor = Colors.white38,
    this.activeWordScale = 1.12,
    this.inactiveWordScale = 0.92,
    this.animationDuration = const Duration(milliseconds: 950),
    this.enableWordLevelHighlight = true,
  }) : super(key: key);

  @override
  State<KaraokeLyricsView> createState() => _KaraokeLyricsViewState();
}

class _KaraokeLyricsViewState extends State<KaraokeLyricsView> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _lineKeys = {};
  int _lastActiveLineIndex = -1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onSyncStateChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onSyncStateChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onSyncStateChanged() {
    if (!mounted) return;
    final activeLineIndex = widget.controller.syncState.activeLineIndex;

    if (activeLineIndex != -1 && activeLineIndex != _lastActiveLineIndex) {
      _lastActiveLineIndex = activeLineIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToActiveLine(activeLineIndex);
      });
    }

    setState(() {});
  }

  void _scrollToActiveLine(int activeLineIndex) {
    if (!_scrollController.hasClients) return;

    final key = _lineKeys[activeLineIndex];
    final context = key?.currentContext;
    final renderObject = context?.findRenderObject();
    final viewport = renderObject == null
        ? null
        : RenderAbstractViewport.maybeOf(renderObject);
    if (renderObject != null && viewport != null) {
      final reveal = viewport.getOffsetToReveal(renderObject, 0.45).offset;
      final target = reveal.clamp(
        _scrollController.position.minScrollExtent,
        _scrollController.position.maxScrollExtent,
      );
      if ((target - _scrollController.offset).abs() > 1.0) {
        _scrollController.animateTo(
          target,
          duration: widget.animationDuration,
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }

    final viewportDimension = _scrollController.position.viewportDimension;
    const estimatedLineExtent = 72.0;
    final target = ((activeLineIndex * estimatedLineExtent) -
            (viewportDimension / 2) +
            (estimatedLineExtent / 2))
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: widget.animationDuration,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = widget.controller.currentLyrics;

    if (lyrics == null || lyrics.lines.isEmpty) {
      return Center(
        child: Text(
          "Searching for lyrics...",
          style: TextStyle(color: Colors.white54, fontSize: 18.sp),
          textAlign: TextAlign.center,
        ),
      );
    }

    final syncState = widget.controller.syncState;
    final activeLineIndex = syncState.activeLineIndex;

    return Container(
      color: Colors.transparent,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 800.s,
            minWidth: 300.s,
          ),
          child: ListView.builder(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(vertical: 40.s, horizontal: 20.s),
            itemCount: lyrics.lines.length,
            itemBuilder: (context, index) {
              final line = lyrics.lines[index];
              final distance =
                  activeLineIndex == -1 ? 999 : (index - activeLineIndex).abs();
              final isActive = distance == 0;
              final isPast = index < activeLineIndex;

              final key = _lineKeys.putIfAbsent(index, () => GlobalKey());

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.controller.seekToLine(index),
                child: _KaraokeLine(
                  key: key,
                  line: line,
                  isActive: isActive,
                  isPast: isPast,
                  distance: distance,
                  activeLineColor: widget.activeLineColor,
                  inactiveLineColor: widget.inactiveLineColor,
                  activeWordColor: widget.activeWordColor,
                  inactiveWordColor: widget.inactiveWordColor,
                  activeWordScale: widget.activeWordScale,
                  inactiveWordScale: widget.inactiveWordScale,
                  enableWordHighlight: widget.enableWordLevelHighlight,
                  syncState: syncState,
                  animDuration: widget.animationDuration,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _KaraokeLine extends StatelessWidget {
  final LyricLine line;
  final bool isActive;
  final bool isPast;
  final int distance;
  final Color activeLineColor;
  final Color inactiveLineColor;
  final Color activeWordColor;
  final Color inactiveWordColor;
  final double activeWordScale;
  final double inactiveWordScale;
  final bool enableWordHighlight;
  final LyricsSyncState syncState;
  final Duration animDuration;

  const _KaraokeLine({
    Key? key,
    required this.line,
    required this.isActive,
    required this.isPast,
    required this.distance,
    required this.activeLineColor,
    required this.inactiveLineColor,
    required this.activeWordColor,
    required this.inactiveWordColor,
    required this.activeWordScale,
    required this.inactiveWordScale,
    required this.enableWordHighlight,
    required this.syncState,
    required this.animDuration,
  }) : super(key: key);

  double _smoothDecay(int d) {
    if (d == 0) return 1.0;
    if (d == 1) return 0.6;
    if (d == 2) return 0.3;
    if (d == 3) return 0.12;
    if (d == 4) return 0.04;
    return 0.0;
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t.clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final t = _smoothDecay(distance);

    final scale = _lerp(1.06, 0.92, 1.0 - t);
    final opacity = _lerp(1.0, 0.28, 1.0 - t);
    final verticalOffset = _lerp(-6.0, 0.0, 1.0 - t);
    const horizontalPad = 18.0;
    const verticalPad = 14.0;

    return AnimatedContainer(
      duration: animDuration,
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPad,
        vertical: verticalPad,
      ),
      transform: Matrix4.translationValues(0, verticalOffset, 0)..scale(scale),
      transformAlignment: Alignment.center,
      child: AnimatedOpacity(
        duration: animDuration,
        curve: Curves.easeOutCubic,
        opacity: opacity,
        child: line.hasWords && enableWordHighlight
            ? _buildWordLevelContent(line, isActive, syncState)
            : _buildLineText(line, isActive),
      ),
    );
  }

  Widget _buildLineText(LyricLine line, bool isActive) {
    return AnimatedDefaultTextStyle(
      duration: animDuration,
      curve: Curves.easeOutCubic,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: isActive ? activeLineColor : inactiveLineColor,
        fontSize: isActive ? 24.0 : 19.0,
        fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
        height: 1.25,
        letterSpacing: 0.3,
        shadows: isActive
            ? [
                Shadow(
                  color: activeLineColor.withValues(alpha: 0.3),
                  blurRadius: 12,
                ),
              ]
            : [],
      ),
      child: Text(line.text),
    );
  }

  Widget _buildWordLevelContent(
    LyricLine line,
    bool isActive,
    LyricsSyncState syncState,
  ) {
    final words = line.words!;
    final activeWordIdx = isActive ? syncState.activeWordIndex : -1;

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6.s,
      runSpacing: 4.s,
      children: words.asMap().entries.map((entry) {
        final wordIdx = entry.key;
        final word = entry.value;
        final isWordActive = isActive && wordIdx == activeWordIdx;
        final isWordPast =
            isActive && wordIdx < activeWordIdx && activeWordIdx != -1;

        final wordScale = isWordActive
            ? activeWordScale
            : isWordPast
                ? 1.0
                : inactiveWordScale;

        final wordOpacity = isActive
            ? (isWordActive
                ? 1.0
                : isWordPast
                    ? 0.85
                    : 0.45)
            : 0.35;

        final wordColor = isWordActive
            ? activeWordColor
            : isWordPast
                ? activeWordColor.withValues(alpha: 0.8)
                : inactiveWordColor;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          transform: Matrix4.identity()..scale(wordScale),
          transformAlignment: Alignment.center,
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            style: TextStyle(
              color: wordColor,
              fontSize: isActive ? 22.0 : 17.0,
              fontWeight: isWordActive
                  ? FontWeight.w900
                  : isWordPast
                      ? FontWeight.w700
                      : FontWeight.w500,
              height: 1.3,
              shadows: isWordActive
                  ? [
                      Shadow(
                        color: activeWordColor.withValues(alpha: 0.4),
                        blurRadius: 10,
                      ),
                    ]
                  : [],
            ),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              opacity: wordOpacity,
              child: Text(word.text),
            ),
          ),
        );
      }).toList(),
    );
  }
}
