import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../models.dart';

class DnsInfoPage extends StatelessWidget {
  const DnsInfoPage({required this.controller, super.key});
  final AppController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('设备域名与 DNS')),
    body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final snapshot = controller.snapshot;
        final connected = snapshot.phase == ConnectionPhase.connected;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: const Text('控制面的 MagicDNS'),
                subtitle: Text(
                  !connected
                      ? '连接后读取当前网络配置'
                      : snapshot.magicDnsEnabled
                      ? '服务器已启用'
                      : '服务器未启用',
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '手机 DNS 保持不变',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            const Text(
              '此页展示服务器提供的设备域名与搜索域，不代表手机已启用系统级 MagicDNS 解析。本版不覆盖手机解析器，也不劫持 100.100.100.100；其他 App 请使用设备 IP 连接。',
              style: TextStyle(color: Colors.blueGrey, height: 1.8),
            ),
            if (connected) ...[
              if (snapshot.selfName.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Text('本机域名'),
                _copyable(
                  context,
                  snapshot.selfName.replaceFirst(RegExp(r'\.$'), ''),
                ),
              ],
              const SizedBox(height: 24),
              const Text('搜索域'),
              if (snapshot.searchDomains.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    '服务器没有下发搜索域',
                    style: TextStyle(color: Colors.blueGrey),
                  ),
                ),
              for (final domain in snapshot.searchDomains)
                _copyable(context, domain),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () =>
                    controller.perform(controller.gateway.openConsole),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('前往用户中心管理 DNS'),
              ),
            ],
          ],
        );
      },
    ),
  );

  Widget _copyable(BuildContext context, String value) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(value),
    trailing: const Icon(Icons.copy_rounded, size: 18),
    onTap: () async {
      await Clipboard.setData(ClipboardData(text: value));
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已复制域名')));
      }
    },
  );
}
