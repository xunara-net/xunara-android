package net.xunara.android

import android.content.Context
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

class ProfileStore(context: Context) {
    private val preferences = context.getSharedPreferences("profile", Context.MODE_PRIVATE)

    fun read(): ProfileCatalog {
        val stored = preferences.getString("catalog_v1", null)
        if (stored != null) {
            return runCatching {
                val json = JSONObject(stored)
                require(json.getInt("version") == 1)
                val profiles = json.getJSONArray("profiles")
                require(profiles.length() in 1..16)
                val entries = (0 until profiles.length()).map { fromJson(profiles.getJSONObject(it)) }
                ProfileCatalog(entries.first { it.server == json.getString("current") }, entries).validated()
            }.getOrElse { error("常用服务器配置无法读取；请勿清除应用数据，先检查存储空间") }
        }
        val name = ("android-" + Build.MODEL).replace(Regex("[^A-Za-z0-9-]"), "-").take(63)
        val legacy = Profile(
            preferences.getString("server", "https://fakeop4.onbed.cn:9090/") ?: "",
            preferences.getString("hostname", name) ?: name,
            preferences.getBoolean("accept_routes", true), preferences.getBoolean("auto_reconnect", true),
        ).validated()
        return write(ProfileCatalog(legacy, listOf(legacy)))
    }

    fun save(profile: Profile): ProfileCatalog = write(read().save(profile))
    fun select(server: String): ProfileCatalog = write(read().select(server))
    fun remove(server: String): ProfileCatalog = write(read().remove(server))

    private fun write(catalog: ProfileCatalog): ProfileCatalog {
        val next = catalog.validated()
        val json = JSONObject().put("version", 1).put("current", next.current.server)
            .put("profiles", JSONArray(next.profiles.map(::toJson)))
        // 一次提交当前项和列表；迁移成功后清除旧键，避免两套偏好混读。
        check(preferences.edit().putString("catalog_v1", json.toString())
            .remove("server").remove("hostname").remove("accept_routes").remove("auto_reconnect").commit()) { "服务器设置未能保存，请检查存储空间" }
        return next
    }

    companion object {
        fun fromJson(json: JSONObject): Profile {
            val packages = json.optJSONArray("applications") ?: JSONArray()
            require(packages.length() <= 256) { "应用清单过大" }
            return Profile(json.getString("server"), json.getString("hostname"), json.optBoolean("accept_routes", true),
                json.optBoolean("auto_reconnect", true), AppRouting(AppRoutingMode.parse(json.optString("app_routing", "all")),
                    (0 until packages.length()).map { packages.getString(it) })).validated()
        }

        fun toJson(profile: Profile): JSONObject = JSONObject().put("server", profile.server).put("hostname", profile.hostname)
            .put("accept_routes", profile.acceptRoutes).put("auto_reconnect", profile.autoReconnect)
            .put("app_routing", profile.appRouting.mode.value).put("applications", JSONArray(profile.appRouting.packages))
    }
}
