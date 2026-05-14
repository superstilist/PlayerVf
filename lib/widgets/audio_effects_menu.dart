import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/music_service.dart';
import '../services/responsive.dart';

class AudioEffectsMenu extends StatelessWidget {
  const AudioEffectsMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicService>(
      builder: (context, service, _) {
        final freqs = service.getEqualizerFrequencies();
        final presets = service.getEqualizerPresets();
        final isDesktop = Responsive.isDesktop;

        return Container(
          width: isDesktop ? 760 : double.infinity,
          height: isDesktop ? 700 : MediaQuery.of(context).size.height * 0.82,
          decoration: BoxDecoration(
            color: const Color(0xFF101214).withOpacity(0.98),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.teal.withOpacity(0.22)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.45),
                blurRadius: 28,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Audio Effects',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: service.resetAudioEffects,
                      icon: const Icon(Icons.restart_alt_rounded,
                          color: Colors.tealAccent),
                      label: const Text('Reset All',
                          style: TextStyle(color: Colors.tealAccent)),
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      value: service.isEffectsEnabled,
                      onChanged: service.setEffectsEnabled,
                      activeColor: Colors.tealAccent,
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white10, height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(18),
                  children: [
                    if (isDesktop)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _buildDspCard(context, service),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildQuickTonesCard(context, service),
                          ),
                        ],
                      )
                    else ...[
                      _buildDspCard(context, service),
                      const SizedBox(height: 16),
                      _buildQuickTonesCard(context, service),
                    ],
                    const SizedBox(height: 18),
                    _buildEqCard(context, service, freqs, presets, isDesktop),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: CheckboxListTile(
                        title: const Text('Save for this song only',
                            style: TextStyle(color: Colors.white)),
                        value: service.useSongSpecificSettings,
                        onChanged: service.isEffectsEnabled
                            ? (value) => service
                                .setUseSongSpecificSettings(value ?? false)
                            : null,
                        activeColor: Colors.teal,
                        checkColor: Colors.black,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDspCard(BuildContext context, MusicService service) {
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Playback Controls'),
          const SizedBox(height: 14),
          _buildSlider(
            context,
            label: 'Speed',
            value: service.speed,
            min: 0.5,
            max: 2.0,
            onChanged: service.setSpeed,
            displayValue: '${service.speed.toStringAsFixed(2)}x',
          ),
          const SizedBox(height: 10),
          _buildSlider(
            context,
            label: 'Pitch',
            value: service.pitch,
            min: 0.5,
            max: 2.0,
            onChanged: service.setPitch,
            displayValue: service.supportsPitchControl
                ? '${service.pitch.toStringAsFixed(2)}x'
                : 'Unavailable on this device',
            enabledOverride: service.supportsPitchControl,
          ),
          const SizedBox(height: 10),
          _buildSlider(
            context,
            label: 'Reverb',
            value: service.reverb,
            min: 0.0,
            max: 1.0,
            onChanged: service.setReverb,
            displayValue: service.reverb > 0.8
                ? 'Large Hall'
                : '${(service.reverb * 100).toInt()}%',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _quickButton('0.9x', () => service.setSpeed(0.9)),
              _quickButton('1.0x', () => service.setSpeed(1.0)),
              _quickButton('1.1x', () => service.setSpeed(1.1)),
              _quickButton('Dry', () => service.setReverb(0.0)),
              _quickButton('Room', () => service.setReverb(0.35)),
              _quickButton('Wide', () => service.setReverb(0.7)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickTonesCard(BuildContext context, MusicService service) {
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Quick Tone Profiles'),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _toneButton('Balanced', service, () {
                service.setEqualizerPreset('Normal');
                service.setReverb(0.0);
                service.setSpeed(1.0);
              }),
              _toneButton('Bass Push', service, () {
                service.setEqualizerPreset('Bass Boost');
                service.setReverb(0.08);
              }),
              _toneButton('Voice Lift', service, () {
                service.setEqualizerPreset('Pop');
                service.setSpeed(1.0);
                service.setReverb(0.03);
              }),
              _toneButton('Airy', service, () {
                service.setEqualizerPreset('Treble Boost');
                service.setReverb(0.28);
              }),
              _toneButton('Club', service, () {
                service.setEqualizerPreset('Electronic');
                service.setReverb(0.18);
                service.setSpeed(1.03);
              }),
              _toneButton('Warm', service, () {
                service.setEqualizerPreset('Jazz');
                service.setReverb(0.12);
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEqCard(
    BuildContext context,
    MusicService service,
    List<int> freqs,
    List<String> presets,
    bool isDesktop,
  ) {
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildSectionHeader('Equalizer'),
              ),
              TextButton.icon(
                onPressed: service.resetEqualizer,
                icon: const Icon(Icons.refresh_rounded,
                    color: Colors.tealAccent, size: 18),
                label: const Text('Reset EQ',
                    style: TextStyle(color: Colors.tealAccent)),
              ),
              Switch(
                value: service.isEqualizerEnabled,
                onChanged: service.isEffectsEnabled
                    ? service.setEqualizerEnabled
                    : null,
                activeColor: Colors.tealAccent,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: presets.map((preset) {
              final isSelected = service.currentPreset == preset;
              return ChoiceChip(
                label: Text(preset),
                selected: isSelected,
                onSelected:
                    service.isEffectsEnabled && service.isEqualizerEnabled
                        ? (_) => service.setEqualizerPreset(preset)
                        : null,
                backgroundColor: Colors.white.withOpacity(0.05),
                selectedColor: Colors.teal.withOpacity(0.24),
                labelStyle: TextStyle(
                    color: isSelected ? Colors.tealAccent : Colors.white70),
                side: BorderSide(
                    color: isSelected
                        ? Colors.tealAccent.withOpacity(0.4)
                        : Colors.white12),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          if (isDesktop)
            _buildDesktopEqBands(context, service, freqs)
          else
            _buildMobileEqBands(context, service, freqs),
        ],
      ),
    );
  }

  Widget _buildDesktopEqBands(
      BuildContext context, MusicService service, List<int> freqs) {
    return Column(
      children: List.generate(freqs.length, (index) {
        final freq = freqs[index];
        final value = service.currentEqBandValues[index];
        final label = freq >= 1000 ? '${freq ~/ 1000} kHz' : '$freq Hz';
        final enabled = service.isEffectsEnabled && service.isEqualizerEnabled;

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  child: Text(
                    label,
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 4,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 7),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 15),
                      activeTrackColor: Colors.teal,
                      inactiveTrackColor: Colors.grey[800],
                      thumbColor: Colors.tealAccent,
                      overlayColor: Colors.teal.withOpacity(0.2),
                    ),
                    child: Slider(
                      value: value,
                      min: -10,
                      max: 10,
                      divisions: 40,
                      label: '${value.toStringAsFixed(1)} dB',
                      onChanged: enabled
                          ? (v) => service.setEqualizerBand(index, v)
                          : null,
                    ),
                  ),
                ),
                SizedBox(
                  width: 58,
                  child: Text(
                    '${value.toStringAsFixed(1)} dB',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: enabled ? Colors.tealAccent : Colors.white38,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildMobileEqBands(
      BuildContext context, MusicService service, List<int> freqs) {
    return SizedBox(
      height: 220,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: freqs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final freq = freqs[index];
          final value = service.currentEqBandValues[index];
          final label = freq >= 1000 ? '${freq ~/ 1000}k' : '$freq';

          return Column(
            children: [
              Expanded(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 4,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: Colors.teal,
                      inactiveTrackColor: Colors.grey[800],
                      thumbColor: Colors.tealAccent,
                      overlayColor: Colors.teal.withOpacity(0.2),
                    ),
                    child: Slider(
                      value: value,
                      min: -10,
                      max: 10,
                      onChanged: (service.isEffectsEnabled &&
                              service.isEqualizerEnabled)
                          ? (v) => service.setEqualizerBand(index, v)
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(label,
                  style: const TextStyle(color: Colors.white54, fontSize: 10)),
              Text('${value.toStringAsFixed(1)}dB',
                  style: const TextStyle(color: Colors.teal, fontSize: 9)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
              letterSpacing: 0),
        ),
      ],
    );
  }

  Widget _sectionCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.035),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white10),
      ),
      child: child,
    );
  }

  Widget _buildSlider(
    BuildContext context, {
    required String label,
    required double value,
    required double min,
    required double max,
    required Function(double) onChanged,
    required String displayValue,
    bool enabledOverride = true,
  }) {
    final service = context.watch<MusicService>();
    final enabled = service.isEffectsEnabled && enabledOverride;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            Text(
              displayValue,
              style: TextStyle(
                color: enabled ? Colors.tealAccent : Colors.white38,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 15),
            activeTrackColor: Colors.teal,
            inactiveTrackColor: Colors.grey[800],
            thumbColor: Colors.tealAccent,
            overlayColor: Colors.teal.withOpacity(0.2),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: 100,
            onChanged: enabled ? onChanged : null,
          ),
        ),
      ],
    );
  }

  Widget _quickButton(String label, VoidCallback onPressed) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: Colors.teal.withOpacity(0.35)),
        foregroundColor: Colors.white,
        backgroundColor: Colors.white.withOpacity(0.03),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(label),
    );
  }

  Widget _toneButton(
      String label, MusicService service, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: service.isEffectsEnabled ? onPressed : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.teal.withOpacity(0.16),
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.white10,
        disabledForegroundColor: Colors.white38,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(label),
    );
  }
}

void showAudioEffectsMenu(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => const Center(
      child: Material(
        color: Colors.transparent,
        child: AudioEffectsMenu(),
      ),
    ),
  );
}
