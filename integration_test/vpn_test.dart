import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xunara_android/models.dart';
import 'package:xunara_android/vpn_gateway.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('真实 Android TUN、Noise 注册、流量与持久身份重连', (tester) async {
    final gateway = AndroidVpnGateway();
    final initial = await gateway.bootstrap();
    expect(initial.coreVersion, isNotEmpty);
    const cache = '/data/user/0/net.xunara.android/cache';
    final secret = File('$cache/integration-auth-key');
    expect(
      await secret.exists(),
      isTrue,
      reason: '请使用 scripts/test-android-vpn.sh，在私有目录提供临时测试密钥',
    );
    var authKey = (await secret.readAsString()).trim();
    await secret.delete();
    if ((await gateway.snapshot()).phase.active) {
      await gateway.disconnect();
      await waitFor(gateway, ConnectionPhase.disconnected);
    }
    try {
      await gateway.saveProfile(
        const ClientProfile(
          server: 'http://127.0.0.1:18080/',
          hostname: 'android-integration',
          acceptRoutes: true,
        ),
      );
      await gateway.connect(authKey: authKey);
      authKey = '';
      final connected = await waitFor(gateway, ConnectionPhase.connected);
      expect(connected.addresses, isNotEmpty);
      await File('$cache/integration-connected')
          .writeAsString(jsonEncode({'addresses': connected.addresses}));
      // 流量由 shell UID 发起，避免用已从 VPN 排除的客户端自身假装验证数据面。
      final finish = File('$cache/integration-finish');
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      while (!await finish.exists()) {
        if (DateTime.now().isAfter(deadline)) fail('外部数据面验收未完成');
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      await finish.delete();
      final verified = await gateway.snapshot();
      expect(verified.bytesReceived, greaterThan(0));
      expect(verified.bytesSent, greaterThan(0));
      expect(verified.devices, isNotEmpty);
      await gateway.disconnect();
      await waitFor(gateway, ConnectionPhase.disconnected);
      // 不再次提供接入密钥，必须复用已有机器私钥，不能重新创建另一台设备。
      await gateway.connect();
      final reconnected = await waitFor(gateway, ConnectionPhase.connected);
      expect(reconnected.addresses, connected.addresses);
    } finally {
      authKey = '';
      await gateway.disconnect();
      await waitFor(gateway, ConnectionPhase.disconnected);
      await gateway.saveProfile(initial.profile);
    }
  });
}

Future<VpnSnapshot> waitFor(VpnGateway gateway, ConnectionPhase phase) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    final snapshot = await gateway.snapshot();
    await File(
      '/data/user/0/net.xunara.android/cache/integration-progress',
    ).writeAsString(
      jsonEncode({'phase': snapshot.phase.name, 'message': snapshot.message}),
    );
    if (snapshot.phase == phase) return snapshot;
    if (snapshot.phase == ConnectionPhase.error) {
      fail('VPN 运行失败：${snapshot.message}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  throw StateError('等待 ${phase.name} 超时');
}
