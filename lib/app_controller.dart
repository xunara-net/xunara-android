import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'vpn_gateway.dart';

class AppController extends ChangeNotifier {
  AppController(this.gateway);
  final VpnGateway gateway;
  ClientProfile? profile;
  VpnSnapshot snapshot = const VpnSnapshot();
  String coreVersion = '';
  String? error;
  bool loading = true;
  bool busy = false;
  bool _disposed = false;
  bool _refreshing = false;
  Timer? _timer;

  Future<void> initialize() async {
    await perform(() async {
      final initial = await gateway.bootstrap();
      profile = initial.profile;
      snapshot = initial.snapshot;
      coreVersion = initial.coreVersion;
    });
    loading = false;
    if (!_disposed) {
      resume();
      notifyListeners();
    }
  }

  void resume() {
    _timer?.cancel();
    if (!_disposed) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
    }
  }

  void pause() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> refresh() async {
    if (_disposed || _refreshing || profile == null) return;
    _refreshing = true;
    try {
      snapshot = await gateway.snapshot();
      if (!_disposed) notifyListeners();
    } on Exception {
      // 不沿用旧的“已连接”结果；系统通道失联不等于隧道仍然健康。
      snapshot = const VpnSnapshot(
        phase: ConnectionPhase.error,
        message: '无法读取系统 VPN 状态，请重新打开应用',
      );
      if (!_disposed) notifyListeners();
    } finally {
      _refreshing = false;
    }
  }

  Future<bool> perform(Future<void> Function() action) async {
    if (busy || _disposed) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on PlatformException catch (exception) {
      error = exception.message ?? '系统操作失败，请重试';
      return false;
    } on Exception {
      error = '操作未完成，请检查网络后重试';
      return false;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> connect({String authKey = ''}) async {
    await perform(() => gateway.connect(authKey: authKey));
    await refresh();
  }

  Future<void> disconnect() async {
    await perform(gateway.disconnect);
    await refresh();
  }

  Future<bool> save(ClientProfile next) => perform(() async {
    profile = await gateway.saveProfile(next);
  });

  @override
  void dispose() {
    _disposed = true;
    pause();
    super.dispose();
  }
}
