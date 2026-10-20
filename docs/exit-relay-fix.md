# 0.5.4 出口链路源码审计与修复

## What changed

- 内核固定至 `82109c5172a8c840609147ddca66a37a1d9e4b94`，只发布通过 DERP 身份握手和随机心跳的 home，不再固定使用最小中继编号。详细协议对照见[核心源码审计](https://github.com/xunara-net/xunara-client/blob/82109c5172a8c840609147ddca66a37a1d9e4b94/docs/exit-path-audit.md)。
- 修正 Android 重连指纹：当前选定的物理网络 / 接口 / 地址仍参与比较，全部可观察 LAN / DNS 保护网段仍参与比较；不再把后台网络编号的增删直接当成当前 Wi-Fi 切网。
- LAN 前缀规范化为网络地址。`10.0.2.15/24` 和 `10.0.2.16/24` 都表示 `10.0.2.0/24`，后台蜂窝与 Wi-Fi 重叠时不再因冗余前缀消失而重启 VPN。DNS 的 /32、/128 保持完整地址，解析器的 IPv6 scope 仍单独保留。
- 诊断显示本机中继的连接确认；缺失、不一致数据仍按未知处理，不用中继心跳代替出口业务验收。
- 双安卓测试使用独立随机 UUID，避免克隆 AVD 沿用相同机器身份；新增后台蜂窝退出 / 恢复但原隧道代次不变的真实回归。

## Why

### 不可达中继形成回包黑洞

首个中继不可达而另一个中继正常时，旧内核仍上报坏 home。UDP 可达时不明显，阻断单向 UDP 后真实 TCP 回退失败。新内核在相同隔离场景选择并发布可用的 900；双安卓公网 DNS UDP / TCP、校验系统 CA / 主机名的 HTTPS 已实测通过。

### 后台蜂窝退出误触发全隧道重建

压力回归曾在出口撤销后收到非预期 NXDOMAIN，不能记为通过。对照 Android ConnectivityService 事件：`2026-10-20 13:58:17 UTC` 后台蜂窝网络失去 `FOREGROUND`，紧接着 VPN 被断开重建；当前 Wi-Fi 仍存在。原指纹包含所有后台 network handle 及非规范化的 LAN 地址，导致冗余蜂窝项消失也改变指纹，代次从 9 变 10，在测试时产生额外的断开窗口。

修复的是这个明确的误判，不是通过关闭自动重连、删除 LAN 保护、改成按进程绑定网卡或放宽 DNS 检查来“通过”测试。真正切网、选定地址变化、新 LAN / DNS 保护网段变化及失去可用网络仍会重新规划。

## Compatibility impact

不修改服务端、数据库、用户归属、路由批准、ACL 或官方 Tailscale 协议。Flutter 仍经原 MethodChannel 调用同一 Rust 内核；JNI 回调签名不变。现有账号和机器身份可同签名覆盖升级，不需要卸载、清数据或重新发设备密钥。

## Security impact

TLS / 证书 pin、机器来源、ACL、所选出口固定和撤销后 VPN 内失败关闭全部保留。不把后台网络丢失当成新账号，也不借用原手机的密钥。真正物理断网、主动停止或进程退出时仍可能恢复系统普通网络，本版本不宣称持久 kill switch。

生产检查时 demo 的四台原设备均离线；只读查看后单独撤销了本轮人类会话，没有修改原手机的设备身份、审批、DNS 或 ACL。模拟器和隔离 fixture 的测试不能等同于 NX769J / Xiaomi 真机验收。

## Tests

- Flutter analyze / 44 项普通测试，原生 Rust fmt / clippy / 3 项生命周期测试，ARM64 交叉检查通过。
- 核心 Rust 52 项普通测试、官方 STUN / 地址改写兼容测试、普通 / SNAT / 不可达首个 DERP 的真实 Linux namespace 回归通过；默认忽略的外部测试不冒充已执行。
- Kotlin 31 项单测通过，包含前缀归一化、后台蜂窝冗余项退出不重连及真正网络 / LAN / DNS 变化仍重连。
- 中继修复后、重连指纹修复前的双安卓测试已通过公网 IP / HTTP、DNS UDP / TCP、HTTPS 和出口撤销不直连。最终指纹修复及 Release 回归须以本次后续验收记录为准。
- 一次 Release 首帧窗口抓取失败已单独定位为测试时序问题；改用有界重试并只读取本次成功生成的窗口。失败轮次未记为成功，截图和页面检查仍必须实际到达目标页面。

### 最终重连修复回归

Android 36 x86_64、普通 shell UID 2000，使用不可达 DERP 1 和正常官方 DERP 900：完整流程退出码 0。真实验证后台蜂窝退出 / 恢复不改变原 VPN 代次且 ICMP 继续可用，真正 Wi-Fi / 模拟移动切换仍重建；双栈 TCP、ACL 拒绝、批准子网、MagicDNS UDP / TCP、官方 tsnet 出口和撤销失败关闭、免 Root 转发 / ACL 撤销、不同账号与跨租户共享隔离均通过。

同一流程覆盖安装最终 `0.5.4` 混淆 Release，验证既有临时身份无需新密钥即可连接、双栈 TCP、系统 MagicDNS、实际网络共享页面、强制停止后无残留 VPN。此项不是用 Debug 页面冒充 Release，也不等同于 ARM64 真机验收。APK 版本码为 `2011` / `4011`；两个 ABI 的 JNI 6 个回调、测试签名和 16 KiB 对齐核对通过。

最终指纹修复后再次运行双安卓专项，退出码 0：两台独立 UUID 身份均向控制面发布 home 900；普通 UID 经安卓出口访问公网 IP / HTTP、DNS UDP / TCP、系统 CA / 主机名校验的 HTTPS 200（577 字节）通过，撤销后 DNS 返回 SERVFAIL、公网不直连且连接代次不变。没有用 App 自身豁免的请求冒充出口流量。

Debug / Release lint 通过。集成测试曾留下测试插件的生成注册状态，直接混跑 Gradle lint 时 Release 编译拒绝该状态；经 `flutter build apk --release --target lib/main.dart` 恢复生产入口后重新验证通过，没有手改生成的 Java 文件或把测试插件带入生产包。最终 APK 检查确认正式默认控制地址来自 Kotlin DEX、诊断解析来自 AOT，不包含集成测试入口或本轮临时测试密钥；两 ABI 的原生 ELF LOAD alignment 均为 16384。
