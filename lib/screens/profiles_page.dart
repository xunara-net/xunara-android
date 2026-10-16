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
        appBar: AppBar(title: const Text('账号与控制器')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              '账号与控制器，随时切换',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              '每项分别保存设备身份、DNS、出口与应用分流。同一服务器可添加多个账号；切换时先结束旧连接，不自动接入新账号。',
              style: TextStyle(color: Colors.blueGrey, height: 1.7),
            ),
            if (controller.snapshot.phase.active) ...[
              const SizedBox(height: 16),
              const Text(
                '切换会先断开当前连接；添加、编辑或移除需先手动断开。',
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
                              profile.displayLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (profile.id == controller.profile?.id)
                            const Chip(label: Text('当前')),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${profile.displayServer}\n${profile.hostname} · ${profile.appRouting.label}',
                        style: const TextStyle(color: Colors.blueGrey),
                      ),
                      const SizedBox(height: 12),
                      if (profile.id == controller.profile?.id &&
                          controller.snapshot.ownerLogin.isNotEmpty)
                        Text(
                          '控制面确认的设备归属：${controller.snapshot.ownerLogin}',
                          style: const TextStyle(color: Colors.blueGrey),
                        ),
                      Wrap(
                        spacing: 12,
                        children: [
                          if (profile.id == controller.profile?.id)
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
                              key: Key('select-${profile.id}'),
                              onPressed:
                                  controller.busy || controller.profile == null
                                  ? null
                                  : () => _select(context, profile),
                              child: const Text('切换到此账号'),
                            ),
                            TextButton(
                              key: Key('forget-${profile.id}'),
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
              '新增同地址账号会创建独立设备，不会转移旧账号的设备。备注不是登录身份；请在浏览器授权页核对实际账号。',
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
                  : () => _add(context),
              icon: const Icon(Icons.add_rounded),
              label: Text(
                controller.profiles.length >= 16 ? '已保存 16 个账号' : '添加账号 / 控制器',
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
        title: const Text('移除此账号配置？'),
        content: const Text(
          '只移除连接记录，不删除服务器上的设备或本机私钥；此操作不撤销设备。重新添加会创建新的设备身份；撤销旧设备请到用户中心操作。',
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
      await controller.forgetProfile(profile.id);
    }
  }

  Future<void> _select(BuildContext context, ClientProfile profile) async {
    if (controller.snapshot.phase.active) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('断开并切换账号？'),
          content: Text('当前连接将结束，切换到“${profile.displayLabel}”后由你点击连接。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('切换账号'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }
    await controller.switchAccount(profile.id);
  }

  Future<void> _add(BuildContext context) async {
    final sameController = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_add_alt_rounded),
              title: const Text('在此控制器添加账号'),
              subtitle: const Text('使用独立设备身份，再授权给另一个账号'),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              leading: const Icon(Icons.add_to_drive_outlined),
              title: const Text('添加其他控制器'),
              subtitle: const Text('连接另一个服务器地址'),
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );
    if (sameController == null ||
        !context.mounted ||
        controller.profile == null) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileEditor(
          controller: controller,
          newServer: true,
          initialServer: sameController ? controller.profile!.server : '',
        ),
      ),
    );
  }
}
