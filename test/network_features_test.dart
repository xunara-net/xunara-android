import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xunara_android/app_controller.dart';
import 'package:xunara_android/main.dart';
import 'package:xunara_android/models.dart';
import 'package:xunara_android/screens/device_detail_sheet.dart';
import 'package:xunara_android/screens/dns_info_page.dart';
import 'package:xunara_android/screens/profile_editor.dart';

import 'fake_gateway.dart';

const connected = VpnSnapshot(
  phase: ConnectionPhase.connected,
  generation: 7,
  selfName: 'phone.example.test.',
  magicDnsEnabled: true,
  searchDomains: ['example.test'],
  devices: [
    NetworkDevice(
      id: '2',
      name: 'home-nas.example.test.',
      addresses: ['100.80.0.2/32'],
      path: 'relay',
      relayRegion: 900,
      relayName: '测试中继',
      os: 'linux',
      routes: ['10.90.0.0/24'],
    ),
  ],
);

void main() {
  testWidgets('详情检测显示真实回包的路径和往返时间', (tester) async {
    final gateway = FakeGateway()..current = connected;
    final controller = AppController(gateway);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeviceDetailSheet(
            controller: controller,
            peerId: '2',
            generation: 7,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('ping-device-button')));
    await tester.pumpAndSettle();
    expect(gateway.pingCalls, 1);
    expect(find.textContaining('12.5 ms'), findsOneWidget);
    expect(find.textContaining('DERP 中继 #900'), findsOneWidget);
    expect(find.text('Linux'), findsOneWidget);
    expect(find.text('10.90.0.0/24'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('切换连接后丢弃旧检测结果，设备撤销不保留操作入口', (tester) async {
    final pending = Completer<PingResult>();
    final gateway = FakeGateway()
      ..current = connected
      ..pingResponse = pending.future;
    final controller = AppController(gateway);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeviceDetailSheet(
            controller: controller,
            peerId: '2',
            generation: 7,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('ping-device-button')));
    await tester.pump();
    gateway.current = const VpnSnapshot(
      phase: ConnectionPhase.reconnecting,
      generation: 8,
    );
    await controller.refresh();
    pending.complete(
      const PingResult(address: '100.80.0.2', rttMs: 1, path: 'direct'),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ping-result')), findsNothing);
    expect(find.byKey(const Key('device-unavailable')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('ping-device-button')))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('DNS 页明确区分服务器 MagicDNS 与手机系统解析器', (tester) async {
    final controller = AppController(FakeGateway()..current = connected);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(home: DnsInfoPage(controller: controller)),
    );
    expect(find.text('服务器已启用'), findsOneWidget);
    expect(find.text('手机 DNS 保持不变'), findsOneWidget);
    expect(find.text('phone.example.test'), findsOneWidget);
    expect(find.text('example.test'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('自动重连开关可以保存，且不携带接入密钥', (tester) async {
    final gateway = FakeGateway();
    final controller = AppController(gateway);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(home: ProfileEditor(controller: controller)),
    );
    await tester.ensureVisible(find.byKey(const Key('auto-reconnect-switch')));
    await tester.tap(find.byKey(const Key('auto-reconnect-switch')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存设置'));
    await tester.tap(find.text('保存设置'));
    await tester.pumpAndSettle();
    expect(gateway.profile.autoReconnect, isFalse);
    expect(gateway.profile.toJson().containsKey('auth_key'), isFalse);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('连接页重连时保持可取消，不伪报在线设备', (tester) async {
    final gateway = FakeGateway()
      ..current = const VpnSnapshot(
        phase: ConnectionPhase.reconnecting,
        message: '网络已断开，等待 Wi-Fi 或移动网络恢复',
      );
    await tester.pumpWidget(XunaraApp(controller: AppController(gateway)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('正在重连'), findsOneWidget);
    expect(find.text('断开连接'), findsOneWidget);
    expect(find.text('已安全连接'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
