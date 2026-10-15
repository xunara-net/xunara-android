import 'package:flutter/material.dart';

import '../app_controller.dart';
import 'connect_page.dart';
import 'devices_page.dart';
import 'settings_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({required this.controller, super.key});
  final AppController controller;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _selected = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.controller.resume();
      widget.controller.refresh();
    } else {
      widget.controller.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      return Scaffold(
        appBar: AppBar(
          title: Text(
            ['玄序 Xunara', '我的设备', '设置'][_selected],
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          actions: [
            if (_selected == 1)
              IconButton(
                onPressed: controller.refresh,
                tooltip: '刷新设备',
                icon: const Icon(Icons.refresh_rounded),
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: controller.loading
              ? const Center(child: CircularProgressIndicator())
              : controller.profile == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(controller.error ?? '无法初始化客户端'),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: controller.initialize,
                          child: const Text('重新加载'),
                        ),
                      ],
                    ),
                  ),
                )
              : IndexedStack(
                  index: _selected,
                  children: [
                    ConnectPage(controller: controller),
                    DevicesPage(controller: controller),
                    SettingsPage(controller: controller),
                  ],
                ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selected,
          onDestinationSelected: (index) => setState(() => _selected = index),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.shield_outlined),
              selectedIcon: Icon(Icons.shield_rounded),
              label: '连接',
            ),
            NavigationDestination(
              icon: Icon(Icons.devices_outlined),
              selectedIcon: Icon(Icons.devices_rounded),
              label: '设备',
            ),
            NavigationDestination(icon: Icon(Icons.tune_rounded), label: '设置'),
          ],
        ),
      );
    },
  );
}
