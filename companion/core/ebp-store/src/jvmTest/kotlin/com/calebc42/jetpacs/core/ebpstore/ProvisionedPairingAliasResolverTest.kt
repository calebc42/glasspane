// SPDX-License-Identifier: GPL-3.0-or-later
package com.calebc42.jetpacs.core.ebpstore

import com.calebc42.ebp.wire.PairingId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ProvisionedPairingAliasResolverTest {
    @Test
    fun snapshotExposesOnlyExplicitlyCompletedProvisioning() {
        val provisionedPairing = PairingId("00000000000000000000000000000001")
        val unprovisionedPairing = PairingId("00000000000000000000000000000002")
        val aliases = ProvisionedPairingAliases(
            credentialKeyAlias = "credential-v1",
            payloadKeyAlias = "payload-v1",
        )
        val source = mutableMapOf(provisionedPairing to aliases)
        val resolver = SnapshotProvisionedPairingAliasResolver(source)

        source.clear()

        assertEquals(aliases, resolver.resolve(provisionedPairing))
        assertNull(resolver.resolve(unprovisionedPairing))
    }
}
