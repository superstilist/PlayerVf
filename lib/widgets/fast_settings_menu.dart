import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/settings_model.dart';
import '../pages/settings_page.dart';
import '../services/music_service.dart';
import '../services/responsive.dart';

Future<void> showFastSettingsMenu(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const FastSettingsMenu(),
  );
}

class FastSettingsMenu extends StatelessWidget {
  const FastSettingsMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsModel>();
    final musicService = context.watch<MusicService>();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.tune_rounded,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Quick Settings',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.settings_rounded,
                      size: 20, color: theme.colorScheme.primary),
                  tooltip: 'Full Settings',
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const SettingsPage()),
                    );
                  },
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          Divider(
              height: 1,
              color: theme.colorScheme.outlineVariant.withOpacity(0.2)),
          _Section(
            icon: Icons.play_circle_outline_rounded,
            label: 'Playback',
            children: [
              _VolumeChip(musicService: musicService),
              _SafeEarsChip(musicService: musicService),
              _PerformanceChip(settings: settings),
            ],
          ),
          _Section(
            icon: Icons.palette_outlined,
            label: 'Appearance',
            children: [
              _ThemeChip(settings: settings),
              _BackgroundChip(settings: settings),
              _AccentChip(settings: settings),
            ],
          ),
          Divider(
              height: 1,
              color: theme.colorScheme.outlineVariant.withOpacity(0.2)),
          GestureDetector(
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'Open Full Settings',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<Widget> children;

  const _Section({
    required this.icon,
    required this.label,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(icon, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: children.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => children[i],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _Chip({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withOpacity(0.18)
              : theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary.withOpacity(0.5)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withOpacity(0.6),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VolumeChip extends StatelessWidget {
  final MusicService musicService;
  const _VolumeChip({required this.musicService});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<double>(
      valueListenable: musicService.volumeNotifier,
      builder: (_, volume, __) {
        return SizedBox(
          width: 160,
          child: Row(
            children: [
              Icon(
                volume <= 0
                    ? Icons.volume_off_rounded
                    : volume < 50
                        ? Icons.volume_down_rounded
                        : Icons.volume_up_rounded,
                size: 16,
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 7),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: theme.colorScheme.primary,
                    inactiveTrackColor:
                        theme.colorScheme.onSurface.withOpacity(0.12),
                    thumbColor: theme.colorScheme.primary,
                    overlayColor: theme.colorScheme.primary.withOpacity(0.12),
                  ),
                  child: Slider(
                    value: volume.clamp(0.0, 100.0),
                    min: 0,
                    max: 100,
                    onChanged: (v) => musicService.setVolume(v),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SafeEarsChip extends StatelessWidget {
  final MusicService musicService;
  const _SafeEarsChip({required this.musicService});

  @override
  Widget build(BuildContext context) {
    return _Chip(
      icon: Icons.hearing_rounded,
      label: 'Safe Ears',
      isSelected: musicService.safeEarsEnabled,
      onTap: () => musicService.setSafeEarsEnabled(!musicService.safeEarsEnabled),
    );
  }
}

class _PerformanceChip extends StatelessWidget {
  final SettingsModel settings;
  const _PerformanceChip({required this.settings});

  @override
  Widget build(BuildContext context) {
    final mode = settings.performanceMode;
    return _Chip(
      icon: mode == PerformanceMode.batterySaver
          ? Icons.battery_saver_rounded
          : mode == PerformanceMode.quality
              ? Icons.star_rounded
              : Icons.balance_rounded,
      label: mode == PerformanceMode.batterySaver
          ? 'Saver'
          : mode == PerformanceMode.quality
              ? 'Quality'
              : 'Balanced',
      isSelected: true,
      onTap: () {
        final next = mode == PerformanceMode.balanced
            ? PerformanceMode.batterySaver
            : mode == PerformanceMode.batterySaver
                ? PerformanceMode.quality
                : PerformanceMode.balanced;
        settings.setPerformanceMode(next);
      },
    );
  }
}

class _ThemeChip extends StatelessWidget {
  final SettingsModel settings;
  const _ThemeChip({required this.settings});

  @override
  Widget build(BuildContext context) {
    final mode = settings.themeMode;
    return _Chip(
      icon: mode == ThemeMode.dark
          ? Icons.dark_mode_rounded
          : mode == ThemeMode.light
              ? Icons.light_mode_rounded
              : Icons.brightness_auto_rounded,
      label: mode == ThemeMode.dark
          ? 'Dark'
          : mode == ThemeMode.light
              ? 'Light'
              : 'Auto',
      isSelected: true,
      onTap: () {
        final next = mode == ThemeMode.dark
            ? ThemeMode.light
            : mode == ThemeMode.light
                ? ThemeMode.system
                : ThemeMode.dark;
        settings.setThemeMode(next);
      },
    );
  }
}

class _BackgroundChip extends StatelessWidget {
  final SettingsModel settings;
  const _BackgroundChip({required this.settings});

  @override
  Widget build(BuildContext context) {
    final mode = settings.backgroundMode;
    return _Chip(
      icon: mode == BackgroundMode.coverArt
          ? Icons.album_rounded
          : Icons.palette_rounded,
      label: mode == BackgroundMode.coverArt ? 'Cover' : 'Solid',
      isSelected: true,
      onTap: () {
        settings.setBackgroundMode(
          mode == BackgroundMode.coverArt
              ? BackgroundMode.solidColor
              : BackgroundMode.coverArt,
        );
      },
    );
  }
}

class _AccentChip extends StatelessWidget {
  final SettingsModel settings;
  const _AccentChip({required this.settings});

  @override
  Widget build(BuildContext context) {
    final current = settings.accentColor;
    return GestureDetector(
      onTap: () {
        final colors = [
          Colors.teal,
          Colors.blue,
          Colors.purple,
          Colors.pink,
          Colors.orange,
          Colors.green,
          Colors.red,
          Colors.indigo,
        ];
        final idx = colors.indexWhere((c) => c.value == current.value);
        final next = colors[(idx + 1) % colors.length];
        settings.setAccentColor(next);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: current.withOpacity(0.18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: current.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(color: current, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              'Accent',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: current,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
