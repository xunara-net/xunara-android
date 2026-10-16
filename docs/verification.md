# 2026-10-16 首版验收

## What changed

独立 Flutter / Kotlin / JNI Android 仓库，复用 xunara-client Rust 数据面，不修改控制服务器。

## Why

不能用静态页面或切换按钮模拟 VPN 成功。先验收真实 Android 系统权限、TUN、跨进程流量与身份重连，再提供预览安装包。

## Compatibility impact

- 与现有 Xunara Noise / WireGuard / DERP 接口兼容，服务端没有新迁移或端点修改。
- Android 仅作节点和子网访问端，不承诺与官方移动端全部特性等价。
- 共用 Rust 内核的 Linux namespace 测试通过官方 Go tsnet 双向互通、子网、ACL、阻断 UDP 后的 DERP 回退与恢复。

## Security impact

- 测试 fixture 在 rootless 独立 user / network namespace，宿主代理仅 127.0.0.1。
- 临时 Auth Key 从 stdin 写入模拟器应用私有缓存，测试读取后删除，不进入 Git、URL、argv 或 APK。
- 实际数据面请求由模拟器 shell UID 发起，不使用客户端自身已绕过 VPN 的请求作为通过依据。
- 没有连接生产账号，没有转移、删除、过期生产设备，没有调整已部署服务、中继或公网端口。
- 预览包使用测试签名；真实手机、厂商后台管理、稳定签名和升级流程尚未验收。

## Tests

已完成：

- Flutter 9 项模型 / Widget 测试：安全地址、未知状态、审批与连接分离、拒绝权限后重试、小屏主操作、设备详情及大字体、临时密钥弹层生命周期、原生组件声明。
- `flutter analyze`、Dart 格式检查通过。
- Kotlin 6 项 `ProfileTest` / `NetworkAddressTest`，包括 DNS host prefix 与 IPv6 scope；Android `testDebugUnitTest` / `lintDebug` / `lintRelease` 通过。
- 原生 Rust 2 项生命周期单测、fmt / clippy / test 通过；Cargo audit 无已报告漏洞。
- Rust 核心 13 项单测、官方 STUN 解析测试、真实 Linux 兼容 / 子网 / ACL / DERP 网络测试通过。
- ARM64 / x86_64 JNI 库成功编译，LOAD alignment 为 16 KiB。
- Android 36 x86_64 Google APIs 专用模拟器真实 VPN 测试全部通过（不是物理手机）：
  - 系统 VPN 授权、TS2021 / Noise 注册、合法映射后建立 TUN。
  - Android 其他 UID 经 TUN 的加密 ICMP。
  - Android 与 Rust 节点经证书 pin DERP 的加密 TCP。
  - 拒绝 ACL 禁止端口。
  - Android 访问服务端批准的远程子网。
  - 流量计数增加、断开、不给 Auth Key 的身份重连，前后地址保持一致。

临时认证状态和完整验收日志只保存在本地私有测试目录，不提交仓库。早期测试发现的代理 namespace 凭据问题和“系统仍绑定 Service 导致一直等待 onDestroy”的退出问题均已修复；最终验收不是用超时或伪状态绕过。

仍待验收：ARM64 真机、不同厂商 ROM、IPv6 内层实际流量、Wi-Fi / 移动切换与省电模式长时间运行、生产浏览器审批全流程。Android 模拟器本轮强制 DERP 路径，不能据此宣称已测 Android UDP 直连。

工具链的 AGP 9 外置 Kotlin 兼容开关仍沿用 Flutter 官方模板，构建会提示未来 AGP 10 的弃用警告；当前不是失败，也未用全局关闭 lint 掩盖。

## 0.1.1 增量验收

### What changed

增加断网 / 切网安全自动重连、可关闭的重连开关、真实加密 ICMP 诊断、动态设备详情（系统 / 到期 / 域名 / 路由 / 中继名称）和 DNS 元信息页。移除原来只提示手动重连的实现和静态设备详情弹层。

### Why

手机不能在切换网络后继续使用可能冲突的旧 LAN 计划，也不能靠 App 自身豁免的请求或“中继候选”宣称已连接设备。

### Compatibility impact

固定 Rust 内核到 `4e572228de19f1063017b8aa94cdd53c462026c5`，不修改控制面、协议 wire、默认出口或手机 DNS。DNS 页只显示服务器元信息；尚不是系统级 MagicDNS。

### Security impact

- 首次连接等待实际网络回调；不把未受监听的后台保活网络缓存为永久可用。实测发现的断网后假在线问题已修复，未使用延时或伪状态绕过。
- 自动重连先退出旧 TUN，重新检查 LAN / 系统 DNS 冲突，只复用机器身份；不保存 / 自动重放 Auth Key。首次等待的密钥只留内存，最多 30 秒；主动断开或权限撤销会取消重连。
- ICMP 诊断只针对当前可见节点，沿用加密、来源、ACL 检查。Flutter → Kotlin → JNI 每层携带并校验 generation，旧请求不得跨连接投递；有界队列、随机 nonce、超时和清理均有回归覆盖。
- 不请求 root、不新增敏感 Android 权限、不接触生产账号；隔离 fixture 的 ICMP sysctl 不影响宿主机，模拟器无线开关结束后恢复。

### Tests

- Flutter 16 项模型 / Widget 测试与 analyze / 格式检查通过；覆盖详情真实结果、迟到结果丢弃、DNS 能力边界、自动重连设置、小屏 / 大字体和原有接入流程。
- Kotlin 12 项单测、`testDebugUnitTest` / `lintRelease` 通过，包含 API 26 直连网关的 null / `0.0.0.0` / `::` 判定，未通过提高最低 SDK 或关闭 lint 绕过兼容问题。
- 原生 Rust 3 项 lifecycle 单测、fmt / clippy / test 通过，覆盖旧 generation 请求拒绝与跨连接隔离；198 项锁定依赖 Cargo audit 无已报告漏洞。
- Rust 核心 17 项单测、Android ARM64 交叉 clippy、真实 Linux namespace 官方 tsnet / ACL / ICMP / 子网 / DERP 回退恢复通过；对应核心 GitHub CI 成功。
- Android 36 x86_64 专用模拟器真实 VPN 验证：TUN / Noise、其他 UID 的 ICMP / TCP / 子网 / ACL、内核诊断收到真实 DERP 回包与 RTT、不可见节点拒绝、对端不回复时实际超时、完全断网进入等待且系统移除旧 VPN、恢复 Wi-Fi 后自动重连及 TCP / 子网恢复、Wi-Fi → 模拟移动网络重连与 TCP、主动断开后网络恢复不自动拉起、不再提供 Auth Key 的手动重连保持地址不变。
- ARM64 / x86_64 Release APK 构建、签名校验和 16 KiB zipalign 通过；基础版本号为 2，按固定 Flutter 的 split-per-ABI 规则实际 versionCode 为 2002 / 4002。R8 保留 JNI 入口和平台回调名称，x86_64 Release 安装 / 中文界面 / JNI 初始化启动通过；真实 VPN 链路运行于 Debug 集成测试，不冒充 Release 真机验收。

模拟移动网络不能代替物理手机验收。ARM64 真机、厂商后台限制、真实蜂窝漫游、Android UDP 直连、IPv6 内层实际流量、正式长期签名、系统级 MagicDNS 和出口节点仍未完成或验证；不宣称已与官方 Android 全功能等价。
