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

class ClientProfile {
  const ClientProfile({
    required this.server,
    required this.hostname,
    this.acceptRoutes = true,
  });
  factory ClientProfile.fromJson(Map<String, dynamic> json) => ClientProfile(
    server: json['server'] as String? ?? '',
    hostname: json['hostname'] as String? ?? 'android',
    acceptRoutes: json['accept_routes'] as bool? ?? true,
  );

  final String server;
  final String hostname;
  final bool acceptRoutes;
  String get displayServer => Uri.tryParse(server)?.authority ?? server;
  Map<String, dynamic> toJson() => {
    'server': server,
    'hostname': hostname,
    'accept_routes': acceptRoutes,
  };

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
  });
  factory NetworkDevice.fromJson(Map<String, dynamic> json) => NetworkDevice(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '未命名设备',
    addresses: (json['addresses'] as List? ?? []).cast<String>(),
    path: json['path'] as String? ?? '',
    relayRegion: (json['relay_region'] as num?)?.toInt() ?? 0,
  );
  final String id;
  final String name;
  final List<String> addresses;
  final String path;
  final int relayRegion;
  String get displayName => name.replaceFirst(RegExp(r'\.$'), '');
  String get pathLabel => path == 'direct' ? '直连已探测' : '中继候选';
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
  });
  factory VpnSnapshot.fromJson(Map<String, dynamic> json) {
    final status = json['status'] as Map<String, dynamic>? ?? {};
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
}

String addressOnly(String cidr) => cidr.split('/').first;
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
