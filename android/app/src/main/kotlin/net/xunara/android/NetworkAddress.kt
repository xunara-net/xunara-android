package net.xunara.android

import java.net.InetAddress
import java.net.Inet6Address

internal object NetworkAddress {
    fun resolver(address: InetAddress): String {
        val host = checkNotNull(address.hostAddress).substringBefore('%')
        // 链路本地 DNS 必须保留数字 scope；接口名不能直接交给 Rust 的 IP 解析器。
        return if (address is Inet6Address) "[$host${if (address.scopeId == 0) "" else "%${address.scopeId}"}]:53" else "$host:53"
    }
    // API 26 的直连路由也会用 0.0.0.0 / :: 表示无网关，不能只判断 null。
    fun isOnLinkGateway(address: InetAddress?): Boolean = address == null || address.isAnyLocalAddress

    fun prefix(address: InetAddress, length: Int): String {
        require(length in 0..address.address.size * 8)
        // IPv6 的 %wlan0 / 数值 scope 只供系统选接口，不属于网段本身。
        val bytes = address.address.clone()
        for (index in bytes.indices) {
            val bits = (length - index * 8).coerceIn(0, 8)
            val mask = (0xff shl (8 - bits)) and 0xff
            bytes[index] = (bytes[index].toInt() and mask).toByte()
        }
        val host = checkNotNull(InetAddress.getByAddress(bytes).hostAddress)
        return "$host/$length"
    }
}
