import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/music_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _autoResize = true;
  double _volume = 1.0;
  double _playbackSpeed = 1.0;
  bool _shuffleEnabled = false;
  bool _repeatEnabled = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicService>(
      builder: (context, musicService, child) {
        final size = MediaQuery.of(context).size;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Screen Settings Section
            _buildSectionHeader('Display & Layout'),
            const SizedBox(height: 8),
            Card(
              color: Colors.grey[900],
              child: Column(
                children: [
                  ListTile(
                    title: const Text('Current Screen Size', style: TextStyle(color: Colors.white)),
                    subtitle: Text(
                      'Width: ${size.width.toStringAsFixed(0)}px | Height: ${size.height.toStringAsFixed(0)}px',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                    trailing: Icon(Icons.devices, color: Colors.teal[300]),
                  ),
                  const Divider(color: Colors.grey, height: 1),
                  ListTile(
                    title: const Text('Grid Columns', style: TextStyle(color: Colors.white)),
                    subtitle: Text(
                      '${_getCrossAxisCount(size.width)} columns',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                    trailing: Icon(Icons.grid_view, color: Colors.teal[300]),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Playback Settings Section
            _buildSectionHeader('Playback'),
            const SizedBox(height: 8),
            Card(
              color: Colors.grey[900],
              child: Column(
                children: [
                  ListTile(
                    title: const Text('Volume', style: TextStyle(color: Colors.white)),
                    subtitle: Slider(
                      value: _volume,
                      onChanged: (value) {
                        setState(() {
                          _volume = value;
                        });
                        musicService.setVolume(value);
                      },
                      activeColor: Colors.teal,
                      inactiveColor: Colors.grey[700],
                    ),
                    trailing: Text(
                      '${(_volume * 100).toStringAsFixed(0)}%',
                      style: TextStyle(color: Colors.teal[300]),
                    ),
                  ),
                  const Divider(color: Colors.grey, height: 1),
                  ListTile(
                    title: const Text('Playback Speed', style: TextStyle(color: Colors.white)),
                    subtitle: Slider(
                      value: _playbackSpeed,
                      min: 0.5,
                      max: 2.0,
                      divisions: 6,
                      onChanged: (value) {
                        setState(() {
                          _playbackSpeed = value;
                        });
                        musicService.setSpeed(value);
                      },
                      activeColor: Colors.teal,
                      inactiveColor: Colors.grey[700],
                    ),
                    trailing: Text(
                      '${_playbackSpeed}x',
                      style: TextStyle(color: Colors.teal[300]),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Player Options Section
            _buildSectionHeader('Player Options'),
            const SizedBox(height: 8),
            Card(
              color: Colors.grey[900],
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Shuffle', style: TextStyle(color: Colors.white)),
                    value: _shuffleEnabled,
                    onChanged: (value) {
                      setState(() {
                        _shuffleEnabled = value;
                      });
                    },
                    activeColor: Colors.teal,
                  ),
                  const Divider(color: Colors.grey, height: 1),
                  SwitchListTile(
                    title: const Text('Repeat', style: TextStyle(color: Colors.white)),
                    value: _repeatEnabled,
                    onChanged: (value) {
                      setState(() {
                        _repeatEnabled = value;
                      });
                    },
                    activeColor: Colors.teal,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // About Section
            _buildSectionHeader('About'),
            const SizedBox(height: 8),
            Card(
              color: Colors.grey[900],
              child: const Column(
                children: [
                  ListTile(
                    title: Text('Material 3 Music Player', style: TextStyle(color: Colors.white)),
                    subtitle: Text('Version 1.0.0', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    trailing: Icon(Icons.info_outline, color: Colors.teal),
                  ),
                  Divider(color: Colors.grey, height: 1),
                  ListTile(
                    title: Text('Responsive Design', style: TextStyle(color: Colors.white)),
                    subtitle: Text('Adapts to mobile, tablet, and desktop screens', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    trailing: Icon(Icons.phone_android, color: Colors.teal),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),
          ],
        );
      },
    );
  }

  int _getCrossAxisCount(double width) {
    if (width < 400) return 2;
    if (width < 600) return 3;
    if (width < 900) return 4;
    if (width < 1200) return 5;
    return 6;
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.teal,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
