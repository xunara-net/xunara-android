enum ConnectionPhase {
  disconnected,
  connecting,
  authorizing,
  connected,
  reconnecting,
  stopping,
  error;

  bool get active => this != disconnected && this != error;
  String get label => switch (this) {
    disconnected => '尚未连接',
    connecting => '正在连接',
    authorizing => '等待设备授权',
    connected => '已安全连接',
    reconnecting => '正在重连',
    stopping => '正在断开',
    error => '连接未完成',
  };
}

enum AppRoutingMode {
  all('全部应用'),
  exclude('排除所选应用'),
  only('仅所选应用');

  const AppRoutingMode(this.label);
  final String label;
  static AppRoutingMode parse(String value) => values.firstWhere(
    (mode) => mode.name == value,
    orElse: () => throw const FormatException('应用分流方式无效'),
  );
}

class ClientProfile {
  const ClientProfile({
    required this.server,
    required this.hostname,
    this.acceptRoutes = true,
    this.autoReconnect = true,
    this.appRouting = AppRoutingMode.all,
    this.applications = const [],
    this.id = '',
    this.label = '',
    this.acceptDns = false,
    this.exitNodeId = '',
    this.exitNodeName = '',
    this.dnsResolver = '',
    this.dnsBootstrap = const [],
    this.validateDnssec = false,
    this.advertiseRoutes = const [],
    this.advertiseExit = false,
  });
  factory ClientProfile.fromJson(Map<String, dynamic> json) => ClientProfile(
    server: json['server'] as String? ?? '',
    hostname: json['hostname'] as String? ?? 'android',
    acceptRoutes: json['accept_routes'] as bool? ?? true,
    autoReconnect: json['auto_reconnect'] as bool? ?? true,
    appRouting: AppRoutingMode.parse(json['app_routing'] as String? ?? 'all'),
    applications: (json['applications'] as List? ?? []).cast<String>(),
    id: json['id'] as String? ?? '',
    label: json['label'] as String? ?? '',
    acceptDns: json['accept_dns'] as bool? ?? false,
    exitNodeId: json['exit_node_id'] as String? ?? '',
    exitNodeName: json['exit_node_name'] as String? ?? '',
    dnsResolver: json['dns_resolver'] as String? ?? '',
    dnsBootstrap: (json['dns_bootstrap'] as List? ?? []).cast<String>(),
    validateDnssec: json['dnssec_validate'] as bool? ?? false,
    advertiseRoutes: (json['advertise_routes'] as List? ?? []).cast<String>(),
    advertiseExit: json['advertise_exit'] as bool? ?? false,
  );

  final String server;
  final String hostname;
  final bool acceptRoutes;
  final bool autoReconnect;
  final AppRoutingMode appRouting;
  final List<String> applications;
  final String id;
  final String label;
  final bool acceptDns;
  final String exitNodeId;
  final String exitNodeName;
  final String dnsResolver;
  final List<String> dnsBootstrap;
  final bool validateDnssec;
  final List<String> advertiseRoutes;
  final bool advertiseExit;
  String get displayLabel => label.isEmpty ? displayServer : label;
  String get displayServer => Uri.tryParse(server)?.authority ?? server;
  Map<String, dynamic> toJson() => {
    'server': server,
    'hostname': hostname,
    'accept_routes': acceptRoutes,
    'auto_reconnect': autoReconnect,
    'app_routing': appRouting.name,
    'applications': applications,
    'id': id,
    'label': label,
    'accept_dns': acceptDns,
    'exit_node_id': exitNodeId,
    'exit_node_name': exitNodeName,
    'dns_resolver': dnsResolver,
    'dns_bootstrap': dnsBootstrap,
    'dnssec_validate': validateDnssec,
    'advertise_routes': advertiseRoutes,
    'advertise_exit': advertiseExit,
  };

