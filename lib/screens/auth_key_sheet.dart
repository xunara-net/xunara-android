import 'package:flutter/material.dart';

class AuthKeySheet extends StatefulWidget {
  const AuthKeySheet({super.key});
  @override
  State<AuthKeySheet> createState() => _AuthKeySheetState();
}

class _AuthKeySheetState extends State<AuthKeySheet> {
  final _key = TextEditingController();
  @override
  void dispose() {
    // 控制器由弹层自身持有，在退场动画结束后清除；不进入应用配置或业务状态。
    _key.clear();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      24,
      0,
      24,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '使用接入密钥',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        const Text(
          '在用户中心创建设备接入密钥后粘贴到这里。\n密钥仅用于此次连接，不会保存到手机。',
          style: TextStyle(color: Colors.blueGrey, height: 1.5),
        ),
        const SizedBox(height: 20),
        TextField(
          key: const Key('auth-key-field'),
          controller: _key,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          maxLength: 4096,
          decoration: const InputDecoration(labelText: '接入密钥', counterText: ''),
          autofillHints: null,
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () {
            final value = _key.text.trim();
            if (value.isNotEmpty) {
              Navigator.pop(context, value);
            }
          },
          child: const Text('安全加入网络'),
        ),
      ],
    ),
  );
}
