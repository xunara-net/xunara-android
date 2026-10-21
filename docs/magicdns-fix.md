# 0.5.6 MagicDNS 与出口 DNS 验收

## What changed

内核固定到 `607d7bc74ad6a0248d6268477bf64a026953b623`，继续使用独立 Rust 内核，不打包 Go sidecar。具体 DNS 调用链、固定官方版本与保护边界见[内核记录](https://github.com/xunara-net/xunara-client/blob/607d7bc74ad6a0248d6268477bf64a026953b623/docs/android-dns.md)。

- 设备 MagicDNS 正向 / 反向记录、搜索域、权威 NXDOMAIN 与网络内分流保留。
- 玄序手机提供出口时，默认公网解析改用该手机物理网络 DNS；平台 / 用户显式加密解析、DNSSEC 和私有分流不被绕过。
- 同组直连解析器有界错峰竞争，避免首个公共 DNS 不通时所有查询排队等待。消费者仍只查询原来选择的出口。
- DNS 地址冲突退避统一用于 Android 系统配置和内部代理。
- 脱敏诊断单独列出其他设备经本机出口的 DNS 查询、生成响应和失败响应，不将其混为本机应用查询，也不导出域名或报文。

## Why

0.5.5 的出口 peerapi 复用了平台 DNS，而官方 Android 的出口解析使用宿主解析能力。公网 IP 通畅不能说明手机能访问平台选择的公共 DNS。旧版还串行等待解析器，首个 DNS 黑洞会阻塞健康备用地址。

在两台新建 Android 36 x86_64 模拟器上，以同一控制面、同一机器身份、同一出口批准构造“平台 DNS 被阻断，手机物理 DNS 可用”的场景：0.5.5 的直接 IP HTTPS 成功，依赖域名的 HTTPS 明确报 `lookup example.com: i/o timeout`；覆盖安装 0.5.6 后，依赖域名的 HTTPS 取得 200，并验证系统 CA 和主机名。

第一次只给出测试 DNS 地址时，旧版仍解析成功，因此该轮不能作为有效负对照。随后仅对本轮专用出口模拟器的玄序 UID，阻断该测试 DNS 的 UDP / TCP 53，确认实际丢弃计数增长后再做红绿对照。规则在升级前后保持相同，没有封禁手机物理 DNS，也没有修改生产网络。

## Compatibility impact

不改服务端、租户 DNS、现有设备归属 / 审批、ACL 或官方协议。参考[官方 Android VPN DNS](https://github.com/tailscale/tailscale-android/blob/1.98.8-t1241b225b-gbcbaf1889/libtailscale/net.go)与[官方宿主出口解析](https://github.com/tailscale/tailscale/blob/v1.98.8/net/dns/resolver/tsdns.go)适配 Rust 实现，不声称已移植官方全部系统 DNS 实现。

Android 8.0+、ARM64 / x86_64 不变。应用版本 `0.5.6+13`，实际 APK 版本码 ARM64 为 2013、x86_64 为 4013。签名与本地发布的 0.5.5 相同，可以覆盖安装，不卸载、不清账号 / 机器身份。
两端均使用玄序时，两台都需升级；官方出口或使用端可以保留官方客户端。

## Security impact

保留固定出口失败关闭、LAN 优先、来源与 ACL 校验、随机 DNS ID / 问题校验、TLS 证书与主机名验证；不硬编码额外公共 DNS、不将消费者查询直接送手机原网络。
平台或用户加密解析与本地 DNSSEC 不降级；私有分流、MagicDNS 和权威 NXDOMAIN 不送到宿主默认 DNS。

测试控制面 / DERP 位于独立 rootless namespace，宿主代理只监听回环地址；Auth Key 通过 stdin 和受保护文件导入，不写入 argv、URL、日志或安装包。
业务探针为普通 Android shell UID 2000，不用豁免 VPN 的 Flutter / 原生应用 HTTP 冒充业务。临时 DNS 丢弃规则仅由测试管理员加入专用模拟器，不给应用 root。
生产只读取过 demo 的 DNS 配置与设备状态，临时人类会话已撤销，未修改生产设备、批准、DNS 或 ACL。

## Tests

- Rust fmt、clippy、64 项普通测试及两项显式执行的官方兼容向量；Go 隔离夹具 build / vet / test / race 通过。
- 最终内核实际 TUN / 官方 tsnet / ACL / 子网 / UDP 阻断后 DERP 回退与恢复通过；先前同改动的 SNAT 回归也通过。
- Flutter analyze、49 项单元 / Widget 测试、native fmt / clippy / 3 项生命周期测试、ARM64 交叉 clippy、Kotlin 单测与 Debug / Release lint 通过。
- 两 ABI 原生构建通过；实际 Release APK 的六个 JNI 回调、版本、原测试签名、ELF / ZIP 16 KiB 对齐通过。
- 最终 Release 双玄序出口：在平台 DNS 仍被阻断时，公网 DNS UDP / TCP、验证证书的 HTTPS、Android 系统 MagicDNS 全名及短设备名通过。覆盖升级未重新签发机器接入密钥。
- 官方 Android 1.98.8 使用最终玄序 Release 提供的出口：公网 DNS / HTTPS 200、系统公网域名解析和 MagicDNS 通过；撤销出口后公网 IP 请求超时，没有直接回退。

以上是专用模拟器验收，不代表已收到用户原物理手机复测结果。Android 严格私人 DNS、应用自带 DoH、运营商 IPv6-only 等既有边界仍需分别验证。

### 完整回归与失败记录

最终固定脚本的 Android 扩展回归退出码为 0，包含短设备名的系统解析、普通 UDP / TCP DNS、官方 tsnet 双栈出口与 peerapi、出口撤销后的 DNS SERVFAIL / 公网阻断、手机双栈转发、ACL 撤销关闭旧流、共享 masquerade 的隔离 / 撤销、账号切换，以及实际混淆 Release 的同身份升级。

另一次开启外部 DoH / DNSSEC 的扩展运行，在 Cloudflare UDP 探针阶段没有于十二秒内取得答复，判定失败，不计入通过；Android 上该扩展仍未完成验收。宿主 Rust 的真实 DoH 签名链、签名否定证明与伪造链拒绝测试单独通过，不能代替 Android 结果。
探针预算随后调整为十六秒，使其长于内核十二秒验证期限；没有增加内核信任或跳过签名检查，也没有把调整前的失败改判成功。

一轮普通回归已完成全部业务断言，但测试运行期间修改同一 shell 脚本造成执行游标错位、退出 127；该轮不作为完整通过证据。最终停止修改脚本后重跑，业务和流程均退出 0。

### 最终安装包

应用源码 `a9bac9d1ad990936cf1828a4fa9f386dd99de731`，内核 `607d7bc74ad6a0248d6268477bf64a026953b623`。源码 CI `39589007171` 通过。

| ABI | 实际版本码 | SHA256 |
| --- | --- | --- |
| ARM64 | 2013 | `29d3a9e3f39e8a3d32a056e779fd778168917631dd9c0ec89643de3b9360489f` |
| x86_64 | 4013 | `93f448ca96373ac632e33be06e68dc06da8733b18ea89951733ad8489e44272f` |

测试签名 SHA256 为 `261f75400df5d471f1c5067d27be2577ea6d76a93f096e61e5ec73fd59374c37`，与上一手工预览版一致。下载需同时核对发布的 `BUILD.json` / `SHA256SUMS`，不能混用 CI 随机构建签名。

已发布 [v0.5.6-preview.1](https://github.com/xunara-net/xunara-android/releases/tag/v0.5.6-preview.1)，从公开下载地址重新取得两个 APK、BUILD.json 与 SHA256SUMS，校验全部一致。集成测试后恢复 `lib/main.dart` 重建的两个包与已验收包逐字节一致，最终 Kotlin 单测及 Release lint 再次通过。
临时 DNS 丢弃规则、代理、namespace、凭据 / 状态目录及两台本轮专用 AVD 已清理，原有三台 AVD 与生产设备配置保留；失败记录保留于受限测试日志，不将其改判通过。

## 0.5.7：DNS 展示与真机排查

### What changed

DNS 页仅展示网络配置的解析器、搜索域、分流域和启用状态，不将内部 VPN 监听地址当作 DNS 服务器。自定义解析器单独注明；选中出口时明确公网解析由出口提供，列出的网络配置不冒充出口实际使用的物理 DNS。内核固定到 `42e38326890d3253bef1b8553e81439860e58845`，只新增内存配置元数据，不改解析行为。

脱敏诊断增加 DNSSEC 保存状态与本次实际验证状态，避免仅凭“已连接”或“已保存”推断验证链路正常。

### Why

按照用户授权，以独立临时官方 Linux `tailscaled 1.102.2` userspace 设备接入真实租户，对两台手机执行只读 Termux 检查：

- 出口手机的系统公网解析、指定上游的 UDP / TCP DNS 和验证证书的 HTTPS 均得到有效结果；经 WireGuard 访问出口 peerapi `/dns-query` 得到 HTTP 200 和有效 DNS 答复。
- 临时官方客户端明确选择同一手机出口后，预解析地址的 HTTPS 取得 200；这不是默认物理网络直连的应用请求。
- 使用端手机的 Android 系统解析失败，预解析地址的部分 HTTPS 请求也超时。因此不能据此认定故障只涉及 DNS，更不能将页面展示改进写成故障已解决。
- SSH 后续间歇卡在握手，尚未取得两台当前应用版本、出口选择、应用分流与 DNSSEC 的完整诊断；已请求用户保持 Termux 前台。不能把 SSH 不响应直接认定为 VPN、账号或手机系统的根因。
- 后续复查时控制面已报告使用端离线，出口端仍在线；需恢复使用端连接后继续采集，不能用离线时的超时判定 DNS 根因。

### Compatibility impact

参考[固定版本官方 DNS 页面](https://github.com/tailscale/tailscale-android/blob/1.98.8-t1241b225b-gbcbaf1889/android/src/main/java/com/tailscale/ipn/ui/view/DNSSettingsView.kt)对已有配置做展示，不改变 TS2021、DNSConfig、WireGuard、DERP、系统路由或审批。内部 DNS 监听地址仍供 Android 配置与验收探针使用，未删除或替换。

### Security impact

不为排障更换原设备、出口、DNS、ACL、应用分流或账号密码。临时接入密钥只从受保护文件导入且接入后已撤销；SSH 密码经交互输入。原始手机报文、账号会话与密钥不提交到源码或发布产物。新增诊断只包含状态，不增加 IP、设备名称、出口身份或 DNS 查询内容。

### Tests

- Rust fmt / clippy、65 项普通测试与两项显式官方兼容向量通过；实际 TUN、官方 tsnet 双向访问、ACL、子网与 UDP 阻断后的 DERP 回退 / 恢复通过。
- Flutter analyze、51 项单元 / Widget 测试、360 像素 DNS 页面与不可变配置元数据测试通过；native 主机检查、3 项生命周期测试、ARM64 clippy 和两个 ABI 原生构建通过。
- 两台独立 Android 36 x86_64 的 Debug 测试通过公网 IP HTTP、DNS UDP / TCP、验证证书的 HTTPS，以及普通 UID 的 Android Bionic/netd 公网域名解析。最后一项是新增断言，不能仅以显式向代理发 DNS 或 Go 自带解析器代替系统解析；公网 ICMP 被禁不算 DNS 失败。
- 撤销出口后 DNS SERVFAIL、公网不直连、无错误重建通过。以上仍是专用模拟器结果，不等于原用户手机解析已恢复。
- 本轮采用十六秒探针，Android 的真实 DoH / DoT、完整 DNSSEC 签名链、错误签名拒绝及普通 VPN 完整回归通过。0.5.6 记录中的旧失败仍保留，不倒改旧运行结果；本轮没有为此禁用 DNSSEC 或跳过 TLS 校验。
- 实际混淆 Release 同签名升级、无接入密钥恢复身份、双栈 TCP、系统 MagicDNS 和新 DNS 页面通过；页面通过真实 JNI 元数据显示夹具解析器，不出现内部监听地址。最终包两个 ABI 均保留全部六个 JNI 回调，签名沿用 0.5.6，版本码为 2014 / 4014，ELF / ZIP 16 KiB 对齐检查通过。
- Kotlin 单测、Debug / Release lint 通过。直接 Gradle 编译曾受集成测试生成的插件注册文件影响而失败；显式使用 `lib/main.dart` 构建正式 APK 后重跑全部通过，没有用 Debug 包替代 Release。
- Rust 源提交 CI `39603705294` 通过；真机使用端故障仍待继续排查，本版不承诺修复该故障。

## 0.5.8：出口 DNS 连接泄漏

### What changed

内核更新到 `4c1f155d88c21a90afa0490b1a5662444aa82c52`。DNS 上游完成、失败或超时后显式终止 TCP，等终止帧入队后才回收用户态 socket；回压期间保留终止帧并有界暂停新连接。页面和账号设置沿用 0.5.7，没有改成其他 DNS 或出口。

### Why

真实用户域名在出口手机的系统解析、指定上游与 HTTPS 均成功，使用端却在 UDP / TCP 查询间出现 SERVFAIL 和超时。旧实现仅删除本地 socket，出口仍保留连接，每设备 32 条连接额度会被已完成查询占满。

先用真实 TCP 报文连接 DNSProxy 与 Forwarder：旧实现第 33 次查询停滞并留下 32 条流，新实现连续 48 次完成且释放连接。

再在两台独立 Android 36 x86_64 上复现，使用端仅将普通 shell UID 纳入 VPN，避免 Android 内核替没有 OS socket 的用户态连接补发 RST。旧内核 `42e3832` 的少量 DNS / Bionic / 公网 HTTP 都通过，但连续探针第 15 次地址查找超时；每次地址查找包含 A / AAAA，另有前序查询占用额度。

只替换为修复内核后，同一测试流程连续 64 次查找通过，耗时约 7.7 秒；出口记录 134 次 DNS 请求、134 次响应、零 SERVFAIL，剩余一条流包含后续 HTTPS。随后验证证书的 HTTPS 与撤销出口后的失败关闭通过。这不是凭一次网页成功判定长期可用。

### Compatibility impact

使用标准 TCP 终止语义，不改 DNSConfig、TS2021、WireGuard、DERP、ACL、路由、设备归属或审批。修复位于玄序使用端；原出口可以保留，覆盖更新不需要重新添加设备或提供接入密钥。旧出口的残留 DNS 连接仍需最多约三十秒回收，升级后应等待旧状态退出再复测。

### Security impact

不提高连接额度，不关闭 DNSSEC / TLS，不要求关闭浏览器安全 DNS，不回退其他出口或手机物理 DNS。仅选中 shell UID 是隔离测试配置，不写入正式安装包或真实用户的账号配置。外部 Go 探针由 adb 运行，不进入 APK，也不是客户端 sidecar。

### Tests

- Rust fmt / clippy、68 项普通测试、两项显式官方兼容向量、真实 TUN / 官方 tsnet / ACL / 子网 / DERP 回退恢复通过。
- Go 隔离夹具 build / vet / test / race 通过；探针单次与整体期限有界，单测验证每轮确实查询指定解析器而不是应用缓存。
- Flutter analyze / 51 项测试、native 主机与 ARM64 clippy、3 项生命周期测试、双 ABI 原生构建与双安卓红绿对照通过。
- 原物理手机仍需覆盖安装本版后复测；不将以上隔离测试写成真实使用端已恢复。
- 最终混淆 Release 同签名覆盖、原身份无密钥恢复、双栈 TCP、系统 MagicDNS、真实 DNS 页面及停止清理通过；Kotlin 单测、Debug / Release lint、两 ABI 的 JNI / 签名 / 16 KiB 对齐通过。
- 内核源提交 CI `39619538447` 通过。额外的本地 Linux musl 构建因缺少 `x86_64-linux-musl-gcc` 工具链未完成，不计入通过项；本次只发布 Android 安装包，不发布 Linux CLI 二进制。
