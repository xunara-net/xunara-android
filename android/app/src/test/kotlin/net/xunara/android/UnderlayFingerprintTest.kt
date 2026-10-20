package net.xunara.android

import java.net.InetAddress
import org.junit.Assert.*
import org.junit.Test

class UnderlayFingerprintTest {
    private fun prefix(address: String, length: Int) = NetworkAddress.prefix(InetAddress.getByName(address), length)
    private val selectedAddresses = listOf("10.0.2.16/24", "fec0::1234/64")
    private val wifi = listOf(prefix("10.0.2.16", 24), prefix("10.0.2.3", 32), prefix("fec0::1234", 64))

    @Test fun overlappingBackgroundCellularLossDoesNotRestartWifi() {
        val before = wifi + listOf(prefix("10.0.2.15", 24), prefix("10.0.2.3", 32))
        assertEquals(UnderlayFingerprint.of(132, "wlan0", selectedAddresses, before),
            UnderlayFingerprint.of(132, "wlan0", selectedAddresses, wifi))
        val policy = ReconnectPolicy(true)
        policy.established(UnderlayFingerprint.of(132, "wlan0", selectedAddresses, before))
        assertEquals(ReconnectPolicy.Action.KEEP, policy.changed(UnderlayFingerprint.of(132, "wlan0", selectedAddresses, wifi)))
    }

    @Test fun realLanDefaultNetworkSelectedAddressAndDnsChangesStillRestart() {
        val initial = UnderlayFingerprint.of(132, "wlan0", selectedAddresses, wifi)
        for (changed in listOf(
            UnderlayFingerprint.of(133, "wlan0", selectedAddresses, wifi),
            UnderlayFingerprint.of(132, "eth1", selectedAddresses, wifi),
            UnderlayFingerprint.of(132, "wlan0", listOf("10.0.2.17/24"), wifi),
            UnderlayFingerprint.of(132, "wlan0", selectedAddresses, wifi + prefix("192.168.9.1", 24)),
            UnderlayFingerprint.of(132, "wlan0", selectedAddresses, wifi + prefix("9.9.9.9", 32)),
            UnderlayFingerprint.of(null, null, emptyList(), wifi),
        )) {
            val policy = ReconnectPolicy(true)
            policy.established(initial)
            assertEquals(ReconnectPolicy.Action.RESTART, policy.changed(changed))
        }
    }
}
