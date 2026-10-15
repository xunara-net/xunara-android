package net.xunara.android

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.system.Os
import android.system.OsConstants
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.Inet4Address
import java.security.MessageDigest

class XunaraVpnService : VpnService() {
    private val main = Handler(Looper.getMainLooper())
    private val lifecycleLock = Any()
    @Volatile private var closing = false
    @Volatile private var worker: Thread? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var configured = false
    private var lastNotification = ""
    private var originalNetworks = ""
    private var generation = 0L

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = try {
        startConnection(intent, startId)
    } catch (_: Exception) {
        synchronized(lifecycleLock) { closing = true; stopMessage = "组网服务启动失败，请检查存储空间与系统权限后重试" }
        NativeBridge.stop(generation)
        if (worker == null) {
            VpnState.finish(stopMessage)
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf(startId)
        } else VpnState.stopping()
        START_NOT_STICKY
    }

    private fun startConnection(intent: Intent?, startId: Int): Int {
        if (intent?.action == ACTION_STOP) { disconnect(); return START_NOT_STICKY }
        if (worker != null) return START_NOT_STICKY
        closing = false
        configured = false
        stopMessage = null
        val preferences = getSharedPreferences("profile", MODE_PRIVATE)
        val profile = runCatching { Profile(preferences.getString("server", "") ?: "", preferences.getString("hostname", "android") ?: "android", preferences.getBoolean("accept_routes", true)).validated() }.getOrElse {
            VpnState.finish("请先填写服务器地址"); stopSelf(); return START_NOT_STICKY
        }
        if (prepare(this) != null) { VpnState.finish("尚未取得系统 VPN 授权"); stopSelf(); return START_NOT_STICKY }
        VpnState.begin()
        val notification = notification("正在连接玄序网络")
        if (Build.VERSION.SDK_INT >= 34) startForeground(NOTIFICATION, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED)
        else startForeground(NOTIFICATION, notification)
        val hash = MessageDigest.getInstance("SHA-256").digest(profile.server.toByteArray()).joinToString("") { "%02x".format(it) }
        // 每个控制面独立保存机器身份；noBackupFilesDir 禁止云备份恢复成克隆设备。
        val directory = File(noBackupFilesDir, "core/$hash")
        directory.mkdirs()
        Os.chmod(directory.absolutePath, 448)
        val configuration = JSONObject().put("server", profile.server).put("hostname", profile.hostname)
            .put("accept_routes", profile.acceptRoutes).put("state_dir", directory.absolutePath)
            .put("interface", "xunara0").put("listen", "0.0.0.0:0").toString()
        var authKey = intent?.getStringExtra("auth_key") ?: ""
        intent?.removeExtra("auth_key")
        generation = NativeBridge.prepare()
        check(generation > 0) { "上一连接正在退出，请重试" }
        originalNetworks = localNetworks()
        worker = Thread({
            val error = try { NativeBridge.run(configuration, authKey, this, generation) } catch (_: Exception) { "组网内核启动失败，请重试" }
            finally { authKey = "" }
            main.post {
                worker = null
                stopMessage = if (closing) stopMessage else error
                synchronized(lifecycleLock) { closing = true; configured = false }
                stopForeground(STOP_FOREGROUND_REMOVE)
                networkCallback?.let { runCatching { getSystemService(ConnectivityManager::class.java).unregisterNetworkCallback(it) } }
                networkCallback = null
                // 系统可能仍绑定 VpnService，不能等 onDestroy 才结束“正在断开”。
                // 此时 Rust 已关闭 TUN 并退出；同一 service 再次启动也可安全创建新实例。
                VpnState.finish(stopMessage)
                stopSelf(startId)
            }
        }, "xunara-vpn-core").also { it.start() }
        observeNetworks()
        return START_NOT_STICKY
    }

    fun protectSocket(descriptor: Int): Boolean = !closing && protect(descriptor)

