import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/music_service.dart';
import '../services/responsive.dart';

class EqualizerSheet extends StatefulWidget {
  const EqualizerSheet({super.key});

  @override
  State<EqualizerSheet> createState() => _EqualizerSheetState();
}

class _EqualizerSheetState extends State<EqualizerSheet> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Consumer<MusicService>(
      builder: (context, musicService, child) {
        final bandValues = musicService.equalizerBandValues;
        final frequencies = musicService.getEqualizerFrequencies();
        final isEnabled = musicService.isEqualizerEnabled;
        final presets = musicService.getEqualizerPresets();
        final currentPreset = musicService.currentPreset;
        
        return Container(
          height: 500.h,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30.s)),
          ),
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 20.h),
          child: Column(
            children: [
              Container(
                width: 40.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2.s),
                ),
              ),
              SizedBox(height: 20.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Equalizer',
                    style: TextStyle(
                      fontSize: 20.sp,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  Switch(
                    value: isEnabled,
                    onChanged: (value) async {
                      await musicService.setEqualizerEnabled(value);
                    },
                    activeColor: Colors.teal,
                  ),
                ],
              ),
              SizedBox(height: 30.h),
              Expanded(
                child: bandValues.isEmpty 
                  ? const Center(child: CircularProgressIndicator(color: Colors.teal))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(bandValues.length, (index) {
                        return _buildEqualizerSlider(index, theme, musicService, bandValues, frequencies, isEnabled);
                      }),
                    ),
              ),
              SizedBox(height: 20.h),
              _buildPresets(theme, musicService, presets, currentPreset, isEnabled),
              SizedBox(height: 20.h),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEqualizerSlider(int index, ThemeData theme, MusicService musicService, List<double> bandValues, List<int> frequencies, bool isEnabled) {
    return Column(
      children: [
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 4.h,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8.s),
                overlayShape: RoundSliderOverlayShape(overlayRadius: 16.s),
                activeTrackColor: isEnabled ? Colors.teal : Colors.grey,
                inactiveTrackColor: theme.colorScheme.onSurface.withOpacity(0.1),
                thumbColor: isEnabled ? Colors.teal : Colors.grey,
              ),
              child: Slider(
                value: bandValues[index],
                min: -10,
                max: 10,
                onChanged: isEnabled
                    ? (value) {
                        musicService.setEqualizerBand(index, value);
                      }
                    : null,
              ),
            ),
          ),
        ),
        SizedBox(height: 8.h),
        Text(
          _formatFrequency(frequencies.isNotEmpty ? frequencies[index] : 0),
          style: TextStyle(
            fontSize: 10.sp,
            color: theme.colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
      ],
    );
  }

  String _formatFrequency(int freq) {
    if (freq >= 1000) return '${(freq / 1000).toStringAsFixed(1)}kHz';
    return '${freq}Hz';
  }

  Widget _buildPresets(ThemeData theme, MusicService musicService, List<String> presets, String currentPreset, bool isEnabled) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: presets.map((preset) {
          final isSelected = currentPreset == preset;
          return Padding(
            padding: EdgeInsets.only(right: 8.w),
            child: ChoiceChip(
              label: Text(preset),
              selected: isSelected,
              onSelected: isEnabled ? (selected) async {
                if (selected) {
                  await musicService.setEqualizerPreset(preset);
                }
              } : null,
              selectedColor: Colors.teal.withOpacity(0.2),
              labelStyle: TextStyle(
                color: isSelected ? Colors.teal : theme.colorScheme.onSurface,
                fontSize: 12.sp,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
