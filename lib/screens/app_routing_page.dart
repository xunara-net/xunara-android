import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../models.dart';
import '../system_diagnostics.dart';

class AppRoutingPage extends StatefulWidget {
  const AppRoutingPage({required this.controller, super.key});
  final AppController controller;
  @override
  State<AppRoutingPage> createState() => _AppRoutingPageState();
}

class _AppRoutingPageState extends State<AppRoutingPage> {
  late final _server = widget.controller.profile!.server;
  late AppRoutingMode _mode = widget.controller.profile!.appRouting;
  late final _selected = widget.controller.profile!.applications.toSet();
  List<InstalledApplication> _applications = const [];
  bool _loading = true;
  String _query = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final applications = await widget.controller.gateway.applications();
      if (mounted) setState(() => _applications = applications);
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message ?? '应用清单读取失败，请重试');
    } on Exception {
      if (mounted) setState(() => _error = '应用清单读取失败，请重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final locked =
          widget.controller.busy ||
          widget.controller.snapshot.phase.active ||
          widget.controller.profile?.server != _server;
      final applications = _applications
          .where(
            (app) => '${app.label} ${app.packageName}'.toLowerCase().contains(
              _query.toLowerCase(),
            ),
          )
          .toList();
      return Scaffold(
        appBar: AppBar(title: const Text('应用分流')),
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '哪些应用能访问私有网络',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '只影响私有网络路由，日常上网和手机 DNS 不变。玄序自身始终通过底层网络连接。应用清单只在本机使用，不上传。',
                      style: TextStyle(color: Colors.blueGrey, height: 1.7),
                    ),
                    const SizedBox(height: 12),
                    RadioGroup<AppRoutingMode>(
                      groupValue: _mode,
                      onChanged: (value) {
                        if (!locked && value != null) {
                          setState(() => _mode = value);
                        }
                      },
                      child: Column(
                        children: [
                          for (final mode in AppRoutingMode.values)
                            RadioListTile<AppRoutingMode>(
                              key: Key('routing-${mode.name}'),
                              contentPadding: EdgeInsets.zero,
                              value: mode,
                              title: Text(mode.label),
                              enabled: !locked,
                            ),
                        ],
                      ),
                    ),
                    if (_mode != AppRoutingMode.all) ...[
                      TextField(
                        key: const Key('application-search'),
                        onChanged: (value) => setState(() => _query = value),
                        decoration: const InputDecoration(
                          hintText: '搜索应用名称或包名',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(child: Text('已选择 ${_selected.length} 个应用')),
                          TextButton(
                            onPressed: locked
                                ? null
                                : () => setState(_selected.clear),
                            child: const Text('清空选择'),
                          ),
                        ],
                      ),
                    ],
                    if (locked)
                      const Text(
                        '请先断开连接，且保持当前服务器不变后再保存。',
                        style: TextStyle(color: Colors.orange),
                      ),
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (!_loading && _error != null)
                      TextButton(onPressed: _load, child: const Text('重新读取应用')),
                  ],
                ),
              ),
            ),
            if (!_loading && _mode != AppRoutingMode.all)
              SliverList.builder(
                itemCount: applications.length,
                itemBuilder: (context, index) {
                  final application = applications[index];
                  final selected = _selected.contains(application.packageName);
                  return CheckboxListTile(
                    key: Key('application-${application.packageName}'),
                    title: Text(application.label),
                    subtitle: Text(
                      application.installed
                          ? application.packageName
                          : '${application.packageName} · 已卸载或不可见',
                    ),
                    value: selected,
                    onChanged: locked || (!application.installed && !selected)
                        ? null
                        : (value) => setState(() {
                            if (value == true) {
                              _selected.add(application.packageName);
                            } else {
                              _selected.remove(application.packageName);
                            }
                          }),
                  );
                },
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  _mode == AppRoutingMode.only
                      ? '仅所选模式至少保留一个已安装应用。全部所选应用卸载后会拒绝建立 VPN，不会偷偷改为全部应用。Android 按 UID 分流，共享同一 UID 的应用可能一起生效。'
                      : '默认对全部应用开放私网路由，也可以排除不希望访问私网的应用。新安装的应用在排除模式下默认可用；Android 共享 UID 的应用可能一起生效。',
                  style: const TextStyle(
                    color: Colors.blueGrey,
                    fontSize: 12,
                    height: 1.7,
                  ),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: FilledButton(
              key: const Key('save-app-routing'),
              onPressed: locked || _loading ? null : _save,
              child: Text(widget.controller.busy ? '正在保存' : '保存分流设置'),
            ),
          ),
        ),
      );
    },
  );

  Future<void> _save() async {
    if (_mode == AppRoutingMode.only &&
        !_applications.any(
          (app) => app.installed && _selected.contains(app.packageName),
        )) {
      setState(() => _error = '请至少选择一个已安装的应用');
      return;
    }
    if (widget.controller.profile?.server != _server) return;
    final saved = await widget.controller.save(
      widget.controller.profile!.copyWith(
        appRouting: _mode,
        applications: _mode == AppRoutingMode.all
            ? const []
            : (_selected.toList()..sort()),
      ),
    );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() => _error = widget.controller.error ?? '设置未能保存，请重试');
    }
  }
}
