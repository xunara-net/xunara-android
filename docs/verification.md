# 2026-10-16 首版验收

最新功能状态以文末增量验收为准，前面的章节是历史记录。

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

## 0.2.0 增量验收

### What changed

增加常用服务器保存 / 手动切换、全部 / 排除 / 仅选中三种应用分流、系统开关诊断和
白名单脱敏摘要。编辑和分流长列表的保存按钮固定在底部。旧单服务器偏好一次性迁移，
成功后删除旧键；服务与 Activity 共用 `ProfileStore`，不继续混读旧实现。

### Why

服务器切换不能丢失各自的设备名与子网偏好，手机应用也不应被一刀切地接管。
Android 的空允许清单意味着全部应用，因此“仅选中但全部卸载”必须失败关闭。
设置提交结果未知时不能继续用旧服务器标签连接，必须先读回真实配置。

### Compatibility impact

Rust 依赖仍为 `4e572228de19f1063017b8aa94cdd53c462026c5`，未修改控制面、
协议 wire、默认路由、DNS、机器身份目录或私钥格式。新版本基础 versionCode 为 3，
ARM64 / x86_64 Release 包实际 versionCode 为 2003 / 4003，versionName 为 0.2.0。

### Security impact

- 待系统授权、连接、重连和停止阶段禁止修改或切换配置；选中配置读回失败时清除
  旧界面选择，禁止继续修改和连接，显式重新加载后才恢复操作。
- 移除连接记录不删除私钥或服务器设备，不能冒充注销或跨账户转移设备。
- 应用清单仅本机按需读取；Release 无 `QUERY_ALL_PACKAGES`、测试 shell 可见性
  或电池豁免申请权限。允许 / 排除清单互斥，外层套接字仍逐个 protect。
- 不上传诊断，不复制原生错误正文；摘要不包含服务器、设备名、IP、包名、授权 URL
  和凭据。系统诊断失败不伪报正常，系统开关正常也不伪报业务可达。
- 先前专用模拟器装有不同签名的预览包。本轮新建 `xunara-settings-test`，未自动
  卸载原 App、清空原数据或删除其机器身份。测试脚本只允许专用模拟器的 Debug 包
  降级安装；签名不兼容时仍拒绝，不用清数据绕过。

### Tests

- Dart / Widget 27 项测试通过，`flutter analyze` 和 Dart 格式检查通过。新增覆盖
  仅选中空清单、配置切换 / 锁定、编辑保留应用偏好、未知提交结果恢复、小屏大字体
  固定保存按钮、脱敏摘要白名单及诊断读取失败。
- Kotlin 18 项单测、Debug / Release lint 通过；未关闭新增 lint、未提高最低 SDK。
- 原生 Rust fmt / clippy / 3 项 lifecycle 测试通过；ARM64 / x86_64 库按原锁文件
  重建，组件声明无变更。
- Android 36 x86_64 新专用模拟器，真实 VPN 最终回归通过：其他 UID 的 ICMP / TCP、
  DERP 证书 pin、拒绝 ACL 端口、已批准子网、诊断真实 RTT / 超时、Wi-Fi / 模拟移动
  切换恢复、主动取消后不自动连接、不再提供 Auth Key 的身份重连。
- 新增真实 IPv6 TCP：模拟器 shell UID 经 TUN / DERP 访问 Rust 节点的 IPv6 HTTP
  监听器成功；这不等于已验收所有 IPv6 协议、扩展头或 IPv6 外层 UDP。
- 应用允许清单选中 shell UID 后真实 TCP 成功；排除该 UID 后私网 TCP 不通；全部
  所选应用不存在时拒绝建立 VPN；恢复全部应用后 TCP / 子网恢复，机器地址不变。
- 常用服务器保存与切换不自动连接，当前记录删除拒绝，原子新偏好与旧键清除通过
  集成验证；Release 另用显式旧格式夹具验证服务器、设备名、两个开关原值完整迁移。
  旧格式夹具由专用模拟器 root 准备，App 仍使用普通 UID；真实 VPN 测试始终由
  非 root shell UID 2000 发起，没有拿 root UID 流量代替按应用分流验收。
- 两 ABI Release APK 构建、签名和 16 KiB zipalign 验证通过。x86_64 Release 实际
  安装，四个设置页 / 原生读取 / 中文界面检查通过，无 JNI 名称裁剪错误。
  截图为实际 Release APK，断开状态，不含生产账户或伪造连接数据。

