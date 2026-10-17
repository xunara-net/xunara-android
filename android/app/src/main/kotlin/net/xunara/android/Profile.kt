package net.xunara.android

import java.net.URI
import java.security.MessageDigest

data class Profile(val server: String, val hostname: String, val acceptRoutes: Boolean, val autoReconnect: Boolean = true, val appRouting: AppRouting = AppRouting(),
    val id: String = "", val label: String = "", val acceptDns: Boolean = false, val exitNodeId: String = "", val exitNodeName: String = "", val dns: DnsPreferences = DnsPreferences()) {
    fun validated(): Profile {
        val uri = URI(server.trim())
        val host = uri.host ?: error("请输入完整服务器地址")
        val scheme = uri.scheme?.lowercase()
        require(scheme == "https" || (scheme == "http" && host.lowercase() in setOf("localhost", "127.0.0.1", "[::1]", "::1"))) { "服务器必须使用 HTTPS" }
        require(uri.rawUserInfo == null && uri.rawQuery == null && uri.rawFragment == null && uri.rawPath in setOf("", "/")) { "只需填写服务器根地址，不要带登录路径或参数" }
        require(uri.port == -1 || uri.port in 1..65535) { "服务器端口无效" }
        require(hostname.matches(Regex("[A-Za-z0-9-]{1,63}"))) { "设备名须为 1–63 位字母、数字或连字符" }
        val port = if ((scheme == "https" && uri.port == 443) || (scheme == "http" && uri.port == 80)) -1 else uri.port
        val canonical = URI(scheme, null, host.lowercase(), port, "/", null, null).toASCIIString()
        val identity = id.ifEmpty { legacyId(canonical) }
        require(!identity.startsWith("legacy-") || identity == legacyId(canonical)) { "旧设备身份不能转移到其他控制地址，请新增账号配置" }
        require(identity.matches(Regex("legacy-[a-f0-9]{64}|[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}"))) { "账号配置标识无效" }
        require(label.trim().length <= 48 && label.none { it.isISOControl() }) { "账号备注最多 48 字，不可含控制字符" }
        require(exitNodeId.length <= 128 && exitNodeId.all { it.isLetterOrDigit() || it in "_-" }) { "出口节点标识无效" }
        require(exitNodeName.length <= 253 && exitNodeName.none { it.isISOControl() }) { "出口节点名称无效" }
        return copy(server = canonical, id = identity, label = label.trim(), appRouting = appRouting.validated(), dns = dns.validated())
    }

    // 老配置沿用原 SHA256(server) 目录；新账号不能因为控制地址相同而复用旧设备。
    fun identityDirectory(): String = if (id.startsWith("legacy-")) id.removePrefix("legacy-") else "profile-$id"

    companion object {
        fun legacyId(server: String): String = "legacy-" + MessageDigest.getInstance("SHA-256")
            .digest(server.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
    }

    fun allowsBrowser(target: String): Boolean = runCatching {
        val source = URI(server)
        val destination = URI(target)
        fun port(uri: URI) = if (uri.port != -1) uri.port else if (uri.scheme == "https") 443 else 80
        source.scheme == destination.scheme && source.host.equals(destination.host, true) && port(source) == port(destination) && destination.rawUserInfo == null && destination.rawFragment == null
    }.getOrDefault(false)
}
