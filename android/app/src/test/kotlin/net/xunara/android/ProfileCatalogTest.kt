package net.xunara.android

import org.junit.Assert.*
import org.junit.Test

class ProfileCatalogTest {
    private val home = Profile("https://home.example/", "phone-home", true).validated()

    @Test fun canonicalServersKeepTheirOwnPreferencesAndSwitchWithoutCopyingIdentity() {
        val office = Profile("https://OFFICE.example:443", "phone-work", false, false, AppRouting(AppRoutingMode.ONLY, listOf("com.example.work"))).validated()
        val catalog = ProfileCatalog(home, listOf(home)).save(office)
        assertEquals(2, catalog.profiles.size)
        assertEquals("https://office.example/", catalog.current.server)
        assertEquals(home, catalog.select(home.id).current)
        assertEquals(catalog.current, catalog.select(home.id).select(office.id).current)
        val edited = catalog.save(office.copy(hostname = "work-edited"))
        assertEquals(2, edited.profiles.size)
        assertEquals("work-edited", edited.current.hostname)
    }

    @Test fun rejectMissingCurrentDuplicatesAndUnlimitedGrowth() {
        for (entries in listOf(emptyList(), listOf(home, home), listOf(home.copy(hostname = "other")))) {
            assertTrue(runCatching { ProfileCatalog(home, entries).validated() }.isFailure)
        }
        val entries = (1..16).map { Profile("https://server$it.example/", "phone", true).validated() }
        val full = ProfileCatalog(entries.first(), entries).validated()
        assertTrue(runCatching { full.save(home) }.isFailure)
        assertTrue(runCatching { full.select(home.id) }.isFailure)
    }

    @Test fun removalNeverChangesTheSelectedServerOrDeletesIt() {
        val saved = ProfileCatalog(home, listOf(home)).save(Profile("https://office.example/", "office", true))
        assertTrue(runCatching { saved.remove(saved.current.id) }.isFailure)
        val removed = saved.remove(home.id)
        assertEquals(saved.current, removed.current)
        assertEquals(1, removed.profiles.size)
        assertTrue(runCatching { removed.remove(home.id) }.isFailure)
    }

    @Test fun sameControllerAccountsHaveIndependentIdentityDirectories() {
        val second = Profile(home.server, "phone-work", true, id = "11111111-1111-4111-8111-111111111111", label = "公司账号")
        val catalog = ProfileCatalog(home, listOf(home)).save(second)
        assertEquals(2, catalog.profiles.size)
        assertNotEquals(home.identityDirectory(), catalog.current.identityDirectory())
        assertEquals(home.identityDirectory(), catalog.select(home.id).current.identityDirectory())
        assertEquals(home.id.removePrefix("legacy-"), home.identityDirectory())
        assertTrue(runCatching { catalog.save(second.copy(server = "https://new.example/")) }.isFailure)
        assertTrue(runCatching { home.copy(server = "https://office.example/").validated() }.isFailure)
        val edited = catalog.save(second.copy(acceptDns = true, exitNodeId = "exit-node", exitNodeName = "公司出口"))
        assertTrue(edited.current.acceptDns)
        assertEquals("exit-node", edited.current.exitNodeId)
    }
}
