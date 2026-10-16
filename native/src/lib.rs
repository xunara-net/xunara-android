use std::{
    os::fd::{FromRawFd, OwnedFd},
    sync::{Arc, Mutex},
    time::Duration,
};

use anyhow::{Context, Result, ensure};
use ipnet::IpNet;
use jni::{
    JNIEnv, JavaVM,
    objects::{GlobalRef, JClass, JObject, JString, JValue},
    sys::{jlong, jstring},
};
use serde_json::Value;
use tokio::sync::{mpsc, watch};
use xunara_client::{
    config::Config,
    control,
    diagnostic::PingRequest,
    engine::Engine,
    mobile::{self, Host, VpnConfiguration},
    state::Store,
};
use zeroize::Zeroizing;
mod lifecycle;
use lifecycle::Lifecycle;

// 这里只保存运行实例的停止通道，账号和机器身份不放入进程级缓存。
static LIFECYCLE: Mutex<Lifecycle> = Mutex::new(Lifecycle::new());

struct AndroidHost {
    vm: JavaVM,
    callback: GlobalRef,
}

impl AndroidHost {
    fn call(
        &self,
        method: &str,
        signature: &str,
        text: Option<&str>,
        number: Option<i32>,
    ) -> Result<i32> {
        let mut env = self.vm.attach_current_thread()?;
        let result = env.with_local_frame(16, |env| -> jni::errors::Result<_> {
            let argument = text.map(|text| env.new_string(text)).transpose()?;
            let object: Option<&JObject<'_>> = argument.as_ref().map(|argument| argument.as_ref());
            let arguments = if let Some(object) = object {
                vec![JValue::Object(object)]
            } else if let Some(number) = number {
                vec![JValue::Int(number)]
            } else {
                Vec::new()
            };
            match env.call_method(self.callback.as_obj(), method, signature, &arguments)? {
                jni::objects::JValueOwned::Bool(value) => Ok(i32::from(value)),
                jni::objects::JValueOwned::Int(value) => Ok(value),
                jni::objects::JValueOwned::Void => Ok(0),
                _ => Err(jni::errors::Error::WrongJValueType("primitive", "object")),
            }
        });
        if env.exception_check()? {
            env.exception_clear()?;
        }
        result.with_context(|| format!("Android VPN 回调执行失败（{method}）"))
    }

    fn strings(&self, method: &str, port: Option<i32>) -> Result<Vec<String>> {
        let mut env = self.vm.attach_current_thread()?;
        let result = env.with_local_frame(16, |env| -> Result<Vec<String>> {
            let arguments = port.map(|port| vec![JValue::Int(port)]).unwrap_or_default();
            let signature = if port.is_some() {
                "(I)Ljava/lang/String;"
            } else {
                "()Ljava/lang/String;"
            };
            let value = env
                .call_method(self.callback.as_obj(), method, signature, &arguments)?
                .l()?;
            let text: String = env.get_string(&JString::from(value))?.into();
            ensure!(text.len() <= 64 * 1024, "平台地址列表过大");
            Ok(serde_json::from_str(&text)?)
        });
        if env.exception_check()? {
            env.exception_clear()?;
        }
        // 只标注固定回调名，不读取 Java 异常正文，避免平台错误夹带连接参数或凭据。
        result.with_context(|| format!("Android VPN 回调执行失败（{method}）"))
    }
}

impl Host for AndroidHost {
    fn protect(&self, descriptor: i32) -> Result<()> {
        ensure!(
            self.call("protectSocket", "(I)Z", None, Some(descriptor))? != 0,
            "Android 拒绝保护网络套接字"
        );
        Ok(())
    }
    fn configure(&self, configuration: &VpnConfiguration) -> Result<OwnedFd> {
        let descriptor = self.call(
            "configureTunnel",
            "(Ljava/lang/String;)I",
            Some(&serde_json::to_string(configuration)?),
            None,
        )?;
        ensure!(descriptor >= 0, "Android 无法建立 VPN");
        // SAFETY: Kotlin detachFd 将新建 TUN 的唯一所有权交给 Rust，禁止 Java 再次关闭。
        Ok(unsafe { OwnedFd::from_raw_fd(descriptor) })
    }
    fn local_networks(&self) -> Result<Vec<IpNet>> {
        self.strings("localNetworks", None)?
            .iter()
            .map(|prefix| prefix.parse().context("Android 局域网地址无效"))
            .collect()
    }
    fn local_endpoints(&self, port: u16) -> Vec<String> {
        self.strings("localEndpoints", Some(i32::from(port)))
            .unwrap_or_default()
    }
    fn dns_servers(&self) -> Result<Vec<std::net::SocketAddr>> {
        self.strings("dnsServers", None)?
            .iter()
            .map(|address| address.parse().context("Android DNS 地址无效"))
            .collect()
    }
    fn event(&self, value: &Value) {
        if let Ok(text) = serde_json::to_string(value) {
            let _ = self.call("onCoreEvent", "(Ljava/lang/String;)V", Some(&text), None);
        }
    }
}

struct Cleanup(u64);
impl Drop for Cleanup {
    fn drop(&mut self) {
        mobile::uninstall();
        if let Ok(mut lifecycle) = LIFECYCLE.lock() {
            lifecycle.finish(self.0);
        }
    }
}

