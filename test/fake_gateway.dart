import 'package:flutter/services.dart';
import 'package:xunara_android/models.dart';
import 'package:xunara_android/vpn_gateway.dart';

class FakeGateway implements VpnGateway {
  ClientProfile profile = const ClientProfile(
    server: 'https://example.test:9090/',
    hostname: 'android-test',
  );
  VpnSnapshot current = const VpnSnapshot();
  bool denyPermission = false;
  int connectCalls = 0;
  int browserCalls = 0;
  int consoleCalls = 0;
  String receivedKey = '';
  @override
  Future<Bootstrap> bootstrap() async => Bootstrap(profile, current, '0.1.0');
  @override
  Future<VpnSnapshot> snapshot() async => current;
  @override
  Future<ClientProfile> saveProfile(ClientProfile profile) async =>
      this.profile = profile;
  @override
  Future<void> connect({String authKey = ''}) async {
    connectCalls++;
    if (denyPermission) {
      throw PlatformException(
        code: 'VPN_PERMISSION_DENIED',
        message: '未开启 VPN 权限，尚未连接网络',
      );
    }
    receivedKey = authKey;
    current = const VpnSnapshot(
      phase: ConnectionPhase.authorizing,
      authorizationAvailable: true,
      message: '请在浏览器中登录并批准这台设备',
    );
  }

  @override
  Future<void> disconnect() async {
    current = const VpnSnapshot();
  }

  @override
  Future<void> openAuthorization() async {
    browserCalls++;
  }

  @override
  Future<void> openConsole() async {
    consoleCalls++;
  }

  @override
  Future<void> vpnSettings() async {}
  @override
  Future<void> notificationSettings() async {}
}
