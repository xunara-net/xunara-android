import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xunara_android/app_controller.dart';
import 'package:xunara_android/models.dart';
import 'package:xunara_android/screens/devices_page.dart';
import 'package:xunara_android/screens/exit_node_page.dart';

import 'fake_gateway.dart';

NetworkDevice peer(String id, bool? online) => NetworkDevice(
  id: id,
  stableId: id,
  name: 'device-$id',
  addresses: const ['100.80.0.2/32'],
  path: 'relay',
  relayRegion: 900,
  online: online,
  exitNode: true,
);

void main() {
  testWidgets('小屏设备列表展示在线离线未知，刷新后自动更新', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = FakeGateway()
      ..current = VpnSnapshot(
        phase: ConnectionPhase.connected,
        devices: [
          peer('live', true),
          peer('offline', false),
          peer('unknown', null),
        ],
      );
    final controller = AppController(gateway);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: controller,
            builder: (_, _) => DevicesPage(controller: controller),
          ),
        ),
      ),
    );
    expect(find.text('在线'), findsOneWidget);
    expect(find.text('离线'), findsOneWidget);
    expect(find.text('状态未知'), findsOneWidget);
    gateway.current = VpnSnapshot(
      phase: ConnectionPhase.connected,
      devices: [peer('live', false)],
    );
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(find.text('在线'), findsNothing);
    expect(find.text('离线'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('已知离线出口禁选，已有选择不自动切换', (tester) async {
    final gateway = FakeGateway()
      ..current = VpnSnapshot(
        phase: ConnectionPhase.connected,
        exitNodeAvailable: true,
        exitNodeOnline: false,
        devices: [peer('offline', false)],
      );
    gateway.profile = gateway.profile.copyWith(
      exitNodeId: 'offline',
      exitNodeName: '旧出口',
    );
    final controller = AppController(gateway);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(home: ExitNodePage(controller: controller)),
    );
    expect(find.textContaining('所选出口已离线'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('exit-offline')));
    final tile = tester.widget<ListTile>(find.byKey(const Key('exit-offline')));
    expect(tile.onTap, isNull);
    expect(tile.enabled, isFalse);
    expect(controller.profile!.exitNodeId, 'offline');
    expect(gateway.profileChanges, 0);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('确认期间出口离线时不保存旧状态', (tester) async {
    final gateway = FakeGateway()
      ..current = VpnSnapshot(
        phase: ConnectionPhase.connected,
        generation: 7,
        devices: [peer('live', true)],
      );
    final controller = AppController(gateway);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(home: ExitNodePage(controller: controller)),
    );
    await tester.ensureVisible(find.byKey(const Key('exit-live')));
    await tester.tap(find.byKey(const Key('exit-live')));
    await tester.pumpAndSettle();
    gateway.current = VpnSnapshot(
      phase: ConnectionPhase.connected,
      generation: 7,
      devices: [peer('live', false)],
    );
    await controller.refresh();
    await tester.tap(find.text('使用出口'));
    await tester.pumpAndSettle();
    expect(find.text('出口状态已变化，请刷新后重新选择'), findsOneWidget);
    expect(gateway.profileChanges, 0);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
