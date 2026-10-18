import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xunara_android/models.dart';
import 'package:xunara_android/vpn_gateway.dart';

import 'phone_lan_fixture.dart';
import 'sharing.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('真实 Android TUN、Noise 注册、流量与持久身份重连', (tester) async {
    final gateway = AndroidVpnGateway();
    final initial = await gateway.bootstrap();
    expect(initial.coreVersion, isNotEmpty);
    final preferences = await File(
      '/data/user/0/net.xunara.android/shared_prefs/profile.xml',
    ).readAsString();
    expect(preferences.contains('name="catalog_v2"'), isTrue);
    expect(preferences.contains('name="catalog_v1"'), isFalse);
    for (final legacyKey in [
      'server',
      'hostname',
      'accept_routes',
      'auto_reconnect',
    ]) {
      expect(
        preferences.contains('name="$legacyKey"'),
        isFalse,
        reason: '成功迁移后不能残留混读旧偏好',
      );
    }
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
      'routing-only',
      'routing-only-verified',
      'routing-excluded',
      'routing-excluded-verified',
      'routing-restored',
      'routing-restored-verified',
      'dns-ready',
      'dns-verified',
      'doh-ready',
      'doh-verified',
      'dot-ready',
      'dot-verified',
      'exit-ready',
      'exit-verified',
      'exit-revocation-ready',
      'exit-revocation-sent',
      'exit-revoked',
      'exit-revoked-verified',
      'phone-subnet-ready',
      'phone-approval-sent',
      'phone-subnet-active',
      'phone-hold-sent',
      'phone-hold-visible',
      'phone-policy-sent',
      'phone-policy-reset',
      'phone-revocation-sent',
      'phone-subnet-stopped',
      'phone-subnet-verified',
      'phone-exit-ready',
      'phone-exit-approval-sent',
      'phone-exit-active',
      'phone-exit-revocation-sent',
      'phone-exit-stopped',
      'phone-exit-verified',
      'second-ready',
      'second-verified',
      'first-restored',
      'first-restored-verified',
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
    ClientProfile? releaseProfile;
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
      await File('$cache/integration-connected').writeAsString(
        jsonEncode({
          'addresses': connected.addresses,
          'devices': connected.devices
              .map(
                (device) => {
                  'id': device.id,
                  'name': device.name,
                  'addresses': device.addresses,
                },
              )
              .toList(),
        }),
      );
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
      await expectLater(
        gateway.selectProfile(initial.profile.id),
        throwsA(isA<PlatformException>()),
      );
      await gateway.disconnect();
      await waitFor(gateway, ConnectionPhase.disconnected);
      final testProfile = (await gateway.bootstrap()).profile;
      const unused = 'https://integration-unused.invalid/';
      final unusedProfile = await gateway.saveProfile(
        testProfile.copyWith(
          id: '',
          server: unused,
          hostname: 'office-phone',
          acceptRoutes: false,
        ),
      );
      expect((await gateway.snapshot()).phase, ConnectionPhase.disconnected);
      await gateway.selectProfile(testProfile.id);
      final restored = await gateway.bootstrap();
      expect(restored.profile.hostname, testProfile.hostname);
      expect(restored.profile.acceptRoutes, isTrue);
      expect(
        restored.profiles.map((profile) => profile.id).toSet().length,
        restored.profiles.length,
      );
      await expectLater(
        gateway.forgetProfile(testProfile.id),
        throwsA(isA<PlatformException>()),
      );
      await gateway.forgetProfile(unusedProfile.id);
      expect((await gateway.systemDiagnostics()).vpnPermission, isTrue);
      expect(await gateway.applications(), isNotEmpty);

      await gateway.saveProfile(
        testProfile.copyWith(
          appRouting: AppRoutingMode.only,
          applications: ['com.android.shell'],
        ),
      );
      await gateway.connect();
      final only = await waitFor(gateway, ConnectionPhase.connected);
      expect(only.addresses, connected.addresses);
      await File('$cache/integration-routing-only').writeAsString('{}');
      await waitForMarker('routing-only-verified');
      await gateway.disconnect();
      await waitFor(gateway, ConnectionPhase.disconnected);

      await gateway.saveProfile(
        testProfile.copyWith(
          appRouting: AppRoutingMode.exclude,
          applications: ['com.android.shell'],
        ),
      );
      await gateway.connect();
      await waitFor(gateway, ConnectionPhase.connected);
      await File('$cache/integration-routing-excluded').writeAsString('{}');
      await waitForMarker('routing-excluded-verified');
      await gateway.disconnect();
      await waitFor(gateway, ConnectionPhase.disconnected);

      await gateway.saveProfile(
        testProfile.copyWith(
          appRouting: AppRoutingMode.only,
          applications: ['com.xunara.integration.removed'],
        ),
      );
      await expectLater(
        gateway.connect(),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.message,
            '空安装清单拒绝',
            contains('已卸载'),
          ),
        ),
      );
      expect((await gateway.snapshot()).phase, ConnectionPhase.disconnected);
      await expectLater(
        gateway.saveProfile(
          testProfile.copyWith(appRouting: AppRoutingMode.only),
        ),
        throwsA(isA<PlatformException>()),
      );
      await gateway.saveProfile(testProfile);
      await gateway.connect();
      final restoredRouting = await waitFor(gateway, ConnectionPhase.connected);
      expect(restoredRouting.addresses, connected.addresses);
      await File('$cache/integration-routing-restored').writeAsString('{}');
      await waitForMarker('routing-restored-verified');
      await gateway.disconnect();
      await waitFor(gateway, ConnectionPhase.disconnected);
      await gateway.saveProfile(testProfile.copyWith(acceptDns: true));
      await gateway.connect();
      final dns = await waitFor(gateway, ConnectionPhase.connected);
      expect(dns.dnsActive, isTrue);
      expect(dns.addresses, connected.addresses);
      expect(dns.dnsAddress, isNotEmpty);
      await File('$cache/integration-dns-ready')
          .writeAsString(jsonEncode({'dns': dns.dnsAddress}));
      await waitForMarker('dns-verified');
      if (const bool.fromEnvironment('XUNARA_TEST_PUBLIC_DNS')) {
        await gateway.disconnect();
        await waitFor(gateway, ConnectionPhase.disconnected);
        await gateway.saveProfile(
          testProfile.copyWith(
            acceptDns: true,
            dnsResolver: 'https://cloudflare-dns.com/dns-query',
            dnsBootstrap: ['1.1.1.1'],
            validateDnssec: true,
          ),
        );
        await gateway.connect();
        final encryptedDns = await waitFor(gateway, ConnectionPhase.connected);
        expect(encryptedDns.dnsActive, isTrue);
        expect(encryptedDns.dnssecActive, isTrue);
        expect(encryptedDns.addresses, connected.addresses);
        final savedDns = (await gateway.bootstrap()).profile;
        expect(savedDns.dnsResolver, 'https://cloudflare-dns.com/dns-query');
        expect(savedDns.validateDnssec, isTrue);
        await File('$cache/integration-doh-ready')
            .writeAsString(jsonEncode({'dns': encryptedDns.dnsAddress}));
        await waitForMarker('doh-verified');
        await gateway.disconnect();
        await waitFor(gateway, ConnectionPhase.disconnected);
        await gateway.saveProfile(
          testProfile.copyWith(
            acceptDns: true,
            dnsResolver: 'tls://one.one.one.one',
            dnsBootstrap: ['1.1.1.1'],
            validateDnssec: true,
          ),
        );
        await gateway.connect();
        final dot = await waitFor(gateway, ConnectionPhase.connected);
        expect(dot.dnssecActive, isTrue);
        expect(dot.addresses, connected.addresses);
        await File('$cache/integration-dot-ready')
            .writeAsString(jsonEncode({'dns': dot.dnsAddress}));
        await waitForMarker('dot-verified');
      }
      final exit = dns.devices.firstWhere(
        (device) => device.exitNode && device.name.startsWith('official-exit.'),
      );
      await gateway.disconnect();
      await waitFor(gateway, ConnectionPhase.disconnected);
      await gateway.saveProfile(
        testProfile.copyWith(
          exitNodeId: exit.stableId,
          exitNodeName: exit.name,
        ),
      );
      await gateway.connect();
      final usingExit = await waitFor(gateway, ConnectionPhase.connected);
      expect(usingExit.dnsActive, isTrue);
      expect(usingExit.exitNodeAvailable, isTrue);
      expect(usingExit.addresses, connected.addresses);
      await File('$cache/integration-exit-ready')
          .writeAsString(jsonEncode({'dns': usingExit.dnsAddress}));
      await waitForMarker('exit-verified');
      final stableExitGeneration = (await gateway.snapshot()).generation;
      await File('$cache/integration-exit-revocation-ready')
          .writeAsString('{}');
      await waitForMarker('exit-revocation-sent');
      final revokeDeadline = DateTime.now().add(const Duration(seconds: 30));
      while ((await gateway.snapshot()).exitNodeAvailable) {
        if (DateTime.now().isAfter(revokeDeadline)) fail('出口撤销没有传播到 Android');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect((await gateway.snapshot()).phase, ConnectionPhase.connected);
      final revokedExit = await gateway.snapshot();
      expect(
        revokedExit.generation,
        stableExitGeneration,
        reason: '仅撤销出口路由不能被误判为物理切网并重启 VPN',
      );
      final rawExit = await const MethodChannel('net.xunara.android/vpn')
          .invokeMethod<String>('snapshot');
      await File('$cache/integration-exit-revoked-status').writeAsString(
        jsonEncode((jsonDecode(rawExit!) as Map<String, dynamic>)['status']),
      );
      await File('$cache/integration-exit-revoked').writeAsString(
        jsonEncode({
          'dns': revokedExit.dnsAddress,
          'dns_active': revokedExit.dnsActive,
          'generation': revokedExit.generation,
        }),
      );
      await waitForMarker('exit-revoked-verified');
      expect((await gateway.snapshot()).generation, stableExitGeneration);
      if (const bool.fromEnvironment('XUNARA_TEST_PHONE_ROUTER')) {
        final lan = await PhoneLanFixture.start();
        addTearDown(lan.close);
        Future<void> marker(String name) =>
            File('$cache/integration-$name').writeAsString('{}');
        Future<VpnSnapshot> forwarding(
          bool active, {
          bool empty = false,
          bool nonempty = false,
        }) async {
          final deadline = DateTime.now().add(const Duration(seconds: 30));
          while (DateTime.now().isBefore(deadline)) {
            final snapshot = await gateway.snapshot();
            if (snapshot.phase == ConnectionPhase.connected &&
                snapshot.forwardingActive == active &&
                (!empty || snapshot.forwardingFlows == 0) &&
                (!nonempty || snapshot.forwardingFlows > 0)) {
              return snapshot;
            }
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          fail('手机转发审批 / 撤销状态没有按控制面更新');
        }

        await gateway.disconnect();
        await waitFor(gateway, ConnectionPhase.disconnected);
        await gateway.saveProfile(
          testProfile.copyWith(advertiseRoutes: ['10.0.2.0/24', 'fec0::/64']),
        );
        await gateway.connect();
        final offered = await waitFor(gateway, ConnectionPhase.connected);
        expect(offered.addresses, connected.addresses);
        expect(offered.forwardingActive, isFalse);
        await marker('phone-subnet-ready');
        await waitForMarker('phone-approval-sent');
        final approved = await forwarding(true);
        expect(approved.forwardingApproved, contains('10.0.2.0/24'));
        await marker('phone-subnet-active');
        await waitForMarker('phone-hold-sent');
        await forwarding(true, nonempty: true);
        await marker('phone-hold-visible');
        await waitForMarker('phone-policy-sent');
        await forwarding(true, empty: true);
        await marker('phone-policy-reset');
        await waitForMarker('phone-revocation-sent');
        await forwarding(false);
        await marker('phone-subnet-stopped');
        await waitForMarker('phone-subnet-verified');
        await gateway.disconnect();
        await waitFor(gateway, ConnectionPhase.disconnected);
        await gateway.saveProfile(testProfile.copyWith(advertiseExit: true));
        await gateway.connect();
        await waitFor(gateway, ConnectionPhase.connected);
        await marker('phone-exit-ready');
        await waitForMarker('phone-exit-approval-sent');
        final exit = await forwarding(true);
        expect(exit.forwardingApproved, containsAll(['0.0.0.0/0', '::/0']));
        expect(exit.dnsActive, isFalse);
        await marker('phone-exit-active');
        await waitForMarker('phone-exit-revocation-sent');
        await forwarding(false);
        await marker('phone-exit-stopped');
        await waitForMarker('phone-exit-verified');
      }
      await gateway.disconnect();
      await waitFor(gateway, ConnectionPhase.disconnected);
      final secondSecret = File('$cache/integration-second-auth-key');
      var secondKey = (await secondSecret.readAsString()).trim();
      await secondSecret.delete();
      final second = await gateway.saveProfile(
        testProfile.copyWith(
          id: '',
          hostname: 'android-second-account',
          label: '第二账号',
          acceptDns: true,
        ),
      );
      expect(second.id, isNot(testProfile.id));
      expect(second.server, testProfile.server);
      await gateway.connect(authKey: secondKey);
      secondKey = '';
      final secondConnected = await waitFor(gateway, ConnectionPhase.connected);
      expect(secondConnected.addresses, isNot(connected.addresses));
      expect(secondConnected.ownerLogin, 'second-account');
      expect(secondConnected.ownerLogin, isNot(connected.ownerLogin));
      await File('$cache/integration-second-ready')
          .writeAsString(jsonEncode({'addresses': secondConnected.addresses}));
      await waitForMarker('second-verified');
      await gateway.disconnect();
      await waitFor(gateway, ConnectionPhase.disconnected);
      await gateway.selectProfile(testProfile.id);
      await gateway.saveProfile(testProfile);
      await gateway.connect();
      final firstRestored = await waitFor(gateway, ConnectionPhase.connected);
      expect(firstRestored.addresses, connected.addresses);
      expect(firstRestored.ownerLogin, connected.ownerLogin);
      await File('$cache/integration-first-restored').writeAsString('{}');
      await waitForMarker('first-restored-verified');
      if (const bool.fromEnvironment('XUNARA_TEST_SHARING')) {
        await verifyDeviceSharing(
          gateway,
          testProfile,
          connected,
          (phase) => waitFor(gateway, phase),
          waitForMarker,
        );
      }
      if (const bool.fromEnvironment('XUNARA_TEST_RELEASE_SMOKE')) {
        releaseProfile = testProfile.copyWith(acceptDns: true);
      }
    } finally {
      authKey = '';
      await gateway.disconnect();
      await waitFor(gateway, ConnectionPhase.disconnected);
      if (releaseProfile != null) {
        // 只保留独立临时身份供同签名正式 APK 升级验收；外层脚本最终恢复原偏好。
        await gateway.saveProfile(releaseProfile);
        await File('$cache/integration-release-upgrade-ready')
            .writeAsString('{}');
      } else {
        await gateway.saveProfile(initial.profile);
        for (final profile in initial.profiles) {
          await gateway.saveProfile(profile);
        }
        await gateway.selectProfile(initial.profile.id);
        final previous = initial.profiles.map((profile) => profile.id).toSet()
          ..add(initial.profile.id);
        for (final profile in (await gateway.bootstrap()).profiles) {
          if (!previous.contains(profile.id)) {
            await gateway.forgetProfile(profile.id);
          }
        }
      }
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
    final raw = await const MethodChannel('net.xunara.android/vpn')
        .invokeMethod<String>('snapshot');
    final snapshot = jsonDecode(raw!) as Map<String, dynamic>;
    snapshot.remove('authorization_url');
    final temporary = File(
      '/data/user/0/net.xunara.android/cache/integration-runtime-snapshot.tmp',
    );
    await temporary.writeAsString(jsonEncode(snapshot));
    await temporary.rename(
      '/data/user/0/net.xunara.android/cache/integration-runtime-snapshot',
    );
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
