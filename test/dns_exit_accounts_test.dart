import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xunara_android/app_controller.dart';
import 'package:xunara_android/models.dart';
import 'package:xunara_android/screens/dns_info_page.dart';
import 'package:xunara_android/screens/exit_node_page.dart';

import 'fake_gateway.dart';

class DelayedSnapshotGateway extends FakeGateway {
  final delayed = Completer<VpnSnapshot>();
  @override
  Future<VpnSnapshot> snapshot() => delayed.future;
}

void main() {
  test('旧账号迟到的状态不覆盖新账号的设备归属或连接状态', () async {
    final gateway = DelayedSnapshotGateway();
    final controller = AppController(gateway);
    await controller.initialize();
    await controller.save(
      controller.profile!.copyWith(id: 'second', label: '第二账号'),
    );
    final refreshing = controller.refresh();
    await controller.switchAccount('home');
    gateway.delayed.complete(
      const VpnSnapshot(
        phase: ConnectionPhase.connected,
        ownerLogin: 'old-account',
      ),
    );
    await refreshing;
    expect(controller.profile!.id, 'home');
    expect(controller.snapshot.phase, ConnectionPhase.disconnected);
    expect(controller.snapshot.ownerLogin, isEmpty);
    controller.dispose();
  });
  test('同控制器可保存多个账号，切换不转移身份和网络偏好', () async {
    final gateway = FakeGateway();
    final controller = AppController(gateway);
    await controller.initialize();
    final first = controller.profile!;
    expect(
      await controller.save(
        first.copyWith(id: '', label: '第二账号', acceptDns: true),
      ),
      isTrue,
    );
    final second = controller.profile!;
    expect(second.id, isNot(first.id));
    expect(controller.profiles, hasLength(2));
    expect(
      controller.profiles.map((profile) => profile.server).toSet(),
      hasLength(1),
    );
    expect(await controller.switchAccount(first.id), isTrue);
    expect(controller.profile!.acceptDns, isFalse);
    expect(await controller.applyNetworkSettings(second), isFalse);
    expect(controller.profile!.id, first.id);
    expect(gateway.connectCalls, 0);
    controller.dispose();
  });

  test('已连接时 DNS 设置先停止旧连接，保存后不用密钥重连', () async {
    final gateway = FakeGateway()
      ..current = const VpnSnapshot(phase: ConnectionPhase.connected);
    final controller = AppController(gateway);
    await controller.initialize();
    expect(
      await controller.applyNetworkSettings(
        controller.profile!.copyWith(acceptDns: true),
      ),
      isTrue,
    );
    expect(controller.profile!.acceptDns, isTrue);
    expect(gateway.connectCalls, 1);
    expect(gateway.receivedKey, isEmpty);
    expect(controller.snapshot.phase, ConnectionPhase.authorizing);
    controller.dispose();
  });

  testWidgets('DNS 开关与真实生效状态分开，出口强制 DNS 不允许误关闭', (tester) async {
    final gateway = FakeGateway();
    gateway.profile = gateway.profile.copyWith(
      exitNodeId: 'exit-one',
      exitNodeName: '办公室出口',
    );
    final controller = AppController(gateway);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(home: DnsInfoPage(controller: controller)),
    );
    final toggle = tester.widget<SwitchListTile>(
      find.byKey(const Key('magic-dns-switch')),
    );
    expect(toggle.value, isTrue);
    expect(toggle.onChanged, isNull);
    expect(find.text('VPN DNS 尚未生效'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('出口只显示已批准节点，失效可明确关闭，不假装联网', (tester) async {
    final gateway = FakeGateway();
    gateway.profile = gateway.profile.copyWith(
      exitNodeId: 'missing-exit',
      exitNodeName: '原出口',
    );
    gateway.current = const VpnSnapshot(
      phase: ConnectionPhase.connected,
      devices: [
        NetworkDevice(
          id: '1',
          stableId: 'exit-approved',
          name: '已批准出口',
          addresses: ['100.80.0.2/32'],
          path: 'relay',
          relayRegion: 900,
          exitNode: true,
        ),
        NetworkDevice(
          id: '2',
          stableId: 'not-approved',
          name: '未批准设备',
          addresses: ['100.80.0.3/32'],
          path: 'relay',
          relayRegion: 900,
        ),
      ],
    );
    final controller = AppController(gateway);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(home: ExitNodePage(controller: controller)),
    );
    expect(find.textContaining('所选出口当前不可用'), findsOneWidget);
    expect(find.text('已批准出口'), findsOneWidget);
    expect(find.text('未批准设备'), findsNothing);
    await tester.tap(find.byKey(const Key('exit-none')));
    await tester.pumpAndSettle();
    expect(controller.profile!.exitNodeId, isEmpty);
    expect(gateway.connectCalls, 1);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