fn run(
    env: &mut JNIEnv<'_>,
    configuration: JString<'_>,
    auth_key: JString<'_>,
    callback: JObject<'_>,
    generation: u64,
) -> Result<()> {
    let mut stopped = LIFECYCLE
        .lock()
        .map_err(|_| anyhow::anyhow!("客户端状态锁损坏"))?
        .start(generation)?;
    let _cleanup = Cleanup(generation);
    if *stopped.borrow() {
        return Ok(());
    }
    let configuration: String = env.get_string(&configuration)?.into();
    let auth_key: Zeroizing<String> = Zeroizing::new(env.get_string(&auth_key)?.into());
    ensure!(
        configuration.len() <= 16 * 1024 && auth_key.len() <= 4096,
        "客户端参数过大"
    );
    let mut config: Config = serde_json::from_str(&configuration)?;
    config.server = xunara_client::config::server_url(&config.server)?.to_string();
    config.validate()?;
    mobile::install(Arc::new(AndroidHost {
        vm: env.get_java_vm()?,
        callback: env.new_global_ref(callback)?,
    }))?;
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    runtime.block_on(async move {
        let config = Arc::new(config);
        let store = Store::open(&config.state_dir)?;
        let identity = Arc::new(store.identity(&config.server)?);
        let (endpoints, receiver) = watch::channel(Vec::new());
        let mut engine = Engine::new(config.clone(), identity.clone(), endpoints).await?;
        let (commands, requests) = mpsc::channel(4);
        engine.enable_diagnostics(requests);
        // 只绑定当前内核实例；stop 或 generation 切换后拒绝再投递诊断。
        if *stopped.borrow() {
            return Ok(());
        }
        LIFECYCLE
            .lock()
            .map_err(|_| anyhow::anyhow!("客户端状态锁损坏"))?
            .attach(generation, commands)?;
        let (maps, updates) = mpsc::channel(4);
        let control = tokio::spawn(control::run(config, identity, auth_key, receiver, maps));
        let result = tokio::select! {
            result = engine.run(updates, &store) => result,
            _ = stopped.changed() => Ok(()),
        };
        control.abort();
        let _ = control.await;
        let cleanup = engine.stop().await;
        let _ = engine.status(&store);
        result?;
        cleanup
    })
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_net_xunara_android_NativeBridge_run(
    mut env: JNIEnv<'_>,
    _class: JClass<'_>,
    configuration: JString<'_>,
    auth_key: JString<'_>,
    callback: JObject<'_>,
    generation: jlong,
) -> jstring {
    match run(
        &mut env,
        configuration,
        auth_key,
        callback,
        generation as u64,
    ) {
        Ok(()) => std::ptr::null_mut(),
        Err(error) => {
            if env.exception_check().unwrap_or(false) {
                let _ = env.exception_clear();
            }
            env.new_string(format!("{error:#}"))
                .map(|value| value.into_raw())
                .unwrap_or(std::ptr::null_mut())
        }
    }
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_net_xunara_android_NativeBridge_stop(
    _env: JNIEnv<'_>,
    _class: JClass<'_>,
    generation: jlong,
) {
    if let Ok(lifecycle) = LIFECYCLE.lock() {
        lifecycle.stop(generation as u64);
    }
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_net_xunara_android_NativeBridge_prepare(
    _env: JNIEnv<'_>,
    _class: JClass<'_>,
) -> jlong {
    LIFECYCLE
        .lock()
        .ok()
        .and_then(|mut lifecycle| lifecycle.prepare().ok())
        .unwrap_or(0) as jlong
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_net_xunara_android_NativeBridge_version(
    env: JNIEnv<'_>,
    _class: JClass<'_>,
) -> jstring {
    env.new_string(xunara_client::VERSION)
        .map(|value| value.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_net_xunara_android_NativeBridge_ping(
    mut env: JNIEnv<'_>,
    _class: JClass<'_>,
    peer: JString<'_>,
    generation: jlong,
) -> jstring {
    let result = (|| -> Result<_> {
        let peer: String = env.get_string(&peer)?.into();
        ensure!(peer.len() <= 20 && !peer.is_empty(), "设备标识无效");
        let peer = peer.parse::<u64>().context("设备标识无效")?;
        let commands = LIFECYCLE
            .lock()
            .map_err(|_| anyhow::anyhow!("客户端状态锁损坏"))?
            .commands(generation as u64)?;
        let (reply, receiver) = std::sync::mpsc::sync_channel(1);
        commands
            .try_send(PingRequest { peer, reply })
            .map_err(|_| anyhow::anyhow!("已有检测进行中或连接已退出"))?;
        // 仅在 Kotlin 专用工作线程等待；主线程和 Rust 转发事件循环都不会阻塞。
        receiver
            .recv_timeout(Duration::from_secs(12))
            .context("检测未完成，请检查连接后重试")?
    })();
    let value = match result {
        Ok(result) => serde_json::json!({"result": result}),
        Err(error) => serde_json::json!({"error": error.to_string()}),
    };
    if env.exception_check().unwrap_or(false) {
        let _ = env.exception_clear();
    }
    env.new_string(value.to_string())
        .map(|value| value.into_raw())
        .unwrap_or(std::ptr::null_mut())
}
