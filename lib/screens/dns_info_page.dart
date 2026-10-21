import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../models.dart';
import 'dns_resolver_page.dart';
import 'system_diagnostics_page.dart';

class DnsInfoPage extends StatelessWidget {
  const DnsInfoPage({required this.controller, super.key});
  final AppController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('设备域名与 DNS'),
      actions: [
        IconButton(
          tooltip: '解析器与 DNSSEC',
          icon: const Icon(Icons.tune_rounded),
          onPressed: controller.profile == null
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => DnsResolverPage(controller: controller),
                  ),
                ),
        ),
      ],
    ),
    body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final snapshot = controller.snapshot;
        final connected = snapshot.phase == ConnectionPhase.connected;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SwitchListTile(
              key: const Key('magic-dns-switch'),
              contentPadding: EdgeInsets.zero,
              title: const Text('使用网络 DNS / MagicDNS'),
              subtitle: Text(
                controller.profile?.exitNodeId.isNotEmpty == true
                    ? '使用出口节点时自动启用，避免 DNS 查询从本地网络泄露'
                    : '在 VPN 内解析设备域名；普通域名使用网络配置的解析器',
              ),
              value:
                  controller.profile?.acceptDns == true ||
                  controller.profile?.exitNodeId.isNotEmpty == true,
              onChanged:
                  controller.busy ||
                      controller.profile == null ||
                      controller.profile!.exitNodeId.isNotEmpty
                  ? null
                  : (value) => controller.applyNetworkSettings(
                      controller.profile!.copyWith(acceptDns: value),
                    ),
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: const Text('MagicDNS'),
                subtitle: Text(
                  !connected
                      ? '连接后读取当前网络配置'
                      : snapshot.magicDnsEnabled
                      ? '此网络已启用'
                      : '此网络未启用',
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              snapshot.dnsActive ? '正在使用玄序 DNS' : '正在使用系统 DNS',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            if (controller.profile?.exitNodeId.isNotEmpty == true)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('设备域名在本机解析；公网域名通过所选出口解析。出口不可用时不会改用手机原网络。'),
              ),
            const Text(
              '开启后使用网络 DNS 设置与设备域名。断开后恢复系统解析；严格私人 DNS 或应用自带 DoH 可能绕过网络 DNS。',
              style: TextStyle(color: Colors.blueGrey, height: 1.8),
            ),
            if (snapshot.dnssecActive)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text('本机 DNSSEC 验证已启用：此状态不代表所有域名都已签名。'),
              ),
            if (connected) ...[
              const SizedBox(height: 24),
              const Text('DNS 服务器'),
              if (controller.profile?.dnsResolver.isNotEmpty == true) ...[
                _copyable(context, controller.profile!.dnsResolver),
                const Text('使用此账号保存的自定义解析器'),
              ] else if (snapshot.dnsResolvers.isNotEmpty) ...[
                for (final resolver in snapshot.dnsResolvers)
                  _copyable(context, resolver),
              ] else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    '未配置全局解析器，跟随当前网络',
                    style: TextStyle(color: Colors.blueGrey),
                  ),
                ),
              if (controller.profile?.exitNodeId.isNotEmpty == true)
                const Text('当前使用出口节点提供的公网解析，以上为已保存的 DNS 配置。'),
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
              for (final route in snapshot.dnsRoutes.entries) ...[
                const SizedBox(height: 24),
                Text('分流域：${route.key}'),
                if (route.value.isEmpty)
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('本机解析'),
                  )
                else
                  for (final resolver in route.value)
                    _copyable(context, resolver),
              ],
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () =>
                    controller.perform(controller.gateway.openConsole),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('前往用户中心管理 DNS'),
              ),
            ],
            TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => SystemDiagnosticsPage(controller: controller),
                ),
              ),
              icon: const Icon(Icons.health_and_safety_outlined),
              label: const Text('检查系统私人 DNS'),
            ),
            if (controller.error != null)
              Text(
                controller.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
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
            .showSnackBar(const SnackBar(content: Text('已复制')));
      }
    },
  );
}
