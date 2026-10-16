package net.xunara.android

import android.app.ActivityManager
import android.app.NotificationManager
import android.content.Context
import android.net.VpnService
import android.os.Build
import android.os.PowerManager
import org.json.JSONObject

object SystemDiagnostics {
    fun read(context: Context): String {
        val information = context.packageManager.getPackageInfo(context.packageName, 0)
        // 只返回系统开关与版本；不导出授权 URL、偏好清单、节点地址、私钥或完整日志。
        return JSONObject().put("android_sdk", Build.VERSION.SDK_INT).put("android_version", Build.VERSION.RELEASE)
            .put("app_version", information.versionName ?: "unknown").put("core_version", NativeBridge.version())
            .put("vpn_permission", VpnService.prepare(context) == null)
            .put("notifications_enabled", context.getSystemService(NotificationManager::class.java).areNotificationsEnabled())
            .put("battery_unrestricted", context.getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(context.packageName))
            .put("background_restricted", Build.VERSION.SDK_INT >= 28 && context.getSystemService(ActivityManager::class.java).isBackgroundRestricted)
            .toString()
    }
}
