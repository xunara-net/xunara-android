# 0.3.0：MagicDNS、指定出口与多账号

## What changed

- 设置页增加真正的网络 DNS 开关、出口选择和账号 / 控制器列表，仍只有连接、设备、设置三个主入口。
- Kotlin 管理 VpnService 的 DNS、搜索域、路由及应用选择；Rust 的 DNS 专用有界端点处理 UDP / TCP，不在 Flutter 重写协议。
- 机器身份以配置 ID 隔离，同一 URL 可以保存多个账号。备注是本机标签，不是登录认证，也不自动切换浏览器的人类会话。
- 连接后展示控制面 Node.User / UserProfiles 确认的设备归属，只作展示，不据此创建人类会话或提升权限。
- catalog_v2 一次提交当前 ID 和配置列表，原单服务器及 v1 身份沿用原哈希目录；新项用 UUID 目录。迁移成功移除旧偏好键，损坏配置不自动重置。

## Why

设备域名不能只显示但无法解析；选择出口不能只设置按钮而没有实际路由。多账号不能共用一个按服务器 URL 定位的 Machine / Node / Disco 身份，更不能用修改设备名或切换浏览器会话转移设备。

## Compatibility impact

- 不改变 TS2021、Noise、Register、Map、WireGuard 或 DERP 的 wire 格式；使用既有 DNSConfig、StableID、AllowedIPs、Hostinfo.Services / ExitNodeID。
- 修复 PeerChange.DERPRegion 没有映射到 Node.HomeDERP 的单向通信问题，忽略零值及非 PeerChange 字段；取得首张 DERPMap 后立即上报 home，不再等周期刷新。
- 普通模式仍只安装私网路由。MagicDNS 支持有效可见设备的 A / AAAA / PTR、ExtraRecords 的空 Type / A / AAAA 地址记录、本地域不存在时 NXDOMAIN；不会把本地域查询泄露给公网解析器。
- 普通解析采用最长后缀分流规则，再选全局 / fallback / 物理网络解析器。支持 IP 与 IP:端口；物理网络保留 IPv6 数字 scope，UDP 优先、截断或不可用再回退 TCP，组网解析器使用 TCP。回复须匹配问题、随机事务 ID 和响应方向；不支持的自定义 DoH / DoT 配置明确报错。
- DNS 虚拟地址从 100.100.100.100 起寻找无冲突 host 地址，必要时退避到 198.18.0.0/24；避让已有 LAN、设备、远程已批准网段、解析器和扩展记录地址，不用自己的地址作为转发上游。
- 只允许显式选择获批双栈默认路由的 StableID；普通节点广播 /0 不会自动变成出口。出口 DNS 走该节点广告的 peerapi4/6 `/dns-query`，HTTP 在 WireGuard 内，不跟随重定向，没有可用服务就 SERVFAIL。
- 出口默认路由通过 CIDR 减法排除现有 LAN、系统 DNS host 与回环 / 链路本地 / 多播，兼容 Android 8–12，不依赖 API 33 的 excludeRoute。
- Linux CLI 不开放系统 DNS 或出口选择，仍不改宿主默认路由 / 系统解析器 / 全局转发开关。

## Security impact

- DNS 与出口默认关闭。开启出口必须同时启用 VPN DNS；用户主动修改网络选项时先停旧连接、保存并读回，再用原机器身份重连，绝不重放 Auth Key。
- 所选出口撤销、过期、失联时，不使用别的默认路由节点。有效 VPN 内保留双栈接管路由并丢弃不可转发流量。来自出口任意互联网源的回复必须命中本机已发出流；不可伪造其他可见设备的源地址。
- 这不是系统“始终开启 / 阻止无 VPN 连接”。用户断开、系统撤销权限、杀进程或服务结束后恢复普通网络。更改设置会短暂断开；需要跨退出防泄漏的场景不能依赖本预览版。
- LAN 访问始终保留；被排除应用及玄序自身不走出口。控制面、DERP、UDP 与普通模式的外部 DNS socket 仍逐个 protect，避免路由递归。Android 严格私人 DNS、应用内 DoH 不等于此 VPN 的 DNS。
- DNS TCP 监听槽、查询队列、帧长度、上游响应、并发及超时均有限制。旧映射 DNS 端点替换时销毁未完成事务，回复不能跨账号、映射或连接代数投递。
- 切换账号结束旧 TUN 后才选择新目录，不自动连接。移除记录不删除私钥或服务端设备，重新添加会生成新身份；服务端撤销仍需在对应用户中心操作。
- 偏好不保存人类密码、会话或接入密钥；私钥继续在禁止备份的私有目录中使用原子写入和实例锁。

## Tests

具体已执行的构建、真实网络与模拟器结果见 `verification.md` 的 0.3.0 验收。设计测试包括双栈 DNS 端点容量、UDP/TCP 实际报文、A/AAAA/PTR、私有 NXDOMAIN、事务绑定、DNS 地址退避、LAN 排除、出口撤销保留阻断、同控制器账号独立设备与切回原身份。

## 回滚

回滚代码仍需读取 catalog_v2，不能直接装只认识 catalog_v1 的旧 APK；不能通过卸载、清除数据或拷贝旧私钥解决签名 / 升级问题。继续使用相同测试签名只支持对应安装来源，正式长期签名与 ARM64 真机仍需单独验收。

参考：[官方 DNSConfig](https://github.com/tailscale/tailscale/blob/main/tailcfg/tailcfg.go)、[出口节点](https://tailscale.com/docs/features/exit-nodes)、[Android VPN Builder](https://developer.android.com/reference/android/net/VpnService.Builder)、[smoltcp](https://github.com/smoltcp-rs/smoltcp)。
