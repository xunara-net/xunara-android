import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'vpn_gateway.dart';

class AppController extends ChangeNotifier {
  AppController(this.gateway);
  final VpnGateway gateway;
  ClientProfile? profile;
  List<ClientProfile> profiles = const [];
  VpnSnapshot snapshot = const VpnSnapshot();
  String coreVersion = '';
  String? error;
  bool loading = true;
  bool busy = false;
  bool _disposed = false;
  bool _refreshing = false;
  int _stateRevision = 0;
  Timer? _timer;

  Future<void> initialize() async {
    await perform(() async {
      final initial = await gateway.bootstrap();
      profile = initial.profile;
      profiles = initial.profiles.isEmpty
          ? [initial.profile]
          : initial.profiles;
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
    if (_disposed || _refreshing || busy || profile == null) return;
    final revision = _stateRevision;
    _refreshing = true;
    try {
      final current = await gateway.snapshot();
      if (_disposed || busy || revision != _stateRevision) return;
      snapshot = current;
      if (!_disposed) notifyListeners();
    } on Exception {
      if (_disposed || busy || revision != _stateRevision) return;
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
    // 切换后丢弃旧账号尚未返回的状态，不能把旧设备归属显示在新账号下面。
    _stateRevision++;
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
    if (profile == null) {
      error = '请先重新加载并确认当前服务器，再连接网络';
      if (!_disposed) notifyListeners();
      return;
    }
    await perform(() => gateway.connect(authKey: authKey));
    await refresh();
  }

  Future<void> disconnect() async {
    await perform(gateway.disconnect);
    await refresh();
  }

  Future<bool> _changeProfiles(Future<void> Function() change) async {
    if (profile == null) {
      error = '请先重新加载并确认当前服务器，再修改设置';
      if (!_disposed) notifyListeners();
      return false;
    }
    if (snapshot.phase.active) {
      error = '请先断开连接，再修改或切换服务器';
      if (!_disposed) notifyListeners();
      return false;
    }
    return perform(() async {
      try {
        await change();
        final current = await gateway.bootstrap();
        profile = current.profile;
        profiles = current.profiles.isEmpty
            ? [current.profile]
            : current.profiles;
        snapshot = current.snapshot;
      } on Exception {
        // 原生提交结果未知时先读回，不拿旧服务器标签启动可能已切换的机器身份。
        profile = null;
        profiles = const [];
        snapshot = const VpnSnapshot(phase: ConnectionPhase.error);
        rethrow;
      }
    });
  }

  Future<bool> save(ClientProfile next) => _changeProfiles(() async {
    await gateway.saveProfile(next);
  });
  Future<bool> selectProfile(String server) =>
      _changeProfiles(() => gateway.selectProfile(server));
  Future<bool> forgetProfile(String server) =>
      _changeProfiles(() => gateway.forgetProfile(server));

  Future<bool> applyNetworkSettings(ClientProfile next) async {
    if (profile == null ||
        next.id != profile!.id ||
        next.server != profile!.server) {
      error = '当前账号已变化，请重新打开网络设置';
      if (!_disposed) notifyListeners();
      return false;
    }
    return _withStopped(() async {
      await gateway.saveProfile(next);
    }, reconnect: true);
  }

  Future<bool> switchAccount(String id) =>
      _withStopped(() => gateway.selectProfile(id), reconnect: false);

  Future<bool> _withStopped(
    Future<void> Function() change, {
    required bool reconnect,
  }) async {
    if (profile == null ||
        !{
          ConnectionPhase.connected,
          ConnectionPhase.disconnected,
          ConnectionPhase.error,
        }.contains(snapshot.phase)) {
      error = '请先结束授权或等待连接完成';
      if (!_disposed) notifyListeners();
      return false;
    }
    final wasConnected = snapshot.phase == ConnectionPhase.connected;
    return perform(() async {
      if (wasConnected) {
        await gateway.disconnect();
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        do {
          snapshot = await gateway.snapshot();
          if (!snapshot.phase.active) break;
          if (DateTime.now().isAfter(deadline)) {
            throw PlatformException(
              code: 'STOP_TIMEOUT',
              message: '旧连接尚未退出，未切换账号或网络设置',
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        } while (true);
      }
      try {
        await change();
        final current = await gateway.bootstrap();
        profile = current.profile;
        profiles = current.profiles.isEmpty
            ? [current.profile]
            : current.profiles;
        snapshot = current.snapshot;
      } on Exception {
        profile = null;
        profiles = const [];
        snapshot = const VpnSnapshot(phase: ConnectionPhase.error);
        rethrow;
      }
      if (wasConnected && reconnect) {
        await gateway.connect();
        snapshot = await gateway.snapshot();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    pause();
    super.dispose();
  }
}
