// SPDX-License-Identifier: GPL-3.0-or-later
package com.calebc42.ebp.companion

/**
 * POC pairing credential accepted by both the Companion and the shipped Emacs
 * composition root. Keeping its display form here prevents onboarding from
 * drifting away from the credential DeviceBridge actually verifies.
 *
 * This remains the public SPEC known-answer credential until real generated,
 * keystore-backed pairing replaces it.
 */
internal const val JETPACS_PAIRING_ID = "101112131415161718191a1b1c1d1e1f"
internal const val JETPACS_PAIRING_TOKEN = "AAECAwQFBgcICQoLDA0ODw"
