import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../models.dart';

class DevicesPage extends StatefulWidget {
  const DevicesPage({required this.controller, super.key});
  final AppController controller;
  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final snapshot = widget.controller.snapshot;
    if (snapshot.phase != ConnectionPhase.connected) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.devices_other_rounded,
                size: 64,
                color: Colors.blueGrey,
              ),
              SizedBox(height: 20),
              Text(
                '连接后查看你的设备',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 10),
              Text(
                '只展示服务器允许本设备发现的节点，\n不会读取其他用户的网络。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.blueGrey, height: 1.6),
              ),
            ],
          ),
        ),
      );
    }
    final devices = snapshot.devices
        .where(
          (device) => '${device.name} ${device.addresses.join(' ')}'
              .toLowerCase()
              .contains(_query.toLowerCase()),
        )
        .toList();
    return RefreshIndicator(
      onRefresh: widget.controller.refresh,
      child: ListView(
        padding: const EdgeInsets.all(20),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              hintText: '搜索设备名称或 IP',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '当前网络 · ${snapshot.devices.length} 台可见设备',
            style: const TextStyle(color: Colors.blueGrey),
          ),
          const SizedBox(height: 12),
          if (devices.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Text(
                '暂未发现匹配的设备\n请确认其他设备已加入、获得授权且 ACL 允许访问。',
                textAlign: TextAlign.center,
                style: TextStyle(height: 1.8, color: Colors.blueGrey),
              ),
            ),
          for (final device in devices)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F7F6),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.computer_rounded),
                  ),
                  title: Text(
                    device.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${device.addresses.isEmpty ? '未分配地址' : addressOnly(device.addresses.first)}\n${device.pathLabel}',
                      style: const TextStyle(height: 1.6),
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _detail(context, device),
                ),
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            '连接方式根据内核最近一次探测显示；中继候选不代表已验证连通，最终访问仍受 ACL 约束。',
            style: TextStyle(fontSize: 12, color: Colors.blueGrey, height: 1.6),
          ),
        ],
      ),
    );
  }

  void _detail(BuildContext context, NetworkDevice device) =>
      showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                device.displayName,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              for (final address in device.addresses)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(addressOnly(address)),
                  subtitle: const Text('点击复制网络地址'),
                  trailing: const Icon(Icons.copy_rounded),
                  onTap: () async {
                    await Clipboard.setData(
                      ClipboardData(text: addressOnly(address)),
                    );
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('已复制地址')));
                    }
                  },
                ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('连接方式'),
                trailing: Text(device.pathLabel),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('中继区域'),
                trailing: Text(
                  device.relayRegion > 0 ? '#${device.relayRegion}' : '未配置',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '改名、审批、过期时间与分享请前往用户中心管理，手机端不申请全局管理权限。',
                style: TextStyle(color: Colors.blueGrey, height: 1.6),
              ),
            ],
          ),
        ),
      );
}
