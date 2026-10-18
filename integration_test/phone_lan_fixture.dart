import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// 模拟器 IPv6 网关不转发到宿主回环；测试专用服务使用手机真实 LAN IPv6。
// 官方 tsnet 从隔离命名空间发包，经 WireGuard 与手机受保护 socket 到达这里。
// 此文件只编入 integration_test，不给正式 App 增加物理监听端口。
class PhoneLanFixture {
  PhoneLanFixture(this.http, this.udp);

  final HttpServer http;
  final RawDatagramSocket udp;

  static Future<PhoneLanFixture> start() async {
    final http = await HttpServer.bind(
      InternetAddress.anyIPv6,
      18088,
      v6Only: true,
    );
    try {
      final udp = await RawDatagramSocket.bind(
        InternetAddress.anyIPv6,
        18088,
        reuseAddress: false,
      );
      http.listen((request) async {
        request.response.headers.contentType = ContentType.text;
        request.response.contentLength = utf8.encode('xunara-core-ok\n').length;
        request.response.write('xunara-core-ok\n');
        await request.response.close();
      });
      udp.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = udp.receive();
        if (datagram == null || datagram.data.length < 12) return;
        final question = datagram.data;
        final response = Uint8List.fromList([
          ...question,
          0xc0,
          0x0c,
          0,
          1,
          0,
          1,
          0,
          0,
          0,
          60,
          0,
          4,
          203,
          0,
          113,
          77,
        ]);
        response[2] = 0x81;
        response[3] = 0x80;
        response[6] = 0;
        response[7] = 1;
        udp.send(response, datagram.address, datagram.port);
      });
      return PhoneLanFixture(http, udp);
    } catch (_) {
      await http.close(force: true);
      rethrow;
    }
  }

  Future<void> close() async {
    udp.close();
    await http.close(force: true);
  }
}
