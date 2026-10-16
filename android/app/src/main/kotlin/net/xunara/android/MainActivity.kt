package net.xunara.android

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private var pendingKey = ""
    private val diagnostics = Executors.newSingleThreadExecutor()
    private val detecting = AtomicBoolean(false)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "net.xunara.android/vpn").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "bootstrap" -> result.success(JSONObject().put("profile", profileJson()).put("snapshot", JSONObject(VpnState.snapshot())).put("core_version", NativeBridge.version()).toString())
                    "snapshot" -> result.success(VpnState.snapshot())
                    "ping" -> {
                        check(VpnState.phase() == "connected") { "请先连接网络" }
                        val peer = call.argument<String>("peer_id") ?: ""
                        require(peer.matches(Regex("[0-9]{1,20}"))) { "设备标识无效" }
                        val generation = call.argument<Number>("generation")?.toLong() ?: error("缺少连接标识")
                        check(generation == VpnState.generation()) { "连接已变化，请重新检测" }
                        check(detecting.compareAndSet(false, true)) { "已有检测进行中，请稍候" }
                        diagnostics.execute {
                            val response = runCatching { NativeBridge.ping(peer, generation) }
                            detecting.set(false)
                            runOnUiThread {
                                if (generation != VpnState.generation() || VpnState.phase() != "connected") result.error("CONNECTION_CHANGED", "连接已变化，请重新检测", null)
                                else response.fold({ result.success(it) }, { result.error("PING_FAILED", "内核检测失败，请重试", null) })
                            }
                        }
                    }
                    "saveProfile" -> {
                        check(VpnState.phase() in setOf("disconnected", "error")) { "请先断开连接再修改网络设置" }
                        val profile = Profile(call.argument<String>("server") ?: "", call.argument<String>("hostname") ?: "", call.argument<Boolean>("accept_routes") ?: true, call.argument<Boolean>("auto_reconnect") ?: true).validated()
                        getSharedPreferences("profile", MODE_PRIVATE).edit().putString("server", profile.server).putString("hostname", profile.hostname).putBoolean("accept_routes", profile.acceptRoutes).putBoolean("auto_reconnect", profile.autoReconnect).apply()
                        result.success(profileJson().toString())
                    }
                    "connect" -> {
                        check(pending == null && VpnState.phase() in setOf("disconnected", "error")) { "连接正在进行，请稍候" }
                        val key = call.argument<String>("auth_key") ?: ""
                        require(key.length <= 4096) { "接入密钥过长" }
                        pending = result
                        pendingKey = key
                        val prepare = VpnService.prepare(this)
                        if (prepare == null) startConnection() else startActivityForResult(prepare, VPN_REQUEST)
                    }
                    "disconnect" -> { startService(Intent(this, XunaraVpnService::class.java).setAction(XunaraVpnService.ACTION_STOP)); result.success(null) }
                    "openAuthorization" -> {
                        val target = JSONObject(VpnState.snapshot()).optString("authorization_url")
                        val profile = currentProfile()
                        require(profile.allowsBrowser(target) && target.isNotEmpty()) { "授权地址已失效，请重新连接" }
                        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(target)).addCategory(Intent.CATEGORY_BROWSABLE))
                        result.success(null)
                    }
                    "openConsole" -> { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(currentProfile().server + "dashboard"))); result.success(null) }
                    "vpnSettings" -> { startActivity(Intent(Settings.ACTION_VPN_SETTINGS)); result.success(null) }
                    "notificationSettings" -> {
                        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED)
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 4002)
                        else startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                if (pending === result) { pending = null; pendingKey = "" }
                result.error("XUNARA_ERROR", error.message ?: "操作失败，请重试", null)
            }
        }
    }

    private fun currentProfile(): Profile {
        val json = profileJson()
        return Profile(json.getString("server"), json.getString("hostname"), json.getBoolean("accept_routes"), json.getBoolean("auto_reconnect")).validated()
    }

    private fun profileJson(): JSONObject {
        val preferences = getSharedPreferences("profile", MODE_PRIVATE)
        val name = ("android-" + Build.MODEL).replace(Regex("[^A-Za-z0-9-]"), "-").take(63)
        return JSONObject().put("server", preferences.getString("server", "https://fakeop4.onbed.cn:9090/"))
            .put("hostname", preferences.getString("hostname", name)).put("accept_routes", preferences.getBoolean("accept_routes", true)).put("auto_reconnect", preferences.getBoolean("auto_reconnect", true))
    }

    private fun startConnection() {
        val result = pending ?: return
        try {
            val profile = currentProfile()
            getSharedPreferences("profile", MODE_PRIVATE).edit().putString("server", profile.server).putString("hostname", profile.hostname).putBoolean("accept_routes", profile.acceptRoutes).apply()
            VpnState.begin()
            startForegroundService(Intent(this, XunaraVpnService::class.java).putExtra("auth_key", pendingKey))
            result.success(null)
        } catch (_: Exception) {
            VpnState.finish("启动 VPN 失败，请重试")
            result.error("VPN_START_FAILED", "无法启动 VPN 服务", null)
        } finally { pendingKey = ""; pending = null }
    }

    @Deprecated("Android VPN 授权回调")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST) {
            if (resultCode == RESULT_OK) startConnection()
            else { pending?.error("VPN_PERMISSION_DENIED", "未开启 VPN 权限，尚未连接网络", null); pending = null; pendingKey = "" }
        }
    }

    override fun onDestroy() {
        pending?.error("ACTIVITY_CLOSED", "页面已关闭，请重试", null)
        pending = null
        pendingKey = ""
        diagnostics.shutdownNow()
        super.onDestroy()
    }

    companion object { private const val VPN_REQUEST = 4001 }
}
