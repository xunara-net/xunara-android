package net.xunara.android

import org.junit.Assert.*
import org.junit.Test

class ForwardingPreferencesTest {
    @Test fun routesAreNumericCanonicalAndBounded() {
        for (route in listOf("192.168.1.0/24", "10.0.0.0/8", "2001:db8::/32", "192.168.1.1/32")) assertTrue(route, ForwardingPreferences.validSubnet(route))
        for (route in listOf("host.example/24", "192.168.1.1/24", "0.0.0.0/0", "::/0", "127.0.0.0/8", "fe80::/64", "192.168.1.0/999", "2001:db8::1/32", "::ffff:192.0.2.0/120")) assertFalse(route, ForwardingPreferences.validSubnet(route))
        assertTrue(runCatching { ForwardingPreferences(List(65) { "10.0.0.0/8" }).validated() }.isFailure)
    }

    @Test fun offeringAnExitNeverSilentlyChainsToAnotherExit() {
        val offer = ForwardingPreferences(listOf("192.168.1.0/24"), true)
        assertEquals(offer, Profile("https://control.test", "phone", true, forwarding = offer).validated().forwarding)
        assertTrue(runCatching { Profile("https://control.test", "phone", true, exitNodeId = "another", forwarding = offer).validated() }.isFailure)
        assertEquals(ForwardingPreferences(), Profile("https://control.test", "new-phone", true).validated().forwarding)
    }
}
