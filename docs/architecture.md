# Flutter Android 当前架构

## What changed

```text
Flutter 中文界面（连接 / 设备 / 设置）
        ↓ MethodChannel（非公开 IPC）
Kotlin MainActivity → 用户明确允许 VpnService.prepare
        ↓
XunaraVpnService（前台通知 / LAN 变化 / TUN 建立）
        ↓ JNI：fd 所有权 / protect / 状态回调
固定 commit 的 xunara-client Rust 数据面
        ↓
TS2021 / Noise / WireGuard / Disco / STUN / DERP
```

Flutter 不实现 WireGuard、不创建机器身份、不保存 Auth Key，也不根据按钮点击直接切换成「已连接」。Kotlin 不实现控制面协议、ACL 或密钥派生。Rust 核心仓库不依赖 GUI / JNI，平台依赖方向始终朝向 `mobile::Host` 接口。

## Android 上游网络路径核查

对照官方 Android 源码快照 `264102cc702fbd844e900227ee02e5cbb4d7f801`：
[App.bindSocketToNetwork](https://github.com/tailscale/tailscale-android/blob/264102cc702fbd844e900227ee02e5cbb4d7f801/android/src/main/java/com/tailscale/ipn/App.kt#L510)
使用 `ParcelFileDescriptor.fromFd` 复制借用的描述符，再调用 `Network.bindSocket`；
[IPNService.newBuilder](https://github.com/tailscale/tailscale-android/blob/264102cc702fbd844e900227ee02e5cbb4d7f801/android/src/main/java/com/tailscale/ipn/IPNService.kt#L192)
同时声明 VPN 的底层网络。`protect` 避免流量重入自身 VPN，不应被当成物理网络绑定的替代。

当前 Kotlin 仍采用逐 socket 保护与切网后整体断开重建的生命周期，不提供独立的物理网卡绑定开关。显式绑定必须与初始网络回调、现有 fd 重绑及 TUN 重建一起验证，不能只把官方一个方法接上就认为完整；本轮未合入存在回归的绑定候选，实际修复位于独立 Rust 内核的双向路径确认与 DERP 回退。

继续保留已有逐 socket 保护和失败关闭，不照抄官方保护失败后仍继续的 best-effort 行为，也不按进程绑定网络或改写系统默认路由。绑定成功不代表真实出口公网转发成功；控制面在线、路由已批准和隧道 ICMP 回应都不能代替 DNS / HTTPS 验收。

## Why

安卓不是把 Linux 可执行文件直接改名成 `.so`。系统授权后才能创建 VPN；所有外层 TCP / UDP / ICMP socket 都必须保护，TUN 的地址 / 路由需要通过 Builder 安装。独立 Flutter 产品层同时避免把 Linux CLI 做成大而全的移动管理平台。

中文首屏保留一个主动作；授权阶段用浏览器授权按钮替换大圆形连接按钮，不让下一步落在屏幕下方。设备与设置通过底栏直接切换，不把所有菜单固定堆在顶部。账号管理仍可打开正式用户中心，避免首版凭不完整 API 编造用户资料。

## Compatibility impact

- 不修改 xunara-server、官方 Tailscale Client、TS2021 / Noise / MapRequest / DERP wire。
- 原生注册只按既有字段报告 `Hostinfo.OS=android`；机器的密钥认证与所属租户由服务端现有机制决定。
- 浏览器批准不是 OAuth 回调承载机器密钥；Flutter 不接管 OAuth state、nonce、PKCE 或服务器 Session。
- 不支持的能力明确不展示开关；Android 不伪装成 Linux 子网路由器。

## Security impact

- `VpnService` 不导出，用 `BIND_VPN_SERVICE` 保护；外部 App 不能发送带 Auth Key 的启动 Intent。
- 先 `prepare`、保护 socket，收到合法授权映射后才 `establish`。`detachFd` 后由 Rust `OwnedFd` 唯一关闭，Java 不保留重复 fd。
- 平台账号 Session 不与 Machine / Node / Disco 私钥混用；不使用旧业务 Agent 的明文登记路径。
- 控制面根地址拒绝明文公网 HTTP、用户名 / 密码、query、fragment、租户路径；浏览器授权 URL 再做同源校验。
- 所有机器身份保存在 `noBackupFilesDir` 的按账号配置 ID 分目录；同一服务器不同账号也不复用身份。目录 / 文件使用 0700 / 0600、原子写入和实例锁。云备份和设备迁移另有显式排除规则。应用数据清除不等于服务端撤销。
- App 自身从 VPN 排除，让 DNS / 系统管理请求留在底层网络；Rust 对每个控制面 / DERP TCP socket、UDP socket 仍显式 `protect`，防止递归捕获。
- 路由计划只接受有效授权节点；用 host prefix 配置本机地址，默认不导入默认路由。明确选择出口后分割接管路由、排除 LAN，出口撤销保留失败关闭；本机地址冲突直接拒绝。
- 手机现有 DNS 服务器另作为保留 host prefix，防止远端子网截走解析器；IPv6 系统地址先去掉 scope zone 再比较网段。
- `UnderlayMonitor` 只使用系统实际通知的 NetworkCapabilities / LinkProperties，不混入 `allNetworks` 的后台保活网络，也不在回调里同步查属性；后台网络若不匹配监听请求就不会收到 onLost，不能缓存为永久在线。记录可见物理网络标识、接口、地址、直连网段和 DNS，无 Internet 能力的 LAN 仍保留冲突保护，但残留 IMS / MMS 网卡不触发重连。首次连接等回调就绪，接入密钥只在内存等待最多 30 秒，取消 / 超时即清理。
- 默认网络回调的 `onLost` 只表示失去默认资格，不能当作物理断网。仍被 NOT_VPN 回调观察到的默认物理网络保持优先，自身 VPN 建立 / 重配不导致错误切到另一个后台网络；真正物理移除或新的物理默认出现时仍重新规划。
- 切网先关闭旧实例，防抖后才重建 TUN；完全断网保持等待。重连沿用机器私钥，绝不持久化或自动重放 Auth Key。首次审批前不会擅自重新注册；主动断开、权限撤销与关闭自动重连都会取消待办。
- 路由规划和 `establish` 再次核对网络指纹，拒绝使用过时 LAN 计划。已进入切网退出状态后忽略迟到内核状态，不让旧“在线”结果覆盖等待状态。策略过期 / 撤销由同一 Rust ACL 与密钥校验机制处理。
- 原生运行实例带 generation；旧 Service 的延迟 stop 不得终止新连接。断开状态在 Rust 已退出、关闭 TUN 后更新，不等待可能仍被系统绑定的 Service 的 `onDestroy`。
- Release 的 R8 规则保留原生入口和从 JNI 字符串调用的平台方法，不能只验证 Debug 后就忽略 Release 的名称裁剪。
- 通知前台类型采用官方 VPN 豁免 `systemExempted`。Lint 对闹钟权限的静态误报只在 VPN service 元素局部排除，不申请无关的精确闹钟权限，也不全局关闭 lint。

## Tests

模型 / Widget 测试验证地址拒绝、同源边界、未知状态默认失败、授权不等于在线、拒绝权限后重试、360×640 首屏主动作、大字体和详情可达。Kotlin 单测复核 URL / 浏览器边界。Rust 单测验证早于 worker 的 stop、重复启动拒绝、旧 generation 不能停止新连接。

`scripts/test-android-vpn.sh` 使用真实 Android VpnService 和隔离 Xunara fixture，真实流量来自模拟器 shell UID，不从 App 自身豁免流量推断成功。验收结果、设备限制另见 `verification.md`。

## 设备诊断与 DNS 元信息

检测由专用 Kotlin 工作线程经 JNI 把 peer ID 发送给内核的有界通道。Rust 构造带随机 nonce 的 ICMPv4 / ICMPv6 Echo，经原有 WireGuard / DERP 发送；回包完成身份、来源、ACL 校验后才能完成请求。请求有频率限制、容量上限和超时；断开清理等待者，generation 变化后 UI 丢弃迟到结果。这里只称 ICMP 连通性，不能推断所有 TCP / UDP 端口可用，也不把配置中的 DERP 区域当作实际回包路径。

详情弹层订阅实时状态，连接切换、映射失效或设备移除后禁用操作，不保留一份过期静态设备对象。DNS 信息只来自可信映射的官方 Node.Name / DNSConfig，不读取未授权租户或根据邮箱拼接域名。用户开启网络 DNS 或选择出口后才安装避让 LAN 的虚拟 DNS host 路由并调用 `Builder.addDnsServer`；默认不改变手机 DNS。手机提供出口但未启用自身网络 DNS 时，只为获准远端提供 peerapi 解析。

## 免 Root 转发与共享

Rust `Forwarder` 在现有 WireGuard / 来源 / ACL 检查之后接收获批目的地址，使用独立用户态流和受保护物理 socket；TCP / UDP 回包绑定原始 peer，ICMP Echo 必须收到真实匹配响应。ACL、批准路由和来源身份 / 共享别名更新时销毁旧流。具体配额与安全边界见 `phone-forwarding.md`。

共享设备仍由控制面按接受记录投影，只接收 peer 专属别名与必要展示数据，不导入源网络子网或拓扑。Flutter 的「跨网络共享」标签只用于展示，不参与授权；实际权限由服务端与 Rust 数据面决定。完整 Tailnet Lock 尚未实现，仍拒绝需要本机签名链验证的映射。

## 上游参考

- [Flutter Platform Channels](https://docs.flutter.dev/platform-integration/platform-channels)
- [Android VPN 生命周期、权限、protect 与 TUN](https://developer.android.com/develop/connectivity/vpn)
- [Android 网络回调和属性时序](https://developer.android.com/develop/connectivity/network-ops/reading-network-state)
- [官方 Node.Name / DNSConfig 字段](https://github.com/tailscale/tailscale/blob/v1.104.1/tailcfg/tailcfg.go)
- [ICMPv4 Echo（RFC 792）](https://www.rfc-editor.org/rfc/rfc792) / [ICMPv6 Echo（RFC 4443）](https://www.rfc-editor.org/rfc/rfc4443)
- [Android Foreground Service 类型](https://developer.android.com/develop/background-work/services/fgs/service-types)
- [官方 Tailscale Android Manifest](https://github.com/tailscale/tailscale-android/blob/main/android/src/main/AndroidManifest.xml)
- [Tailscale Android socket protection](https://github.com/tailscale/tailscale/blob/v1.104.1/net/netns/netns_android.go)
- [JNI 0.21 JavaVM 生命周期](https://docs.rs/jni/0.21.1/jni/struct.JavaVM.html)
