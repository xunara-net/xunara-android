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
