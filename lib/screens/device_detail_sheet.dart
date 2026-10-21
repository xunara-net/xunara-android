import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../models.dart';

class DeviceDetailSheet extends StatefulWidget {
  const DeviceDetailSheet({
    required this.controller,
    required this.peerId,
    required this.generation,
    super.key,
  });
  final AppController controller;
  final String peerId;
  final int generation;

  @override
  State<DeviceDetailSheet> createState() => _DeviceDetailSheetState();
}

class _DeviceDetailSheetState extends State<DeviceDetailSheet> {
  int get _generation => widget.generation;
  bool _testing = false;
  PingResult? _result;
  String? _error;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final snapshot = widget.controller.snapshot;
      final device = snapshot.devices
          .where((device) => device.id == widget.peerId)
          .firstOrNull;
      final available =
          snapshot.phase == ConnectionPhase.connected &&
          snapshot.generation == _generation &&
          device != null;
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                device?.displayName ?? '设备已不可见',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('ping-device-button'),
                onPressed: available && !_testing ? _ping : null,
                icon: _testing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.network_ping_rounded),
                label: Text(_testing ? '正在检测，最多等待 12 秒' : '检测连通性'),
              ),
              const SizedBox(height: 8),
              const Text(
                '发送真实加密 ICMP，不绕过 ACL；超时不一定代表设备离线。',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.blueGrey,
                  height: 1.6,
                ),
              ),
              if (!available)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    '连接已变化或设备已被撤销，请关闭详情后刷新。',
                    key: Key('device-unavailable'),
                  ),
                ),
              if (available && _result != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    '已收到加密回包 · ${_result!.rttMs.toStringAsFixed(1)} ms\n${_result!.pathLabel}${_result!.relayRegion > 0 ? ' #${_result!.relayRegion}' : ''} · ${_result!.address}',
                    key: const Key('ping-result'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      height: 1.7,
                    ),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (available) ...[
                const SizedBox(height: 12),
                if (device.shared) _value('设备来源', '跨网络共享 · 访问仍受 ACL 和共享状态约束'),
                _value('在线状态（控制面）', device.onlineLabel),
                if (device.online != true)
                  _value('最近在线（本地时间）', lastSeenLabel(device.lastSeen)),
                _value('操作系统', osLabel(device.os)),
                if (device.name.contains('.'))
                  _copyable('设备域名（控制面）', device.displayName),
                for (final address in device.addresses)
                  _copyable(
                    address.contains(':') ? 'IPv6' : 'IPv4',
                    addressOnly(address),
                  ),
                const Divider(),
                _value('连接方式', device.pathLabel),
                _value(
                  '中继区域',
                  device.relayRegion > 0
                      ? '${device.relayName.isEmpty ? '' : '${device.relayName} · '}#${device.relayRegion}'
                      : '未配置',
                ),
                _value('密钥到期（本地时间）', expiryLabel(device.keyExpiry)),
                if (device.routes.isNotEmpty) ...[
                  const Divider(),
                  _value('已批准的子网路由', device.routes.join('\n')),
                ],
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => widget.controller.perform(
                    widget.controller.gateway.openConsole,
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('在用户中心管理设备'),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );

  Widget _value(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
        ),
        const SizedBox(height: 5),
        Text(value),
      ],
    ),
  );

  Widget _copyable(String label, String value) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(value),
    subtitle: Text('$label · 点击复制'),
    trailing: const Icon(Icons.copy_rounded, size: 18),
    onTap: () async {
      await Clipboard.setData(ClipboardData(text: value));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已复制')));
      }
    },
  );

  Future<void> _ping() async {
    setState(() {
      _testing = true;
      _result = null;
      _error = null;
    });
    try {
      final result = await widget.controller.gateway.ping(
        widget.peerId,
        generation: _generation,
      );
      if (!mounted) return;
      final snapshot = widget.controller.snapshot;
      if (snapshot.phase != ConnectionPhase.connected ||
          snapshot.generation != _generation) {
        setState(() => _error = '连接已变化，请重新检测');
      } else {
        setState(() => _result = result);
      }
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message ?? '检测未完成，请重试');
    } on Exception {
      if (mounted) setState(() => _error = '检测未完成，请检查网络后重试');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }
}