仍未宣称完成：ARM64 物理手机、各厂商后台长时间运行、物理蜂窝漫游、Android UDP
直连、正式长期签名、系统级 MagicDNS、出口节点、共享地址转换、Tailnet Lock。
保持预览版标识；两套测试签名不同不能视为可无损覆盖安装的稳定升级方案。

## 0.3.0 增量验收

### What changed

落地可选 VPN DNS / MagicDNS、双栈指定出口、同控制器多账号与多控制器切换。旧配置迁移到 catalog_v2，保留原哈希身份目录；新增配置使用独立 UUID 目录。连接后展示控制面确认的设备归属，切换后的迟到状态不能覆盖新账号。

### Why

不能只显示 DNS 配置或出口开关。验收必须包括真实解析、加密转发、撤销后不回退，以及同服务器不同账号确实使用不同设备身份，再无密钥切回原设备。

### Compatibility impact

- Rust 内核固定到 `33f47a10861fb444aeef915c8e0c233b22d4de5e`，服务端没有新迁移或协议修改。
- 修复 DERPRegion 增量没有更新 HomeDERP、首张 DERPMap 后延迟上报 home 导致的单向通信；按上游实际代码接受显式 A / AAAA 扩展记录。
- Linux 不接管系统 DNS / 默认出口。Android 默认仍是私网模式，DNS 与出口由用户明确开启；手机不是子网或出口路由器。

### Security impact

- 所选出口撤销后保留有效 VPN 的双栈接管路由，公网与 DNS 不回退；私网仍能访问。主动断开、系统撤销 VPN / 杀进程后恢复普通网络，不冒充锁定模式。
- DNS 地址避让 LAN、远程网段、解析器与扩展地址；外部查询绑定随机事务和问题，普通网络 UDP / TCP socket 继续保护；IPv6 系统 DNS 保留数字 scope。
- 账号备注不当成人类认证；两个测试账号的服务端用户 ID、设备 ID 和 IP 均不同，切回时不再次提供 Auth Key，原设备和归属不变。
- fixture 位于 rootless user/net namespace，所有认证文件只从 stdin 写入专用模拟器私有缓存，读取后删除。测试明确 `--no-uninstall` 保留身份，不因签名或重跑清除数据；不触碰真机、生产账号或部署。

### Tests

- Dart / Widget 32 项、格式检查与 `flutter analyze` 通过；涵盖开关真实状态、出口候选与失效提示、同地址账号、切换先断开、旧账号迟到状态、小屏与既有接入流程。
- Kotlin 20 项单测，Debug assemble / unit test / lint 与 Release assemble / lint 通过；包括独立账号目录、旧目录沿用、同 ID 不可改控制地址、IPv6 DNS scope。
- 原生 Rust 3 项 lifecycle 测试、fmt / clippy / test 与 ARM64 交叉 clippy，通过锁定 Git 源构建 ARM64 / x86_64 JNI。
- 核心 Rust 27 项单测、官方 STUN 解析、真实 Linux namespace 官方 tsnet 双向互通、子网、ACL、UDP 阻断后的 DERP 回退恢复通过；本轮同时完成 SNAT、身份重连及非本程序规则保留回归。
- 专用 Android 36 x86_64 模拟器的 Debug 真实 VPN：系统解析器解析设备名、DNS UDP / TCP、未知私有域 NXDOMAIN、经 ACL 的远程 DNS；选择官方 tsnet 转发 fixture 后 IPv4 / IPv6 TCP 与 peerapi DNS-over-WireGuard；撤销后阻止公网与 DNS 回退、保留私网；同控制器第二账号独立授权及无密钥切回。原 ICMP / ACL / 子网 / 应用分流 / 切网恢复全部通过。
- DNS 普通上游的真实 UDP 与截断后 TCP 回退、IPv6 scope、远程网段 / 上游自循环避让由 Rust / Kotlin 单测验证；不把这些单测冒充 ARM64 真机验收。
- Release ARM64 / x86_64 APK 签名和 16 KiB 对齐校验通过，版本 `0.3.0+4`，实际 split versionCode 为 `2004 / 4004`。x86_64 Release 实际安装并检查设置、账号、DNS、出口、应用分流、诊断六页；截图来自该 APK，不连接生产网络。真实 VPN 验收是 Debug 集成测试，不冒充 Release 真机验收。

