// SPDX-License-Identifier: GPL-3.0-or-later
package com.calebc42.ebp.companion

import com.calebc42.ebp.wire.SessionState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReconnectNotificationTest {
    @Test
    fun notificationTargetsAndroidEmacs() {
        assertEquals("org.gnu.emacs", ANDROID_EMACS_PACKAGE)
    }

    @Test
    fun onlyAuthenticatedStatesCountAsAConnection() {
        assertFalse(isAuthenticatedConnectionState(SessionState.CONNECTED))
        assertFalse(isAuthenticatedConnectionState(SessionState.CHALLENGED))
        assertTrue(isAuthenticatedConnectionState(SessionState.SYNCING))
        assertTrue(isAuthenticatedConnectionState(SessionState.READY))
        assertFalse(isAuthenticatedConnectionState(SessionState.CLOSED))
    }

    @Test
    fun onlyCurrentAuthenticatedSessionLossPostsReconnect() {
        assertTrue(shouldPostReconnectNotification(true, true))
        assertFalse(shouldPostReconnectNotification(false, true))
        assertFalse(shouldPostReconnectNotification(true, false))
        assertFalse(shouldPostReconnectNotification(false, false))
    }
}
