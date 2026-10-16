# 玄序 Android · Xunara

独立的 **Flutter 安卓客户端**，不是 WebView 套壳，也不要求先安装官方 Tailscale App。中文界面、底部「连接 / 设备 / 设置」、单手操作、简洁卡片；组网复用独立 [xunara-client](https://github.com/xunara-net/xunara-client) 的 Rust 内核。

**当前为测试预览版，不是完整替代官方客户端的正式发行版。** 支持 Android 8.0+、ARM64 / x86_64。APK 下载见 [Releases](https://github.com/xunara-net/xunara-android/releases)，安装前对照同版本 `SHA256SUMS`。预览包使用测试签名，不承诺跨 CI 构建直接覆盖安装；正式发布前需配置长期维护的私有签名。

<p>
  <img src="docs/screenshots/connect.png" width="240" alt="连接首页" />
  <img src="docs/screenshots/devices.png" width="240" alt="设备页面" />
  <img src="docs/screenshots/settings.png" width="240" alt="设置页面" />
</p>

截图来自实际 Release APK 的 Android 模拟器，不含伪造设备或连接数据。

## 已实现

- 原生 Android VPN 权限、前台服务、通知栏状态与断开操作，Flutter 退出前台不影响内核工作。
- 官方兼容 TS2021 / Noise 设备注册与网络映射；浏览器登录和设备审批，或临时接入密钥加入。
- WireGuard 加密、UDP 直连探测、Disco、STUN、私有 DERP 的 TLS / 证书指纹校验和回退。
- 已授权设备发现、名称 / IP 搜索、IP 复制、直连探测状态与中继区域详情。
- 设备详情补充操作系统、控制面域名、密钥到期时间、已批准子网和中继名称；检测按钮发送真实加密 ICMP，显示实际回包路径与 RTT，明确提示超时 / 不可见设备。
- 接收已批准的远程子网路由、ACL 检查、真实发送 / 接收计数。
- 本机仅安装 host address；冲突时保留手机局域网、跳过重叠远程路由，不接管默认出口或手机 DNS。
- 私有且禁止备份的机器身份、按控制面隔离持久化、不再提供 Auth Key 的重连。
- Wi-Fi / 移动网络切换、断网恢复后自动重连：先退出旧 TUN，再重新检查 LAN / DNS 冲突，沿用机器身份、不保存或重放接入密钥。主动断开会取消待重连任务；可在网络设置关闭自动重连。
- DNS 信息页读取控制面 MagicDNS 状态、搜索域与本机域名；不会误导为已接管手机的系统解析器。
- 系统通知设置、VPN 设置和浏览器用户中心入口，不复制一套臃肿的管理后台。

## 怎么使用

1. 安装 ARM64 APK（主流安卓手机）；x86_64 包用于相应设备 / 模拟器。
2. 默认服务器为 `https://fakeop4.onbed.cn:9090/`。连接其他部署可在「设置 → 服务器与设备名」修改，只填根地址，**没有网络标识、登录范围或 `/t/用户名/login`**。
3. 点「连接网络」并允许 Android VPN；首次接入点「前往浏览器登录并授权」，登录自己的账号并批准这台设备。返回 App，收到授权映射并建好真实 TUN 后才显示「已安全连接」。
4. 免交互接入可选「使用接入密钥加入」，粘贴从自己用户中心生成的设备接入密钥；不会保存该密钥。
5. 访问远程子网：在网络管理中批准路由、配置允许访问的 ACL，再保持「访问远程子网」开启。

账号登录不改变已登记机器的归属，不能靠切换浏览器账号接管另一用户的设备。要重新登记到其他账号，先在原用户中心移除这台设备，再清除应用数据重新加入。请勿清除应用数据来代替服务端撤销设备。

Android 同时只能运行一个 VPN。网络环境改变时，默认安全退出旧隧道并自动重连，不沿用可能截走新 LAN 的旧路由；完全断网时通知栏显示等待网络恢复。主动断开、撤销权限、关闭自动重连后不会擅自重新连接。首次注册未完成时不自动重放接入密钥。前台服务仍可能受到部分厂商后台限制，需结合真机电源管理实测；本版不承诺被系统杀进程、重启手机后自动拉起 VPN。

## 当前边界

- 暂不支持系统级 MagicDNS / 本地 DNS 代理、出口节点、共享地址 masquerade、Tailnet Lock、文件传输和自动升级。展示域名与配置不等于其他 App 已能用域名访问，请使用设备 IP。
- 手机仅作子网**访问端**，不要求 root、不在 Android 上广播子网或开启内核转发。
- 外层 UDP 目前使用 IPv4；隧道可传 IPv4 / IPv6 的 TCP、UDP、ICMP，不支持 IP 分片或 IPv6 扩展头。最多 256 个可见节点。
- 「中继候选」表示内核配置的回退路径，不伪报对端在线或已测速。STUN 不是 UDP 业务中继。
- 人类账号 / OAuth Session 留在系统浏览器；App 没有平台管理员令牌，不自动继承浏览器登录权限。
- 控制面必须使用可信 HTTPS，只有回环 HTTP 可用于隔离测试；没有“忽略证书校验”。私钥在 Android 应用私有文件中，并非硬件 Keystore 不可导出密钥。

## 本地构建

固定工具：Flutter **3.47.7** / Dart **3.13.5**、JDK 17、Android SDK 36、NDK **29.0.14206865**、Rust **1.98.1**。原生脚本当前面向 Linux x86_64 开发机，不将本机绝对路径提交到 Git。

```sh
export ANDROID_HOME="$HOME/Android/Sdk"
flutter pub get
rustup target add aarch64-linux-android x86_64-linux-android
sh scripts/build-native.sh
flutter build apk --release --target lib/main.dart \
  --target-platform android-arm64,android-x64 --split-per-abi
```

Rust 依赖固定到独立仓库的具体 commit，`Cargo.lock` / `pubspec.lock` 一起提交。`jniLibs` 是生成物，不纳入 Git；缺少任一默认 ABI 的内核时 Gradle 会明确失败，不生成只有界面的空壳安装包。NDK ELF 使用 16 KiB LOAD alignment。

`scripts/collect-native-notices.sh` 同步原生组件的原始声明，随 APK 打包，可在「设置 → 开源组件声明」查看；清单受 Cargo 锁文件约束。

## 验证

```sh
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test test
(cd native && cargo fmt --check && cargo clippy --locked --all-targets -- -D warnings && cargo test --locked --all-targets)
flutter build apk --debug
(cd android && ./gradlew :app:testDebugUnitTest :app:lintDebug)
```

真实 VPN 测试先在相邻目录准备 `xunara-client` 和其 `tests/compat` 所需固定版本的 `xunara-server`：

```sh
(cd ../xunara-client && cargo build --locked)
(cd ../xunara-client/tests/compat && go build -race -o ../../target/compat-fixture .)
sh scripts/test-android-vpn.sh emulator-5580
```

需先启动专用 Android 模拟器，并安装 `socat`、`jq`、`iproute2`；宿主机允许 rootless user / network namespace。测试只允许 `emulator-*`，不自动给真机授权。测试服务运行在隔离 namespace，宿主代理只监听 127.0.0.1，Auth Key 通过 stdin 写入应用私有缓存，不出现在 argv、URL 或 APK 中，不访问生产账号。

测试验证的是其他 Android UID 发起的真实 TUN / ICMP / TCP / ACL / DERP / 子网流量，而非 App 自己从被排除的网络请求制造“组网成功”。与官方 Go tsnet 的双向兼容、直连 / DERP 切换由 Rust 内核仓库的真实 Linux 网络测试覆盖；不能把它说成 Android 真机已验收。

扩展验收会切换专用模拟器的 Wi-Fi / 移动数据开关，并在隔离 namespace 暂停 ICMP 回复，验证诊断实际超时、断网移除旧 VPN、Wi-Fi 恢复 / 模拟移动网络切换后的自动重连和 TCP / 子网恢复，以及主动断开后不再自动连接。结束时恢复模拟器原有开关并停止测试 App；不要在个人工作模拟器上运行。此过程不要求安装包取得 root。

详见 [架构和安全边界](docs/architecture.md)、[验收记录](docs/verification.md)、[安全反馈](SECURITY.md)。
