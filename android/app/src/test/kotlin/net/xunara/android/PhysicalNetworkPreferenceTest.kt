package net.xunara.android

import org.junit.Assert.*
import org.junit.Test

class PhysicalNetworkPreferenceTest {
    @Test fun ownVpnDefaultChangesDoNotReplaceAnObservedPhysicalNetwork() {
        val preference = PhysicalNetworkPreference()
        preference.capabilities(200, false)
        assertEquals(200L, preference.select(listOf(100, 200)))
        preference.defaultLost(200, setOf(100, 200))
        preference.capabilities(300, true)
        assertEquals(200L, preference.select(listOf(100, 200)))
        preference.defaultLost(300, setOf(100, 200))
        assertEquals(200L, preference.select(listOf(100, 200)))
    }

    @Test fun realPhysicalLossNeverKeepsAGhostNetworkOnline() {
        val preference = PhysicalNetworkPreference()
        preference.capabilities(200, false)
        preference.physicalLost(200)
        assertEquals(100L, preference.select(listOf(100)))
        preference.physicalLost(100)
        assertNull(preference.select(emptyList()))
        preference.defaultLost(200, emptySet())
        assertNull(preference.select(emptyList()))
    }

    @Test fun aNewPhysicalDefaultWinsOverTheOldStillAvailableWifi() {
        val preference = PhysicalNetworkPreference()
        preference.capabilities(200, false)
        preference.capabilities(100, false)
        assertEquals(100L, preference.select(listOf(100, 200)))
        preference.defaultLost(200, setOf(100, 200))
        assertEquals(100L, preference.select(listOf(100, 200)))
        preference.defaultLost(100, setOf(200))
        assertEquals(200L, preference.select(listOf(200)))
    }
}
