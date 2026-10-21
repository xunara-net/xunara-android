import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xunara_android/app_controller.dart';
import 'package:xunara_android/models.dart';
import 'package:xunara_android/screens/dns_info_page.dart';
import 'package:xunara_android/system_diagnostics.dart';

import 'fake_gateway.dart';

void main() {
  test('DNS 配置保留上游与分流清单，不把监听地址混入解析器', () {
    final snapshot = VpnSnapshot.fromJson({
      'status': {
        'dns': {
          'address': '100.100.100.100',
          'resolvers': ['1.1.1.1', '114.114.114.114'],
          'routes': {
            'office.example': ['10.0.0.53'],
            'local.example': [],
          },
        },
      },
    });
    expect(snapshot.dnsResolvers, ['1.1.1.1', '114.114.114.114']);
    expect(snapshot.dnsRoutes['office.example'], ['10.0.0.53']);
    expect(snapshot.dnsRoutes['local.example'], isEmpty);
    expect(() => snapshot.dnsResolvers.add('8.8.8.8'), throwsUnsupportedError);
    expect(
      () => snapshot.dnsRoutes['office.example']!.clear(),
      throwsUnsupportedError,
    );
    expect(VpnSnapshot.fromJson({}).dnsResolvers, isEmpty);
  });

  testWidgets('DNS 页展示解析器与分流，不展示内部 DNS 监听地址', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = FakeGateway()
      ..current = VpnSnapshot.fromJson({
        'phase': 'connected',
        'status': {
          'dns': {
            'active': true,
            'address': '100.100.100.100',
            'enabled': true,
            'resolvers': ['1.1.1.1', '114.114.114.114'],
            'domains': ['mesh.example'],
            'routes': {
              'office.example': ['10.0.0.53'],
            },
          },
        },
      });
    final controller = AppController(gateway);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(home: DnsInfoPage(controller: controller)),
    );
    expect(find.text('正在使用玄序 DNS'), findsOneWidget);
    expect(find.text('100.100.100.100'), findsNothing);
    await tester.scrollUntilVisible(find.text('1.1.1.1'), 180);
    expect(find.text('1.1.1.1'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('10.0.0.53'), 180);
    expect(find.text('分流域：office.example'), findsOneWidget);
    expect(find.text('10.0.0.53'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  test('DNS 设置增量序列化，不复用其他账号配置', () {
    const profile = ClientProfile(
      server: 'https://control.test/',
      hostname: 'phone',
      id: 'first',
      dnsResolver: 'tls://one.one.one.one',
      dnsBootstrap: ['1.1.1.1'],
      validateDnssec: true,
    );
    final restored = ClientProfile.fromJson(profile.toJson());
    expect(restored.dnsResolver, profile.dnsResolver);
    expect(restored.dnsBootstrap, profile.dnsBootstrap);
    expect(restored.copyWith(hostname: 'renamed').validateDnssec, isTrue);
    expect(
      const ClientProfile(
        server: 'https://control.test/',
        hostname: 'another',
      ).dnsResolver,
      isEmpty,
    );
    expect(
      ClientProfile.fromJson({'server': 'https://control.test/'})
          .validateDnssec,
      isFalse,
    );
  });

  test('DNSSEC 是否生效只认内核状态，不认配置保存结果', () {
    expect(
      VpnSnapshot.fromJson({
        'phase': 'connected',
        'status': {
          'dns': {'active': true, 'dnssec_validate': true},
        },
      }).dnssecActive,
      isTrue,
    );
    expect(
      VpnSnapshot.fromJson({
        'phase': 'connected',
        'status': {
          'dns': {'active': true},
        },
      }).dnssecActive,
      isFalse,
    );
  });

  test('私人 DNS 缺失状态不伪装为关闭，不输出系统解析器域名', () {
    final diagnostics = SystemDiagnostics.fromJson({
      'android_sdk': 36,
      'android_version': '16',
      'app_version': '0.4.0',
      'core_version': '0.1.0',
      'vpn_permission': true,
      'notifications_enabled': true,
      'battery_unrestricted': false,
      'background_restricted': false,
    });
    expect(diagnostics.privateDnsActive, isNull);
    expect(diagnostics.privateDnsDescription, contains('未提供'));
  });

  testWidgets('加密 DNS 独立配置页保存参数且不保存接入密钥', (tester) async {
    final gateway = FakeGateway();
    final controller = AppController(gateway);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(home: DnsInfoPage(controller: controller)),
    );
    await tester.tap(find.byTooltip('解析器与 DNSSEC'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cloudflare DoH'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('本机验证 DNSSEC'));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存并应用'));
    await tester.pumpAndSettle();
    expect(gateway.profile.id, 'home');
    expect(gateway.profile.dnsResolver, 'https://cloudflare-dns.com/dns-query');
    expect(gateway.profile.dnsBootstrap, ['1.1.1.1', '1.0.0.1']);
    expect(gateway.profile.validateDnssec, isTrue);
    expect(gateway.receivedKey, isEmpty);
    expect(gateway.connectCalls, 0);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('自定义 DNS 拒绝 URL 凭据，不提交无效配置', (tester) async {
    final gateway = FakeGateway();
    final controller = AppController(gateway);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(home: DnsInfoPage(controller: controller)),
    );
    await tester.tap(find.byTooltip('解析器与 DNSSEC'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'https://user:placeholder@resolver.test/dns-query',
    );
    await tester.tap(find.text('保存并应用'));
    await tester.pumpAndSettle();
    expect(gateway.profileChanges, 0);
    expect(find.textContaining('不含凭据'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('切换账号后旧 DNS 编辑页不能覆盖新账号', (tester) async {
    final gateway = FakeGateway();
    gateway.savedProfiles['home'] = gateway.profile;
    gateway.savedProfiles['other'] = gateway.profile.copyWith(
      id: 'other',
      hostname: 'other-phone',
    );
    final controller = AppController(gateway);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(home: DnsInfoPage(controller: controller)),
    );
    await tester.tap(find.byTooltip('解析器与 DNSSEC'));
    await tester.pumpAndSettle();
    await controller.switchAccount('other');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存并应用'))
          .onPressed,
      isNull,
    );
    expect(gateway.profile.dnsResolver, isEmpty);
    expect(find.textContaining('当前账号已变化'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
