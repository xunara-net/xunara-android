package net.xunara.android

import java.net.InetAddress

data class ForwardingPreferences(val subnets: List<String> = emptyList(), val advertiseExit: Boolean = false) {
    fun validated(): ForwardingPreferences {
        require(subnets.size <= 64 && subnets.all(::validSubnet)) { "填写最多 64 个规范 CIDR；默认路由请使用提供出口开关" }
        return copy(subnets = subnets.distinct())
    }

    companion object {
        fun validSubnet(value: String): Boolean = runCatching {
            if (value.length > 49) return false
            val parts = value.split('/')
            if (parts.size != 2 || !DnsPreferences.numericAddress(parts[0])) return false
            val prefix = parts[1].toIntOrNull() ?: return false
            // 只有通过数字地址词法检查后才能调用 InetAddress，不查询任何域名。
            val address = InetAddress.getByName(parts[0])
            if (parts[0].contains(':') && address.address.size != 16) return false
            if (address.isAnyLocalAddress || address.isLoopbackAddress || address.isMulticastAddress || address.isLinkLocalAddress || prefix !in 1..address.address.size * 8) return false
            address.address.withIndex().all { (index, byte) ->
                val hostBits = (8 - (prefix - index * 8)).coerceIn(0, 8)
                byte.toInt() and ((1 shl hostBits) - 1) == 0
            }
        }.getOrDefault(false)
    }
}
