import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models.dart';

class ProfileEditor extends StatefulWidget {
  const ProfileEditor({
    required this.controller,
    this.newServer = false,
    this.initialServer = '',
    super.key,
  });
  final AppController controller;
  final bool newServer;
  final String initialServer;
  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  final _form = GlobalKey<FormState>();
  late final _base = widget.newServer
      ? ClientProfile(
          server: widget.initialServer,
          hostname: widget.controller.profile!.hostname,
        )
      : widget.controller.profile!;
  late final _server = TextEditingController(text: _base.server);
  late final _hostname = TextEditingController(text: _base.hostname);
  late final _label = TextEditingController(text: _base.label);
  late bool _routes = _base.acceptRoutes;
  late bool _reconnect = _base.autoReconnect;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _server.dispose();
    _hostname.dispose();
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.newServer ? '添加账号 / 控制器' : '账号连接设置')),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '正在保存' : '保存设置'),
        ),
      ),
    ),
    body: SafeArea(
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              '连接到哪里',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              '同一控制器可以添加多个账号，每项独立授权并保存设备身份。备注仅供区分，不代表已登录的账号。',
              style: TextStyle(color: Colors.blueGrey, height: 1.6),
            ),
            const SizedBox(height: 24),
            TextFormField(
              key: const Key('server-field'),
              controller: _server,
              validator: ClientProfile.validateServer,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              readOnly: !widget.newServer && _base.id.isNotEmpty,
              decoration: InputDecoration(
                labelText: '服务器地址',
                hintText: 'https://your-server.example.com',
                helperText: !widget.newServer && _base.id.isNotEmpty
                    ? '更换地址请在账号列表添加控制器，原身份不会被转移'
                    : null,
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              key: const Key('profile-label-field'),
              controller: _label,
              maxLength: 48,
              decoration: const InputDecoration(
                labelText: '账号备注',
                hintText: '例如：个人账号、公司账号',
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              key: const Key('hostname-field'),
              controller: _hostname,
              validator: ClientProfile.validateHostname,
              autocorrect: false,
              decoration: const InputDecoration(labelText: '本机设备名'),
            ),
            const SizedBox(height: 24),
            Card(
              child: SwitchListTile(
                title: const Text('访问远程子网'),
                subtitle: const Text('接收网络管理员已批准的子网路由，冲突时保留本地局域网'),
                value: _routes,
                onChanged: (value) => setState(() => _routes = value),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: SwitchListTile(
                key: const Key('auto-reconnect-switch'),
                title: const Text('网络恢复后自动重连'),
                subtitle: const Text('切换 Wi-Fi / 移动网络后重新检查局域网；主动断开不会自行连接'),
                value: _reconnect,
                onChanged: (value) => setState(() => _reconnect = value),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '默认仅连接私有网络，DNS 与出口节点可在设置中单独开启。更换控制地址请新增配置，避免混用设备身份。',
              style: TextStyle(
                fontSize: 12,
                color: Colors.blueGrey,
                height: 1.6,
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final saved = await widget.controller.save(
      _base.copyWith(
        server: _server.text.trim(),
        hostname: _hostname.text.trim(),
        acceptRoutes: _routes,
        autoReconnect: _reconnect,
        label: _label.text.trim(),
      ),
    );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _error = widget.controller.error;
      });
    }
  }
}
