import 'dart:convert';

import 'package:flutter/services.dart';

import 'models.dart';

class Bootstrap {
  const Bootstrap(this.profile, this.snapshot, this.coreVersion);
  final ClientProfile profile;
  final VpnSnapshot snapshot;
  final String coreVersion;
}

abstract class VpnGateway {
  Future<Bootstrap> bootstrap();
  Future<VpnSnapshot> snapshot();
  Future<ClientProfile> saveProfile(ClientProfile profile);
  Future<void> connect({String authKey = ''});
  Future<void> disconnect();
  Future<void> openAuthorization();
  Future<void> openConsole();
  Future<void> vpnSettings();
  Future<void> notificationSettings();
  Future<PingResult> ping(String peerId, {required int generation});
}

class AndroidVpnGateway implements VpnGateway {
  static const _channel = MethodChannel('net.xunara.android/vpn');
  Future<Map<String, dynamic>> _json(String method, [Object? arguments]) async {
    final value = await _channel.invokeMethod<String>(method, arguments);
    if (value == null) throw const FormatException('系统未返回有效状态');
    return jsonDecode(value) as Map<String, dynamic>;
  }

  @override
  Future<Bootstrap> bootstrap() async {
    final json = await _json('bootstrap');
    return Bootstrap(
      ClientProfile.fromJson(json['profile'] as Map<String, dynamic>),
      VpnSnapshot.fromJson(json['snapshot'] as Map<String, dynamic>),
      json['core_version'] as String,
    );
  }

  @override
  Future<VpnSnapshot> snapshot() async =>
      VpnSnapshot.fromJson(await _json('snapshot'));
  @override
  Future<ClientProfile> saveProfile(ClientProfile profile) async =>
      ClientProfile.fromJson(await _json('saveProfile', profile.toJson()));
  @override
  Future<void> connect({String authKey = ''}) =>
      _channel.invokeMethod<void>('connect', {'auth_key': authKey});
  @override
  Future<void> disconnect() => _channel.invokeMethod<void>('disconnect');
  @override
  Future<void> openAuthorization() =>
      _channel.invokeMethod<void>('openAuthorization');
  @override
  Future<void> openConsole() => _channel.invokeMethod<void>('openConsole');
  @override
  Future<void> vpnSettings() => _channel.invokeMethod<void>('vpnSettings');
  @override
  Future<void> notificationSettings() =>
      _channel.invokeMethod<void>('notificationSettings');
  @override
  Future<PingResult> ping(String peerId, {required int generation}) async {
    final json = await _json('ping', {
      'peer_id': peerId,
      'generation': generation,
    });
    if (json['error'] case final String message) {
      throw PlatformException(code: 'PING_FAILED', message: message);
    }
    return PingResult.fromJson(json['result'] as Map<String, dynamic>);
  }
}
