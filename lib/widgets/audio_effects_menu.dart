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

        return Container(
          width: Responsive.isDesktop ? 500 : double.infinity,
          height: Responsive.isDesktop ? 600 : MediaQuery.of(context).size.height * 0.75,
          decoration: BoxDecoration(
            color: Colors.grey[900]!.withOpacity(0.95),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.teal.withOpacity(0.3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Audio Effects', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    Switch(
                      value: service.isEffectsEnabled,
                      onChanged: service.setEffectsEnabled,
                      activeColor: Colors.teal,
                    ),
                  ],
                ),
              ),
              
              const Divider(color: Colors.white10),
              
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // DSP Controls (Pitch, Speed, Reverb)
                    _buildSectionTitle('DSP Effects'),
                    const SizedBox(height: 16),
                    _buildSlider(context, 'Speed', service.speed, 0.5, 2.0, (v) => service.setSpeed(v), '${service.speed.toStringAsFixed(2)}x'),
                    _buildSlider(context, 'Pitch', service.pitch, 0.5, 2.0, (v) => service.setPitch(v), '${service.pitch.toStringAsFixed(2)}x'),
                    _buildSlider(context, 'Reverb & Spatial', service.reverb, 0.0, 1.0, (v) => service.setReverb(v), service.reverb > 0.8 ? 'Max Room' : '${(service.reverb * 100).toInt()}%'),
                    
                    const SizedBox(height: 24),
                    const Divider(color: Colors.white10),
                    const SizedBox(height: 16),

                    // Equalizer
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildSectionTitle('Equalizer'),
                        Switch(
                          value: service.isEqualizerEnabled,
                          onChanged: service.isEffectsEnabled ? service.setEqualizerEnabled : null,
                          activeColor: Colors.teal,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Presets
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: presets.map((preset) {
                          final isSelected = service.currentPreset == preset;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: FilterChip(
                              label: Text(preset),
                              selected: isSelected,
                              onSelected: service.isEffectsEnabled && service.isEqualizerEnabled 
                                ? (_) => service.setEqualizerPreset(preset) 
                                : null,
                              backgroundColor: Colors.black26,
                              selectedColor: Colors.teal.withOpacity(0.3),
                              labelStyle: TextStyle(color: isSelected ? Colors.tealAccent : Colors.white70),
                              checkmarkColor: Colors.tealAccent,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    
                    const SizedBox(height: 24),

                    // EQ Bands
                    SizedBox(
                      height: 200,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: freqs.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final freq = freqs[index];
                          final val = service.currentEqBandValues[index];
                          final label = freq >= 1000 ? '${freq ~/ 1000}k' : '$freq';
                          
                          return Column(
                            children: [
                              Expanded(
                                child: RotatedBox(
                                  quarterTurns: 3,
                                  child: SliderTheme(
                                    data: SliderThemeData(
                                      trackHeight: 4,
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                                      activeTrackColor: Colors.teal,
                                      inactiveTrackColor: Colors.grey[800],
                                      thumbColor: Colors.tealAccent,
                                      overlayColor: Colors.teal.withOpacity(0.2),
                                    ),
                                    child: Slider(
                                      value: val,
                                      min: -10,
                                      max: 10,
                                      onChanged: (service.isEffectsEnabled && service.isEqualizerEnabled)
                                        ? (v) => service.setEqualizerBand(index, v)
                                        : null,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
                              Text('${val.toInt()}dB', style: const TextStyle(color: Colors.teal, fontSize: 9)),
                            ],
                          );
                        },
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Song Specific Toggle
                    CheckboxListTile(
                      title: const Text('Save for this song only', style: TextStyle(color: Colors.white)),
                      value: service.useSongSpecificSettings,
                      onChanged: service.isEffectsEnabled ? (v) => service.setUseSongSpecificSettings(v!) : null,
                      activeColor: Colors.teal,
                      checkColor: Colors.black,
                      contentPadding: EdgeInsets.zero,
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

  Widget _buildSectionTitle(String title) {
    return Text(title, style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1));
  }

  Widget _buildSlider(BuildContext context, String label, double value, double min, double max, Function(double) onChanged, String displayValue) {
    final service = context.watch<MusicService>();
    final enabled = service.isEffectsEnabled;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
            Text(displayValue, style: const TextStyle(color: Colors.tealAccent, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: Colors.teal,
            inactiveTrackColor: Colors.grey[800],
            thumbColor: Colors.tealAccent,
            overlayColor: Colors.teal.withOpacity(0.2),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            onChanged: enabled ? onChanged : null,
          ),
        ),
      ],
    );
  }
}

// Function to show the floating menu
void showAudioEffectsMenu(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => Center(
      child: Material(
        color: Colors.transparent,
        child: const AudioEffectsMenu(),
      ),
    ),
  );
}