    fun configureTunnel(raw: String): Int = synchronized(lifecycleLock) {
        check(!closing) { "VPN 正在停止" }
        val configuration = JSONObject(raw)
        val builder = Builder().setSession("玄序 · 私有组网").setMtu(configuration.getInt("mtu")).setBlocking(false)
            .setConfigureIntent(PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
        builder.allowFamily(OsConstants.AF_INET).allowFamily(OsConstants.AF_INET6)
        // 自身不走 VPN，保护系统 DNS 查询与浏览器回到 App 后的管理请求；外层 TCP/UDP 另逐个 protect。
        builder.addDisallowedApplication(packageName)
        val addresses = configuration.getJSONArray("addresses")
        for (index in 0 until addresses.length()) {
            val (address, prefix) = splitPrefix(addresses.getString(index))
            builder.addAddress(address, prefix)
        }
        val routes = configuration.getJSONArray("routes")
        for (index in 0 until routes.length()) {
            val (address, prefix) = splitPrefix(routes.getString(index))
            require(prefix > 0) { "首版不接管默认路由" }
            builder.addRoute(address, prefix)
        }
        if (Build.VERSION.SDK_INT >= 29) builder.setMetered(false)
        val tunnel = checkNotNull(builder.establish()) { "VPN 权限已撤销" }
        configured = true
        VpnState.update(JSONObject().put("type", "configuration").put("skipped_routes", configuration.optJSONArray("skipped_routes")))
        // detachFd 后只由 Rust OwnedFd 负责关闭，避免复用 fd 被 Java 二次关闭。
        tunnel.detachFd()
    }

    private fun underlays(): List<android.net.LinkProperties> {
        val manager = getSystemService(ConnectivityManager::class.java)
        return manager.allNetworks.filter { manager.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == false }
            .mapNotNull { manager.getLinkProperties(it) }
    }

    fun localNetworks(): String = JSONArray(underlays().flatMap { properties ->
        properties.routes.filter { !it.isDefaultRoute && it.gateway == null }.map { it.destination.toString() } +
            properties.linkAddresses.map { NetworkAddress.prefix(it.address, it.prefixLength) } +
            // 系统解析器可能位于非直连网段，不能让已导入的子网截走手机 DNS。
            properties.dnsServers.map { NetworkAddress.prefix(it, if (it is Inet4Address) 32 else 128) }
    }.distinct().sorted()).toString()

    fun localEndpoints(port: Int): String = JSONArray(underlays().flatMap { it.linkAddresses }.mapNotNull {
        val address = it.address
        if (address is Inet4Address && !address.isLoopbackAddress && !address.isLinkLocalAddress && !address.isAnyLocalAddress) "${address.hostAddress}:$port" else null
    }.distinct().take(32)).toString()

    fun onCoreEvent(raw: String) {
        if (closing) return
        val event = JSONObject(raw)
        VpnState.update(event)
        val text = when (VpnState.phase()) {
            "connected" -> "已连接 · 仅私有网络流量经过玄序"
            "authorizing" -> "等待浏览器登录并批准设备"
            "reconnecting" -> "正在重新连接"
            else -> "正在建立加密连接"
        }
        main.post {
            if (!closing && text != lastNotification) {
                lastNotification = text
                getSystemService(NotificationManager::class.java).notify(NOTIFICATION, notification(text))
            }
        }
    }

    private fun observeNetworks() {
        val manager = getSystemService(ConnectivityManager::class.java)
        networkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onLinkPropertiesChanged(network: Network, properties: android.net.LinkProperties) {
                // LAN 改变后旧 VPN 路由可能截走新内网；安全断开，用户明确重连重新计算。
                if (configured && localNetworks() != originalNetworks) {
                    main.post { if (!closing) { disconnect("网络环境已变化，请重新连接以避免局域网冲突") } }
                }
            }
            override fun onLost(network: Network) {
                main.post { if (configured && !closing && localNetworks() != originalNetworks) disconnect("网络已切换，请重新连接") }
            }
        }
        manager.registerNetworkCallback(NetworkRequest.Builder().addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN).build(), networkCallback!!)
    }

    private var stopMessage: String? = null
    private fun disconnect(message: String? = null) {
        synchronized(lifecycleLock) { closing = true; stopMessage = message }
        VpnState.stopping()
        NativeBridge.stop(generation)
        if (worker == null) { VpnState.finish(message); stopSelf() }
    }

    override fun onRevoke() { main.post { disconnect() }; super.onRevoke() }
    override fun onDestroy() {
        synchronized(lifecycleLock) { closing = true }
        if (worker != null) VpnState.stopping()
        NativeBridge.stop(generation)
        networkCallback?.let { runCatching { getSystemService(ConnectivityManager::class.java).unregisterNetworkCallback(it) } }
        super.onDestroy()
    }

    private fun notification(text: String): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "组网连接状态", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val stop = PendingIntent.getService(this, 1, Intent(this, XunaraVpnService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        return Notification.Builder(this, CHANNEL).setSmallIcon(net.xunara.android.R.drawable.ic_xunara)
            .setContentTitle("玄序 Xunara").setContentText(text).setContentIntent(open).setOngoing(true)
            .addAction(Notification.Action.Builder(null, "断开连接", stop).build()).build()
    }

    companion object {
        const val ACTION_STOP = "net.xunara.android.STOP"
        private const val CHANNEL = "xunara_vpn"
        private const val NOTIFICATION = 1001
        private fun splitPrefix(value: String): Pair<String, Int> {
            val parts = value.split('/')
            require(parts.size == 2)
            return parts[0] to parts[1].toInt()
        }
    }
}
