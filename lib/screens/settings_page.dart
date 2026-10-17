import 'package:flutter/material.dart';

import '../app_controller.dart';
import 'profile_editor.dart';
import 'dns_info_page.dart';
import 'profiles_page.dart';
import 'app_routing_page.dart';
import 'system_diagnostics_page.dart';
import 'exit_node_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({required this.controller, super.key});
  final AppController controller;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.hub_rounded, color: Colors.white),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '玄序 Xunara',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text('简单连接，安心组网', style: TextStyle(color: Colors.blueGrey)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      const _Section('网络与账号'),
      const SizedBox(height: 10),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: const Text('服务器与设备名'),
              subtitle: Text(
                controller.snapshot.phase.active
                    ? '断开后可修改'
                    : controller.profile!.displayServer,
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: controller.snapshot.phase.active
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ProfileEditor(controller: controller),
                      ),
                    ),
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.swap_horiz_rounded),
              title: const Text('账号与控制器'),
              subtitle: Text('已保存 ${controller.profiles.length} 项，支持同一控制器多账号'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ProfilesPage(controller: controller),
                ),
              ),
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.apps_rounded),
              title: const Text('应用分流'),
              subtitle: Text(controller.profile!.appRouting.label),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AppRoutingPage(controller: controller),
                ),
              ),
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.language_rounded),
              title: const Text('设备域名与 DNS'),
              subtitle: Text(
                controller.profile!.acceptDns ||
                        controller.profile!.exitNodeId.isNotEmpty
                    ? 'VPN 内 DNS 已开启'
                    : '按需启用设备域名解析',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DnsInfoPage(controller: controller),
                ),
              ),
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.manage_accounts_outlined),
              title: const Text('打开用户中心'),
              subtitle: const Text('管理账号、设备、邀请与访问权限'),
              trailing: const Icon(Icons.open_in_new_rounded, size: 18),
              onTap: () => controller.perform(controller.gateway.openConsole),
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.public_rounded),
              title: const Text('出口节点'),
              subtitle: Text(
                controller.profile!.exitNodeId.isEmpty
                    ? '默认关闭，不接管日常上网'
                    : controller.profile!.exitNodeName,
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ExitNodePage(controller: controller),
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      const _Section('系统与连接'),
      const SizedBox(height: 10),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.health_and_safety_outlined),
              title: const Text('系统与连接诊断'),
              subtitle: const Text('权限、后台限制与脱敏诊断摘要'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SystemDiagnosticsPage(controller: controller),
                ),
              ),
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.notifications_none_rounded),
              title: const Text('连接状态通知'),
              subtitle: const Text('锁屏也能查看连接状态并快速断开'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () =>
                  controller.perform(controller.gateway.notificationSettings),
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.vpn_key_outlined),
              title: const Text('系统 VPN 设置'),
              subtitle: const Text('Android 同一时间只能启用一个 VPN'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => controller.perform(controller.gateway.vpnSettings),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      const _Section('隐私与版本'),
      const SizedBox(height: 10),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '默认只连接你的私有网络',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              const Text(
                '不上传通讯录，不采集浏览记录，无广告与统计 SDK。机器私钥保存在应用私有且禁止备份的目录；接入密钥不会持久保存。',
                style: TextStyle(color: Colors.blueGrey, height: 1.6),
              ),
              const SizedBox(height: 16),
              Text(
                'Android 预览版 0.4.0 · Rust ${controller.coreVersion}',
                style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
            ],
          ),
        ),
      ),
      TextButton.icon(
        onPressed: () => showLicensePage(
          context: context,
          applicationName: '玄序 Xunara',
          applicationVersion: '0.4.0 预览版',
        ),
        icon: const Icon(Icons.description_outlined, size: 18),
        label: const Text('开源组件声明'),
      ),
      if (controller.error != null)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(
            controller.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      const SizedBox(height: 24),
      const Text(
        '支持 Android 8.0 及以上 · ARM64 / x86_64\n支持 MagicDNS、DoH / DoT、DNSSEC 与出口访问；手机转发和完整 Tailnet Lock 尚在开发。\n网络切换后默认安全重连；主动断开不会自动连接。',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: Colors.blueGrey, height: 1.8),
      ),
    ],
  );
}

class _Section extends StatelessWidget {
  const _Section(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Text(
      label,
      style: const TextStyle(
        color: Colors.blueGrey,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