## 0.3.1 连接异常修复（2026-10-17）

### What changed

- 补齐 `dnsServers()` 的 R8 保留规则。Rust 按固定名称调用 Kotlin；发布包不能删除或改名该方法。
- JNI 错误标注固定回调名，不读取或打印 Java 异常正文、连接参数或凭据。
- 新增最终 APK 的 JNI 契约检查：从实际 Rust 调用点提取方法名和签名，用官方 `apkanalyzer` 检查原始 DEX；CI 对两个 ABI 的发布包执行，不使用反混淆映射掩盖改名。
- 版本 `0.3.1+5`，ARM64 / x86_64 实际 versionCode 为 `2005 / 4005`。

### Why

0.3.0 的 `usage.txt` 明确记录 `dnsServers()` 被裁剪，两个已发布 APK 的 DEX 均缺失该方法。读取系统 DNS 位于建立首张网络映射的路径，即使未开启 MagicDNS，也会触发 JNI 异常。Debug 不进行这项裁剪，之前的 Debug VPN 集成和 Release 页面检查没有覆盖故障。

在专用模拟器安装原 0.3.0 Release，使用隔离服务中已注册的临时机器身份，实际复现 `Java exception was thrown` 且未显示已连接；保留相同身份、配置和签名覆盖安装 0.3.1 后，真实 VPN 成功建立。不用删除账号、清空数据或重新签发设备密钥绕过问题。

### Compatibility impact

- 内核仍固定 `33f47a10861fb444aeef915c8e0c233b22d4de5e`，不修改控制面、DNS / Tailscale 协议、套餐、身份目录或配置迁移。
- 本地发布签名与上一公开预览包一致，支持覆盖升级。其他 CI 签名不自动视为相同；签名冲突时不建议卸载或清除数据。

### Security impact

- 没有关闭 R8、TLS、ACL、套接字保护或身份检查，也未添加可从外部注入配置或密钥的生产入口。
- 回归只访问 rootless 隔离 fixture。测试身份和模拟器偏好仅在专用 AVD 中准备；真实流量由普通 shell UID 2000 发起，不能把 root 准备步骤当作 VPN 可达验收。
- 发布包保持不可调试；Auth Key、私钥和生产账户不进入仓库、APK、公开日志或测试截图。

### Tests

- 5 项 JNI 契约检查器测试通过；两个原 0.3.0 发布包均被正确拒绝；两个新发布包均保留全部 6 个回调及原始签名。
- Dart 格式、analyze、32 项测试；Rust fmt、clippy、3 项生命周期测试；Kotlin 20 项测试与 Debug / Release lint 通过。
- Android 36 x86_64 的实际混淆 Release，覆盖升级后确认原机器地址不变；普通 UID 的 ICMP、IPv4 / IPv6 TCP、私有 DERP、批准子网访问成功，禁止 ACL 端口仍拒绝。
- 在 Release 界面开启网络 DNS 后自动重建连接，Android 系统解析器成功解析 `rust-router.core.test`。
- Release 选择官方 tsnet 出口后，实际 IPv4 / IPv6 公网 TCP 和 peerapi 加密 DNS 成功；撤销出口后 VPN 保持、公网被阻止、私网仍可访问，UDP / TCP DNS 均返回 SERVFAIL，不回退普通网络。
- 两 ABI 的 Release 构建、签名和 16 KiB APK 对齐校验通过；Release manifest 的 `debuggable` 为 false。

ARM64 物理手机、各厂商后台和物理移动网络仍需真机验收，不用 x86_64 模拟器结果冒充。

## 0.4.0：加密 DNS / 本地 DNSSEC / 共享地址转换

### What changed

