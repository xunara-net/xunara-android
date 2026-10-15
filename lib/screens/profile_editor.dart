import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models.dart';

class ProfileEditor extends StatefulWidget {
  const ProfileEditor({required this.controller, super.key});
  final AppController controller;
  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  final _form = GlobalKey<FormState>();
  late final _server = TextEditingController(
    text: widget.controller.profile!.server,
  );
  late final _hostname = TextEditingController(
    text: widget.controller.profile!.hostname,
  );
  late bool _routes = widget.controller.profile!.acceptRoutes;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _server.dispose();
    _hostname.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('网络设置')),
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
              '只需服务器地址，不需要填写网络标识。登录后设备将加入你实际授权的账号。',
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
              decoration: const InputDecoration(
                labelText: '服务器地址',
                hintText: 'https://your-server.example.com',
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
            const Text(
              '本版本不接管默认出口，不更改手机 DNS。Android 作为子网访问端使用，不在手机上开启需要 root 的转发。',
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
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '正在保存' : '保存设置'),
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
      ClientProfile(
        server: _server.text.trim(),
        hostname: _hostname.text.trim(),
        acceptRoutes: _routes,
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
