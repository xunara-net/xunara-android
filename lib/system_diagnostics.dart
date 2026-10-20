import 'models.dart';

class InstalledApplication {
  const InstalledApplication({
    required this.packageName,
    required this.label,
    this.installed = true,
  });
  factory InstalledApplication.fromJson(Map<String, dynamic> json) =>
      InstalledApplication(
        packageName: json['package'] as String,
        label: json['label'] as String,
        installed: json['installed'] as bool,
      );
  final String packageName;
  final String label;
  final bool installed;
}

class SystemDiagnostics {
  const SystemDiagnostics({
    required this.androidSdk,
    required this.androidVersion,
    required this.appVersion,
    required this.coreVersion,
    required this.vpnPermission,
    required this.notificationsEnabled,
    required this.batteryUnrestricted,
    required this.backgroundRestricted,
    this.privateDnsActive,
    this.privateDnsStrict,
  });
  factory SystemDiagnostics.fromJson(Map<String, dynamic> json) =>
      SystemDiagnostics(
        androidSdk: json['android_sdk'] as int,
        androidVersion: json['android_version'] as String,
        appVersion: json['app_version'] as String,
        coreVersion: json['core_version'] as String,
        vpnPermission: json['vpn_permission'] as bool,
        notificationsEnabled: json['notifications_enabled'] as bool,
        batteryUnrestricted: json['battery_unrestricted'] as bool,
        backgroundRestricted: json['background_restricted'] as bool,
        privateDnsActive: json['private_dns_active'] as bool?,
        privateDnsStrict: json['private_dns_strict'] as bool?,
      );
  final int androidSdk;
  final String androidVersion;
  final String appVersion;
  final String coreVersion;
  final bool vpnPermission;
  final bool notificationsEnabled;
  final bool batteryUnrestricted;
  final bool backgroundRestricted;
  final bool? privateDnsActive;
  final bool? privateDnsStrict;

  String get privateDnsDescription => privateDnsStrict == true
      ? '严格私人 DNS 可能绕过网络 DNS；请到系统网络设置检查'
      : privateDnsActive == true
      ? '系统加密 DNS 已启用，应用自带 DoH 仍需在应用内设置'
      : privateDnsActive == false
      ? '当前未检测到系统私人 DNS；不代表应用自带 DoH 已关闭'
      : '系统未提供私人 DNS 状态，请手动检查';

  String report(VpnSnapshot snapshot, ClientProfile profile) => [
    '玄序 Android 连接诊断',
    '应用 $appVersion · 内核 $coreVersion',
    'Android $androidVersion · SDK $androidSdk',
    '连接状态：${snapshot.phase.label}',
    '底层网络：${snapshot.networkLabel.isEmpty ? '尚未观察到' : snapshot.networkLabel}',
    '系统 VPN 权限：${vpnPermission ? '已允许' : '待允许'}',
    '状态通知：${notificationsEnabled ? '已开启' : '未开启'}',
    '电池优化：${batteryUnrestricted ? '不受优化限制' : '由系统管理'}',
    '后台限制：${backgroundRestricted ? '受限制' : '未限制'}',
    '私人 DNS：$privateDnsDescription',
    '应用分流：${profile.appRouting.label} · 已选择 ${profile.applications.length} 个',
    '远程子网：${profile.acceptRoutes ? '接收已批准路由' : '关闭'}',
    '切网重连：${profile.autoReconnect ? '开启' : '关闭'}',
    '连接代次：${snapshot.generation} · 本次自动重连 ${snapshot.reconnects} 次',
    '使用其他出口：${profile.exitNodeId.isEmpty ? '未选择' : '已选择'} · 本次出口条件${snapshot.exitNodeAvailable ? '匹配，不代表已出网' : '未确认匹配'}',
    '网络 DNS：${profile.acceptDns ? '已保存开启' : '未单独开启'} · 内核 DNS ${snapshot.dnsActive ? '已启用' : '未报告启用'}',
    '本机提供出口：${profile.advertiseExit ? '已请求' : '未请求'} · 本次转发${snapshot.forwardingActive ? '已启用' : '未报告启用'}',
    '可见设备：${snapshot.devices.length} · 跳过冲突路由：${snapshot.skippedRoutes.length}',
    '发送 ${formatBytes(snapshot.bytesSent)} · 接收 ${formatBytes(snapshot.bytesReceived)}',
    if (snapshot.packetCounters == null)
      '数据包统计：内核未提供有效统计，不按零丢包处理'
    else ...[
      '本次连接累计数据包统计（不等于业务验收）：',
      for (final counter in packetCounterLabels.entries)
        if (snapshot.packetCounters!.containsKey(counter.key))
          '${counter.value}：${snapshot.packetCounters![counter.key]}',
    ],
    '未导出服务器地址、设备名称、IP、应用清单、授权链接或密钥。',
    '这是本机状态摘要，不代表已验证服务器或业务端口连通。',
  ].join('\n');
}