- DNS 页右上角进入独立的解析器编辑页，支持 IP、DoH、DoT、最多四个引导 IP 与本机 DNSSEC。保存按钮固定在底部，旧账号编辑页不能覆盖切换后的账号。
- Rust 内核固定 `48a4abc7d3f32e140115c079183d6c2ab004a0f8`，本地验证完整 DNSSEC 信任链；原始 AD 被清除，只有本地验证成功且查询设置 DO / AD 才置位。未请求 DNSSEC 时移除未显式查询的签名记录，兼容普通手机解析器。MagicDNS 的本地记录不冒充 DNSSEC 签名。
- DNS / DNSSEC 设置按账号保存，默认保持关闭。设置在网络 DNS 关闭时保留但不启用；出口模式仍使用所选出口的 peerapi，绝不因自定义解析器绕回手机原网络。
- 系统诊断增加私人 DNS 的开启 / 严格状态，未知明确显示未知，不导出提供商名称；可由用户打开系统网络设置，不越权更改系统开关。
- 内核按认证 peer 的共享别名转换源 / 目的地址及双栈校验和，不合并机器身份，也不跳过来源 / ACL 检查。

### Why

不能把解析器 URL 只存到界面，不能把上游 AD 当成本机验证，不能让同一控制器的不同账号共享私钥。手机上的高级设置应是独立可收纳页面，而不是把连接首页继续加长。

### Compatibility impact

- 无服务端迁移、新端点或协议分叉；保留旧 catalog_v2 和身份目录，新增字段默认空 / false。
- 版本 `0.4.0+6`，两个 ABI 的基础版本递增；正式包继续沿用上一公开预览的本地测试签名。
- DNSConfig / BootstrapResolution 和 SelfNodeV4/V6MasqAddrForThisPeer 按上游语义消费。Linux 不接管宿主 DNS / 默认路由。
- 完整 Tailnet Lock 未完成，启用时明确拒绝不具备本机签名链验证的连接，不冒充已支持。

### Security impact

- 所有物理 DNS socket 仍 protect；TLS 校验 CA / 主机名，没有测试 CA 或接受任意证书的生产开关。加密或签名失败返回失败，不降级明文；DNSSEC 子查询也使用原来的 DNS / 出口路由。
- 凭据 / query / fragment 不进入解析器 URL；DNS 设置解析不发起系统 DNS，非法地址错误不回显原始输入。脱敏诊断不包含自定义解析器 URL、IP 或查询域名。
- Android 私人 DNS 和任意第三方 HTTPS DoH 无法在不破解证书的前提下透明强制改写。这里提供检测与用户设置引导，不使用中间人证书、不伪报已全局接管。

### Tests

- Dart 38 项测试、analyze；Kotlin 23 项测试、Debug lint；JNI 生命周期 3 项及 APK 契约检查器 5 项通过。
- Rust 36 项单测、fmt / clippy；另外实际运行公共 DoH 验证签名记录、签名 NXDOMAIN、错误签名域名拒绝及普通解析器响应兼容。官方 Go 对照 STUN 与双栈 TCP / UDP / ICMP 地址改写通过。
- Linux 真实 namespace 的普通与 SNAT 模式通过，包括官方 tsnet 双向、独立子网、ACL、阻断 UDP 后 DERP 回退、恢复和 NAT 清理。
- `XUNARA_TEST_PUBLIC_DNS=true scripts/test-android-vpn.sh` 在 Android 36 x86_64 完整通过：真实 TUN、普通 UID 流量、MagicDNS、真实 DoH / DoT 与 DNSSEC 正反例、切网、应用分流、官方出口撤销后公网 / DNS 不回退、同控制器账号隔离和原身份恢复。
- 两个 ABI 的最终 Release 均保留 6 个 JNI 回调，签名 / 16 KiB 对齐 / 不可调试检查通过，versionCode 为 `2006 / 4006`。实际安装的 x86_64 APK SHA256 与待发布文件一致，同身份接入隔离服务；普通 UID 的双栈 TCP、MagicDNS、DoH、DNSSEC 签名正例、签名 NXDOMAIN、伪签名失败及 DO / AD 响应兼容通过。新增截图来自该 Release。
- 核心 AMD64 / ARM64 musl 构建通过；两者均没有外部 INTERP / NEEDED，AMD64 实际运行版本命令通过。没有把 Linux 二进制当作 Android 程序。

### 尚未完成

- 手机作为子网 / 出口路由器：默认按免 Root 用户态转发推进，需要 TCP / UDP / ICMP 数据面、批准路由交集、ACL 更新时关闭旧流、出口 peerapi DNS 和远端官方客户端的专项验收；不是只广播路由。
- 完整 Tailnet Lock：本机密钥 / 信任根、AUM 验证和同步、节点签名、轮换、撤销、带证明的禁用，以及持久化 / 损坏恢复均须完成，不先挂无效开关。
- 共享 masquerade 已接入内核与协议对照，跨租户共享的专项端到端验收仍未完成；ARM64 真机和厂商后台仍需实测。

