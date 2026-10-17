import 'dart:io';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models.dart';

class DnsResolverPage extends StatefulWidget {
  const DnsResolverPage({required this.controller, super.key});
  final AppController controller;

  @override
  State<DnsResolverPage> createState() => _DnsResolverPageState();
}

class _DnsResolverPageState extends State<DnsResolverPage> {
  final form = GlobalKey<FormState>();
  late final ClientProfile original;
  late final TextEditingController resolver;
  late final TextEditingController bootstrap;
  late bool validateDnssec;

  @override
  void initState() {
    super.initState();
    original = widget.controller.profile!;
    resolver = TextEditingController(text: original.dnsResolver);
    bootstrap = TextEditingController(text: original.dnsBootstrap.join('\n'));
    validateDnssec = original.validateDnssec;
  }

  @override
  void dispose() {
    resolver.dispose();
    bootstrap.dispose();
    super.dispose();
  }

  List<String> get addresses => bootstrap.text
      .split(RegExp(r'[\s,，]+'))
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList();

  String? validateResolver(String? value) {
    final address = value?.trim() ?? '';
    if (address.isEmpty) return null;
    if (address.length > 2048) return '解析器地址过长';
    if (InternetAddress.tryParse(address) != null) return null;
    final encrypted =
        address.startsWith('https://') || address.startsWith('tls://');
    final uri = Uri.tryParse(encrypted ? address : 'dns://$address');
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.hasPort && (uri.port < 1 || uri.port > 65535))) {
      return '填写不含凭据的 IP、IP:端口、https:// 或 tls:// 地址';
    }
    if ((!encrypted || uri.scheme == 'tls') &&
        uri.path.isNotEmpty &&
        uri.path != '/') {
      return '此类型只填写主机和端口';
    }
    if (InternetAddress.tryParse(uri.host) == null) {
      if (!encrypted) return '普通解析器必须使用 IP';
      if (addresses.isEmpty) return '域名形式的加密解析器需要填写引导 IP';
    }
    return null;
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
    final saved = await controller.applyNetworkSettings(
      current.copyWith(
        dnsResolver: resolver.text.trim(),
        dnsBootstrap: addresses,
        validateDnssec: validateDnssec,
      ),
    );
    if (mounted && saved) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final editable =
          !controller.busy &&
          controller.profile?.id == original.id &&
          {
            ConnectionPhase.disconnected,
            ConnectionPhase.error,
            ConnectionPhase.connected,
          }.contains(controller.snapshot.phase);
      return Scaffold(
        appBar: AppBar(title: const Text('解析器与 DNSSEC')),
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
                if (controller.profile?.id != original.id)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text('当前账号已变化，请返回后重新打开 DNS 设置。'),
                  ),
                const Text(
                  '为空时跟随网络配置；只覆盖普通域名的默认解析，保留 MagicDNS 与分流规则。使用出口时由出口提供解析，自定义地址不会偷偷直连。',
                  style: TextStyle(height: 1.7),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('跟随网络'),
                      onPressed: editable
                          ? () => setState(() {
                              resolver.clear();
                              bootstrap.clear();
                            })
                          : null,
                    ),
                    ActionChip(
                      label: const Text('Cloudflare DoH'),
                      onPressed: editable
                          ? () => setState(() {
                              resolver.text =
                                  'https://cloudflare-dns.com/dns-query';
                              bootstrap.text = '1.1.1.1\n1.0.0.1';
                            })
                          : null,
                    ),
                    ActionChip(
                      label: const Text('Cloudflare DoT'),
                      onPressed: editable
                          ? () => setState(() {
                              resolver.text = 'tls://one.one.one.one';
                              bootstrap.text = '1.1.1.1\n1.0.0.1';
                            })
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: resolver,
                  enabled: editable,
                  maxLength: 2048,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: '默认解析器',
                    hintText: 'https://dns.example.com/dns-query',
                    helperText: '支持 IP / IP:端口 / DoH / DoT',
                  ),
                  validator: validateResolver,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: bootstrap,
                  enabled: editable,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 200,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: '引导 IP',
                    helperText: '加密解析器使用域名时必填；最多四个，换行或逗号分隔',
                    helperMaxLines: 2,
                  ),
                  validator: (_) =>
                      addresses.length > 4 ||
                          addresses.any(
                            (address) =>
                                address.contains('%') ||
                                InternetAddress.tryParse(address) == null,
                          )
                      ? '填写最多四个有效 IP，不要填写域名'
                      : null,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: validateDnssec,
                  onChanged: editable
                      ? (value) => setState(() {
                          validateDnssec = value;
                        })
                      : null,
                  title: const Text('本机验证 DNSSEC'),
                  subtitle: const Text(
                    '独立校验签名和信任链，不信任上游 AD 标志。签名错误返回失败；未签名区域不显示为安全。非公开分流区可能无法验证。',
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  controller.profile?.acceptDns == true ||
                          controller.profile?.exitNodeId.isNotEmpty == true
                      ? '保存后会短暂重建连接，不会更换机器身份。'
                      : '配置先保存；在上一页开启网络 DNS 后才生效。',
                  style: const TextStyle(color: Colors.blueGrey),
                ),
                if (controller.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      controller.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
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
