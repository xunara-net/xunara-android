import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../models.dart';
import 'profile_editor.dart';
import 'auth_key_sheet.dart';

class ConnectPage extends StatelessWidget {
  const ConnectPage({required this.controller, super.key});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot;
    final phase = snapshot.phase;
    final connected = phase == ConnectionPhase.connected;
    final primary = Theme.of(context).colorScheme.primary;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: connected ? primary : Colors.blueGrey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        phase.label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const Icon(
                      Icons.lock_outline_rounded,
                      size: 18,
                      color: Colors.blueGrey,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  connected ? '让远方设备，像在身边' : '随时回到你的私有网络',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(
                  phase == ConnectionPhase.disconnected
                      ? '一键连接电脑、NAS 和服务器\n仅接管私有网络，不影响日常上网'
                      : snapshot.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.blueGrey, height: 1.5),
                ),
                const SizedBox(height: 24),
                if (!snapshot.authorizationAvailable)
                  Semantics(
                    button: true,
                    label: connected ? '断开私有网络' : '连接私有网络',
                    child: SizedBox(
                      width: 144,
                      height: 144,
                      child: FilledButton(
                        key: const Key('connect-button'),
                        style: FilledButton.styleFrom(
                          shape: const CircleBorder(),
                          backgroundColor: connected
                              ? primary
                              : const Color(0xFF143C43),
                        ),
                        onPressed:
                            controller.busy || phase == ConnectionPhase.stopping
                            ? null
                            : phase.active
                            ? () => _disconnect(context)
                            : controller.connect,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (controller.busy ||
                                phase == ConnectionPhase.connecting ||
                                phase == ConnectionPhase.stopping)
                              const SizedBox(
                                width: 32,
                                height: 32,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            else
                              Icon(
                                connected
                                    ? Icons.power_settings_new_rounded
                                    : Icons.link_rounded,
                                size: 36,
                              ),
                            const SizedBox(height: 8),
                            Text(
                              phase.active ? '断开连接' : '连接网络',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
                if (snapshot.authorizationAvailable) ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('authorize-button'),
                      onPressed: controller.busy
                          ? null
                          : () => controller.perform(
                              controller.gateway.openAuthorization,
                            ),
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('前往浏览器登录并授权'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: controller.busy
                        ? null
                        : () => _disconnect(context),
                    child: const Text('取消本次连接'),
                  ),
                  const Text(
                    '已有账号直接登录，新用户在网页登录注册。\n完成后返回此处，无需复制任何验证码。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.blueGrey,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ] else if (!phase.active)
                  TextButton(
                    key: const Key('auth-key-option'),
                    onPressed: controller.busy ? null : () => _withKey(context),
                    child: const Text('使用接入密钥加入'),
                  ),
              ],
            ),
          ),
        ),
        if (controller.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _notice(
              controller.error!,
              Icons.error_outline_rounded,
              Colors.red.shade700,
            ),
          ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 4,
            ),
            leading: const Icon(Icons.dns_outlined),
            title: Text(
              controller.profile!.hostname,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              controller.profile!.displayServer,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: phase.active
                ? const Icon(Icons.check_circle_outline, size: 20)
                : const Icon(Icons.chevron_right_rounded),
            onTap: phase.active
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ProfileEditor(controller: controller),
                    ),
                  ),
          ),
        ),
        if (connected) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '本机网络地址',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  for (final address in snapshot.addresses)
                    InkWell(
                      onTap: () => _copy(context, addressOnly(address)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                addressOnly(address),
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const Icon(Icons.copy_rounded, size: 16),
                          ],
                        ),
                      ),
                    ),
                  const Divider(height: 24),
                  Wrap(
                    spacing: 20,
                    runSpacing: 12,
                    children: [
                      Text('可见设备  ${snapshot.devices.length}'),
                      Text('接收  ${formatBytes(snapshot.bytesReceived)}'),
                      Text('发送  ${formatBytes(snapshot.bytesSent)}'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        if (snapshot.skippedRoutes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: _notice(
              '已保留本地局域网，跳过冲突路由：${snapshot.skippedRoutes.join('、')}',
              Icons.info_outline,
              Colors.orange.shade800,
            ),
          ),
        const SizedBox(height: 18),
        const Text(
          '首次连接需允许系统 VPN 权限。设备审批、访问权限由所属网络管理；账号登录不会自动授予设备访问权。',
          style: TextStyle(fontSize: 12, height: 1.6, color: Colors.blueGrey),
        ),
      ],
    );
  }

  Widget _notice(String message, IconData icon, Color color) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .06),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message, style: TextStyle(color: color, height: 1.5)),
        ),
      ],
    ),
  );

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已复制网络地址')));
    }
  }

  Future<void> _disconnect(BuildContext context) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('断开私有网络？'),
        content: const Text('断开后无法访问远程设备，日常上网不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续连接'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('断开'),
          ),
        ],
      ),
    );
    if (approved == true) await controller.disconnect();
  }

  Future<void> _withKey(BuildContext context) async {
    final key = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => const AuthKeySheet(),
    );
    if (key != null && key.isNotEmpty && context.mounted) {
      await controller.connect(authKey: key);
    }
  }
}
