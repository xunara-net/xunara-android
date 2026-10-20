import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xunara_android/app_controller.dart';
import 'package:xunara_android/models.dart';
import 'package:xunara_android/screens/app_routing_page.dart';
import 'package:xunara_android/screens/profile_editor.dart';
import 'package:xunara_android/screens/profiles_page.dart';
import 'package:xunara_android/screens/system_diagnostics_page.dart';
import 'package:xunara_android/system_diagnostics.dart';

import 'fake_gateway.dart';

Future<void> openPage(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => page)),
            child: const Text('测试入口'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('测试入口'));
  await tester.pumpAndSettle();
}

void main() {
  test('旧配置默认全部应用，未知分流模式拒绝读取', () {
    final legacy = ClientProfile.fromJson({
      'server': 'https://home.example/',
      'hostname': 'phone',
    });
    expect(legacy.appRouting, AppRoutingMode.all);
    expect(legacy.applications, isEmpty);
    final selected = legacy.copyWith(
      appRouting: AppRoutingMode.only,
      applications: ['com.example.nas'],
    );
    expect(ClientProfile.fromJson(selected.toJson()).applications, [
      'com.example.nas',
    ]);
    expect(
      selected.copyWith(hostname: 'renamed').appRouting,
      AppRoutingMode.only,
    );
    expect(selected.toJson().containsKey('auth_key'), isFalse);
    expect(
      () => ClientProfile.fromJson({
        ...legacy.toJson(),
        'app_routing': 'unknown',
      }),
      throwsFormatException,
    );
  });

  test('切换保留各自设置，不自动连接或复制接入密钥', () async {
    final gateway = FakeGateway();
    final controller = AppController(gateway);
    await controller.initialize();
    final home = controller.profile!;
    final office = home.copyWith(
      id: 'office',
      server: 'https://office.example/',
      hostname: 'work',
      acceptRoutes: false,
      appRouting: AppRoutingMode.only,
      applications: ['com.example.nas'],
    );
    expect(await controller.save(office), isTrue);
    expect(controller.profiles, hasLength(2));
    expect(await controller.selectProfile(home.id), isTrue);
    expect(controller.profile!.server, home.server);
    expect(controller.profile!.appRouting, AppRoutingMode.all);
    expect(await controller.selectProfile(office.id), isTrue);
    expect(controller.profile!.applications, office.applications);
    expect(controller.profile!.acceptRoutes, isFalse);
    expect(gateway.connectCalls, 0);
    expect(await controller.forgetProfile(home.id), isTrue);
    expect(controller.profiles, hasLength(1));
    expect(gateway.receivedKey, isEmpty);
    controller.dispose();
  });

  test('连接中不允许保存切换或移除服务器', () async {
    final gateway = FakeGateway()
      ..current = const VpnSnapshot(phase: ConnectionPhase.connected);
    final controller = AppController(gateway);
    await controller.initialize();
    expect(
      await controller.save(controller.profile!.copyWith(hostname: 'other')),
      isFalse,
    );
    expect(await controller.selectProfile('https://office.example/'), isFalse);
    expect(await controller.forgetProfile('https://office.example/'), isFalse);
    expect(gateway.profileChanges, 0);
    expect(controller.error, contains('先断开连接'));
    controller.dispose();
  });

  test('原生已保存但读回失败时拒绝用旧标签继续连接', () async {
    final gateway = FakeGateway();
    final controller = AppController(gateway);
    await controller.initialize();
    gateway.bootstrapUnavailable = true;
    expect(
      await controller.save(
        controller.profile!.copyWith(server: 'https://office.example/'),
      ),
      isFalse,
    );
    expect(gateway.profile.server, 'https://office.example/');
    expect(controller.profile, isNull);
    expect(
      await controller.save(gateway.profile.copyWith(hostname: 'retry')),
      isFalse,
    );
    expect(gateway.profileChanges, 1);
    await controller.connect();
    expect(gateway.connectCalls, 0);
    gateway.bootstrapUnavailable = false;
    await controller.initialize();
    expect(controller.profile!.server, 'https://office.example/');
    expect(gateway.connectCalls, 0);
    controller.dispose();
  });

  testWidgets('仅所选拒绝空清单，选择应用后保留网络设置', (tester) async {
    final gateway = FakeGateway()
      ..profile = const ClientProfile(
        server: 'https://home.example/',
        hostname: 'phone',
        acceptRoutes: false,
        autoReconnect: false,
      );
    final controller = AppController(gateway);
    await controller.initialize();
    await openPage(tester, AppRoutingPage(controller: controller));
    await tester.tap(find.byKey(const Key('routing-only')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-app-routing')));
    await tester.pumpAndSettle();
    expect(find.text('请至少选择一个已安装的应用'), findsOneWidget);
    expect(gateway.profileChanges, 0);
    final application = find.byKey(const Key('application-com.example.nas'));
    await tester.ensureVisible(application);
    await tester.pumpAndSettle();
    await tester.tap(application);
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(application).value, isTrue);
    await tester.tap(find.byKey(const Key('save-app-routing')));
    await tester.pumpAndSettle();
    expect(gateway.profile.appRouting, AppRoutingMode.only);
    expect(gateway.profile.applications, ['com.example.nas']);
    expect(gateway.profile.acceptRoutes, isFalse);
    expect(gateway.profile.autoReconnect, isFalse);
    expect(gateway.connectCalls, 0);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('修改设备名不会清空已保存的应用分流', (tester) async {
    final gateway = FakeGateway();
    gateway.profile = gateway.profile.copyWith(
      appRouting: AppRoutingMode.only,
      applications: ['com.example.nas'],
    );
    final controller = AppController(gateway);
    await controller.initialize();
    await openPage(tester, ProfileEditor(controller: controller));
    await tester.enterText(
      find.byKey(const Key('hostname-field')),
      'renamed-phone',
    );
    await tester.tap(find.text('保存设置'));
    await tester.pumpAndSettle();
    expect(gateway.profile.hostname, 'renamed-phone');
    expect(gateway.profile.appRouting, AppRoutingMode.only);
    expect(gateway.profile.applications, ['com.example.nas']);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('小屏大字体保存按钮保持固定可达', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final controller = AppController(FakeGateway());
    await controller.initialize();
    await openPage(tester, AppRoutingPage(controller: controller));
    final button = find.byKey(const Key('save-app-routing'));
    expect(tester.getBottomRight(button).dy, lessThanOrEqualTo(640));
    expect(tester.getTopLeft(button).dy, greaterThan(0));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('账号页连接中切换需确认并先停止旧连接', (tester) async {
    final gateway = FakeGateway();
    gateway.savedProfiles[gateway.profile.id] = gateway.profile;
    const office = ClientProfile(
      server: 'https://office.example/',
      hostname: 'work',
      id: 'office',
    );
    gateway.savedProfiles[office.id] = office;
    gateway.current = const VpnSnapshot(phase: ConnectionPhase.connected);
    final controller = AppController(gateway);
    await controller.initialize();
    await openPage(tester, ProfilesPage(controller: controller));
    final select = find.byKey(const Key('select-office'));
    await tester.ensureVisible(select);
    await tester.pumpAndSettle();
    await tester.tap(select);
    await tester.pumpAndSettle();
    expect(find.text('断开并切换账号？'), findsOneWidget);
    expect(gateway.profileChanges, 0);
    await tester.tap(find.text('切换账号'));
    await tester.pumpAndSettle();
    expect(controller.profile!.id, 'office');
    expect(controller.snapshot.phase, ConnectionPhase.disconnected);
    expect(gateway.connectCalls, 0);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  test('诊断白名单不泄露服务器、地址、应用或授权错误正文', () async {
    final gateway = FakeGateway();
    final diagnostics = await gateway.systemDiagnostics();
    final report = diagnostics.report(
      const VpnSnapshot(
        phase: ConnectionPhase.connected,
        message: 'private-token-in-error',
        addresses: ['100.80.0.1/32'],
        selfName: 'private-phone.example.',
        skippedRoutes: ['192.168.50.0/24'],
        authorizationAvailable: true,
      ),
      gateway.profile.copyWith(
        appRouting: AppRoutingMode.only,
        applications: ['com.private.application'],
      ),
    );
    expect(report, contains('SDK 36'));
    expect(report, contains('已选择 1 个'));
    for (final secret in [
      gateway.profile.server,
      '100.80.0.1',
      '192.168.50.0',
      'private-phone',
      'private-token',
      'com.private.application',
    ]) {
      expect(report, isNot(contains(secret)));
    }
  });

  testWidgets('系统诊断显示真实开关，不声称业务已经连通', (tester) async {
    final controller = AppController(FakeGateway());
    await controller.initialize();
    await openPage(tester, SystemDiagnosticsPage(controller: controller));
    expect(find.text('系统正在限制后台运行'), findsOneWidget);
    expect(find.text('未开启，锁屏可能看不到连接通知'), findsOneWidget);
    expect(find.text('已安全连接'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  test('诊断报告区分出口与 DNS 状态并保留真实丢包计数但不导出身份', () async {
    final gateway = FakeGateway();
    final diagnostics = await gateway.systemDiagnostics();
    final report = diagnostics.report(
      const VpnSnapshot(
        phase: ConnectionPhase.connected,
        generation: 4,
        reconnects: 2,
        dnsActive: true,
        exitNodeAvailable: true,
        packetCounters: {'tun_packets': 8, 'source_drops': 3, 'private-id': 9},
      ),
      gateway.profile.copyWith(
        exitNodeId: 'private-exit-id',
        exitNodeName: 'private-exit-name',
      ),
    );
    expect(report, contains('连接代次：4 · 本次自动重连 2 次'));
    expect(report, contains('已选择'));
    expect(report, contains('匹配，不代表已出网'));
    expect(report, contains('内核 DNS 已启用'));
    expect(report, contains('对端来源不匹配丢弃：3'));
    for (final value in [
      'private-exit-id',
      'private-exit-name',
      'private-id',
      gateway.profile.server,
    ]) {
      expect(report, isNot(contains(value)));
    }
    final unknown = diagnostics.report(const VpnSnapshot(), gateway.profile);
    expect(unknown, contains('不按零丢包处理'));
    expect(unknown, isNot(contains('解密失败：0')));
  });

  testWidgets('系统诊断读取失败不把未知状态伪装成正常', (tester) async {
    final controller = AppController(_UnavailableDiagnosticsGateway());
    await controller.initialize();
    await openPage(tester, SystemDiagnosticsPage(controller: controller));
    expect(find.text('无法读取系统状态，请刷新后重试'), findsOneWidget);
    expect(find.byKey(const Key('copy-diagnostics')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}

class _UnavailableDiagnosticsGateway extends FakeGateway {
  @override
  Future<SystemDiagnostics> systemDiagnostics() async =>
      throw PlatformException(code: 'UNAVAILABLE');
}
