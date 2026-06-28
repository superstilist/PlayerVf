import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/settings_model.dart';

enum LyricsLayoutTarget { header, lyrics, controls, visual }

enum LyricsEditHitZone { tiny, compact, touch }

class LyricsLayeredObject {
  final int layer;
  final Widget child;

  const LyricsLayeredObject({
    required this.layer,
    required this.child,
  });
}

class LyricsVisualDraftItem {
  String id;
  String path;
  bool show;
  Offset offset;
  double scale;
  double rotation;
  int layer;
  double opacity;

  LyricsVisualDraftItem({
    required this.id,
    required this.path,
    required this.show,
    required this.offset,
    required this.scale,
    required this.rotation,
    required this.layer,
    required this.opacity,
  });

  factory LyricsVisualDraftItem.fromSettings(
    LyricsFullscreenVisualItem item,
  ) {
    return LyricsVisualDraftItem(
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

class LyricsLayoutDraft {
  Color textColor;
  LyricsFullscreenPosition position;
  LyricsFullscreenTextAlign textAlign;
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
  double coverScale;
  double headerTextScale;
  LyricsFullscreenFadeMode fadeMode;
  double headerRotation;
  double lyricsRotation;
  double controlsRotation;
  double letterSpacing;
  double lineHeight;
  LyricsFullscreenFontPreset fontPreset;
  LyricsFullscreenHeaderStyle headerStyle;
  LyricsFullscreenControlsStyle controlsStyle;
  LyricsFullscreenSpecialEffect specialEffect;
  LyricsFullscreenParticlePack particlePack;
  String customParticlePack;
  int headerLayer;
  int lyricsLayer;
  int controlsLayer;
  List<LyricsVisualDraftItem> visualItems;
  int selectedVisualIndex;

  LyricsLayoutDraft({
    required this.textColor,
    required this.position,
    required this.textAlign,
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
    required this.coverScale,
    required this.headerTextScale,
    required this.fadeMode,
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
    this.letterSpacing = 0.0,
    this.lineHeight = 1.2,
  });

  factory LyricsLayoutDraft.fromSettings(SettingsModel settings) {
    return LyricsLayoutDraft(
      textColor: settings.lyricsFullscreenTextColor,
      position: settings.lyricsFullscreenPosition,
      textAlign: settings.lyricsFullscreenTextAlign,
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
      coverScale: settings.lyricsFullscreenCoverScale,
      headerTextScale: 1.0,
      fadeMode: settings.lyricsFullscreenFadeMode,
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
      letterSpacing: settings.lyricsFullscreenWidth,
      lineHeight: settings.lyricsFullscreenHeight > 0
          ? settings.lyricsFullscreenHeight
          : 1.2,
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
    coverScale = 1.0;
    headerTextScale = 1.0;
    fadeMode = LyricsFullscreenFadeMode.both;
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

  LyricsVisualDraftItem? get selectedVisual {
    if (visualItems.isEmpty) return null;
    selectedVisualIndex = selectedVisualIndex.clamp(0, visualItems.length - 1);
    return visualItems[selectedVisualIndex];
  }

  static List<LyricsVisualDraftItem> _visualDraftItemsFromSettings(
    SettingsModel settings,
  ) {
    final items = settings.lyricsFullscreenVisualItems
        .map(LyricsVisualDraftItem.fromSettings)
        .toList(growable: true);
    if (items.isEmpty &&
        settings.lyricsFullscreenVisualPath.trim().isNotEmpty) {
      items.add(LyricsVisualDraftItem(
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