  ClientProfile copyWith({
    String? server,
    String? hostname,
    bool? acceptRoutes,
    bool? autoReconnect,
    AppRoutingMode? appRouting,
    List<String>? applications,
    String? id,
    String? label,
    bool? acceptDns,
    String? exitNodeId,
    String? exitNodeName,
    String? dnsResolver,
    List<String>? dnsBootstrap,
    bool? validateDnssec,
    List<String>? advertiseRoutes,
    bool? advertiseExit,
  }) => ClientProfile(
    server: server ?? this.server,
    hostname: hostname ?? this.hostname,
    acceptRoutes: acceptRoutes ?? this.acceptRoutes,
    autoReconnect: autoReconnect ?? this.autoReconnect,
    appRouting: appRouting ?? this.appRouting,
    applications: applications ?? this.applications,
    id: id ?? this.id,
    label: label ?? this.label,
    acceptDns: acceptDns ?? this.acceptDns,
    exitNodeId: exitNodeId ?? this.exitNodeId,
    exitNodeName: exitNodeName ?? this.exitNodeName,
    dnsResolver: dnsResolver ?? this.dnsResolver,
    dnsBootstrap: dnsBootstrap ?? this.dnsBootstrap,
    validateDnssec: validateDnssec ?? this.validateDnssec,
    advertiseRoutes: advertiseRoutes ?? this.advertiseRoutes,
    advertiseExit: advertiseExit ?? this.advertiseExit,
  );

  static String? validateServer(String? raw) {
    final uri = Uri.tryParse(raw?.trim() ?? '');
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
      return '请输入完整服务器地址';
    }
    final local = {'localhost', '127.0.0.1', '::1'}.contains(uri.host);
    if (uri.scheme != 'https' && !(uri.scheme == 'http' && local)) {
      return '请使用 HTTPS，避免泄露设备身份';
    }
    if (uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      return '只需服务器根地址，不要带 /login 等路径';
    }
    if (uri.port < 1 || uri.port > 65535) return '服务器端口无效';
    return null;
  }

  static String? validateHostname(String? value) =>
      RegExp(r'^[a-zA-Z0-9-]{1,63}$').hasMatch(value ?? '')
      ? null
      : '请输入 1–63 位字母、数字或连字符';
}

class NetworkDevice {
  const NetworkDevice({
    required this.id,
    required this.name,
    required this.addresses,
    required this.path,
    required this.relayRegion,
    this.relayName = '',
    this.os = '',
    this.keyExpiry,
    this.routes = const [],
    this.stableId = '',
    this.exitNode = false,
    this.online,
    this.lastSeen,
  });
  factory NetworkDevice.fromJson(Map<String, dynamic> json) => NetworkDevice(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '未命名设备',
    addresses: (json['addresses'] as List? ?? []).cast<String>(),
    path: json['path'] as String? ?? '',
    relayRegion: (json['relay_region'] as num?)?.toInt() ?? 0,
    relayName: json['relay_name'] as String? ?? '',
    os: json['os'] as String? ?? '',
    keyExpiry: json['key_expiry'] as String?,
    routes: (json['routes'] as List? ?? []).cast<String>(),
    stableId: json['stable_id'] as String? ?? '',
    exitNode: json['exit_node'] as bool? ?? false,
    online: json['online'] is bool ? json['online'] as bool : null,
    lastSeen: json['last_seen'] is String ? json['last_seen'] as String : null,
  );
  final String id;
  final String name;
  final List<String> addresses;
  final String path;
  final int relayRegion;
  final String relayName;
  final String os;
  final String? keyExpiry;
  final List<String> routes;
  final String stableId;
  final bool exitNode;
  final bool? online;
  final String? lastSeen;
  String get onlineLabel => switch (online) {
    true => '在线',
    false => '离线',
    null => '状态未知',
  };
  bool get shared => stableId.startsWith('share:');
  String get displayName => name.replaceFirst(RegExp(r'\.$'), '');
  String get pathLabel => path == 'direct' ? '直连已探测' : '中继候选';
}

class PingResult {
  const PingResult({
    required this.address,
    required this.rttMs,
    required this.path,
    this.relayRegion = 0,
  });
  factory PingResult.fromJson(Map<String, dynamic> json) {
    final milliseconds = (json['rtt_ms'] as num).toDouble();
    if (!milliseconds.isFinite ||
        milliseconds < 0 ||
        !{'direct', 'relay'}.contains(json['path'])) {
      throw const FormatException('检测结果无效');
    }
    return PingResult(
      address: json['address'] as String,
      rttMs: milliseconds,
      path: json['path'] as String,
      relayRegion: (json['relay_region'] as num?)?.toInt() ?? 0,
    );
  }
  final String address;
  final double rttMs;
  final String path;
  final int relayRegion;
  String get pathLabel => path == 'direct' ? 'UDP 直连' : 'DERP 中继';
}

