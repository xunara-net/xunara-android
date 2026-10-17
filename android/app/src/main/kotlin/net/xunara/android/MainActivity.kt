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
                    "bootstrap" -> {
                        val catalog = ProfileStore(this).read()
                        result.success(JSONObject().put("profile", ProfileStore.toJson(catalog.current))
                            .put("profiles", org.json.JSONArray(catalog.profiles.map(ProfileStore::toJson)))
                            .put("snapshot", JSONObject(VpnState.snapshot())).put("core_version", NativeBridge.version()).toString())
                    }
                    "snapshot" -> result.success(VpnState.snapshot())
                    "systemDiagnostics" -> result.success(SystemDiagnostics.read(this))
                    "batterySettings" -> {
                        startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                        result.success(null)
                    }
                    "applications" -> {
                        val selected = currentProfile().appRouting.packages
                        diagnostics.execute {
                            val response = runCatching { ApplicationInventory.list(this, selected) }
                            runOnUiThread { response.fold({ result.success(it) }, { result.error("APPLICATIONS_UNAVAILABLE", "应用清单暂时无法读取，请重试", null) }) }
                        }
                    }
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
                        requireIdle()
                        val json = JSONObject(call.arguments as Map<*, *>)
                        if (json.optString("id").isEmpty()) json.put("id", java.util.UUID.randomUUID().toString())
                        val profile = ProfileStore.fromJson(json)
                        val saved = ProfileStore(this).save(profile)
                        VpnState.finish()
                        result.success(ProfileStore.toJson(saved.current).toString())
                    }
                    "selectProfile" -> {
                        requireIdle()
                        ProfileStore(this).select(call.argument<String>("id") ?: "")
                        VpnState.finish()
                        result.success(null)
                    }
                    "forgetProfile" -> {
                        requireIdle()
                        ProfileStore(this).remove(call.argument<String>("id") ?: "")
                        result.success(null)
                    }
                    "connect" -> {
                        requireIdle()
                        val key = call.argument<String>("auth_key") ?: ""
                        require(key.length <= 4096) { "接入密钥过长" }
                        ApplicationInventory.plan(this, currentProfile().appRouting)
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
                    "networkSettings" -> { startActivity(Intent(Settings.ACTION_WIRELESS_SETTINGS)); result.success(null) }
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

    private fun currentProfile(): Profile = ProfileStore(this).read().current

    private fun requireIdle() {
        check(pending == null && VpnState.phase() in setOf("disconnected", "error")) { "请先结束授权并断开连接，再修改或切换服务器" }
    }

    private fun startConnection() {
        val result = pending ?: return
        try {
            val profile = currentProfile()
            ApplicationInventory.plan(this, profile.appRouting)
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
