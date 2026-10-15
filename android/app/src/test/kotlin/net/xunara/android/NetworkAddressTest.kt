package net.xunara.android

import java.net.InetAddress
import java.net.Inet6Address
import org.junit.Assert.*
import org.junit.Test

class NetworkAddressTest {
    @Test fun ipv4DnsIsProtectedAsAHostPrefix() {
        assertEquals("100.100.100.100/32", NetworkAddress.prefix(InetAddress.getByName("100.100.100.100"), 32))
    }
    @Test fun ipv6ScopeDoesNotLeakIntoCidrParser() {
        val address = Inet6Address.getByAddress(null, InetAddress.getByName("fe80::1").address, 3)
        assertTrue(address.hostAddress!!.contains('%'))
        val prefix = NetworkAddress.prefix(address, 64)
        assertFalse(prefix.contains('%'))
        assertTrue(prefix.endsWith("/64"))
        assertArrayEquals(address.address, InetAddress.getByName(prefix.substringBefore('/')).address)
    }
    @Test fun rejectImpossiblePrefixLengths() {
        assertTrue(runCatching { NetworkAddress.prefix(InetAddress.getByName("10.0.0.1"), 128) }.isFailure)
    }
}
