package net.xunara.android

import org.junit.Assert.*
import org.junit.Test

class ProfileTest {
    @Test fun canonicalRootAndLocalDevelopment() {
        assertEquals("https://example.com:9090/", Profile("https://EXAMPLE.com:9090", "android", true).validated().server)
        assertEquals("http://127.0.0.1:18080/", Profile("http://127.0.0.1:18080", "android", false).validated().server)
        assertEquals("https://example.com/", Profile("HTTPS://EXAMPLE.com:443/", "android", true).validated().server)
    }
    @Test fun rejectSecretsTenantPathsAndCleartext() {
        for (server in listOf("https://u:password@example.com", "http://example.com", "https://example.com/t/test/login", "https://example.com/?token=secret", "https://example.com/#secret", "https://example.com:99999")) {
            assertTrue(server, runCatching { Profile(server, "android", true).validated() }.isFailure)
        }
    }
    @Test fun browserAuthorizationIsSameOriginOnly() {
        val profile = Profile("https://example.com:9090/", "android", true).validated()
        assertTrue(profile.allowsBrowser("https://example.com:9090/register/request-id"))
        for (target in listOf("https://evil.test", "https://example.com/", "https://example.com:9090@evil.test", "javascript:alert(1)", "https://example.com:9090/register#fragment")) {
            assertFalse(target, profile.allowsBrowser(target))
        }
    }
}
