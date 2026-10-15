# 补充上游声明

这些文件仅保留第三方依赖的声明，不为 Xunara 自身指定许可证。

部分 crates.io 包没有打包工作区根许可证，补充来源固定到其 `.cargo_vcs_info.json` 的源提交：

- BoringTun 0.7.1：[原始 LICENSE.md](https://github.com/cloudflare/boringtun/blob/051c9d47dc9c5cb36e461b7d36dcd673820dc98b/LICENSE.md)。
- Tailscale Rust 0.6.1 的五个底层组件：[原始 LICENSE](https://github.com/tailscale/tailscale-rs/blob/d34658bbb2eb4593ae6df959aa93e9ee1e0457c6/LICENSE)。
- jni-sys-macros 0.4.1 选用 MIT：[原始 LICENSE-MIT](https://github.com/jni-rs/jni-sys/blob/64d77b7a5f119d7b55b4e2c169a4668067ff59e6/LICENSE-MIT)。
- cesu8 1.1.0 选用 MIT，作者与双许可声明来自 [该版源文件](https://github.com/emk/cesu8-rs/blob/f18962a9de5189f21600b7ff2898845157df4447/src/lib.rs)，同时保留 crate 中的 `COPYRIGHT-RUST.txt`。

`scripts/collect-native-notices.sh` 从固定 Cargo 图与原始声明生成应用内清单；缺失声明时失败，不静默略过。Flutter 自带依赖的声明由 Flutter LicenseRegistry 管理。
