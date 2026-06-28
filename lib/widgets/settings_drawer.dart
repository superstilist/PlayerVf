import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/settings_model.dart';
import '../pages/settings_page.dart';
import '../services/responsive.dart';

class SettingsDrawer extends StatelessWidget {
  const SettingsDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsModel>();

    return Container(
      width: 320,
      height: double.infinity,
      color: Colors.transparent,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.all(24.s),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Settings',
                    style:
                        TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: 16.s),
                children: [
                  _buildQuickTile(
                    context: context,
                    icon: Icons.play_circle_rounded,
                    title: 'Open Full Settings',
                    subtitle: 'All categories and options',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SettingsPage(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  _buildSectionTitle(context, 'Quick Access'),
                  _buildQuickTile(
                    context: context,
                    icon: Icons.history_rounded,
                    title: 'Remember Playback',
                    subtitle: settings.musicSourcePaths.isEmpty
                        ? 'Resume last track'
                        : '${settings.musicSourcePaths.length} folder(s)',
                    trailing: Switch(
                      value: true,
                      onChanged: null,
                      activeColor: settings.accentColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildQuickTile(
                    context: context,
                    icon: Icons.sync_rounded,
                    title: 'Update Library',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SettingsPage(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildQuickTile(
                    context: context,
                    icon: Icons.speed_rounded,
                    title: 'Performance',
                    subtitle: _performanceLabel(settings.performanceMode),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SettingsPage(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _performanceLabel(PerformanceMode mode) {
    switch (mode) {
      case PerformanceMode.auto:
        return 'Auto';
      case PerformanceMode.quality:
        return 'Quality';
      case PerformanceMode.balanced:
        return 'Balanced';
      case PerformanceMode.batterySaver:
        return 'Battery Saver';
      case PerformanceMode.maxPerformance:
        return 'Max Performance';
    }
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildQuickTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: trailing,
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}
