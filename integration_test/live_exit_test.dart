import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xunara_android/app_controller.dart';
import 'package:xunara_android/models.dart';
import 'package:xunara_android/vpn_gateway.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('现网出口诊断采集，不以控制面在线冒充业务连通', (tester) async {
    const cache = '/data/user/0/net.xunara.android/cache';
    const channel = MethodChannel('net.xunara.android/vpn');
    final settingsFile = File('$cache/live-exit-settings');
    final settings = jsonDecode(await settingsFile.readAsString()) as Map;
    await settingsFile.delete();
    final server = settings['server'] as String;
    final hostname = settings['hostname'] as String;
    final profileId = settings['profile_id'] as String;
    final exitId = settings['exit_id'] as String;
    final selectAfterConnect = settings['select_after_connect'] == true;
    final reuseProfile = settings['reuse_profile'] == true;
    final holdMinutes = settings['hold_minutes'] as int? ?? 4;
    expect(holdMinutes, inInclusiveRange(1, 20));
    expect(ClientProfile.validateServer(server), isNull);
    expect(Uri.parse(server).scheme, 'https');
    expect(hostname, startsWith('diag-'));
    expect(
      profileId,
      matches(
        r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
      ),
    );
    expect(exitId, isNotEmpty);

    final secretFile = File('$cache/live-exit-auth-key');
    var authKey = '';
    if (await secretFile.exists()) {
      authKey = (await secretFile.readAsString()).trim();
      await secretFile.delete();
    }
    expect(reuseProfile || authKey.isNotEmpty, isTrue);
    final gateway = AndroidVpnGateway();
    AppController? controller;
    final original = await gateway.bootstrap();
    expect(
      original.profiles.any((profile) => profile.id == profileId),
      reuseProfile,
    );
    if (reuseProfile) {
      final previous = original.profiles.singleWhere(
        (profile) => profile.id == profileId,
      );
      expect(previous.hostname, hostname);
      expect(previous.server, server);
    }

    Future<VpnSnapshot> until(bool Function(VpnSnapshot) condition) async {
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while (DateTime.now().isBefore(deadline)) {
        final state = await gateway.snapshot();
        expect(state.phase, isNot(ConnectionPhase.error));
        if (condition(state)) return state;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      fail('现网诊断连接阶段超时');
    }

    Future<void> record() async {
      final raw = jsonDecode(
        (await channel.invokeMethod<String>('snapshot'))!,
      ) as Map<String, dynamic>;
      raw.remove('authorization_url');
      final temporary = File('$cache/live-exit-status.tmp');
      await temporary.writeAsString(jsonEncode(raw));
      await temporary.rename('$cache/live-exit-status');
    }

    try {
      await gateway.disconnect();
      await until((state) => state.phase == ConnectionPhase.disconnected);
      // 独立 UUID 创建临时机器身份，不借用原账号的身份目录或人类会话。
      await gateway.saveProfile(
        ClientProfile(
          id: profileId,
          server: server,
          hostname: hostname,
          acceptRoutes: true,
          acceptDns: !selectAfterConnect,
          exitNodeId: selectAfterConnect ? '' : exitId,
          autoReconnect: false,
        ),
      );
      if (selectAfterConnect) {
        // 走真实页面使用的控制器：先普通连接，再停止旧 VPN、保存出口并重新连接。
        controller = AppController(gateway);
        await controller.initialize();
        await controller.connect(authKey: authKey);
        authKey = '';
        await until((state) => state.phase == ConnectionPhase.connected);
        await controller.refresh();
        expect(
          await controller.applyNetworkSettings(
            controller.profile!.copyWith(exitNodeId: exitId),
          ),
          isTrue,
        );
      } else {
        await gateway.connect(authKey: authKey);
      }
      authKey = '';
      final active = await until(
        (state) =>
            state.phase == ConnectionPhase.connected &&
            state.exitNodeAvailable &&
            state.dnsActive,
      );
      expect(active.devices.any((device) => device.stableId == exitId), isTrue);
      await record();
      await File('$cache/live-exit-ready').writeAsString('{}');
      final exit = active.devices.singleWhere(
        (device) => device.stableId == exitId,
      );
      final results = <String, Object>{};
      try {
        final ping = await gateway.ping(exit.id, generation: active.generation);
        results['exit_ping'] = true;
        results['exit_ping_path'] = ping.path;
        results['exit_ping_rtt_ms'] = ping.rttMs;
      } on PlatformException catch (error) {
        results['exit_ping'] = false;
        results['exit_ping_error'] = error.code;
      }
      await File('$cache/live-exit-ping').writeAsString(jsonEncode(results));
      final deadline = DateTime.now().add(Duration(minutes: holdMinutes));
      // 公网请求必须由 shell UID 验证；App 自身的受保护连接不算出口测试通过。
      while (!await File('$cache/live-exit-finish').exists()) {
        if (DateTime.now().isAfter(deadline)) fail('现网诊断采集超时');
        await record();
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    } finally {
      authKey = '';
      await gateway.disconnect();
      controller?.dispose();
    }
  });
}
