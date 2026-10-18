import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xunara_android/app_controller.dart';
import 'package:xunara_android/models.dart';
import 'package:xunara_android/screens/forwarding_page.dart';

import 'fake_gateway.dart';

void main() {
  test('广播字段默认关闭，不把配置当成已获批转发', () {
    final profile = ClientProfile.fromJson({'server': 'https://control.test/'});
    expect(profile.advertiseRoutes, isEmpty);
    expect(profile.advertiseExit, isFalse);
    final next = profile.copyWith(
      advertiseRoutes: ['192.168.1.0/24'],
      advertiseExit: true,
    );
    expect(
      ClientProfile.fromJson(next.toJson()).advertiseRoutes,
      next.advertiseRoutes,
    );
    expect(
      VpnSnapshot.fromJson({
        'phase': 'connected',
        'status': {
          'forwarding': {
            'active': true,
            'approved': ['192.168.1.0/24'],
            'flows': 2,
          },
        },
      }).forwardingFlows,
      2,
    );
    expect(const VpnSnapshot().forwardingActive, isFalse);
    for (final route in [
      '192.168.1.1/24',
      '127.0.0.0/8',
      '::/0',
      '0.0.0.0/0',
      'example.test/24',
      'fe80::/64',
      '::ffff:192.0.2.0/120',
    ]) {
      expect(validForwardingSubnet(route), isFalse, reason: route);
    }
    expect(validForwardingSubnet('192.168.1.0/24'), isTrue);
    expect(validForwardingSubnet('2001:db8::/32'), isTrue);
  });

  testWidgets('小屏可保存转发配置，并保留账号身份和 DNS', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = FakeGateway();
    gateway.profile = gateway.profile.copyWith(dnsResolver: '1.1.1.1');
    final controller = AppController(gateway);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(home: ForwardingPage(controller: controller)),
    );
    await tester.enterText(
      find.byType(TextFormField),
      '192.168.1.0/24\n10.0.0.0/8',
    );
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存并应用'));
    await tester.pumpAndSettle();
    expect(gateway.profile.advertiseRoutes, ['192.168.1.0/24', '10.0.0.0/8']);
    expect(gateway.profile.advertiseExit, isTrue);
    expect(gateway.profile.dnsResolver, '1.1.1.1');
    expect(gateway.profile.id, 'home');
    expect(gateway.receivedKey, isEmpty);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('切换账号后旧网络共享页面不能覆盖新账号', (tester) async {
    final gateway = FakeGateway();
    gateway.savedProfiles['home'] = gateway.profile;
    gateway.savedProfiles['other'] = gateway.profile.copyWith(
      id: 'other',
      hostname: 'other-phone',
    );
    final controller = AppController(gateway);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(home: ForwardingPage(controller: controller)),
    );
    await tester.enterText(find.byType(TextFormField), '192.168.1.0/24');
    await controller.switchAccount('other');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存并应用'))
          .onPressed,
      isNull,
    );
    expect(gateway.profile.advertiseRoutes, isEmpty);
    expect(gateway.profile.advertiseExit, isFalse);
    expect(find.textContaining('当前账号已变化'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
