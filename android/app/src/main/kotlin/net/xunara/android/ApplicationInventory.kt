package net.xunara.android

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import org.json.JSONArray
import org.json.JSONObject

object ApplicationInventory {
    fun plan(context: Context, policy: AppRouting): AppRoutingPlan {
        val installed = policy.packages.filter { packageName ->
            try { context.packageManager.getApplicationInfo(packageName, 0); true }
            catch (_: PackageManager.NameNotFoundException) { false }
        }.toSet()
        return policy.plan(installed, context.packageName)
    }

    fun list(context: Context, selected: List<String>): String {
        val manager = context.packageManager
        // 仅在用户打开选择页时查询可启动应用，不申请 QUERY_ALL_PACKAGES、不上传清单。
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val packages = (manager.queryIntentActivities(launcher, 0).map { it.activityInfo.packageName } + selected)
            .filter { it != context.packageName }.distinct()
        check(packages.size <= 2048) { "可选应用过多，请先整理应用后再试" }
        val entries = packages.map { packageName ->
            val information = try { manager.getApplicationInfo(packageName, 0) }
            catch (_: PackageManager.NameNotFoundException) { null }
            val label = information?.loadLabel(manager)?.toString()?.filterNot { it.isISOControl() }?.take(100)?.ifBlank { packageName } ?: packageName
            JSONObject().put("package", packageName).put("label", label).put("installed", information != null)
        }.sortedWith(compareBy({ it.getString("label").lowercase() }, { it.getString("package") }))
        return JSONObject().put("applications", JSONArray(entries)).toString()
    }
}
