import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/settings_model.dart';
import '../services/music_service.dart';
import '../widgets/glass_container.dart';

class PlaybackSettingsScreen extends StatefulWidget {
  const PlaybackSettingsScreen({super.key});

  @override
  State<PlaybackSettingsScreen> createState() => _PlaybackSettingsScreenState();
}

class _PlaybackSettingsScreenState extends State<PlaybackSettingsScreen> {
  bool _isApplyingAudioDecoder = false;
  bool _isApplyingVideoDecoder = false;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsModel>();
    final musicService = context.watch<MusicService>();
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Playback',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        children: [
          _buildGlassSettingCard(
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              activeColor: settings.accentColor,
              secondary:
                  Icon(Icons.history_rounded, color: theme.colorScheme.primary),
              title: const Text('Remember playback'),
              subtitle: const Text('Resume the last track and position.'),
              value: musicService.rememberPlayback,
              onChanged: musicService.setRememberPlayback,
            ),
          ),
          const SizedBox(height: 12),
          _buildGlassSettingCard(
            child: _buildSafeEarsSetting(context, settings, musicService),
          ),
          const SizedBox(height: 12),
          _buildGlassSettingCard(
            child: _buildRealtimeDspSetting(context, settings, musicService),
          ),
          const SizedBox(height: 12),
          _buildGlassSettingCard(
            child: _buildDecoderModeRow(
              title: 'Audio decoder',
              value: settings.audioDecoderMode,
              isApplying: _isApplyingAudioDecoder,
              onChanged: (mode) => _applyAudioDecoderMode(
                settings,
                musicService,
                mode,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildGlassSettingCard(
            child: _buildDecoderModeRow(
              title: 'Video decoder',
              value: settings.videoDecoderMode,
              isApplying: _isApplyingVideoDecoder,
              onChanged: (mode) => _applyVideoDecoderMode(
                settings,
                musicService,
                mode,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildGlassSettingCard(
            child: _buildPlaybackLyricsSetting(context, settings),
          ),
          const SizedBox(height: 12),
          _buildGlassSettingCard(
            child: _buildSeekStepSetting(context, settings),
          ),
          const SizedBox(height: 12),
          _buildGlassSettingCard(
            child: _buildSongGapSetting(
              context,
              settings,
              musicService,
            ),
          ),
          const SizedBox(height: 12),
          _buildGlassSettingCard(
            child: _buildCoverArtDisplayModeSetting(context, settings),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildGlassSettingCard({required Widget child}) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(16),
      blur: 14,
      child: child,
    );
  }

  Widget _buildSafeEarsSetting(
    BuildContext context,
    SettingsModel settings,
    MusicService musicService,
  ) {
    final theme = Theme.of(context);
    final maxVolume = musicService.safeEarsMaxVolume.round();
    final enabled = musicService.safeEarsEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          activeColor: settings.accentColor,
          secondary:
              Icon(Icons.hearing_rounded, color: theme.colorScheme.primary),
          title: const Text('Safe Ears'),
          subtitle: Text(
            enabled
                ? 'Volume is capped at $maxVolume% and boosted EQ is softened.'
                : 'Limit maximum output volume for long listening.',
          ),
          value: enabled,
          onChanged: musicService.setSafeEarsEnabled,
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Maximum volume',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Text(
              '$maxVolume%',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        Slider(
          value: musicService.safeEarsMaxVolume,
          min: 35,
          max: 100,
          divisions: 13,
          label: '$maxVolume%',
          onChanged: (value) => musicService.setSafeEarsMaxVolume(value),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: const [60, 70, 72, 80, 90].map((volume) {
            final selected = maxVolume == volume;
            return ChoiceChip(
              label: Text('$volume%'),
              selected: selected,
              onSelected: (_) =>
                  musicService.setSafeEarsMaxVolume(volume.toDouble()),
              selectedColor:
                  theme.colorScheme.primaryContainer.withOpacity(0.72),
              backgroundColor:
                  theme.colorScheme.surfaceContainerHighest.withOpacity(0.34),
              labelStyle: TextStyle(
                color: selected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
              visualDensity: VisualDensity.compact,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildRealtimeDspSetting(
    BuildContext context,
    SettingsModel settings,
    MusicService musicService,
  ) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          activeColor: settings.accentColor,
          secondary: Icon(Icons.tune_rounded, color: theme.colorScheme.primary),
          title: const Text('Real-time DSP'),
          subtitle: const Text('Stable loudness, peak limiting, and tone EQ.'),
          value: musicService.dspEnabled,
          onChanged: musicService.setDspEnabled,
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              label: const Text('Loudness'),
              selected: musicService.dspLoudnessNormalizationEnabled,
              onSelected: musicService.setDspLoudnessNormalizationEnabled,
            ),
            FilterChip(
              label: const Text('Limiter'),
              selected: musicService.dspLimiterEnabled,
              onSelected: musicService.setDspLimiterEnabled,
            ),
            FilterChip(
              label: const Text('Smooth compressor'),
              selected: musicService.dspCompressorEnabled,
              onSelected: musicService.setDspCompressorEnabled,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildDspToneSlider(
          context,
          label: 'Bass',
          value: musicService.dspBass,
          onChanged: (value) => musicService.setDspTone(bass: value),
        ),
        _buildDspToneSlider(
          context,
          label: 'Mid',
          value: musicService.dspMid,
          onChanged: (value) => musicService.setDspTone(mid: value),
        ),
        _buildDspToneSlider(
          context,
          label: 'Treble',
          value: musicService.dspTreble,
          onChanged: (value) => musicService.setDspTone(treble: value),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: musicService.resetDspTone,
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: const Text('Reset tone'),
          ),
        ),
      ],
    );
  }

  Widget _buildDspToneSlider(
    BuildContext context, {
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    final theme = Theme.of(context);
    final sign = value > 0 ? '+' : '';
    return Row(
      children: [
        SizedBox(
          width: 58,
          child:
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: -6,
            max: 6,
            divisions: 24,
            label: '$sign${value.toStringAsFixed(1)} dB',
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 58,
          child: Text(
            '$sign${value.toStringAsFixed(1)}',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingDropdown({
    required String label,
    required int value,
    required List<int> values,
    required List<String> displayLabels,
    required Function(int) onChanged,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            decoration: InputDecoration(
              labelText: label,
              labelStyle: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
                fontSize: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: theme.colorScheme.outlineVariant.withOpacity(0.3),
                ),
              ),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.1),
              prefixIcon: Icon(icon, color: theme.colorScheme.primary),
            ),
            value: value,
            items: List.generate(displayLabels.length, (index) {
              return DropdownMenuItem<int>(
                value: values[index],
                child: Text(displayLabels[index]),
              );
            }),
            onChanged: (newValue) {
              if (newValue != null) onChanged(newValue);
            },
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaybackLyricsSetting(
    BuildContext context,
    SettingsModel settings,
  ) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.translate_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            const Text(
              'Lyrics',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          activeColor: settings.accentColor,
          title: const Text('Generate lyric romaji'),
          subtitle: const Text(
            'Show clean romaji under hiragana and katakana lyric lines.',
          ),
          value: settings.generateKanaLyrics,
          onChanged: settings.setGenerateKanaLyrics,
        ),
      ],
    );
  }

  Widget _buildSeekStepSetting(
    BuildContext context,
    SettingsModel settings,
  ) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Seek Step', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [5, 10, 15, 30].map((seconds) {
            final selected = settings.seekStepSeconds == seconds;
            return ChoiceChip(
              label: Text(
                '$seconds sec',
                style: const TextStyle(fontSize: 12),
              ),
              selected: selected,
              onSelected: (_) => settings.setSeekStepSeconds(seconds),
              selectedColor:
                  theme.colorScheme.primaryContainer.withOpacity(0.68),
              backgroundColor:
                  theme.colorScheme.surfaceContainerHighest.withOpacity(0.34),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              visualDensity: VisualDensity.compact,
              labelStyle: TextStyle(
                color: selected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurface.withOpacity(0.8),
                fontWeight: FontWeight.w600,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCoverArtDisplayModeSetting(
    BuildContext context,
    SettingsModel settings,
  ) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.image_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            const Text(
              'Cover Art',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildGlassSettingCard(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildSettingDropdown(
                      label: 'Display mode',
                      value: settings.coverArtDisplayMode.index,
                      values: CoverArtDisplayMode.values.map((mode) => mode.index).toList(),
                      displayLabels: CoverArtDisplayMode.values.map((mode) => _getCoverArtModeLabel(mode)).toList(),
                      onChanged: (index) => _setCoverArtDisplayMode(context, index),
                      icon: Icons.aspect_ratio_rounded,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _getCoverArtModeLabel(CoverArtDisplayMode mode) {
    switch (mode) {
      case CoverArtDisplayMode.fit:
        return 'Fit';
      case CoverArtDisplayMode.crop:
        return 'Crop';
      case CoverArtDisplayMode.square:
        return 'Square';
      case CoverArtDisplayMode.custom:
        return 'Custom';
    }
  }

  void _setCoverArtDisplayMode(BuildContext context, int index) {
    if (index >= 0 && index < CoverArtDisplayMode.values.length) {
      Provider.of<SettingsModel>(context, listen: false)
          .setCoverArtDisplayMode(CoverArtDisplayMode.values[index]);
    }
  }

  Widget _buildSongGapSetting(
    BuildContext context,
    SettingsModel settings,
    MusicService musicService,
  ) {
    final theme = Theme.of(context);
    final seconds = settings.songGapMs / 1000.0;
    final label = settings.songGapMs == 0
        ? 'No empty time'
        : '${seconds.toStringAsFixed(seconds % 1 == 0 ? 0 : 1)} sec';

    Future<void> setGapMs(int milliseconds) async {
      await _applySongGap(settings, musicService, milliseconds);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Empty time between songs',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Adds clean silence before the next track. Set to 0 for smooth crossfade.',
          style: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.58),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 10),
        Slider(
          value: settings.songGapMs.toDouble(),
          min: 0,
          max: 5000,
          divisions: 10,
          label: label,
          onChanged: (value) => setGapMs(value.round()),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: const [0, 500, 1000, 2000, 5000].map((milliseconds) {
            final selected = settings.songGapMs == milliseconds;
            final chipLabel = milliseconds == 0
                ? 'Off'
                : '${(milliseconds / 1000).toStringAsFixed(milliseconds % 1000 == 0 ? 0 : 1)}s';
            return ChoiceChip(
              label: Text(chipLabel),
              selected: selected,
              onSelected: (_) => setGapMs(milliseconds),
              selectedColor:
                  theme.colorScheme.primaryContainer.withOpacity(0.72),
              backgroundColor:
                  theme.colorScheme.surfaceContainerHighest.withOpacity(0.34),
              labelStyle: TextStyle(
                color: selected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
              visualDensity: VisualDensity.compact,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildDecoderModeRow({
    required String title,
    required DecoderMode value,
    required bool isApplying,
    required ValueChanged<DecoderMode> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        SegmentedButton<DecoderMode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: DecoderMode.auto,
              icon: Icon(Icons.auto_mode_rounded),
              label: Text('Auto'),
            ),
            ButtonSegment(
              value: DecoderMode.software,
              icon: Icon(Icons.memory_rounded),
              label: Text('CPU'),
            ),
            ButtonSegment(
              value: DecoderMode.hardware,
              icon: Icon(Icons.developer_board_rounded),
              label: Text('GPU'),
            ),
          ],
          selected: {value},
          onSelectionChanged:
              isApplying ? null : (next) => onChanged(next.first),
        ),
        if (isApplying) ...[
          const SizedBox(height: 10),
          const LinearProgressIndicator(minHeight: 2),
        ],
      ],
    );
  }

  Future<void> _applyAudioDecoderMode(
    SettingsModel settings,
    MusicService musicService,
    DecoderMode mode,
  ) async {
    if (_isApplyingAudioDecoder || settings.audioDecoderMode == mode) return;
    setState(() => _isApplyingAudioDecoder = true);
    try {
      await settings.setAudioDecoderMode(mode);
      await _applyDecoderModes(settings, musicService);
    } finally {
      if (mounted) setState(() => _isApplyingAudioDecoder = false);
    }
  }

  Future<void> _applyVideoDecoderMode(
    SettingsModel settings,
    MusicService musicService,
    DecoderMode mode,
  ) async {
    if (_isApplyingVideoDecoder || settings.videoDecoderMode == mode) return;
    setState(() => _isApplyingVideoDecoder = true);
    try {
      await settings.setVideoDecoderMode(mode);
      await _applyDecoderModes(settings, musicService);
    } finally {
      if (mounted) setState(() => _isApplyingVideoDecoder = false);
    }
  }

  Future<void> _applyDecoderModes(
    SettingsModel settings,
    MusicService musicService,
  ) async {
    await musicService.setDecoderModes(
      audio: settings.audioDecoderMode,
      video: settings.videoDecoderMode,
    );
  }

  Future<void> _applySongGap(
    SettingsModel settings,
    MusicService musicService,
    int milliseconds,
  ) async {
    final clamped = milliseconds.clamp(0, 5000);
    await settings.setSongGapMs(clamped);
    await musicService.setSongGapDuration(Duration(milliseconds: clamped));
  }
}