const packetCounterLabels = {
  'tun_packets': 'VPN 发出包',
  'tun_source_drops': '本机来源不匹配丢弃',
  'dns_queries': 'VPN DNS 数据包（含 TCP 控制包）',
  'encrypted_packets': '收到加密包',
  'decoded_packets': '成功解密包',
  'decrypt_errors': '解密失败',
  'invalid_packets': '无效包丢弃',
  'source_drops': '对端来源不匹配丢弃',
  'destination_drops': '目标不匹配丢弃',
  'acl_drops': '访问策略丢弃',
  'related_icmp': '已关联连接的 ICMP 控制回包',
  'untracked_exit_drops': '出口回包未匹配有效连接',
};

Map<String, int>? _parsePacketCounters(Object? raw) {
  return _parseCounters(raw, packetCounterLabels.keys);
}

const dnsCounterLabels = {
  'queries': '实际 DNS 请求',
  'responses': 'DNS 已生成响应',
  'servfail': 'DNS 服务器失败响应',
  'peer_queries': '其他设备经本机出口的 DNS 查询',
  'peer_responses': '本机出口生成的 DNS 响应',
  'peer_servfail': '本机出口 DNS 失败响应',
  'nxdomain': 'DNS 无此域名响应',
  'timeouts': 'DNS 上游超时次数',
  'connect_timeouts': 'DNS 上游建连超时',
  'response_timeouts': 'DNS 上游响应超时',
  'upstream_closed': 'DNS 上游提前关闭',
  'invalid_responses': 'DNS 上游无效响应',
};

Map<String, int>? _parseCounters(Object? raw, Iterable<String> names) {
  if (raw is! Map) return null;
  final counters = <String, int>{};
  // 诊断只接收固定名称的非负整数，不能把任意内核字段或日志带入可复制报告。
  for (final key in names) {
    if (!raw.containsKey(key)) continue;
    final value = raw[key];
    if (value is! int || value < 0) return null;
    counters[key] = value;
  }
  return counters.isEmpty ? null : Map.unmodifiable(counters);
}

