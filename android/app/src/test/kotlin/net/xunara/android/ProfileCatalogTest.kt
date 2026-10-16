package net.xunara.android

import org.junit.Assert.*
import org.junit.Test

class ProfileCatalogTest {
    private val home = Profile("https://home.example/", "phone-home", true)

    @Test fun canonicalServersKeepTheirOwnPreferencesAndSwitchWithoutCopyingIdentity() {
        val office = Profile("https://OFFICE.example:443", "phone-work", false, false, AppRouting(AppRoutingMode.ONLY, listOf("com.example.work")))
        val catalog = ProfileCatalog(home, listOf(home)).save(office)
        assertEquals(2, catalog.profiles.size)
        assertEquals("https://office.example/", catalog.current.server)
        assertEquals(home, catalog.select(home.server).current)
        assertEquals(catalog.current, catalog.select(home.server).select(office.server).current)
        val edited = catalog.save(office.copy(hostname = "work-edited"))
        assertEquals(2, edited.profiles.size)
        assertEquals("work-edited", edited.current.hostname)
    }

    @Test fun rejectMissingCurrentDuplicatesAndUnlimitedGrowth() {
        for (entries in listOf(emptyList(), listOf(home, home), listOf(home.copy(hostname = "other")))) {
            assertTrue(runCatching { ProfileCatalog(home, entries).validated() }.isFailure)
        }
        val entries = (1..16).map { home.copy(server = "https://server$it.example/") }
        val full = ProfileCatalog(entries.first(), entries).validated()
        assertTrue(runCatching { full.save(home) }.isFailure)
        assertTrue(runCatching { full.select(home.server) }.isFailure)
    }

    @Test fun removalNeverChangesTheSelectedServerOrDeletesIt() {
        val saved = ProfileCatalog(home, listOf(home)).save(home.copy(server = "https://office.example/"))
        assertTrue(runCatching { saved.remove(saved.current.server) }.isFailure)
        val removed = saved.remove(home.server)
        assertEquals(saved.current, removed.current)
        assertEquals(1, removed.profiles.size)
        assertTrue(runCatching { removed.remove(home.server) }.isFailure)
    }
}
