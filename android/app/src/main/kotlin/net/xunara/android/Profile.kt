package net.xunara.android

import java.net.URI

data class Profile(val server: String, val hostname: String, val acceptRoutes: Boolean, val autoReconnect: Boolean = true, val appRouting: AppRouting = AppRouting()) {
    fun validated(): Profile {
        val uri = URI(server.trim())
        val host = uri.host ?: error("请输入完整服务器地址")
        val scheme = uri.scheme?.lowercase()
        require(scheme == "https" || (scheme == "http" && host.lowercase() in setOf("localhost", "127.0.0.1", "[::1]", "::1"))) { "服务器必须使用 HTTPS" }
        require(uri.rawUserInfo == null && uri.rawQuery == null && uri.rawFragment == null && uri.rawPath in setOf("", "/")) { "只需填写服务器根地址，不要带登录路径或参数" }
        require(uri.port == -1 || uri.port in 1..65535) { "服务器端口无效" }
        require(hostname.matches(Regex("[A-Za-z0-9-]{1,63}"))) { "设备名须为 1–63 位字母、数字或连字符" }
        val port = if ((scheme == "https" && uri.port == 443) || (scheme == "http" && uri.port == 80)) -1 else uri.port
        return copy(server = URI(scheme, null, host.lowercase(), port, "/", null, null).toASCIIString(), appRouting = appRouting.validated())
    }

    fun allowsBrowser(target: String): Boolean = runCatching {
        val source = URI(server)
        val destination = URI(target)
        fun port(uri: URI) = if (uri.port != -1) uri.port else if (uri.scheme == "https") 443 else 80
        source.scheme == destination.scheme && source.host.equals(destination.host, true) && port(source) == port(destination) && destination.rawUserInfo == null && destination.rawFragment == null
    }.getOrDefault(false)
}