仍需单独验收：ARM64 真机、厂商省电 / 长时间后台、真实蜂窝漫游、Android UDP 直连、严格私人 DNS / 应用 DoH 与长期正式签名。完整 Tailnet Lock、手机子网 / 出口转发和跨租户共享专项验收尚未完成；DoH / DoT、本机 DNSSEC 与 peer 专属共享地址转换已按上述范围实现。

## 0.5.0：手机子网 / 出口转发与跨租户共享验收

### What changed

- Rust 固定到 `00c8e9f64fce34878c5d860be1cc597f2f28a868`，正式构建不使用本机路径依赖。独立「共享本机网络」页支持 CIDR、提供出口、实际批准状态与连接数，固定底部保存；账号变化后旧页面不能覆盖新配置。
- 有界 TCP / UDP / 真实 ICMP Echo 用户态转发，物理 socket 使用前保护。出口提供官方 peerapi DNS，手机自身网络 DNS 默认不因此启用；不开放物理代理端口。
- 重连主动发送有额度限制的首握手，避免纯接收端等待对方旧 WireGuard 会话失效；ACL、机器来源、共享别名和路由变化清理旧流。聚合收包 / 拒绝计数不包含业务内容或凭据。
- 物理默认网络选择区分默认资格丢失与真实断网，避免自身 VPN 重配被误判为切网。回归测试额外核对仅撤销出口路由时内核 generation 不变，防止误重连造成 DNS 绕出 VPN。
- 设备清单和详情标识跨网络共享。清理当前架构文档中过时的「只接收子网」「不安装 DNS」与按服务器共用身份目录描述。

### Why

手机作为路由器必须有真实数据面，不能只有广播开关。共享必须实际穿过原地址重叠的两端，并验证接受、撤销和其他用户 / 租户边界。

### Compatibility impact

- 沿用官方 `Hostinfo.RoutableIPs`、`Services`、`AllowedIPs`、WireGuard 和 peerapi；不修改控制面兼容协议，不在 App 内捆绑 Go sidecar。
- 版本 `0.5.0+7`；ARM64 / x86_64 APK 版本码分别为 2007 / 4007。延续公开预览的本机测试签名；完整 Tailnet Lock、文件传输及自动升级仍未完成。

### Security impact

- 路由请求与批准取交集，出口双栈同时获批才生效。来源 / ACL / 路由撤销关闭旧流，出口失效不回退为手机直连。
- 跨租户使用 `(provider_id, subject)` 和目标租户绑定；错误用户和同 subject 的其他租户不能接受或访问共享机器。共享不带出源租户的子网和其他机器。
- 测试保留原偏好、账号和机器私钥；临时密钥经 stdin 进入应用私有缓存，不在 URL、argv 或 APK。诊断快照剔除授权 URL，私有 fixture 目录不作为公开产物。

### Tests

- Rust fmt / clippy / 全量测试：默认 43 项通过；外部 DoH / DNSSEC 与真实 ICMP 测试、2 项官方协议向量另行执行通过。Go fixture build-race / vet / test-race、Linux 真实 netns 普通与 SNAT 回归通过。修复 DNS 测试双协议临时端口碰撞，仅重试端口预约，不重试功能断言。
- Flutter analyze / 41 项测试、28 项 Kotlin 单测、3 项 JNI 生命周期和 5 项实际 DEX 合约测试通过。正式 APK 构建、签名、16 KiB 对齐及实际安装另按发布产物核对。
- 专用未 Root Android 36 x86_64 模拟器对接真实 Xunara 控制面 `fabf0991cdf27c8bff927f7928f4c8806d8a59c2` 与官方 tsnet v1.104.1：批准前禁止转发，批准后双栈 TCP / UDP / ICMP Echo；ACL 禁止端口、撤销 ACL 后旧 / 新流拒绝、撤销子网、手机出口与 peerapi DNS、撤销默认路由后旧流关闭均通过。
- 三租户实际注册、控制面 API 创建 / 接受 / 撤销共享；原地址完全重叠时双栈别名与 ICMP / TCP 通过，ACL 禁止端口和源子网仍不可达。待接受不可见，同租户另一用户及同 subject 的第三租户不能接受 / 访问；撤销后移除 peer 和真实路由，切回原控制器 / 账号无需接入密钥。
- 本机完整专项包含公网 DoH / DoT、DNSSEC、双栈手机转发、共享以及出口撤销时 generation 不变，全部通过。实际 R8 Release 同签名覆盖后无密钥恢复原临时机器，真实双栈 TCP 与系统 MagicDNS 通过；已安装文件 SHA256 与待发布 x86_64 APK 一致，停止后 VPN 移除。共享页面在实际 Release 手动复核，自动化额外等待固定保存按钮出现，避免把导航动画中的设置列表当成目标页。

