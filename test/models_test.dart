import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xunara_android/models.dart';

void main() {
  testWidgets('安装包包含原生加密组件和协议组件的上游声明', (tester) async {
    final contents = await tester.runAsync(
      () => rootBundle.loadString('assets/native_licenses.json'),
    );
    final entries = jsonDecode(contents!) as List;
    for (final name in ['boringtun', 'ts_noise', 'jni']) {
      expect(
        entries.any(
          (entry) =>
              entry['name'] == name && (entry['text'] as String).length > 100,
        ),
        isTrue,
      );
    }
  });
  test('只接受无凭据、无租户路径的安全根地址', () {
    expect(ClientProfile.validateServer('https://example.test:9090/'), isNull);
    expect(ClientProfile.validateServer('http://127.0.0.1:18080'), isNull);
    for (final server in [
      'http://example.test',
      'https://user:secret@example.test',
      'https://example.test/t/user/login',
      'https://example.test?token=secret',
      'https://example.test#fragment',
      'https://example.test:99999',
      'not-a-url',
    ]) {
      expect(ClientProfile.validateServer(server), isNotNull, reason: server);
    }
  });
  test('状态解析不把授权地址暴露为业务字段', () {
    final snapshot = VpnSnapshot.fromJson({
      'phase': 'authorizing',
      'authorization_url': 'https://example.test/register/id',
    });
    expect(snapshot.phase, ConnectionPhase.authorizing);
    expect(snapshot.authorizationAvailable, isTrue);
    expect(snapshot.devices, isEmpty);
    expect(
      VpnSnapshot.fromJson({'phase': 'unknown'}).phase,
      ConnectionPhase.error,
    );
    expect(ClientProfile.validateHostname('手机'), isNotNull);
    expect(ClientProfile.validateHostname('android-12'), isNull);
  });
  test('中继候选不伪报为对端在线或中继已联通', () {
    final device = NetworkDevice.fromJson({
      'id': '42',
      'name': 'nas.example.test.',
      'path': 'relay',
      'addresses': ['100.80.0.2/32'],
      'relay_region': 900,
    });
    expect(device.pathLabel, '中继候选');
    expect(addressOnly(device.addresses.first), '100.80.0.2');
    expect(device.displayName, 'nas.example.test');
    expect(formatBytes(2048), '2.0 KB');
  });
}
