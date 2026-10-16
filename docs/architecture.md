# Flutter Android 首版设计

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

## Why

安卓不是把 Linux 可执行文件直接改名成 `.so`。系统授权后才能创建 VPN；所有外层 TCP / UDP socket 都必须保护，TUN 的地址 / 路由需要通过 Builder 安装。独立 Flutter 产品层同时避免把 Linux CLI 做成大而全的移动管理平台。

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
- 所有机器身份保存在 `noBackupFilesDir` 的按服务器哈希分目录，0700 / 0600、原子写入、实例锁。云备份和设备迁移另有显式排除规则。应用数据清除不等于服务端撤销。
- App 自身从 VPN 排除，让 DNS / 系统管理请求留在底层网络；Rust 对每个控制面 / DERP TCP socket、UDP socket 仍显式 `protect`，防止递归捕获。
- 路由计划只接受有效授权节点；用 host prefix 配置本机地址，拒绝默认路由，冲突 LAN 优先，本机地址冲突直接拒绝。
- 手机现有 DNS 服务器另作为保留 host prefix，防止远端子网截走解析器；IPv6 系统地址先去掉 scope zone 再比较网段。
- `UnderlayMonitor` 只使用系统实际通知的 NetworkCapabilities / LinkProperties，不混入 `allNetworks` 的后台保活网络，也不在回调里同步查属性；后台网络若不匹配监听请求就不会收到 onLost，不能缓存为永久在线。记录可见物理网络标识、接口、地址、直连网段和 DNS，无 Internet 能力的 LAN 仍保留冲突保护，但残留 IMS / MMS 网卡不触发重连。首次连接等回调就绪，接入密钥只在内存等待最多 30 秒，取消 / 超时即清理。
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

详情弹层订阅实时状态，连接切换、映射失效或设备移除后禁用操作，不保留一份过期静态设备对象。DNS 信息只来自可信映射的官方 Node.Name / DNSConfig，不读取其他租户或根据邮箱拼接域名；不安装虚拟 DNS 地址，不调用 `Builder.addDnsServer`，明确区分控制面的 MagicDNS 开关与手机系统解析能力。

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
