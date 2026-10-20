package net.xunara.android

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import java.net.Inet4Address

class UnderlayMonitor(context: Context, private val handler: Handler, private val changed: () -> Unit) {
    data class Snapshot(
        val fingerprint: String = "",
        val localNetworks: List<String> = emptyList(),
        val ipv4Addresses: List<String> = emptyList(),
        val label: String = "等待网络恢复",
        val available: Boolean = false,
        val dnsServers: List<String> = emptyList(),
    )
    private data class Entry(var capabilities: NetworkCapabilities? = null, var properties: LinkProperties? = null)
    private val manager = context.getSystemService(ConnectivityManager::class.java)
    private val entries = mutableMapOf<Network, Entry>()
    private val preference = PhysicalNetworkPreference()
    private var registered = false
    private var defaultRegistered = false
    private var closed = false
    @Volatile var snapshot = Snapshot()
        private set

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) { entries.getOrPut(network) { Entry() } }
        override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
            entries.getOrPut(network) { Entry() }.capabilities = NetworkCapabilities(capabilities)
            publish()
        }
        override fun onLinkPropertiesChanged(network: Network, properties: LinkProperties) {
            entries.getOrPut(network) { Entry() }.properties = properties
            publish()
        }
        override fun onLost(network: Network) {
            entries.remove(network)
            preference.physicalLost(network.networkHandle)
            publish()
        }
    }
    private val defaultCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
            if (!capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
                preference.capabilities(network.networkHandle, false)
                publish()
            }
        }
        override fun onLost(network: Network) {
            preference.defaultLost(network.networkHandle, entries.keys.map { it.networkHandle }.toSet())
            publish()
        }
    }

    fun start() {
        // 只认回调实际观察到的网络。allNetworks 可能包含后台保活网络，
        // 它们未匹配 LISTEN，随后不会收到 onLost，混入缓存会造成永久“假在线”。
        manager.registerNetworkCallback(NetworkRequest.Builder().addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN).build(), callback, handler)
        registered = true
        // App 自身被 VPN 排除，因此此处跟随 App 的物理默认网络，而不是把 VPN 建立当成切网。
        manager.registerDefaultNetworkCallback(defaultCallback, handler)
        defaultRegistered = true
    }

    fun close() {
        closed = true
        if (registered) { runCatching { manager.unregisterNetworkCallback(callback) }; registered = false }
        if (defaultRegistered) { runCatching { manager.unregisterNetworkCallback(defaultCallback) }; defaultRegistered = false }
    }

    private fun publish() {
        if (closed) return
        val physical = entries.entries.filter { (_, entry) ->
            entry.capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == false &&
                !entry.properties?.linkAddresses.isNullOrEmpty()
        }.sortedBy { it.key.networkHandle }
        // 不能联网的 LAN 仍必须保留；但 IMS / MMS 网卡不能触发自动重连。
        val usable = physical.filter { it.value.capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true }
        val properties = physical.mapNotNull { it.value.properties }
        val preferred = preference.select(usable.map { it.key.networkHandle })
        val selected = usable.firstOrNull { it.key.networkHandle == preferred }
        val capabilities = selected?.value?.capabilities
        val label = when {
            capabilities == null -> "等待网络恢复"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "Wi-Fi"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "移动网络"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "以太网"
            else -> "其他网络"
        }
        val local = properties.flatMap { link ->
            link.routes.filter { !it.isDefaultRoute && NetworkAddress.isOnLinkGateway(it.gateway) }.map { it.destination.toString() } +
                link.linkAddresses.map { NetworkAddress.prefix(it.address, it.prefixLength) } +
                link.dnsServers.map { NetworkAddress.prefix(it, if (it is Inet4Address) 32 else 128) }
        }.distinct().sorted()
        val addresses = properties.flatMap { it.linkAddresses }.mapNotNull {
            val address = it.address
            if (address is Inet4Address && !address.isLoopbackAddress && !address.isLinkLocalAddress && !address.isAnyLocalAddress) address.hostAddress else null
        }.distinct().sorted().take(32)
        // 后台蜂窝失去 FOREGROUND 不等于当前 Wi-Fi 切网；仍比较全部 LAN，避免漏掉真正的新网段。
        val fingerprint = UnderlayFingerprint.of(selected?.key?.networkHandle, selected?.value?.properties?.interfaceName,
            selected?.value?.properties?.linkAddresses?.map { it.toString() } ?: emptyList(), local)
        val previous = snapshot
        snapshot = Snapshot(fingerprint, local, addresses, label, usable.isNotEmpty(), selected?.value?.properties?.dnsServers?.map(NetworkAddress::resolver) ?: emptyList())
        if (previous != snapshot) changed()
    }
}
