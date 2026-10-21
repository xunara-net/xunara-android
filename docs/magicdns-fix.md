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
