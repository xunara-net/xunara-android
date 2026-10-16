package net.xunara.android

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.system.Os
import android.system.OsConstants
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

class XunaraVpnService : VpnService() {
    private val main = Handler(Looper.getMainLooper())
    private val lifecycleLock = Any()
    @Volatile private var closing = false
    @Volatile private var worker: Thread? = null
    private var monitor: UnderlayMonitor? = null
    private var policy: ReconnectPolicy? = null
    private var lastNotification = ""
    private var plannedFingerprint = ""
    private var generation = 0L
    private var activeStartId = 0
    private var configuration = ""
    private var stopMessage: String? = null
    private var destroyed = false
    private var reconnects = 0
    private var initialKey = ""
    private var appRouting = AppRouting()
    private val initialTimeout = Runnable { if (generation == 0L && worker == null) disconnect("尚无可用网络，请联网后重试") }
    private val restart = Runnable {
        val snapshot = monitor?.snapshot ?: return@Runnable
        if (policy?.ready(snapshot.available, worker != null) == true) {
            try { reconnects++; startWorker("") }
            catch (_: Exception) { disconnect("自动重连失败，请手动重试") }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = try {
        startConnection(intent, startId)
    } catch (_: Exception) {
        disconnect("组网服务启动失败，请检查存储空间与系统权限后重试")
        START_NOT_STICKY
    }

    private fun startConnection(intent: Intent?, startId: Int): Int {
        activeStartId = startId
        if (intent?.action == ACTION_STOP) { disconnect(); return START_NOT_STICKY }
        var authKey = intent?.getStringExtra("auth_key") ?: ""
        intent?.removeExtra("auth_key")
        if (worker != null || policy?.wanted == true) { authKey = ""; return START_NOT_STICKY }
        stopMessage = null
        reconnects = 0
        generation = 0
        val profile = runCatching { ProfileStore(this).read().current }.getOrElse {
            VpnState.finish("请先填写服务器地址"); stopSelf(); return START_NOT_STICKY
        }
        if (prepare(this) != null) { VpnState.finish("尚未取得系统 VPN 授权"); stopSelf(); return START_NOT_STICKY }
        val notification = notification("正在连接玄序网络")
        if (Build.VERSION.SDK_INT >= 34) startForeground(NOTIFICATION, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED)
        else startForeground(NOTIFICATION, notification)
        val hash = MessageDigest.getInstance("SHA-256").digest(profile.server.toByteArray()).joinToString("") { "%02x".format(it) }
        // 每个控制面独立保存机器身份；noBackupFilesDir 禁止云备份恢复成克隆设备。
        val directory = File(noBackupFilesDir, "core/$hash")
        directory.mkdirs()
        Os.chmod(directory.absolutePath, 448)
        configuration = JSONObject().put("server", profile.server).put("hostname", profile.hostname)
            .put("accept_routes", profile.acceptRoutes).put("state_dir", directory.absolutePath)
            .put("interface", "xunara0").put("listen", "0.0.0.0:0").toString()
        appRouting = profile.appRouting
        policy = ReconnectPolicy(profile.autoReconnect)
        // 只等本次用户操作的首次网络就绪，不把密钥写入偏好设置或用于自动重连。
        initialKey = authKey
        VpnState.begin()
        monitor = UnderlayMonitor(this, main, ::networkChanged)
        monitor?.start()
        publishNetwork()
        main.postDelayed(initialTimeout, 30_000)
        authKey = ""
        return START_NOT_STICKY
    }

    private fun startWorker(key: String) {
        check(worker == null && !destroyed && prepare(this) == null) { "VPN 权限已撤销或上一连接未退出" }
        val attempt = NativeBridge.prepare()
        check(attempt > 0) { "上一连接正在退出，请重试" }
        generation = attempt
        synchronized(lifecycleLock) { closing = false; plannedFingerprint = "" }
        policy?.started(monitor?.snapshot?.fingerprint ?: "")
        VpnState.begin(attempt, reconnects > 0)
        publishNetwork()
        var authKey = key
        worker = Thread({
            val error = try { NativeBridge.run(configuration, authKey, this, attempt) } catch (_: Exception) { "组网内核启动失败，请重试" }
            finally { authKey = "" }
            main.post {
                if (generation != attempt) return@post
                worker = null
                if (VpnState.generation() != attempt) return@post
                val wasClosing = closing
                synchronized(lifecycleLock) { closing = true }
                if (!destroyed && policy?.wanted == true && policy?.pending == true) {
                    scheduleRestart()
                    return@post
                }
                // 系统可能仍绑定 VpnService，不能等 onDestroy 才结束“正在断开”。
                finish(if (wasClosing) stopMessage else error, attempt)
            }
        }, "xunara-vpn-core").also { it.start() }
    }

    fun protectSocket(descriptor: Int): Boolean = !closing && protect(descriptor)

    fun configureTunnel(raw: String): Int = synchronized(lifecycleLock) {
        check(!closing) { "VPN 正在停止" }
        val snapshot = checkNotNull(monitor).snapshot
        check(snapshot.available) { "物理网络不可用，请等待网络恢复" }
        check(plannedFingerprint == snapshot.fingerprint) { "局域网已变化，请重新规划连接" }
        val configuration = JSONObject(raw)
        val builder = Builder().setSession("玄序 · 私有组网").setMtu(configuration.getInt("mtu")).setBlocking(false)
            .setConfigureIntent(PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
        builder.allowFamily(OsConstants.AF_INET).allowFamily(OsConstants.AF_INET6)
        val applicationPlan = ApplicationInventory.plan(this, appRouting)
        // Builder 的允许/排除清单互斥；仅选中模式不添加自身，外层 socket 仍逐个 protect。
        applicationPlan.allowed.forEach { builder.addAllowedApplication(it) }
        applicationPlan.disallowed.forEach { builder.addDisallowedApplication(it) }
        val addresses = configuration.getJSONArray("addresses")
        for (index in 0 until addresses.length()) {
            val (address, prefix) = splitPrefix(addresses.getString(index))
            builder.addAddress(address, prefix)
        }
        val routes = configuration.getJSONArray("routes")
        for (index in 0 until routes.length()) {
            val (address, prefix) = splitPrefix(routes.getString(index))
            require(prefix > 0) { "不接管默认路由" }
            builder.addRoute(address, prefix)
        }
        if (Build.VERSION.SDK_INT >= 29) builder.setMetered(false)
        val tunnel = checkNotNull(builder.establish()) { "VPN 权限已撤销" }
        val attempt = generation
        main.post {
            if (!closing && generation == attempt) {
                policy?.established(snapshot.fingerprint)
                networkChanged()
            }
        }
        VpnState.update(JSONObject().put("type", "configuration").put("skipped_routes", configuration.optJSONArray("skipped_routes")))
        // detachFd 后只由 Rust OwnedFd 负责关闭，避免复用 fd 被 Java 二次关闭。
        tunnel.detachFd()
    }

    fun localNetworks(): String = synchronized(lifecycleLock) {
        val snapshot = checkNotNull(monitor).snapshot
        plannedFingerprint = snapshot.fingerprint
        JSONArray(snapshot.localNetworks).toString()
    }

    fun localEndpoints(port: Int): String = JSONArray(monitor?.snapshot?.ipv4Addresses?.map { "$it:$port" } ?: emptyList<String>()).toString()

    fun onCoreEvent(raw: String): Unit = synchronized(lifecycleLock) {
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

    private fun networkChanged() {
        publishNetwork()
        if (generation == 0L && worker == null && policy?.wanted == true && monitor?.snapshot?.available == true) {
            main.removeCallbacks(initialTimeout)
            val key = initialKey
            initialKey = ""
            try { startWorker(key) } catch (_: Exception) { disconnect("连接启动失败，请重试") }
            return
        }
        when (policy?.changed(monitor?.snapshot?.fingerprint ?: "")) {
            ReconnectPolicy.Action.RESTART -> {
                // 先退出旧 TUN，再按新 LAN 重新建路由；绝不靠“继续显示在线”掩盖断网。
                synchronized(lifecycleLock) { closing = true }
                NativeBridge.stop(generation)
                scheduleRestart()
            }
            ReconnectPolicy.Action.STOP -> disconnect("网络已变化；自动重连已关闭，请手动连接")
            else -> Unit
        }
    }

    private fun publishNetwork() {
        VpnState.network(monitor?.snapshot?.label ?: "等待网络恢复", reconnects)
    }

    private fun scheduleRestart() {
        main.removeCallbacks(restart)
        val available = monitor?.snapshot?.available == true
        VpnState.reconnecting(if (available) "网络已切换，正在重新检查局域网并连接" else "网络已断开，等待 Wi-Fi 或移动网络恢复")
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION, notification(if (available) "正在安全重连" else "等待网络恢复"))
        if (available) main.postDelayed(restart, 1000)
    }

    private fun disconnect(message: String? = null) {
        policy?.cancel()
        initialKey = ""
        main.removeCallbacks(initialTimeout)
        main.removeCallbacks(restart)
        monitor?.close()
        synchronized(lifecycleLock) { closing = true; stopMessage = message }
        VpnState.stopping()
        NativeBridge.stop(generation)
        if (worker == null) finish(message)
    }

    private fun finish(message: String?, attempt: Long? = null) {
        policy?.cancel()
        monitor?.close()
        monitor = null
        configuration = ""
        lastNotification = ""
        stopForeground(STOP_FOREGROUND_REMOVE)
        VpnState.finish(message, attempt)
        stopSelf(activeStartId)
    }

    override fun onRevoke() { main.post { disconnect() }; super.onRevoke() }
    override fun onDestroy() {
        synchronized(lifecycleLock) { closing = true }
        destroyed = true
        policy?.cancel()
        initialKey = ""
        main.removeCallbacks(initialTimeout)
        main.removeCallbacks(restart)
        if (worker != null) VpnState.stopping()
        NativeBridge.stop(generation)
        monitor?.close()
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