class VpnSnapshot {
  const VpnSnapshot({
    this.phase = ConnectionPhase.disconnected,
    this.message = '',
    this.authorizationAvailable = false,
    this.addresses = const [],
    this.devices = const [],
    this.bytesReceived = 0,
    this.bytesSent = 0,
    this.directPeers = 0,
    this.skippedRoutes = const [],
    this.generation = 0,
    this.networkLabel = '',
    this.reconnects = 0,
    this.selfName = '',
    this.keyExpiry,
    this.magicDnsEnabled = false,
    this.searchDomains = const [],
    this.dnsResolvers = const [],
    this.dnsRoutes = const {},
    this.dnsActive = false,
    this.dnsAddress = '',
    this.dnssecActive = false,
    this.exitNodeAvailable = false,
    this.exitNodeOnline,
    this.ownerLogin = '',
    this.forwardingActive = false,
    this.forwardingApproved = const [],
    this.forwardingFlows = 0,
    this.packetCounters,
    this.dnsCounters,
    this.homeRelayRegion,
  });
  factory VpnSnapshot.fromJson(Map<String, dynamic> json) {
    final status = json['status'] as Map<String, dynamic>? ?? {};
    final dns = status['dns'] as Map<String, dynamic>? ?? {};
    final forwarding = status['forwarding'] as Map<String, dynamic>? ?? {};
    final exit = status['exit_node'] as Map<String, dynamic>? ?? {};
    return VpnSnapshot(
      phase: ConnectionPhase.values.firstWhere(
        (phase) => phase.name == json['phase'],
        orElse: () => ConnectionPhase.error,
      ),
      message: json['message'] as String? ?? '',
      // URL 只留在原生层内存中；Flutter 只获得是否能打开授权页面。
      authorizationAvailable:
          (json['authorization_url'] as String? ?? '').isNotEmpty,
      addresses: (status['addresses'] as List? ?? []).cast<String>(),
      devices: (status['devices'] as List? ?? [])
          .map(
            (device) => NetworkDevice.fromJson(
              Map<String, dynamic>.from(device as Map),
            ),
          )
          .toList(),
      bytesReceived: (status['bytes_received'] as num?)?.toInt() ?? 0,
      bytesSent: (status['bytes_sent'] as num?)?.toInt() ?? 0,
      directPeers: (status['direct_peers'] as num?)?.toInt() ?? 0,
      skippedRoutes: (json['skipped_routes'] as List? ?? []).cast<String>(),
      generation: (json['generation'] as num?)?.toInt() ?? 0,
      networkLabel: json['network_label'] as String? ?? '',
      reconnects: (json['reconnects'] as num?)?.toInt() ?? 0,
      selfName: status['self_name'] as String? ?? '',
      keyExpiry: status['key_expiry'] as String?,
      magicDnsEnabled: dns['enabled'] as bool? ?? false,
      searchDomains: (dns['domains'] as List? ?? []).cast<String>(),
      dnsResolvers: List.unmodifiable(
        (dns['resolvers'] as List? ?? []).whereType<String>(),
      ),
      dnsRoutes: Map.unmodifiable({
        for (final entry in (dns['routes'] as Map? ?? {}).entries)
          if (entry.key is String && entry.value is List)
            entry.key as String: List<String>.unmodifiable(
              (entry.value as List).whereType<String>(),
            ),
      }),
      dnsActive: dns['active'] as bool? ?? false,
      dnsAddress: dns['address'] as String? ?? '',
      dnssecActive: dns['dnssec_validate'] as bool? ?? false,
      exitNodeAvailable: exit['available'] as bool? ?? false,
      exitNodeOnline: exit['online'] is bool ? exit['online'] as bool : null,
      ownerLogin: status['owner_login'] as String? ?? '',
      forwardingActive: forwarding['active'] as bool? ?? false,
      forwardingApproved: (forwarding['approved'] as List? ?? [])
          .cast<String>(),
      forwardingFlows: forwarding['flows'] as int? ?? 0,
      packetCounters: _parsePacketCounters(status['receive_stats']),
      dnsCounters: _parseCounters(dns['statistics'], dnsCounterLabels.keys),
      homeRelayRegion: _parseHomeRelayRegion(status['relay']),
    );
  }
  final ConnectionPhase phase;
  final String message;
  final bool authorizationAvailable;
  final List<String> addresses;
  final List<NetworkDevice> devices;
  final int bytesReceived;
  final int bytesSent;
  final int directPeers;
  final List<String> skippedRoutes;
  final int generation;
  final String networkLabel;
  final int reconnects;
  final String selfName;
  final String? keyExpiry;
  final bool magicDnsEnabled;
  final List<String> searchDomains;
  final List<String> dnsResolvers;
  final Map<String, List<String>> dnsRoutes;
  final bool dnsActive;
  final String dnsAddress;
  final bool dnssecActive;
  final bool exitNodeAvailable;
  final bool? exitNodeOnline;
  final String ownerLogin;
  final bool forwardingActive;
  final List<String> forwardingApproved;
  final int forwardingFlows;
  final Map<String, int>? packetCounters;
  final Map<String, int>? dnsCounters;
  final int? homeRelayRegion;
}

int? _parseHomeRelayRegion(dynamic raw) {
  if (raw is! Map) return null;
  final region = raw['home_region'];
  final connected = raw['connected'];
  if (region is! int ||
      region < 0 ||
      region > 65535 ||
      connected is! bool ||
      connected != (region > 0)) {
    return null;
  }
  return region;
}

String expiryLabel(String? raw) {
  final expiry = raw == null ? null : DateTime.tryParse(raw);
  if (expiry == null) return '服务器未提供';
  if (expiry.year <= 1) return '不自动过期';
  return _localTime(expiry);
}

String lastSeenLabel(String? raw) {
  final seen = raw == null ? null : DateTime.tryParse(raw);
  return seen == null || seen.year <= 1 ? '服务器未提供' : _localTime(seen);
}

String _localTime(DateTime value) {
  final local = value.toLocal();
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${pad(local.month)}-${pad(local.day)} ${pad(local.hour)}:${pad(local.minute)}';
}

String osLabel(String os) =>
    const {
      'android': 'Android',
      'linux': 'Linux',
      'windows': 'Windows',
      'macOS': 'macOS',
      'darwin': 'macOS',
      'ios': 'iOS',
    }[os] ??
    (os.isEmpty ? '未知系统' : os);

String addressOnly(String cidr) => cidr.split('/').first;
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
