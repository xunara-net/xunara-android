package net.xunara.android

import java.net.URI

data class DnsPreferences(val resolver: String = "", val bootstrap: List<String> = emptyList(), val validateDnssec: Boolean = false) {
    fun validated(): DnsPreferences {
        val address = resolver.trim()
        require(address.length <= 2048 && bootstrap.size <= 4) { "DNS 配置超过上限" }
        require(bootstrap.all(::numericAddress)) { "引导地址必须是 IP，最多四个" }
        if (address.isNotEmpty()) {
            val encrypted = address.startsWith("https://") || address.startsWith("tls://")
            if (encrypted) {
                val uri = runCatching { URI(address) }.getOrElse { error("DNS 解析器地址格式无效") }
                require(uri.host != null && uri.rawUserInfo == null && uri.rawQuery == null && uri.rawFragment == null) { "加密 DNS 地址不可包含凭据或参数" }
                require(uri.port == -1 || uri.port in 1..65535) { "DNS 端口无效" }
                require(uri.scheme != "tls" || uri.rawPath in setOf("", "/")) { "DoT 只填写主机与端口" }
                require(numericAddress(uri.host.removeSurrounding("[", "]")) || bootstrap.isNotEmpty()) { "域名解析器请填写引导 IP，避免 DNS 递归" }
            } else if (!numericAddress(address)) {
                val uri = runCatching { URI("dns://$address") }.getOrElse { error("DNS 解析器地址格式无效") }
                require(uri.host != null && numericAddress(uri.host.removeSurrounding("[", "]")) && uri.rawUserInfo == null && uri.rawQuery == null && uri.rawFragment == null && uri.rawPath in setOf("", "/") && (uri.port == -1 || uri.port in 1..65535)) { "填写 IP、IP:端口、https:// 或 tls:// 地址" }
            }
        }
        return copy(resolver = address, bootstrap = bootstrap.distinct())
    }

    companion object {
        // URI 的数字 IPv6 校验不发起 DNS；IPv4 也只做词法解析，避免保存设置时联网。
        fun numericAddress(value: String): Boolean {
            if (value.isEmpty() || value.length > 45 || value.any { it !in "0123456789abcdefABCDEF:." }) return false
            if (value.contains(':')) return runCatching { URI("http://[$value]/").host != null }.getOrDefault(false)
            val parts = value.split('.')
            return parts.size == 4 && parts.all { part -> part.isNotEmpty() && (part.length == 1 || !part.startsWith("0")) && part.all { it in '0'..'9' } && (part.toIntOrNull() ?: -1) in 0..255 }
        }
    }
}
