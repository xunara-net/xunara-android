package net.xunara.android

class PhysicalNetworkPreference {
    private var preferred: Long? = null

    fun capabilities(handle: Long, vpn: Boolean) {
        if (!vpn) preferred = handle
    }

    fun defaultLost(handle: Long, observedPhysical: Set<Long>) {
        // 默认资格丢失不等于网卡断开；自身 VPN 的默认切换不能把仍在线的 Wi-Fi 换成移动网络。
        if (preferred == handle && handle !in observedPhysical) preferred = null
    }

    fun physicalLost(handle: Long) {
        if (preferred == handle) preferred = null
    }

    fun select(usable: List<Long>): Long? = preferred?.takeIf { it in usable } ?: usable.minOrNull()
}
