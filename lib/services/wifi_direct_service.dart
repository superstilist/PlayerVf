import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_share_service.dart';

enum NearbyDeviceTransport { wifiDirect, localNetwork }

class NearbyShareDevice {
  final String id;
  final String name;
  final String type;
  final String status;
  final NearbyDeviceTransport transport;
  final String? url;
  final bool trusted;

  const NearbyShareDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.status,
    required this.transport,
    this.url,
    this.trusted = false,
  });

  NearbyShareDevice copyWith({
    String? status,
    String? url,
    bool? trusted,
  }) {
    return NearbyShareDevice(
      id: id,
      name: name,
      type: type,
      status: status ?? this.status,
      transport: transport,
      url: url ?? this.url,
      trusted: trusted ?? this.trusted,
    );
  }
}

class WifiDirectConnectionInfo {
  final bool connected;
  final bool isGroupOwner;
  final String? groupOwnerAddress;

  const WifiDirectConnectionInfo({
    required this.connected,
    required this.isGroupOwner,
    required this.groupOwnerAddress,
  });

  factory WifiDirectConnectionInfo.fromMap(Map<dynamic, dynamic>? map) {
    return WifiDirectConnectionInfo(
      connected: map?['connected'] == true,
      isGroupOwner: map?['isGroupOwner'] == true,
      groupOwnerAddress: map?['groupOwnerAddress']?.toString(),
    );
  }
}

class WifiDirectService {
  static const MethodChannel _channel = MethodChannel('player_vf_wifi_direct');
  static const String _trustedDevicesKey = 'trusted_share_devices';

  final LocalShareService localShareService;

  WifiDirectService({required this.localShareService});

  bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> isWifiDirectSupported() async {
    if (!isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> ensurePermissions() async {
    if (!isAndroid) return true;
    final hasPermissions =
        await _channel.invokeMethod<bool>('hasPermissions') ?? false;
    if (hasPermissions) return true;
    await _channel.invokeMethod<void>('requestPermissions');
    return await _channel.invokeMethod<bool>('hasPermissions') ?? false;
  }

  Future<List<NearbyShareDevice>> searchDevices() async {
    final trusted = await _trustedDeviceIds();
    final devices = <NearbyShareDevice>[];

    if (await isWifiDirectSupported()) {
      final hasPermissions = await ensurePermissions();
      if (hasPermissions) {
        try {
          await _channel.invokeMethod<bool>('startDiscovery');
          await Future<void>.delayed(const Duration(milliseconds: 1500));
          final rawPeers =
              await _channel.invokeMethod<List<dynamic>>('getPeers') ??
                  <dynamic>[];
          for (final raw in rawPeers.whereType<Map>()) {
            final map = Map<dynamic, dynamic>.from(raw);
            final address = map['address']?.toString() ?? '';
            if (address.isEmpty) continue;
            devices.add(
              NearbyShareDevice(
                id: address,
                name: map['name']?.toString().trim().isNotEmpty == true
                    ? map['name'].toString()
                    : 'Android device',
                type: map['type']?.toString() ?? 'Android Wi-Fi Direct',
                status: map['status']?.toString() ?? 'available',
                transport: NearbyDeviceTransport.wifiDirect,
                trusted: trusted.contains(address),
              ),
            );
          }
        } catch (_) {}
      }
    }

    final localDevices = await localShareService.discoverDevices();
    for (final device in localDevices) {
      devices.add(
        NearbyShareDevice(
          id: device.url,
          name: device.deviceName,
          type: 'Local network',
          status: 'available',
          transport: NearbyDeviceTransport.localNetwork,
          url: device.url,
          trusted: trusted.contains(device.url),
        ),
      );
    }

    devices.sort((a, b) {
      if (a.trusted != b.trusted) return a.trusted ? -1 : 1;
      if (a.transport != b.transport) {
        return a.transport == NearbyDeviceTransport.wifiDirect ? -1 : 1;
      }
      return a.name.compareTo(b.name);
    });
    return devices;
  }

  Future<WifiDirectConnectionInfo> connectWifiDirect(
    NearbyShareDevice device,
  ) async {
    if (device.transport != NearbyDeviceTransport.wifiDirect) {
      return const WifiDirectConnectionInfo(
        connected: true,
        isGroupOwner: false,
        groupOwnerAddress: null,
      );
    }

    await ensurePermissions();
    await _channel.invokeMethod<bool>('connect', {'address': device.id});
    await Future<void>.delayed(const Duration(seconds: 2));
    final infoMap = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getConnectionInfo',
    );
    await trustDevice(device.id);
    return WifiDirectConnectionInfo.fromMap(infoMap);
  }

  Future<void> disconnectWifiDirect() async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('disconnect');
    } catch (_) {}
  }

  Future<void> stopDiscovery() async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('stopDiscovery');
    } catch (_) {}
  }

  Future<void> trustDevice(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final trusted = prefs.getStringList(_trustedDevicesKey) ?? <String>[];
    if (!trusted.contains(id)) {
      trusted.add(id);
      await prefs.setStringList(_trustedDevicesKey, trusted);
    }
  }

  Future<Set<String>> _trustedDeviceIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_trustedDevicesKey) ?? <String>[]).toSet();
  }
}
