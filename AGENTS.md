# Android 客户端开发规则

- Flutter 负责中文移动端交互，Kotlin 负责 Android VPN 权限和生命周期，Rust 内核来自独立的 xunara-client 仓库；不得复制另一套协议实现。
- 真实 TUN 建立且取得有效映射才能显示已连接。浏览器登录、人类会话与设备授权始终分离，不使用平台管理员令牌。
- 不在 URL、日志、偏好设置、构建产物或测试截图中存放 Auth Key；机器私钥只保存在禁止备份的应用私有目录。
- 所有底层套接字必须保护，VPN 不接管默认路由和系统 DNS；冲突优先保留手机 LAN。
- 使用中文注释解释安全边界、跨语言 fd 所有权和生命周期；清除脚手架演示和占位功能。
- 修改后运行 dart format、flutter analyze、flutter test、Rust fmt/clippy/test，以及 Android assemble/test/lint。涉及 VPN 的功能需要模拟器或真机验收；没有做过的测试必须明确说明。
- Git 中文标题，说明包含 What changed / Why / Compatibility impact / Security impact / Tests。
