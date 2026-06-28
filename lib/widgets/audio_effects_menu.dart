import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/settings_model.dart';
import '../services/music_service.dart';
import '../services/responsive.dart';

class AudioEffectsMenu extends StatelessWidget {
  const AudioEffectsMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicService>(
      builder: (context, service, _) {
        final theme = Theme.of(context);
        final glass = context.select<SettingsModel, double>(
          (settings) => settings.glassEffect.clamp(0.0, 1.0),
        );
        final isDesktop = Responsive.isDesktop;
        final freqs = service.getEqualizerFrequencies();
        final presets = service.getEqualizerPresets();
        final viewport = MediaQuery.sizeOf(context);

        return SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isDesktop ? 900 : double.infinity,
                maxHeight: isDesktop ? 760 : viewport.height * 0.88,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Material(
                  color: _glassSurfaceColor(theme, glass),
                  child: Column(
                    children: [
                      _Header(service: service),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.all(18),
                          children: [
                            if (isDesktop)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                      child: _PlaybackCard(service: service)),
                                  const SizedBox(width: 14),
                                  Expanded(child: _ToneCard(service: service)),
                                ],
                              )
                            else ...[
                              _PlaybackCard(service: service),
                              const SizedBox(height: 14),
                              _ToneCard(service: service),
                            ],
                            const SizedBox(height: 14),
                            _EqualizerCard(
                              service: service,
                              freqs: freqs,
                              presets: presets,
                            ),
                            const SizedBox(height: 14),
                            _SongScopeTile(service: service),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final MusicService service;

  const _Header({required this.service});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withOpacity(0.72),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.tune_rounded,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Audio effects',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                Text(
                  service.isEffectsEnabled ? 'Processing enabled' : 'Bypassed',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: service.resetAudioEffects,
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: const Text('Reset'),
          ),
          const SizedBox(width: 8),
          Switch(
            value: service.isEffectsEnabled,
            onChanged: service.setEffectsEnabled,
          ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}

class _PlaybackCard extends StatelessWidget {
  final MusicService service;

  const _PlaybackCard({required this.service});

  @override
  Widget build(BuildContext context) {
    return _EffectCard(
      title: 'Playback',
      icon: Icons.speed_rounded,
      child: Column(
        children: [
          _ReleaseSlider(
            label: 'Speed',
            value: service.speed,
            min: 0.5,
            max: 2.0,
            divisions: 150,
            enabled: service.isEffectsEnabled,
            valueText: (value) => '${value.toStringAsFixed(2)}x',
            onChangeEnd: service.setSpeed,
          ),
          const SizedBox(height: 12),
          _ReleaseSlider(
            label: 'Pitch',
            value: service.pitch,
            min: 0.5,
            max: 2.0,
            divisions: 150,
            enabled: service.isEffectsEnabled && service.supportsPitchControl,
            valueText: (value) => service.supportsPitchControl
                ? '${value.toStringAsFixed(2)}x'
                : 'Unavailable',
            onChangeEnd: service.setPitch,
          ),
          const SizedBox(height: 12),
          _ReleaseSlider(
            label: 'Space',
            value: service.reverb,
            min: 0.0,
            max: 1.0,
            divisions: 100,
            enabled: service.isEffectsEnabled,
            valueText: (value) => value > 0.82
                ? 'Large'
                : value < 0.06
                    ? 'Dry'
                    : '${(value * 100).round()}%',
            onChangeEnd: service.setReverb,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _QuickAction(
                  label: '0.9x', onPressed: () => service.setSpeed(0.9)),
              _QuickAction(
                  label: '1.0x', onPressed: () => service.setSpeed(1.0)),
              _QuickAction(
                  label: '1.1x', onPressed: () => service.setSpeed(1.1)),
              _QuickAction(
                  label: 'Dry', onPressed: () => service.setReverb(0.0)),
              _QuickAction(
                  label: 'Room', onPressed: () => service.setReverb(0.35)),
              _QuickAction(
                  label: 'Wide', onPressed: () => service.setReverb(0.7)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToneCard extends StatelessWidget {
  final MusicService service;

  const _ToneCard({required this.service});

  @override
  Widget build(BuildContext context) {
    final tones = <_TonePreset>[
      _TonePreset('Balanced', Icons.balance_rounded, () {
        service.setEqualizerPreset('Normal');
        service.setReverb(0.0);
        service.setSpeed(1.0);
      }),
      _TonePreset('Bass', Icons.graphic_eq_rounded, () {
        service.setEqualizerPreset('Bass Boost');
        service.setReverb(0.08);
      }),
      _TonePreset('Voice', Icons.record_voice_over_rounded, () {
        service.setEqualizerPreset('Pop');
        service.setReverb(0.03);
      }),
      _TonePreset('Air', Icons.air_rounded, () {
        service.setEqualizerPreset('Treble Boost');
        service.setReverb(0.28);
      }),
      _TonePreset('Club', Icons.nightlife_rounded, () {
        service.setEqualizerPreset('Electronic');
        service.setReverb(0.18);
        service.setSpeed(1.03);
      }),
      _TonePreset('Warm', Icons.wb_twilight_rounded, () {
        service.setEqualizerPreset('Jazz');
        service.setReverb(0.12);
      }),
      _TonePreset('Metal', Icons.bolt_rounded, () {
        service.setEqualizerPreset('Metal');
        service.setReverb(0.08);
      }),
      _TonePreset('Podcast', Icons.mic_rounded, () {
        service.setEqualizerPreset('Podcast');
        service.setReverb(0.0);
        service.setSpeed(1.0);
      }),
      _TonePreset('Movie', Icons.movie_filter_rounded, () {
        service.setEqualizerPreset('Movie');
        service.setReverb(0.22);
      }),
      _TonePreset('Deep', Icons.south_rounded, () {
        service.setEqualizerPreset('Deep');
        service.setReverb(0.10);
      }),
      _TonePreset('Bright', Icons.wb_sunny_rounded, () {
        service.setEqualizerPreset('Bright');
        service.setReverb(0.06);
      }),
      _TonePreset('Soft', Icons.spa_rounded, () {
        service.setEqualizerPreset('Soft');
        service.setReverb(0.14);
      }),
    ];

    return _EffectCard(
      title: 'Tone profiles',
      icon: Icons.auto_awesome_rounded,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: tones
            .map(
              (tone) => _ToneButton(
                tone: tone,
                enabled: service.isEffectsEnabled,
              ),
            )
            .toList(),
      ),
    );
  }
}

class _EqualizerCard extends StatelessWidget {
  final MusicService service;
  final List<int> freqs;
  final List<String> presets;

  const _EqualizerCard({
    required this.service,
    required this.freqs,
    required this.presets,
  });

  @override
  Widget build(BuildContext context) {
    final equalizerActive =
        service.isEffectsEnabled && service.isEqualizerEnabled;

    return _EffectCard(
      title: 'Equalizer',
      icon: Icons.equalizer_rounded,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton.icon(
            onPressed: service.resetEqualizer,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Reset EQ'),
          ),
          Switch(
            value: equalizerActive,
            onChanged:
                service.isEffectsEnabled ? service.setEqualizerEnabled : null,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: presets.map((preset) {
              final selected =
                  service.isEqualizerEnabled && service.currentPreset == preset;
              return ChoiceChip(
                label: Text(
                  preset,
                  style: const TextStyle(fontSize: 12),
                ),
                selected: selected,
                onSelected: (_) => service.setEqualizerPreset(preset),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          _VerticalEqBands(service: service, freqs: freqs),
        ],
      ),
    );
  }
}

class _VerticalEqBands extends StatelessWidget {
  final MusicService service;
  final List<int> freqs;

  const _VerticalEqBands({required this.service, required this.freqs});

  @override
  Widget build(BuildContext context) {
    final values = service.currentEqBandValues;
    final enabled = service.isEffectsEnabled && service.isEqualizerEnabled;
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final isDesktop = Responsive.isDesktop;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : size.width - 72;
        final bandWidth =
            (width / freqs.length).clamp(isDesktop ? 42.0 : 28.0, 58.0);
        final sliderHeight = (size.height * (isDesktop ? 0.30 : 0.24))
            .clamp(isDesktop ? 180.0 : 132.0, isDesktop ? 260.0 : 190.0)
            .toDouble();

        return SizedBox(
          height: sliderHeight + 58,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: List.generate(freqs.length, (index) {
              return Expanded(
                child: Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: bandWidth < 34 ? 1 : 3),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 20,
                        child: Text(
                          values[index].toStringAsFixed(0),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: enabled
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Expanded(
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: _BareReleaseSlider(
                            value: values[index],
                            min: -12,
                            max: 12,
                            divisions: 48,
                            enabled: enabled,
                            onChanged: (value) =>
                                service.previewEqualizerBand(index, value),
                            onChangeEnd: (value) =>
                                service.setEqualizerBand(index, value),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 28,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _formatFrequency(freqs[index]),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

class _SongScopeTile extends StatelessWidget {
  final MusicService service;

  const _SongScopeTile({required this.service});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: _glassSurfaceColor(theme, _glassIntensity(context)),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(
            0.18 + (_glassIntensity(context) * 0.08),
          ),
          width: 0.7,
        ),
      ),
      child: CheckboxListTile(
        value: service.useSongSpecificSettings,
        onChanged: service.isEffectsEnabled
            ? (value) => service.setUseSongSpecificSettings(value ?? false)
            : null,
        title: const Text('Save changes for this song only'),
        subtitle: Text(
          service.currentMusic?.title ?? 'Applies when a track is selected',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    );
  }
}

class _EffectCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  const _EffectCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _glassSurfaceColor(theme, _glassIntensity(context)),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(
            0.18 + (_glassIntensity(context) * 0.08),
          ),
          width: 0.7,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _ReleaseSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final bool enabled;
  final String Function(double value) valueText;
  final ValueChanged<double> onChangeEnd;

  const _ReleaseSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.valueText,
    required this.onChangeEnd,
    this.divisions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _ReleaseValueBuilder(
      value: value,
      min: min,
      max: max,
      builder: (context, preview, setPreview, clearPreview) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  valueText(preview),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: enabled
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            _BareSlider(
              value: preview,
              min: min,
              max: max,
              divisions: divisions,
              enabled: enabled,
              onChanged: setPreview,
              onChangeEnd: (next) {
                onChangeEnd(next);
                clearPreview();
              },
            ),
          ],
        );
      },
    );
  }
}

class _BareReleaseSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final bool enabled;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double> onChangeEnd;

  const _BareReleaseSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChangeEnd,
    this.onChanged,
    this.divisions,
  });

  @override
  Widget build(BuildContext context) {
    return _ReleaseValueBuilder(
      value: value,
      min: min,
      max: max,
      builder: (context, preview, setPreview, clearPreview) {
        return _BareSlider(
          value: preview,
          min: min,
          max: max,
          divisions: divisions,
          enabled: enabled,
          onChanged: (next) {
            setPreview(next);
            onChanged?.call(next);
          },
          onChangeEnd: (next) {
            onChangeEnd(next);
            clearPreview();
          },
        );
      },
    );
  }
}

class _BareSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _BareSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
    this.divisions,
  });

  @override
  Widget build(BuildContext context) {
    return Slider(
      value: value.clamp(min, max).toDouble(),
      min: min,
      max: max,
      divisions: divisions,
      onChanged: enabled ? onChanged : null,
      onChangeEnd: enabled ? onChangeEnd : null,
    );
  }
}

class _ReleaseValueBuilder extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final Widget Function(
    BuildContext context,
    double preview,
    ValueChanged<double> setPreview,
    VoidCallback clearPreview,
  ) builder;

  const _ReleaseValueBuilder({
    required this.value,
    required this.min,
    required this.max,
    required this.builder,
  });

  @override
  State<_ReleaseValueBuilder> createState() => _ReleaseValueBuilderState();
}

class _ReleaseValueBuilderState extends State<_ReleaseValueBuilder> {
  double? _preview;

  @override
  void didUpdateWidget(covariant _ReleaseValueBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _preview = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final value =
        (_preview ?? widget.value).clamp(widget.min, widget.max).toDouble();
    return widget.builder(
      context,
      value,
      (next) => setState(() => _preview = next),
      () => setState(() => _preview = null),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _QuickAction({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

class _TonePreset {
  final String label;
  final IconData icon;
  final VoidCallback apply;

  const _TonePreset(this.label, this.icon, this.apply);
}

class _ToneButton extends StatelessWidget {
  final _TonePreset tone;
  final bool enabled;

  const _ToneButton({required this.tone, required this.enabled});

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: enabled ? tone.apply : null,
      icon: Icon(tone.icon, size: 18),
      label: Text(tone.label),
    );
  }
}

String _formatFrequency(int freq, {bool spaced = false}) {
  if (freq >= 1000) {
    return spaced ? '${freq ~/ 1000} kHz' : '${freq ~/ 1000}k';
  }
  return '$freq Hz';
}

double _glassIntensity(BuildContext context) {
  return context.select<SettingsModel, double>(
    (settings) => settings.glassEffect.clamp(0.0, 1.0),
  );
}

Color _glassSurfaceColor(ThemeData theme, double intensity) {
  final base = theme.brightness == Brightness.dark
      ? theme.colorScheme.surfaceContainerHighest
      : theme.colorScheme.surfaceContainerLow;
  final opacity = theme.brightness == Brightness.dark
      ? 0.94 - (0.14 * intensity)
      : 0.98 - (0.10 * intensity);
  return base.withOpacity(opacity.clamp(0.80, 0.98));
}

void showAudioEffectsMenu(BuildContext context) {
  showDialog(
    context: context,
    builder: (dialogContext) => SizedBox(
      width: MediaQuery.sizeOf(context).width * 0.96,
      height: MediaQuery.sizeOf(context).height * 0.84,
      child: const Material(
        color: Colors.transparent,
        child: AudioEffectsMenu(),
      ),
    ),
  );
}

class AudioEffectsPanel extends StatelessWidget {
  final bool showHeader;
  const AudioEffectsPanel({super.key, this.showHeader = true});

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicService>(
      builder: (context, service, _) {
        final theme = Theme.of(context);
        final freqs = service.getEqualizerFrequencies();
        final presets = service.getEqualizerPresets();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHeader) ...[
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withOpacity(0.72),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.tune_rounded,
                      color: theme.colorScheme.onPrimaryContainer,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Equalizer & Effects',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          service.isEffectsEnabled ? 'Processing active' : 'Bypassed',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: service.resetAudioEffects,
                    icon: const Icon(Icons.restart_alt_rounded, size: 16),
                    label: const Text('Reset'),
                  ),
                  const SizedBox(width: 4),
                  Switch(
                    value: service.isEffectsEnabled,
                    onChanged: service.setEffectsEnabled,
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            _PlaybackCard(service: service),
            const SizedBox(height: 14),
            _ToneCard(service: service),
            const SizedBox(height: 14),
            _EqualizerCard(
              service: service,
              freqs: freqs,
              presets: presets,
            ),
            const SizedBox(height: 14),
            _SongScopeTile(service: service),
          ],
        );
      },
    );
  }
}

