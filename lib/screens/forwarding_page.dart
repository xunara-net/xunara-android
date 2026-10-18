import 'dart:io';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models.dart';

bool validForwardingSubnet(String value) {
  final parts = value.split('/');
  if (parts.length != 2 || value.length > 49) return false;
  final address = InternetAddress.tryParse(parts[0]);
  final prefix = int.tryParse(parts[1]);
  if (address == null ||
      prefix == null ||
      address.isLoopback ||
      address.isMulticast ||
      address.isLinkLocal ||
      address.rawAddress.every((byte) => byte == 0)) {
    return false;
  }
  final bytes = address.rawAddress;
  if (bytes.length == 16 &&
      bytes.take(10).every((byte) => byte == 0) &&
      bytes[10] == 255 &&
      bytes[11] == 255) {
    return false;
  }
  if (prefix < 1 || prefix > bytes.length * 8) return false;
  for (var index = 0; index < bytes.length; index++) {
    final hostBits = (8 - (prefix - index * 8)).clamp(0, 8);
    if (bytes[index] & ((1 << hostBits) - 1) != 0) return false;
  }
  return true;
}

class ForwardingPage extends StatefulWidget {
  const ForwardingPage({required this.controller, super.key});
  final AppController controller;

  @override
  State<ForwardingPage> createState() => _ForwardingPageState();
}

class _ForwardingPageState extends State<ForwardingPage> {
  final form = GlobalKey<FormState>();
  late final original = widget.controller.profile!;
  late final subnets = TextEditingController(
    text: original.advertiseRoutes.join('\n'),
  );
  late bool exit = original.advertiseExit;
  List<String> get routes => subnets.text
      .split(RegExp(r'[\s,，]+'))
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList();

  @override
  void dispose() {
    subnets.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    final controller = widget.controller;
    final current = controller.profile;
    if (current == null ||
        current.id != original.id ||
        current.server != original.server) {
      return;
    }
    if (await controller.applyNetworkSettings(
          current.copyWith(advertiseRoutes: routes, advertiseExit: exit),
        ) &&
        mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final current = controller.profile;
      final snapshot = controller.snapshot;
      final active =
          snapshot.phase == ConnectionPhase.connected &&
          snapshot.forwardingActive;
      final changed =
          current?.id != original.id || current?.server != original.server;
      final editable =
          !changed &&
          !controller.busy &&
          {
            ConnectionPhase.connected,
            ConnectionPhase.disconnected,
            ConnectionPhase.error,
          }.contains(snapshot.phase);
      return Scaffold(
        appBar: AppBar(title: const Text('共享本机网络')),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: editable ? save : null,
              child: Text(controller.busy ? '正在应用…' : '保存并应用'),
            ),
          ),
        ),
        body: Form(
          key: form,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '把手机能访问的网络分享给其他设备',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  '无需 Root。手机以用户态代理转发 TCP、UDP 和 ICMP；不修改系统转发或防火墙。请只分享你有权管理的网络。',
                  style: TextStyle(height: 1.7),
                ),
                const SizedBox(height: 20),
                if (changed) const Text('当前账号已变化，请返回后重新打开此页面。'),
                TextFormField(
                  controller: subnets,
                  enabled: editable,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 4096,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: '转发的局域网 CIDR',
                    hintText: '192.168.1.0/24\n10.10.0.0/16',
                    helperText: '最多 64 个，换行或逗号分隔；留空表示不分享子网',
                    helperMaxLines: 2,
                  ),
                  validator: (_) =>
                      routes.length > 64 ||
                          routes.any((route) => !validForwardingSubnet(route))
                      ? '请填写规范网络 CIDR，例如 192.168.1.0/24'
                      : null,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('将本机用作出口节点'),
                  subtitle: const Text('允许获授权设备通过手机上网并使用出口 DNS，会消耗手机流量和电量。'),
                  value: exit,
                  onChanged: editable && current?.exitNodeId.isEmpty == true
                      ? (value) => setState(() => exit = value)
                      : null,
                ),
                if (current?.exitNodeId.isNotEmpty == true)
                  const Text('正在使用其他出口；请先在出口节点页面关闭，再提供本机出口。'),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          active
                              ? '转发已生效 · ${snapshot.forwardingFlows} 条连接'
                              : '设置不等于已批准',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '保存后需要在用户中心批准广播的路由，并配置访问 ACL。只有本机选择、控制面批准及 ACL 允许三者同时满足才转发；撤销后关闭旧连接。',
                        ),
                        if (active) ...[
                          const SizedBox(height: 8),
                          Text(snapshot.forwardingApproved.join('\n')),
                        ],
                        TextButton.icon(
                          onPressed: () => controller.perform(
                            controller.gateway.openConsole,
                          ),
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('前往用户中心审批'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '保存会短暂重建 VPN，沿用当前设备身份。应用分流只影响手机本地应用，不能代替远端 ACL。切网先结束旧流，再按新网络和已保存配置重建；主动断开或系统停止服务后结束转发。不监听手机物理网卡的代理端口，不转发回环、链路本地、多播或其他组网设备地址。',
                  style: TextStyle(color: Colors.blueGrey, height: 1.7),
                ),
                if (controller.error != null)
                  Text(
                    controller.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
