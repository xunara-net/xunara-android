# 0.5.5 设备在线状态与官方 Android 双向出口测试

## What changed

- 内核固定至 `22d0d5b6aff7aa2db8877b982dd395ed29cdc310`，不复制另一套控制协议。具体差异、固定上游和真实 TUN 红绿回归见[核心审计](https://github.com/xunara-net/xunara-client/blob/22d0d5b6aff7aa2db8877b982dd395ed29cdc310/docs/exit-return-presence.md)。
- 设备列表和详情显示在线、离线、未知及最近在线。未收到状态不伪装成离线，不用密钥到期时间代替最近在线；小屏状态可换行。
- 已知离线出口禁止新选择；已保存的出口离线时保留原选择，提示检查远端，不自动换出口或直连。确认弹窗期间重新核对账号、连接代次和当前出口状态。
- 已建立 TCP 的出口 peerapi DNS 使用十秒资源预算，未建连仍有四秒快速失败。保留固定出口，不改为手机原网络解析。
- ICMP 错误引用必须匹配未过期的本机出站连接，仍经过 WireGuard 身份、来源、目标和地址冲突校验，不放行任意 ICMP 或重定向。
- 中继反向路由只从已通过 WireGuard 校验的 peer 学习，绑定具体 DERP 连接；连接重建、PeerGone 和节点删除清除旧提示。正常已连接 home 仍优先，控制面 home 未同步时不再把合法回包发往区域 0。
- 诊断区分真实 DNS 请求、生成响应、SERVFAIL、NXDOMAIN、超时与 VPN DNS 数据包。只导出白名单数字，不包含查询域名、地址、报文或凭据；代理重建后消息统计重新开始。

## Why

旧模型没有保留官方 Online / LastSeen，也没有合并 OnlineChange / PeerSeenChange，单独添加 Flutter 标签无法解决状态缺失。
旧内核还把正常的 ICMP 错误当成没有许可的新流；真实独立 LAN 的 UDP 关闭端口测试在旧二进制上只能超时，修复后收到 ECONNREFUSED。
官方 peerapi 允许五秒解析，旧内核四秒就放弃已连接请求；回归完成真实用户态 TCP 握手，再把已等待时长设为 4.5 秒，验证旧版提前失败而新版交付合法答复。这不是物理链路延迟实测。

扩展共享回归先发现夹具的 ICMP 来源遗漏共享别名，修正后仍无法收到回包；增加握手等待也没有解决。隔离跟踪确认请求已放行、Linux 已生成回复，但 peer 的 home 尚为 0。补齐官方已有的连接绑定反向路由后，共享双栈通信、隔离与撤销通过。跟踪代码已删除，不把局部夹具修复或中继握手冒充业务通过。

这些是已复现的差异，不足以单独解释用户原手机的全部断网；不能用解密包数、DNS 包数或中继心跳宣称已出网。

## Compatibility impact

不改服务端、数据库、现有审批、ACL 或 TS2021 / Noise / WireGuard / DNS / DERP wire。
消费已有官方状态字段；在线报告与授权、数据面健康独立，状态更新不切换机器身份或出口。
Android 8.0+ 和 ARM64 / x86_64 保持不变，同测试签名可覆盖升级，不需要卸载、清数据或重新签发机器密钥。

## Security impact

保留 TLS / 私有中继证书 pin、来源校验、ACL、LAN 优先、固定出口与 VPN 内失败关闭。
测试使用两个新建专用 Android 36 x86_64 模拟器，应用没有 root，业务由普通 shell UID 2000 和真实 Chrome 发起，不用豁免 VPN 的 App 请求代替。
隔离控制面 / DERP 运行于 rootless user / network namespace，宿主代理只绑定回环地址；临时 Auth Key 从 stdin 写入受保护文件并在读取后删除，不进入 argv、URL、日志或 APK。
不借用原手机机器私钥，不改生产设备归属、批准、DNS 或 ACL；模拟移动网络不等于真实运营商。
强制中继对照只在本轮新建模拟器中由测试管理员添加限于玄序 UID 的临时 UDP 丢弃规则，保留物理 DNS；业务探针仍为 UID 2000，应用没有 root。规则已按原规则精确删除，没有修改宿主防火墙或清空系统已有规则。

## Tests

### 已执行的双向混测

官方 APK 来自官方 GitHub 的 `1.98.8-t1241b225b-gbcbaf1889`，版本码 626；文件 SHA256 为 `f28edfd184d1db3060d764a79c9aa24da4530951052fb1cf75c92bbc0adfc4b2`，发布摘要与签名已核对。
控制面仍为 Xunara 隔离 fixture，中继 1 不可达、900 可用；两端报告实际连接的 900，不伪造回退状态。

| 出口提供端 | 出口使用端 | 已实际通过 |
| --- | --- | --- |
| 官方 Android 1.98.8 | 玄序 0.5.5 | 公网 IPv4 HTTP、VPN DNS UDP / TCP、系统域名解析、系统 CA 与主机名校验的 HTTPS 200、Chrome 实际页面 |
| 玄序 0.5.5 | 官方 Android 1.98.8 | 公网 IPv4 HTTP、VPN DNS UDP / TCP、系统域名解析、系统 CA 与主机名校验的 HTTPS 200、Chrome 实际页面 |

普通混测允许直连，不能只凭 home 900 宣称业务全部经过中继。另行在玄序提供端单向丢弃外层 UDP 后，实际丢包计数增长、direct_peers=0、设备路径回到中继候选，官方消费者仍完成真实 DNS / HTTPS 200；该轮才作为强制 DERP 的业务证据。

官方出口进程停止、恢复时，玄序的同一设备从在线变离线再变在线，离线时有 LastSeen；原出口 StableID 与连接代次保持不变。
正式应用入口的设备列表也已实际显示同一个官方对端从在线变离线，不仅验证测试 JSON 或 Widget 假数据。
恢复后的第一轮 DNS 请求曾超时，不能把 Online=true 当成业务就绪；随后实际 IP HTTP 与 DNS / HTTPS 恢复通过，保留失败记录，不将其改判成功。
撤销玄序出口双栈批准后，实际 forwarding.active 变为 false，官方消费端公网请求超时而不是直连。

原始并发 netcat 探针一轮没有收到 UDP 答复，顺序复测取得有效 UDP / TCP 答复，失败轮次仍保留。
官方消费端 TCP DNS 的空答复另做了对照：立即结束 stdin 可重复得到空文件，保持写端打开后取得有效答复；官方 DNS Manager 在读到 EOF 时会关闭会话并撤销查询。测试命令应在写入 DNS 帧后保持 stdin 打开到答复完成，不能把探针提前半关闭当成出口故障，也不能把空文件或进程退出码当成成功。参见[固定版本的 TCP 会话处理](https://github.com/tailscale/tailscale/blob/v1.98.8/net/dns/manager.go)。

### 源码与内核回归

- Flutter 格式、analyze、49 项模型 / Widget 测试通过，包括 360 像素列表、三态状态更新、离线出口禁选及确认期间状态变化。
- 原生 Rust fmt / clippy / 3 项生命周期测试、ARM64 交叉 clippy、两个 ABI 原生构建和 JNI 合约 5 项测试通过。
- Android Debug 单测与 lint 通过；没有提高最低 SDK 或关闭 lint 规避检查。
- 核心 Rust 59 项普通测试、另行显式执行的两个上游兼容向量，Go fixture build / vet / test / race 通过。
- 冻结最终内核二进制的普通 / SNAT / 坏首个 DERP 真实 namespace 回归通过：官方 tsnet 双向通信、批准子网、ACL 拒绝、相关 ICMP、UDP 阻断回退与恢复；旧二进制 ICMP 测试失败，不将失败混入通过结果。

### 最终内核与 APK 验收

最终包源码为 `3b6ad350640e3bde01c315214ace84de00776345`，内核为 `22d0d5b6aff7aa2db8877b982dd395ed29cdc310`。基础版本码 12，ARM64 / x86_64 实际版本码为 2012 / 4012；测试签名与 0.5.4 相同，可直接覆盖，不卸载、不清除玄序数据。

- 两 ABI 的实际 DEX 均保留六个 JNI 回调，原生 ELF 和 APK 通过 16 KiB 对齐、架构、签名及版本检查。最终 AOT 包含新增诊断，默认控制器正确，不含集成测试入口、临时密钥或明文跟踪代码。
- 固定最终内核后，完整 Android 扩展回归退出码 0：真实 TUN、双栈 TCP、拒绝 ACL、远程子网、系统 MagicDNS、UDP / TCP DNS、Wi-Fi / 模拟移动切换、后台蜂窝退出不误重连、应用分流、官方 tsnet 出口、手机免 Root 双栈转发和三租户共享隔离 / 撤销全部通过。
- 同一流程覆盖安装最终混淆 Release，无新密钥恢复既有身份，验证双栈 TCP、系统 MagicDNS、网络共享页面与停止清理；不是用 Debug 或空界面冒充 Release。
- 两向混测各自先完成独立机器授权，再覆盖为最终 Release、无新密钥重新连接。官方 1.98.8 提供出口 / 玄序消费，以及玄序提供出口 / 官方消费，均实际完成公网 IP HTTP、DNS UDP / TCP、系统解析、校验系统 CA 与主机名的 HTTPS 200 和 Chrome 页面。
- 最终 Release 的强制中继对照中，临时 UDP 规则实际丢弃 47 包，direct_peers=0、本机 home=900、转发 active 且有真实流量；官方消费端仍取得 DNS / HTTPS 页面。撤销出口后纯 IP 请求超时，不回退直连；临时规则随后删除。
- 最终 Release 的设备页面实际显示同一个官方设备从在线变离线。Flutter 49 项、Kotlin 31 项、native 3 项、JNI 合约五项及 Debug / Release lint 通过；恢复生产入口后重新生成的两个 APK 与验收包逐字节一致。

Chrome 曾只向 UIAutomator 暴露 Web View，而实际页面已经渲染，固定查找 Example Domain 的旧断言失败；失败脚本保留，最终页面以实际截图目视核验，TLS / 正文则另由验证证书的探针独立验收。切换隔离控制面时官方测试 AVD 的旧登录状态也导致一次准备失败，重置的仅是本轮一次性官方测试环境，不是用户手机或玄序账号；这不作为产品故障修复或无损迁移的证据。

本轮不把代理心跳、绿色连接、包数或最终安装成功等同于用户真机恢复。ARM64 真机、真实运营商和公网 IPv6 仍未验收；生产设备、审批与服务未改动。

## 发布与清理

已发布 [v0.5.5-preview.1](https://github.com/xunara-net/xunara-android/releases/tag/v0.5.5-preview.1)。两个 APK、BUILD.json 和 SHA256SUMS 从 GitHub 重新下载后校验通过；下载包与实际验收文件逐字节一致，签名再次验证通过。发布源仍为上述 `3b6ad35`，后续提交仅补充验收记录；对应 Android 和核心代码 CI 均通过。

- ARM64 SHA256：`6f76508732b6bca7d5f8f94c2c720cea4aadf2847a77c578110981c3f5ab8268`
- x86_64 SHA256：`f5ded0362137ed227a522995ec72b1f3358e3ddceaf91d2d26f46aa6b842aea3`

隔离服务、代理与测试端口已关闭，临时 UDP 规则已删除。仅删除本轮两个一次性 AVD，原有三个 AVD 保留；清理 21 个隔离状态目录及 99 份已知明文临时凭据，保留脱敏日志和无密钥截图，原始 UI 树也已移除。没有通过清除用户手机数据、转移设备、放宽生产 ACL 或重启生产服务使测试通过。
