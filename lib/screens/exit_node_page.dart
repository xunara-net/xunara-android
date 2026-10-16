import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models.dart';

class ExitNodePage extends StatelessWidget {
  const ExitNodePage({required this.controller, super.key});
  final AppController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('出口节点')),
    body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final profile = controller.profile;
        final snapshot = controller.snapshot;
        final selected = profile?.exitNodeId ?? '';
        final candidates =
            snapshot.devices
                .where(
                  (device) => device.exitNode && device.stableId.isNotEmpty,
                )
                .toList()
              ..sort(
                (first, second) =>
                    first.displayName.compareTo(second.displayName),
              );
        final editable =
            !controller.busy &&
            profile != null &&
            {
              ConnectionPhase.connected,
              ConnectionPhase.disconnected,
              ConnectionPhase.error,
            }.contains(snapshot.phase);
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              '让网络从指定设备出去',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              '只显示控制面已批准双栈默认路由的设备。选择后，参与 VPN 的应用使用该出口上网，并使用出口的 DNS；手机局域网仍可直连。未参与 VPN 的应用与玄序自身不受影响。',
              style: TextStyle(color: Colors.blueGrey, height: 1.7),
            ),
            const SizedBox(height: 20),
            Card(
              child: ListTile(
                key: const Key('exit-none'),
                leading: const Icon(Icons.home_work_outlined),
                title: const Text('不使用出口节点'),
                subtitle: const Text('默认方式：只连接私有网络，日常上网保持不变'),
                trailing: selected.isEmpty
                    ? const Icon(Icons.check_circle_rounded)
                    : null,
                onTap: editable && selected.isNotEmpty
                    ? () => controller.applyNetworkSettings(
                        profile.copyWith(exitNodeId: '', exitNodeName: ''),
                      )
                    : null,
              ),
            ),
            if (selected.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  snapshot.phase == ConnectionPhase.connected
                      ? snapshot.exitNodeAvailable
                            ? '已选择：${profile!.exitNodeName}。实际联网能力取决于远端转发、ACL 与链路。'
                            : '所选出口当前不可用，公网流量被阻止，不会自动改走其他出口。请恢复出口或关闭出口模式。'
                      : '已保存出口：${profile!.exitNodeName}，连接后生效。',
                  style: TextStyle(
                    color:
                        snapshot.phase == ConnectionPhase.connected &&
                            !snapshot.exitNodeAvailable
                        ? Colors.orange.shade800
                        : Colors.blueGrey,
                    height: 1.6,
                  ),
                ),
              ),
            if (snapshot.phase != ConnectionPhase.connected)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('连接网络后获取可用的出口节点。'),
              ),
            for (final device in candidates)
              Card(
                child: ListTile(
                  key: Key('exit-${device.stableId}'),
                  leading: const Icon(Icons.public_rounded),
                  title: Text(device.displayName),
                  subtitle: Text(
                    '${osLabel(device.os)} · ${device.addresses.map(addressOnly).join(' / ')}',
                  ),
                  trailing: selected == device.stableId
                      ? const Icon(Icons.check_circle_rounded)
                      : null,
                  onTap: editable && selected != device.stableId
                      ? () => _select(context, profile, device)
                      : null,
                ),
              ),
            if (snapshot.phase == ConnectionPhase.connected &&
                candidates.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('暂无可用出口。请先在电脑或服务器上广播出口路由，并由管理员批准。'),
              ),
            if (controller.error != null)
              Text(
                controller.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 20),
            const Text(
              '出口不可达时保留 VPN 路由并丢弃公网流量；主动断开、撤销 VPN 权限或系统停止服务后，Android 会恢复普通网络。本版不是跨服务退出仍生效的锁定模式。',
              style: TextStyle(
                color: Colors.blueGrey,
                fontSize: 12,
                height: 1.7,
              ),
            ),
          ],
        );
      },
    ),
  );

  Future<void> _select(
    BuildContext context,
    ClientProfile profile,
    NetworkDevice device,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('使用此出口节点？'),
        content: Text(
          '参与 VPN 的应用将通过“${device.displayName}”上网。设置会重建连接；请只使用你信任的出口。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('使用出口'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await controller.applyNetworkSettings(
        profile.copyWith(
          exitNodeId: device.stableId,
          exitNodeName: device.displayName,
        ),
      );
    }
  }
}
