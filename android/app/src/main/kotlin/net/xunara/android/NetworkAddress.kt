package net.xunara.android

import java.net.InetAddress

internal object NetworkAddress {
    // API 26 的直连路由也会用 0.0.0.0 / :: 表示无网关，不能只判断 null。
    fun isOnLinkGateway(address: InetAddress?): Boolean = address == null || address.isAnyLocalAddress

    fun prefix(address: InetAddress, length: Int): String {
        require(length in 0..address.address.size * 8)
        // IPv6 的 %wlan0 / 数值 scope 只供系统选接口，不属于网段本身。
        val host = checkNotNull(address.hostAddress).substringBefore('%')
        return "$host/$length"
    }
}
