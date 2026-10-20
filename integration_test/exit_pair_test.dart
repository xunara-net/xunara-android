import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xunara_android/models.dart';
import 'package:xunara_android/vpn_gateway.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('两台安卓通过真实隧道互用出口', (tester) async {
    const cache = '/data/user/0/net.xunara.android/cache';
    const channel = MethodChannel('net.xunara.android/vpn');
    final settingsFile = File('$cache/exit-pair-settings');
    final settings = jsonDecode(await settingsFile.readAsString()) as Map;
    await settingsFile.delete();
    final isExit = settings['role'] == 'exit';
    final profileId = settings['profile_id'] as String;
    expect(
      profileId,
      matches(
        r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
      ),
    );
    final secretFile = File('$cache/exit-pair-auth-key');
    var authKey = (await secretFile.readAsString()).trim();
    await secretFile.delete();
    final gateway = AndroidVpnGateway();
    final original = await gateway.bootstrap();
    expect(
      original.profiles.any((profile) => profile.id == profileId),
      isFalse,
    );
    await gateway.disconnect();

    Future<VpnSnapshot> until(bool Function(VpnSnapshot) condition) async {
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while (DateTime.now().isBefore(deadline)) {
        final state = await gateway.snapshot();
        expect(state.phase, isNot(ConnectionPhase.error));
        if (condition(state)) return state;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      fail('双安卓测试阶段超时');
    }

    Future<void> record() async {
      final raw = jsonDecode(
        (await channel.invokeMethod<String>('snapshot'))!,
      ) as Map<String, dynamic>;
      raw.remove('authorization_url');
      final temporary = File('$cache/exit-pair-status.tmp');
      await temporary.writeAsString(jsonEncode(raw));
      await temporary.rename('$cache/exit-pair-status');
    }

    try {
      await until((state) => state.phase == ConnectionPhase.disconnected);
      var profile = await gateway.saveProfile(
        ClientProfile(
          id: profileId,
          server: 'http://127.0.0.1:18080/',
          hostname: isExit ? 'android-pair-exit' : 'android-pair-client',
          acceptRoutes: true,
          acceptDns: !isExit,
          advertiseExit: isExit,
        ),
      );
      await gateway.connect(authKey: authKey);
      authKey = '';
      await until((state) => state.phase == ConnectionPhase.connected);
      await record();
      await File('$cache/exit-pair-registered').writeAsString('{}');
      if (isExit) {
        await until((state) => state.forwardingActive);
      } else {
        final available = await until(
          (state) => state.devices.any(
            (device) =>
                device.name == 'android-pair-exit.core.test.' &&
                device.exitNode,
          ),
        );
        final exit = available.devices.firstWhere(
          (device) => device.name == 'android-pair-exit.core.test.',
        );
        await gateway.disconnect();
        await until((state) => state.phase == ConnectionPhase.disconnected);
        profile = await gateway.saveProfile(
          profile.copyWith(exitNodeId: exit.stableId, exitNodeName: exit.name),
        );
        await gateway.connect();
        final selected = await until(
          (state) =>
              state.phase == ConnectionPhase.connected &&
              state.exitNodeAvailable &&
              state.dnsActive,
        );
        expect(selected.dnsAddress, isNotEmpty);
      }
      await record();
      await File('$cache/exit-pair-ready').writeAsString('{}');
      final deadline = DateTime.now().add(const Duration(minutes: 5));
      // 业务请求由 shell UID 发起，不能用已从 VPN 排除的 Flutter 请求冒充隧道流量。
      while (!await File('$cache/exit-pair-finish').exists()) {
        if (DateTime.now().isAfter(deadline)) fail('双安卓外部数据面验收超时');
        await record();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    } finally {
      authKey = '';
      await gateway.disconnect();
    }
  });
}
