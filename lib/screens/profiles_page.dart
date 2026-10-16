import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models.dart';
import 'profile_editor.dart';

class ProfilesPage extends StatelessWidget {
  const ProfilesPage({required this.controller, super.key});
  final AppController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final locked =
          controller.profile == null ||
          controller.busy ||
          controller.snapshot.phase.active;
      return Scaffold(
        appBar: AppBar(title: const Text('常用服务器')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              '在家与办公，分别保存',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              '每个服务器分别保存设备名、子网与应用分流设置，机器身份也按控制面隔离。切换服务器不会自动连接，仍由你确认接入。',
              style: TextStyle(color: Colors.blueGrey, height: 1.7),
            ),
            if (controller.snapshot.phase.active) ...[
              const SizedBox(height: 16),
              const Text(
                '请先断开连接，再切换、添加或移除服务器。',
                style: TextStyle(color: Colors.orange),
              ),
            ],
            const SizedBox(height: 20),
            if (controller.profile == null) ...[
              const Text('设置可能已变更，请重新加载确认当前服务器，不会自动连接。'),
              TextButton(
                onPressed: controller.busy ? null : controller.initialize,
                child: const Text('重新加载配置'),
              ),
            ],
            for (final profile in controller.profiles) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.dns_outlined),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              profile.displayServer,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (profile.server == controller.profile?.server)
                            const Chip(label: Text('当前')),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${profile.hostname} · ${profile.appRouting.label}',
                        style: const TextStyle(color: Colors.blueGrey),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        children: [
                          if (profile.server == controller.profile?.server)
                            TextButton.icon(
                              onPressed: locked
                                  ? null
                                  : () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => ProfileEditor(
                                          controller: controller,
                                        ),
                                      ),
                                    ),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: const Text('编辑设置'),
                            )
                          else ...[
                            FilledButton.tonal(
                              key: Key('select-${profile.server}'),
                              onPressed: locked
                                  ? null
                                  : () => controller.selectProfile(
                                      profile.server,
                                    ),
                              child: const Text('切换到此服务器'),
                            ),
                            TextButton(
                              key: Key('forget-${profile.server}'),
                              onPressed: locked
                                  ? null
                                  : () => _forget(context, profile),
                              child: const Text('移除记录'),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            const Text(
              '同一控制面的多个账号不是多个服务器。账号与设备授权仍在系统浏览器完成，不能通过切换设置转移已登记设备。',
              style: TextStyle(
                color: Colors.blueGrey,
                fontSize: 12,
                height: 1.7,
              ),
            ),
            if (controller.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  controller.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: FilledButton.icon(
              onPressed: locked || controller.profiles.length >= 16
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ProfileEditor(
                          controller: controller,
                          newServer: true,
                        ),
                      ),
                    ),
              icon: const Icon(Icons.add_rounded),
              label: Text(
                controller.profiles.length >= 16 ? '已保存 16 个服务器' : '添加服务器',
              ),
            ),
          ),
        ),
      );
    },
  );

  Future<void> _forget(BuildContext context, ClientProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除此服务器记录？'),
        content: const Text(
          '只移除本机保存的连接设置，不删除机器私钥或服务器上的设备。重新添加相同服务器仍复用原机器身份；这不是退出账号或撤销设备。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除记录'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await controller.forgetProfile(profile.server);
    }
  }
}
