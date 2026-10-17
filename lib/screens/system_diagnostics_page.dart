import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../system_diagnostics.dart';

class SystemDiagnosticsPage extends StatefulWidget {
  const SystemDiagnosticsPage({required this.controller, super.key});
  final AppController controller;
  @override
  State<SystemDiagnosticsPage> createState() => _SystemDiagnosticsPageState();
}

class _SystemDiagnosticsPageState extends State<SystemDiagnosticsPage>
    with WidgetsBindingObserver {
  SystemDiagnostics? _diagnostics;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final diagnostics = await widget.controller.gateway.systemDiagnostics();
      if (mounted) setState(() => _diagnostics = diagnostics);
    } on Exception {
      if (mounted) {
        setState(() {
          _diagnostics = null;
          _error = '无法读取系统状态，请刷新后重试';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('系统与连接诊断'),
      actions: [
        IconButton(
          onPressed: _loading ? null : _load,
          tooltip: '刷新系统状态',
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final diagnostics = _diagnostics;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              '先看真实系统状态',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              '这里检查权限、电池与后台限制，不把系统开关正常当作设备已连通。设备详情中的连通检测才会发送真实加密探测。',
              style: TextStyle(color: Colors.blueGrey, height: 1.7),
            ),
            const SizedBox(height: 20),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (diagnostics != null) ...[
              Card(
                child: Column(
                  children: [
                    _entry(
                      Icons.vpn_key_outlined,
                      '系统 VPN 权限',
                      diagnostics.vpnPermission ? '已允许建立 VPN' : '连接时需要允许，尚未授权',
                      widget.controller.gateway.vpnSettings,
                    ),
                    const Divider(height: 1),
                    _entry(
                      Icons.dns_outlined,
                      '系统私人 DNS',
                      diagnostics.privateDnsDescription,
                      widget.controller.gateway.networkSettings,
                    ),
                    const Divider(height: 1),
                    _entry(
                      Icons.notifications_outlined,
                      '连接状态通知',
                      diagnostics.notificationsEnabled
                          ? '已开启'
                          : '未开启，锁屏可能看不到连接通知',
                      widget.controller.gateway.notificationSettings,
                    ),
                    const Divider(height: 1),
                    _entry(
                      Icons.battery_saver_outlined,
                      '电池与后台运行',
                      diagnostics.backgroundRestricted
                          ? '系统正在限制后台运行'
                          : diagnostics.batteryUnrestricted
                          ? '未受电池优化限制'
                          : '由系统电池策略管理，不一定代表故障',
                      widget.controller.gateway.batterySettings,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Android ${diagnostics.androidVersion} · SDK ${diagnostics.androidSdk}',
              ),
              const SizedBox(height: 8),
              Text(
                '应用 ${diagnostics.appVersion} · 内核 ${diagnostics.coreVersion}',
              ),
              const SizedBox(height: 20),
              const Text(
                '部分厂商还提供独立的自启动和后台锁定设置；本页不会自动申请电池豁免，也不保证杀进程后自动恢复。',
                style: TextStyle(color: Colors.blueGrey, height: 1.7),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                key: const Key('copy-diagnostics'),
                onPressed: () => _copy(diagnostics),
                icon: const Icon(Icons.copy_rounded),
                label: const Text('复制脱敏诊断摘要'),
              ),
              const SizedBox(height: 10),
              const Text(
                '仅复制版本、系统开关、连接状态和计数；不包含服务器、IP、设备名、应用清单、授权链接或密钥，不自动上传。',
                style: TextStyle(
                  color: Colors.blueGrey,
                  fontSize: 12,
                  height: 1.7,
                ),
              ),
            ],
            if (widget.controller.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  widget.controller.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        );
      },
    ),
  );

  Widget _entry(
    IconData icon,
    String title,
    String detail,
    Future<void> Function() action,
  ) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(detail),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: () => widget.controller.perform(action),
  );

  Future<void> _copy(SystemDiagnostics diagnostics) async {
    final controller = widget.controller;
    if (controller.profile == null) return;
    await Clipboard.setData(
      ClipboardData(
        text: diagnostics.report(controller.snapshot, controller.profile!),
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已复制脱敏诊断摘要')));
    }
  }
}
