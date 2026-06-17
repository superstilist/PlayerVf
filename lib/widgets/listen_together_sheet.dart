import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/music_service.dart';
import '../services/listen_together_service.dart';
import '../services/responsive.dart';
import 'glass_container.dart';

class ListenTogetherSheet extends StatelessWidget {
  const ListenTogetherSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final musicService = Provider.of<MusicService>(context);

    return Consumer<ListenTogetherService>(
      builder: (context, party, _) {
        return GlassContainer(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          color: theme.colorScheme.surface.withOpacity(0.88),
          blur: 10,
          child: Padding(
            padding: EdgeInsets.fromLTRB(24.w, 22.h, 24.w, 28.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.groups_rounded, color: theme.colorScheme.primary),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: Text(
                        'Listen Together',
                        style: TextStyle(
                          fontSize: 20.sp,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                SizedBox(height: 12.h),
                _partyStatusPill(theme, party),
                if (party.partyHostUrl != null) ...[
                  SizedBox(height: 10.h),
                  SelectableText(
                    party.partyHostUrl!,
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
                if (party.partyDevices.isNotEmpty) ...[
                  SizedBox(height: 12.h),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: 176.h),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: party.partyDevices.length,
                      separatorBuilder: (_, __) => SizedBox(height: 6.h),
                      itemBuilder: (context, index) {
                        final device = party.partyDevices[index];
                        return ListTile(
                          dense: true,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16.s),
                          ),
                          tileColor: theme.colorScheme.surfaceContainerHighest
                              .withOpacity(0.34),
                          leading: const Icon(Icons.devices_rounded),
                          title: Text(
                            device.deviceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                              '${device.trackCount} tracks  |  ${device.url}'),
                          trailing: FilledButton.tonal(
                            onPressed: party.isPartyBusy
                                ? null
                                : () async {
                                    await party.connect(
                                      musicService,
                                      device,
                                    );
                                  },
                            child: const Text('Join'),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                SizedBox(height: 18.h),
                Wrap(
                  spacing: 10.w,
                  runSpacing: 10.h,
                  children: [
                    FilledButton.icon(
                      onPressed: party.isPartyBusy ||
                              musicService.currentMusic == null ||
                              party.isPartyHosting
                          ? null
                          : () async {
                              await party.startHost(musicService);
                            },
                      icon: const Icon(Icons.wifi_tethering_rounded),
                      label: const Text('Host Party'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: party.isPartyBusy || party.isPartyJoined
                          ? null
                          : () async {
                              await party.join(musicService);
                            },
                      icon: const Icon(Icons.radar_rounded),
                      label: const Text('Join Party'),
                    ),
                    if (party.isPartyHosting || party.isPartyJoined)
                      OutlinedButton.icon(
                        onPressed: () {
                          party.stop();
                        },
                        icon: const Icon(Icons.stop_circle_rounded),
                        label: const Text('Stop'),
                      ),
                  ],
                ),
                SizedBox(height: 10.h),
                Text(
                  'Both devices need to be on the same Wi-Fi or hotspot. The guest streams the host song and follows play, pause, and seek.',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12.sp,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _partyStatusPill(ThemeData theme, ListenTogetherService party) {
    final icon = party.isPartyHosting
        ? Icons.wifi_tethering_rounded
        : party.isPartyJoined
            ? Icons.link_rounded
            : Icons.group_add_rounded;
    final label = party.partyStatus ??
        (party.isPartyHosting
            ? 'Hosting party'
            : party.isPartyJoined
                ? 'Joined party'
                : 'Ready to host or join');
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 9.h),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.48),
        borderRadius: BorderRadius.circular(12.s),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17.s, color: theme.colorScheme.primary),
          SizedBox(width: 8.w),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void showListenTogetherSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => const ListenTogetherSheet(),
  );
}
