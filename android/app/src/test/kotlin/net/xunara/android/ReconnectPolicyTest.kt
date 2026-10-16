package net.xunara.android

import org.junit.Assert.*
import org.junit.Test

class ReconnectPolicyTest {
    @Test fun neverAutoReplaysEnrollmentBeforeAuthorizedTunnel() {
        val policy = ReconnectPolicy(true)
        policy.started("wifi")
        assertEquals(ReconnectPolicy.Action.KEEP, policy.changed("mobile"))
        assertFalse(policy.ready(true, false))
    }

    @Test fun networkLossWaitsForWorkerExitAndUnderlayRecovery() {
        val policy = ReconnectPolicy(true)
        policy.started("wifi")
        policy.established("wifi")
        assertEquals(ReconnectPolicy.Action.KEEP, policy.changed("wifi"))
        assertEquals(ReconnectPolicy.Action.RESTART, policy.changed("offline"))
        assertFalse(policy.ready(false, false))
        assertFalse(policy.ready(true, true))
        assertTrue(policy.ready(true, false))
        policy.started("mobile")
        assertFalse(policy.ready(true, false))
        assertEquals(ReconnectPolicy.Action.KEEP, policy.changed("mobile"))
    }

    @Test fun returningToSameLanStillRebuildsLostSockets() {
        val policy = ReconnectPolicy(true)
        policy.established("wifi")
        policy.changed("offline")
        assertEquals(ReconnectPolicy.Action.RESTART, policy.changed("wifi"))
        assertTrue(policy.ready(true, false))
    }

    @Test fun manualDisconnectAndRevocationAlwaysCancelPendingRestart() {
        val policy = ReconnectPolicy(true)
        policy.established("wifi")
        policy.changed("mobile")
        policy.cancel()
        assertEquals(ReconnectPolicy.Action.KEEP, policy.changed("wifi"))
        assertFalse(policy.ready(true, false))
    }

    @Test fun disabledAutomaticReconnectPreservesSafeDisconnect() {
        val policy = ReconnectPolicy(false)
        policy.established("wifi")
        assertEquals(ReconnectPolicy.Action.STOP, policy.changed("mobile"))
        assertFalse(policy.wanted)
        assertFalse(policy.ready(true, false))
    }
}
