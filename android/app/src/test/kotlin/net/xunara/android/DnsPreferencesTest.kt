package net.xunara.android

import org.junit.Assert.*
import org.junit.Test

class DnsPreferencesTest {
    @Test fun numericAddressesNeverNeedNameResolution() {
        for (address in listOf("1.1.1.1", "192.168.10.2", "::1", "2001:db8::53", "::ffff:192.0.2.1")) assertTrue(address, DnsPreferences.numericAddress(address))
        for (address in listOf("resolver.example", "999.1.1.1", "1.2.3", "1.2.3.0004", "1.2.3.4:53", "2001:::1", "fe80::1%wlan0", "", "[::1]")) assertFalse(address, DnsPreferences.numericAddress(address))
    }

    @Test fun encryptedDnsNeedsBootstrapAndNeverAcceptsCredentials() {
        for (address in listOf("https://user:secret@resolver.example/dns-query", "https://resolver.example/dns-query?token=secret", "http://resolver.example/dns-query", "tls://resolver.example/path", "https://resolver.example/dns-query")) {
            assertTrue(address, runCatching { DnsPreferences(address).validated() }.isFailure)
        }
        for (address in listOf("https://resolver.example/dns-query", "tls://resolver.example:8853")) {
            assertEquals(address, DnsPreferences(address, listOf("192.0.2.53")).validated().resolver)
        }
        for (address in listOf("1.1.1.1", "1.1.1.1:5353", "::1", "[2001:db8::53]:5353", "https://1.1.1.1/dns-query")) {
            assertEquals(address, DnsPreferences(address).validated().resolver)
        }
    }

    @Test fun disabledDnsPreservesSettingsForTheSameAccountOnly() {
        val dns = DnsPreferences("tls://one.one.one.one", listOf("1.1.1.1"), true)
        val profile = Profile("https://control.test", "phone", true, dns = dns).validated()
        assertFalse(profile.acceptDns)
        assertEquals(dns, profile.copy(acceptDns = true).validated().dns)
        assertEquals(DnsPreferences(), Profile("https://control.test", "another-phone", true).validated().dns)
    }
}
