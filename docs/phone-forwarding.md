# 手机共享子网与提供出口

手机设置中的「共享本机网络」与「使用出口节点」是不同方向：前者让获授权的远端设备通过手机访问网络，后者让手机使用另一台设备的出口。提供本机出口与使用其他出口不能同时开启，避免形成循环；子网可单独配置，物理转发不会借用手机所选的组网出口。全部默认关闭，按账号独立保存，不新增一套机器身份。

## 操作

1. 连接后进入「设置 → 共享本机网络」，填写手机能访问且你有权管理的规范 CIDR，例如 `192.168.50.0/24`。最多 64 个，换行或逗号分隔；留空不提供子网。
2. 如需让远端设备通过手机上网，明确开启「将本机用作出口节点」。这会消耗手机的流量、电量和后台资源。
3. 保存并应用，VPN 会短暂重建。到用户中心批准这台设备广播的路由，配置允许访问的 ACL；远端设备还需要接收子网路由或选择此出口。
4. 页面和通知栏区分等待批准与实际生效。仅广播没有转发权限；部分子网获批时只转发已批准部分，出口要求双栈默认路由同时获批。

切网结束旧连接，随后按新的物理网络与已保存配置重建；请确认切网后仍有权分享所填 CIDR。主动断开、系统停止服务或撤销授权后不继续转发。不要求 Root，不开启系统内核转发，不更改 Android 防火墙，也不是二层桥接或 VLAN。实际能力受物理网络的 IPv4 / IPv6 连通性和系统免特权 ICMP 权限约束，不能凭开关制造不存在的网络能力。

## 数据面与边界

- `Hostinfo.RoutableIPs` 使用官方字段。可转发前缀是用户请求与本机已批准 `Node.AllowedIPs` 的精确交集，不通过界面开关自行授权。
- Rust `Forwarder` 仅接收 Engine 完成 WireGuard 对端身份、来源前缀、目的地及 ACL 校验的数据包。TCP / UDP 每条流使用独立的 smoltcp 用户态栈，再经使用前受 `VpnService.protect` 保护的物理 socket 访问目标。
- TCP 先建立受保护的物理连接，再向隧道客户端完成握手；失败返回连接拒绝，不提前发送 SYN-ACK。保留半关闭与背压；UDP 使用连接式 socket，响应绑定原始对端和五元组。回包不会根据任意目的 IP 重新选择另一个 peer。
- 出口物理网络不能访问某个 IPv6 目标时，支持双栈回退的应用可尝试经同一出口访问 IPv4。不会全局禁用 IPv6、伪造 AAAA 答案或改走手机自己的公网直连；指定出口本身失效仍失败关闭。
- ICMP 只支持真实 Echo 探测：使用免特权 ping socket，核对随机令牌和响应，再返回原始查询对应的回包。系统不允许或目标不响应时不伪造成功。不支持分片、IPv6 扩展头、任意 ICMP 错误或任意 IP 协议。
- 不转发回环、链路本地、多播、未指定和映射地址，不把其他组网设备的地址当成手机物理网络目的地。
- 全局最多 128 条流，每个对端最多 32 条；新流、待拨号、DNS 请求及 ICMP 任务另有限额和超时。断开销毁 socket 和后台任务，不留下物理代理监听端口。
- ACL、来源身份 / 地址 / 共享别名或批准路由变化时销毁旧流；控制映射失效或设备过期时失败关闭。应用分流只控制手机本地 UID，不能代替远端 ACL。

## 出口 DNS

提供出口时按官方 `Hostinfo.Services` 广播 `peerapi4` / `peerapi6`。`/dns-query` 仅在 WireGuard 内的本机地址提供，不能从物理网卡访问；HTTP 由组网隧道加密，不是公网明文 DNS 代理。

DNS 使用已有 MagicDNS / Split DNS / DoH / DoT / DNSSEC 数据面。即使手机没有开启自身的网络 DNS，获准的出口客户端也能单独使用出口解析；不会顺带更改手机系统 DNS。入口额外检查官方 peerapi 的互联网访问探针，已有 TCP 状态不能代替权限。仅接受有界 GET 或固定长度 POST，不接受重定向、分块及流水线请求。

## 验收

```sh
XUNARA_TEST_PHONE_ROUTER=true sh scripts/test-android-vpn.sh emulator-5580
XUNARA_TEST_SHARING=true sh scripts/test-android-vpn.sh emulator-5580
```

预先构建并校验 `lib/main.dart` 的 Release 包后，可额外传入 `XUNARA_TEST_RELEASE_APK` 的绝对路径。Debug 专项全部通过才保留本轮临时机器身份并同签名升级实际正式包；通过界面连接后验收真实双栈 TCP、系统 MagicDNS、网络共享页面及停止清理，核对已安装 APK 与待发布文件 SHA256 一致。退出时恢复原偏好并保留正式包，不卸载 App 或清除机器身份。

测试使用隔离的真实 Xunara 控制面、官方 Go tsnet 与专用未 Root 的 Android 模拟器。IPv4 物理目标在宿主回环代理后；模拟器 IPv6 网关不代理宿主回环，IPv6 使用 integration_test 内手机 LAN 地址上的测试服务，经官方远端、WireGuard 和受保护 socket 访问。测试服务不编入正式 `lib/main.dart` 安装包。

脚本保留原账号目录与私钥，备份 / 恢复偏好，并只清理本轮端口和临时标记。不用 App 自身被 VPN 豁免的请求冒充远端转发。实际通过项目、安装包源提交及物理手机限制以 `verification.md` 的最新版本记录为准。

本机排障可额外设置 `XUNARA_TEST_PAUSE_ON_FAILURE=true`，断言失败时保留现场 45 秒后清理，最终仍返回失败。临时快照不包含授权 URL；不要把包含测试身份文件的私有目录整体上传为公开构建产物。

## 双安卓公网出口专项

```sh
(cd ../xunara-client/tests/compat && go build -race -o ../../target/compat-fixture . && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags='-s -w' -o ../../target/compat-web-probe .)
sh scripts/test-android-exit-pair.sh emulator-5580 emulator-5584
```

需要两台已启动、同测试签名且已初始化应用的专用未 Root 模拟器，以及重新构建的 Go compat fixture。脚本预检原 APK 的签名，不卸载、清空或覆盖不同签名的旧应用；应为这种情况另建模拟器。

一台提供出口，另一台明确选用该出口。隔离控制面使用默认 ACL 和 `114.114.114.114` / `1.1.1.1`，普通 shell UID 直接请求公网 IPv4 HTTP、经 VPN DNS 查询真实公网域名的 UDP / TCP 响应，再解析域名并下载实际 HTTPS 页面。HTTPS 探针只在 x86_64 模拟器 shell 临时执行，使用系统 CA 验证主机名与证书链，不配置代理、不跳过证书验证，也不打包进客户端。最后撤销出口，确认 DNS 返回 SERVFAIL、公网请求不能直连，客户端 generation 不变；不能只凭 App 显示“出口可用”算通过。

该专项安装 Debug 集成入口，使用与预览包相同的原生内核，不冒充 ARM64 真机或双安卓 Release 验收。结束恢复原偏好及原 APK，保留账号私钥，清除专项私有缓存。私有日志只适合本机排障，不要整体上传其中的 fixture 身份目录。
