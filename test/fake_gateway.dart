import 'package:flutter/services.dart';
import 'package:xunara_android/models.dart';
import 'package:xunara_android/vpn_gateway.dart';
import 'package:xunara_android/system_diagnostics.dart';

class FakeGateway implements VpnGateway {
  ClientProfile profile = const ClientProfile(
    server: 'https://example.test:9090/',
    hostname: 'android-test',
    id: 'home',
  );
  VpnSnapshot current = const VpnSnapshot();
  bool denyPermission = false;
  int connectCalls = 0;
  int browserCalls = 0;
  int consoleCalls = 0;
  String receivedKey = '';
  int pingCalls = 0;
  Future<PingResult>? pingResponse;
  final Map<String, ClientProfile> savedProfiles = {};
  int profileChanges = 0;
  int batteryCalls = 0;
  bool bootstrapUnavailable = false;
  List<InstalledApplication> applicationList = const [
    InstalledApplication(packageName: 'com.example.nas', label: '家庭 NAS'),
    InstalledApplication(packageName: 'com.example.browser', label: '浏览器'),
  ];
  @override
  Future<Bootstrap> bootstrap() async {
    if (bootstrapUnavailable) {
      throw PlatformException(code: 'UNAVAILABLE', message: '系统读取暂时不可用');
    }
    return Bootstrap(
      profile,
      current,
      '0.1.0',
      profiles: savedProfiles.isEmpty
          ? [profile]
          : savedProfiles.values.toList(),
    );
  }

  @override
  Future<VpnSnapshot> snapshot() async => current;
  @override
  Future<ClientProfile> saveProfile(ClientProfile profile) async {
    profileChanges++;
    savedProfiles[this.profile.id] = this.profile;
    if (profile.id.isEmpty) {
      profile = profile.copyWith(id: 'account-$profileChanges');
    }
    savedProfiles[profile.id] = profile;
    current = const VpnSnapshot();
    return this.profile = profile;
  }

  @override
  Future<void> selectProfile(String id) async {
    profileChanges++;
    profile = savedProfiles[id]!;
    current = const VpnSnapshot();
  }

  @override
  Future<void> forgetProfile(String id) async {
    profileChanges++;
    savedProfiles.remove(id);
  }

  @override
  Future<List<InstalledApplication>> applications() async => applicationList;
  @override
  Future<SystemDiagnostics> systemDiagnostics() async =>
      const SystemDiagnostics(
        androidSdk: 36,
        androidVersion: '16',
        appVersion: '0.2.0',
        coreVersion: '0.1.0',
        vpnPermission: true,
        notificationsEnabled: false,
        batteryUnrestricted: false,
        backgroundRestricted: true,
      );
  @override
  Future<void> batterySettings() async {
    batteryCalls++;
  }

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
  @override
  Future<PingResult> ping(String peerId, {required int generation}) async {
    pingCalls++;
    return pingResponse ??
        Future.value(
          const PingResult(
            address: '100.80.0.2',
            rttMs: 12.5,
            path: 'relay',
            relayRegion: 900,
          ),
        );
  }
}
