import 'package:flutter/material.dart';

import '../app_controller.dart';
import 'profile_editor.dart';

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
              leading: const Icon(Icons.manage_accounts_outlined),
              title: const Text('打开用户中心'),
              subtitle: const Text('管理账号、设备、邀请与访问权限'),
              trailing: const Icon(Icons.open_in_new_rounded, size: 18),
              onTap: () => controller.perform(controller.gateway.openConsole),
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
                'Android 预览版 0.1.0 · Rust ${controller.coreVersion}',
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
          applicationVersion: '0.1.0 预览版',
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
        '支持 Android 8.0 及以上 · ARM64 / x86_64\n首版暂不支持 MagicDNS、出口节点或手机充当子网路由器。\nWi-Fi / 移动网络切换后需手动重新连接。',
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
