import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xunara_android/app_controller.dart';
import 'package:xunara_android/main.dart';
import 'package:xunara_android/models.dart';

import 'fake_gateway.dart';

void main() {
  testWidgets('密钥弹层遮蔽输入，提交后清理控件且不加入配置', (tester) async {
    final gateway = FakeGateway();
    await tester.pumpWidget(XunaraApp(controller: AppController(gateway)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('auth-key-option')));
    await tester.pumpAndSettle();
    const testKey = 'example-only-not-a-real-auth-key';
    final input = find.byKey(const Key('auth-key-field'));
    expect(tester.widget<TextField>(input).obscureText, isTrue);
    await tester.enterText(input, testKey);
    await tester.tap(find.text('安全加入网络'));
    await tester.pumpAndSettle();
    expect(gateway.receivedKey, testKey);
    expect(gateway.profile.toJson().containsKey('auth_key'), isFalse);
    expect(find.byKey(const Key('auth-key-field')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('小屏首屏可连接，底栏直接切页，没有网络标识输入', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = FakeGateway();
    final controller = AppController(gateway);
    await tester.pumpWidget(XunaraApp(controller: controller));
    await tester.pumpAndSettle();
    final button = find.byKey(const Key('connect-button'));
    expect(tester.getBottomRight(button).dy, lessThan(550));
    expect(find.text('网络标识'), findsNothing);
    await tester.tap(find.text('设备'));
    await tester.pumpAndSettle();
    expect(find.text('连接后查看你的设备'), findsOneWidget);
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    expect(find.text('打开用户中心'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('浏览器登录不等于已联网，授权按钮只打开受控地址', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = FakeGateway();
    await tester.pumpWidget(XunaraApp(controller: AppController(gateway)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('connect-button')));
    await tester.pumpAndSettle();
    expect(find.text('等待设备授权'), findsOneWidget);
    expect(find.text('已安全连接'), findsNothing);
    expect(
      tester.getBottomRight(find.byKey(const Key('authorize-button'))).dy,
      lessThan(550),
    );
    await tester.tap(find.byKey(const Key('authorize-button')));
    await tester.pumpAndSettle();
    expect(gateway.browserCalls, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('拒绝 VPN 权限后允许重试，不伪造在线状态', (tester) async {
    final gateway = FakeGateway()..denyPermission = true;
    await tester.pumpWidget(XunaraApp(controller: AppController(gateway)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('connect-button')));
    await tester.pumpAndSettle();
    expect(find.text('未开启 VPN 权限，尚未连接网络'), findsOneWidget);
    expect(find.text('已安全连接'), findsNothing);
    expect(gateway.connectCalls, 1);
    await tester.tap(find.byKey(const Key('connect-button')));
    await tester.pumpAndSettle();
    expect(gateway.connectCalls, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('设备搜索与详情直接可达，允许大字体', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final gateway = FakeGateway()
      ..current = const VpnSnapshot(
        phase: ConnectionPhase.connected,
        addresses: ['100.80.0.1/32'],
        devices: [
          NetworkDevice(
            id: '2',
            name: 'home-nas',
            addresses: ['100.80.0.2/32'],
            path: 'relay',
            relayRegion: 900,
          ),
        ],
      );
    await tester.pumpWidget(XunaraApp(controller: AppController(gateway)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设备'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('home-nas'));
    await tester.pumpAndSettle();
    expect(find.text('中继区域'), findsOneWidget);
    expect(find.text('#900'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
