package net.xunara.android

import org.junit.Assert.*
import org.junit.Test

class AppRoutingTest {
    private val own = "net.xunara.android"
    private val example = "com.example.viewer"

    @Test fun defaultAndExclusionsAlwaysBypassOwnApplication() {
        assertEquals(AppRoutingPlan(emptyList(), listOf(own)), AppRouting().plan(emptySet(), own))
        val plan = AppRouting(AppRoutingMode.EXCLUDE, listOf(example, "com.removed.app")).plan(setOf(example), own)
        assertTrue(plan.allowed.isEmpty())
        assertEquals(listOf(example, own), plan.disallowed)
    }

    @Test fun inclusionNeverFallsBackToAllApplications() {
        assertTrue(runCatching { AppRouting(AppRoutingMode.ONLY).validated() }.isFailure)
        assertTrue(runCatching { AppRouting(AppRoutingMode.ONLY, listOf(example)).plan(emptySet(), own) }.isFailure)
        val plan = AppRouting(AppRoutingMode.ONLY, listOf(example)).plan(setOf(example), own)
        assertEquals(listOf(example), plan.allowed)
        assertTrue(plan.disallowed.isEmpty())
    }

    @Test fun rejectUnknownModesOwnAppMalformedAndOversizedLists() {
        assertTrue(runCatching { AppRoutingMode.parse("fallback") }.isFailure)
        for (name in listOf(own, "invalid/package", "com.test;reboot", "com..test", "")) {
            assertTrue(runCatching { AppRouting(AppRoutingMode.EXCLUDE, listOf(name)).validated() }.isFailure)
        }
        assertTrue(runCatching { AppRouting(AppRoutingMode.ALL, listOf(example)).validated() }.isFailure)
        assertTrue(runCatching { AppRouting(AppRoutingMode.EXCLUDE, List(257) { example }).validated() }.isFailure)
        assertEquals(listOf(example), AppRouting(AppRoutingMode.ONLY, listOf(example, example)).validated().packages)
    }
}
