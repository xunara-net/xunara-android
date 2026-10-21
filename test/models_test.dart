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
    expect(device.online, isNull);
    expect(device.onlineLabel, '状态未知');
    expect(addressOnly(device.addresses.first), '100.80.0.2');
    expect(device.displayName, 'nas.example.test');
    expect(formatBytes(2048), '2.0 KB');
  });
  test('在线状态保持三态，最近在线时间不当成到期时间', () {
    for (final state in [true, false, null, 'false', 0]) {
      final device = NetworkDevice.fromJson({'online': state});
      expect(device.online, state is bool ? state : null);
    }
    expect(NetworkDevice.fromJson({'online': true}).onlineLabel, '在线');
    expect(NetworkDevice.fromJson({'online': false}).onlineLabel, '离线');
    expect(lastSeenLabel(null), '服务器未提供');
    expect(lastSeenLabel('invalid'), '服务器未提供');
    expect(lastSeenLabel('0001-01-01T00:00:00Z'), '服务器未提供');
    expect(lastSeenLabel('2026-10-21T01:00:00Z'), contains('2026-10-21'));
    final state = VpnSnapshot.fromJson({
      'status': {
        'exit_node': {'available': true, 'online': false},
      },
    });
    expect(state.exitNodeAvailable, isTrue);
    expect(state.exitNodeOnline, isFalse);
  });
  test('到期、DNS 和切网字段缺失时不编造状态', () {
    expect(expiryLabel(null), '服务器未提供');
    expect(expiryLabel('invalid'), '服务器未提供');
    expect(expiryLabel('0001-01-01T00:00:00Z'), '不自动过期');
    expect(expiryLabel('2026-12-31T00:00:00Z'), contains('2026-12-31'));
    expect(
      ClientProfile.fromJson({'server': 'https://example.test'}).autoReconnect,
      isTrue,
    );
    final snapshot = VpnSnapshot.fromJson({
      'phase': 'connected',
      'generation': 2,
      'network_label': 'Wi-Fi',
      'reconnects': 1,
      'status': {
        'self_name': 'phone.example.test.',
        'dns': {
          'enabled': true,
          'domains': ['example.test'],
        },
        'devices': [
          {
            'id': '2',
            'os': 'linux',
            'key_expiry': '0001-01-01T00:00:00Z',
            'relay_name': '测试中继',
            'routes': ['10.90.0.0/24'],
          },
        ],
      },
    });
    expect(snapshot.searchDomains, ['example.test']);
    expect(snapshot.magicDnsEnabled, isTrue);
    expect(snapshot.generation, 2);
    expect(snapshot.devices.single.relayName, '测试中继');
    expect(osLabel(snapshot.devices.single.os), 'Linux');
    expect(snapshot.devices.single.routes, ['10.90.0.0/24']);
  });
  test('只接受有限的真实 ICMP 诊断结果', () {
    expect(
      PingResult.fromJson({
        'address': '100.80.0.2',
        'rtt_ms': 12.4,
        'path': 'relay',
      }).pathLabel,
      'DERP 中继',
    );
    for (final milliseconds in [-1, double.nan, double.infinity]) {
      expect(
        () => PingResult.fromJson({
          'address': '100.80.0.2',
          'rtt_ms': milliseconds,
          'path': 'relay',
        }),
        throwsFormatException,
      );
    }
    expect(
      () => PingResult.fromJson({
        'address': '100.80.0.2',
        'rtt_ms': 1,
        'path': 'unknown',
      }),
      throwsFormatException,
    );
  });

  test('数据包诊断只接收固定名称的非负整数且不能被调用方改写', () {
    final snapshot = VpnSnapshot.fromJson({
      'status': {
        'receive_stats': {
          'tun_packets': 17,
          'acl_drops': 0,
          'private-token': 99,
        },
      },
    });
    expect(snapshot.packetCounters, {'tun_packets': 17, 'acl_drops': 0});
    expect(
      () => snapshot.packetCounters!['tun_packets'] = 0,
      throwsUnsupportedError,
    );
    for (final invalid in [
      null,
      'not-a-map',
      {'tun_packets': -1},
      {'acl_drops': 1.2},
      {'dns_queries': '0'},
      {'private-token': 99},
    ]) {
      expect(
        VpnSnapshot.fromJson({
          'status': {'receive_stats': invalid},
        }).packetCounters,
        isNull,
      );
    }
  });

  test('DNS 诊断只解析真实消息计数，不导出查询名称或编造零值', () {
    final snapshot = VpnSnapshot.fromJson({
      'status': {
        'dns': {
          'statistics': {
            'queries': 2,
            'responses': 1,
            'timeouts': 1,
            'domain': 'private.example.test',
          },
        },
      },
    });
    expect(snapshot.dnsCounters, {'queries': 2, 'responses': 1, 'timeouts': 1});
    expect(() => snapshot.dnsCounters!['queries'] = 0, throwsUnsupportedError);
    for (final invalid in [
      null,
      {},
      {'queries': -1},
      {'responses': '1'},
      {'domain': 'private.example.test'},
    ]) {
      expect(
        VpnSnapshot.fromJson({
          'status': {
            'dns': {'statistics': invalid},
          },
        }).dnsCounters,
        isNull,
      );
    }
  });

  test('本机中继只接受一致的区域编号与连接确认，不把旧内核当作已连接', () {
    for (final raw in [
      null,
      'invalid',
      {},
      {'home_region': 900},
      {'home_region': 0, 'connected': true},
      {'home_region': 900, 'connected': false},
      {'home_region': '900', 'connected': true},
      {'home_region': -1, 'connected': false},
      {'home_region': 65536, 'connected': true},
    ]) {
      expect(
        VpnSnapshot.fromJson({
          'status': {'relay': raw},
        }).homeRelayRegion,
        isNull,
      );
    }
    for (final region in [0, 900]) {
      expect(
        VpnSnapshot.fromJson({
          'status': {
            'relay': {'home_region': region, 'connected': region > 0},
          },
        }).homeRelayRegion,
        region,
      );
    }
  });
}
