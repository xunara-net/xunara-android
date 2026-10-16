import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
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
    for (final name in [
      'connected',
      'finish',
      'roaming-ready',
      'offline',
      'auto-connected',
      'roaming-finish',
      'cancel-ready',
      'cancel-stopped',
      'network-restored',
      'ping-timeout-ready',
      'ping-timeout-enabled',
      'ping-timeout-complete',
      'mobile-ready',
      'mobile-connected',
      'mobile-finish',
    ]) {
      final marker = File('$cache/integration-$name');
      if (await marker.exists()) await marker.delete();
    }
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
      expect(connected.magicDnsEnabled, isTrue);
      expect(connected.searchDomains, contains('core.test'));
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
      final router = verified.devices.firstWhere(
        (peer) => peer.name.startsWith('rust-router.'),
      );
      final ping = await gateway.ping(
        router.id,
        generation: verified.generation,
      );
      expect(ping.address, addressOnly(router.addresses.first));
      expect(ping.path, 'relay');
      expect(ping.relayRegion, greaterThan(0));
      expect(ping.rttMs, greaterThanOrEqualTo(0));
      await expectLater(
        gateway.ping('18446744073709551615', generation: verified.generation),
        throwsA(isA<PlatformException>()),
      );
      await File('$cache/integration-ping-timeout-ready').writeAsString('{}');
      await waitForMarker('ping-timeout-enabled');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await expectLater(
        gateway.ping(router.id, generation: verified.generation),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.message,
            '超时提示',
            contains('检测超时'),
          ),
        ),
      );
      await File('$cache/integration-ping-timeout-complete')
          .writeAsString('{}');
      await File('$cache/integration-roaming-ready').writeAsString('{}');
      final offline = await waitForOffline(gateway);
      expect(offline.addresses, isEmpty, reason: '切网不保留伪在线映射');
      await Future<void>.delayed(const Duration(seconds: 2));
      expect((await gateway.snapshot()).phase, ConnectionPhase.reconnecting);
      await File('$cache/integration-offline').writeAsString('{}');
      final automatic = await waitFor(gateway, ConnectionPhase.connected);
      expect(automatic.generation, greaterThan(connected.generation));
      expect(automatic.reconnects, greaterThan(0));
      expect(automatic.addresses, connected.addresses);
      expect(
        (await gateway.ping(router.id, generation: automatic.generation)).path,
        'relay',
      );
      await expectLater(
        gateway.ping(router.id, generation: connected.generation),
        throwsA(isA<PlatformException>()),
      );
      await File('$cache/integration-auto-connected').writeAsString('{}');
      await waitForMarker('roaming-finish');
      await File('$cache/integration-mobile-ready').writeAsString('{}');
      final mobile = await waitForMobile(gateway, automatic.generation);
      expect(mobile.addresses, connected.addresses);
      expect(
        (await gateway.ping(router.id, generation: mobile.generation)).path,
        'relay',
      );
      await File('$cache/integration-mobile-connected').writeAsString('{}');
      await waitForMarker('mobile-finish');
      await File('$cache/integration-cancel-ready').writeAsString('{}');
      await waitForOffline(gateway);
      await gateway.disconnect();
      await waitFor(gateway, ConnectionPhase.disconnected);
      await File('$cache/integration-cancel-stopped').writeAsString('{}');
      await waitForMarker('network-restored');
      await Future<void>.delayed(const Duration(seconds: 4));
      expect(
        (await gateway.snapshot()).phase,
        ConnectionPhase.disconnected,
        reason: '用户主动断开后不能自动拉起 VPN',
      );
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

Future<void> waitForMarker(String name) async {
  final marker = File(
    '/data/user/0/net.xunara.android/cache/integration-$name',
  );
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (!await marker.exists()) {
    if (DateTime.now().isAfter(deadline)) fail('等待测试阶段 $name 超时');
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

Future<VpnSnapshot> waitForOffline(VpnGateway gateway) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    final snapshot = await gateway.snapshot();
    await File('/data/user/0/net.xunara.android/cache/integration-progress')
        .writeAsString(
          jsonEncode({
            'phase': snapshot.phase.name,
            'network': snapshot.networkLabel,
            'generation': snapshot.generation,
            'message': snapshot.message,
          }),
        );
    if (snapshot.phase == ConnectionPhase.reconnecting &&
        snapshot.networkLabel == '等待网络恢复') {
      return snapshot;
    }
    if (snapshot.phase == ConnectionPhase.error) {
      fail('等待断网失败：${snapshot.message}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw StateError('等待物理网络完全断开超时');
}

Future<VpnSnapshot> waitForMobile(
  VpnGateway gateway,
  int previousGeneration,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    final snapshot = await gateway.snapshot();
    if (snapshot.phase == ConnectionPhase.connected &&
        snapshot.networkLabel == '移动网络' &&
        snapshot.generation > previousGeneration) {
      return snapshot;
    }
    if (snapshot.phase == ConnectionPhase.error) {
      fail('切换移动网络失败：${snapshot.message}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw StateError('等待移动网络重连超时');
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