### 尚未完成

完整 Tailnet Lock 的本机信任根、AUM 链、签名 / 轮换 / 撤销和持久恢复仍需实现；不提供虚假开关。ARM64 物理手机、厂商省电和长期后台、真实蜂窝漫游、Android UDP 直连与长期正式签名仍需单独验收。严格私人 DNS / 任意应用 DoH 只能检测和引导，不能在不破解 TLS 的前提下透明强制改写。

## 2026-10-19：双安卓公网出口复测

### What changed

新增 `integration_test/exit_pair_test.dart` 和 `scripts/test-android-exit-pair.sh`：两台独立安卓身份接入隔离控制面，真实申请、批准并选用手机出口；普通 UID 验证公网 IP / HTTP、真实公网 DNS UDP / TCP 和撤销后的失败关闭。DNS 检查器新增不依赖 CDN 固定地址的 ANSWER 检查。

### Why

官方 tsnet 与单台安卓之间的回归不能替代“安卓使用另一台安卓出口”的公网测试。此次专项模拟默认 ACL 和公网 DNS 配置，区分控制面配置、WireGuard 数据面和实际物理网络的故障。

### Compatibility impact

只修改测试和验收文档，不改变 APK、协议字段、路由授权、DNS 转发或生产 ACL，不发布未经验证的新客户端版本。测试内核仍为 `00c8e9f64fce34878c5d860be1cc597f2f28a868`，控制面为 `fabf0991cdf27c8bff927f7928f4c8806d8a59c2`。

### Security impact

无认证的 fixture 审批入口只在 rootless user / network namespace 中启动，宿主代理仅绑定回环。接入密钥经 stdin 进入私有缓存，不进 URL、argv、APK 或 Git。升级前核对原签名，保留原账号与私钥，结束恢复偏好和原 APK；不使用线上平台令牌，不修改现网租户配置。

### Tests

- 两台未 Root Android 36 x86_64 模拟器实际通过：出口双栈获批、客户端 DNS 接管、普通 UID 经安卓出口访问 `1.1.1.1:80` 并取得真实 HTTP 响应，公网域名 A 查询 UDP / TCP 均有答案。
- 出口有实际解密 / 转发流量，ACL、来源和解密丢弃计数为零；撤销出口后 DNS 为 SERVFAIL、公网 HTTP 无响应，客户端 generation 保持不变，没有通过直连伪造成功。
- Flutter analyze / 41 项普通测试、Rust fmt / clippy / 43 项普通测试、Go fixture test-race / vet / build-race 和 Linux 真实 netns 回归通过。
- 扩展回归 `XUNARA_TEST_PUBLIC_DNS=true XUNARA_TEST_PHONE_ROUTER=true XUNARA_TEST_RELEASE_APK=... scripts/test-android-vpn.sh` 完整通过：真实 DoH / DoT、DNSSEC 正反例、官方出口、手机双栈 TCP / UDP / ICMP、ACL / 路由撤销以及实际混淆 Release 升级后的双栈 TCP / 系统 MagicDNS。
- 首轮扩展回归在错误签名域名的 TCP 查询中出现一次无响应，现场曾发生重连；未改生产代码的完整复测通过，但不将首轮失败改判为成功，也不据此认定现网故障根因。模拟器同时冷启动等实验室物理网络变化不能替代真机现场诊断。

### 尚未确认

双安卓专项使用 Debug 入口，不代表 ARM64 物理手机、厂商后台、实际蜂窝网络或双安卓 Release 全部通过。实验室成功不等于现网问题已修复；现场仍需两台设备同时在线，核对实际 APP 版本、出口选择、后台限制和两端运行诊断。
