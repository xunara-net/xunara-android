import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xunara_android/models.dart';
import 'package:xunara_android/vpn_gateway.dart';

Future<void> verifyDeviceSharing(
  VpnGateway gateway,
  ClientProfile original,
  VpnSnapshot originalSnapshot,
  Future<VpnSnapshot> Function(ConnectionPhase) waitPhase,
  Future<void> Function(String) waitMarker,
) async {
  const cache = '/data/user/0/net.xunara.android/cache';
  Future<void> marker(String name, [Object body = const {}]) =>
      File('$cache/integration-share-$name').writeAsString(jsonEncode(body));
  bool shared(NetworkDevice device) => device.stableId.startsWith('share:');
  Future<VpnSnapshot> visible(bool expected) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      final snapshot = await gateway.snapshot();
      if (snapshot.phase == ConnectionPhase.connected &&
          snapshot.devices.any(shared) == expected) {
        return snapshot;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    fail('共享映射没有按接受 / 撤销决定更新');
  }

  Future<ClientProfile> join(String name, int port) async {
    await gateway.disconnect();
    await waitPhase(ConnectionPhase.disconnected);
    final profile = await gateway.saveProfile(
      ClientProfile(
        server: 'http://127.0.0.1:$port/',
        hostname: 'android-share-$name',
        label: '共享验收 $name',
        acceptRoutes: true,
      ),
    );
    final secret = File('$cache/integration-share-$name-auth-key');
    var authKey = (await secret.readAsString()).trim();
    await secret.delete();
    await gateway.connect(authKey: authKey);
    authKey = '';
    await waitPhase(ConnectionPhase.connected);
    return profile;
  }

  final recipient = await join('recipient', 18082);
  final pending = await visible(false);
  // 与被分享的 Rust 路由器原地址完全重叠，不能绕开 peer 专属双栈 masquerade。
  expect(
    pending.addresses,
    containsAll(['100.80.0.1/32', 'fd7a:115c:a1e0::1/128']),
  );
  await marker('pending-ready');
  await waitMarker('share-created');
  expect((await gateway.snapshot()).devices.any(shared), isFalse);
  await marker('pending-verified');
  await waitMarker('share-accepted');
  final accepted = await visible(true);
  final device = accepted.devices.singleWhere(shared);
  expect(device.stableId, startsWith('share:owner:'));
  expect(device.routes, isEmpty);
  expect(device.exitNode, isFalse);
  expect(device.addresses.any(pending.addresses.contains), isFalse);
  final ping = await gateway.ping(device.id, generation: accepted.generation);
  expect(ping.address, isNotEmpty);
  await marker('active', {'addresses': device.addresses});
  await waitMarker('share-verified');

  await join('outsider', 18082);
  await visible(false);
  await marker('outsider-ready');
  await waitMarker('share-outsider-verified');
  await join('same-subject', 18083);
  await visible(false);
  await marker('third-ready');
  await waitMarker('share-third-verified');

  await gateway.disconnect();
  await waitPhase(ConnectionPhase.disconnected);
  await gateway.selectProfile(recipient.id);
  await gateway.connect();
  final restored = await visible(true);
  expect(restored.addresses, pending.addresses);
  expect(restored.devices.singleWhere(shared).addresses, device.addresses);
  await marker('restored');
  await waitMarker('share-revocation-sent');
  final revoked = await visible(false);
  expect(revoked.addresses, pending.addresses);
  await expectLater(
    gateway.ping(device.id, generation: revoked.generation),
    throwsA(isA<PlatformException>()),
  );
  await marker('revoked');
  await waitMarker('share-revoked-verified');

  await gateway.disconnect();
  await waitPhase(ConnectionPhase.disconnected);
  await gateway.selectProfile(original.id);
  await gateway.saveProfile(original);
  await gateway.connect();
  final back = await waitPhase(ConnectionPhase.connected);
  expect(back.addresses, originalSnapshot.addresses);
  expect(back.ownerLogin, originalSnapshot.ownerLogin);
  await marker('original-restored');
  await waitMarker('share-original-verified');
}
