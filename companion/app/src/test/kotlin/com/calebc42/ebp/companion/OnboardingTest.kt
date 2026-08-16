// SPDX-License-Identifier: GPL-3.0-or-later
package com.calebc42.ebp.companion

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class OnboardingTest {
    @Test
    fun vaultChoicesResolveIndependently() {
        assertEquals("/sdcard", selectedVault(JetpacsVaultChoice.SDCARD))
        assertEquals(
            "/data/data/org.gnu.emacs/files",
            selectedVault(JetpacsVaultChoice.EMACS),
        )
        assertEquals(
            "/data/data/com.termux/files/home",
            selectedVault(JetpacsVaultChoice.TERMUX),
        )
        assertEquals("~/", selectedVault(JetpacsVaultChoice.REMOTE))
    }

    @Test
    fun unixHomeChoicesResolveIndependently() {
        assertEquals(
            "/data/data/org.gnu.emacs/files",
            selectedConfigHome(JetpacsEmacsHomeChoice.LOCAL),
        )
        assertEquals(
            "/data/data/com.termux/files/home",
            selectedConfigHome(JetpacsEmacsHomeChoice.TERMUX_SHARED),
        )
        assertNull(selectedConfigHome(JetpacsEmacsHomeChoice.REMOTE))
    }

    @Test
    fun installCommandCarriesBothIndependentChoices() {
        val default = termuxInstallCommand(
            JetpacsVaultChoice.SDCARD,
            JetpacsEmacsHomeChoice.LOCAL,
        )!!
        val crossProduct = termuxInstallCommand(
            JetpacsVaultChoice.EMACS,
            JetpacsEmacsHomeChoice.TERMUX_SHARED,
        )!!
        assertTrue(default.startsWith("termux-setup-storage\n"))
        assertTrue(default.contains("install shared emacs"))
        assertTrue(crossProduct.contains("install emacs termux"))
        assertTrue(default.endsWith("&& rm -rf ~/storage/shared/Documents/jetpacs-installer"))
        assertTrue(crossProduct.endsWith("&& rm -rf ~/storage/shared/Documents/jetpacs-installer"))
        assertNull(
            termuxInstallCommand(
                JetpacsVaultChoice.TERMUX,
                JetpacsEmacsHomeChoice.REMOTE,
            ),
        )
    }

    @Test
    fun advancedFlowNeverOffersTermuxVaultToLocalOrRemoteEmacs() {
        assertEquals(
            listOf(JetpacsVaultChoice.SDCARD, JetpacsVaultChoice.EMACS),
            allowedVaultChoices(JetpacsEmacsHomeChoice.LOCAL),
        )
        assertEquals(
            listOf(JetpacsVaultChoice.REMOTE),
            allowedVaultChoices(JetpacsEmacsHomeChoice.REMOTE),
        )
        assertTrue(
            JetpacsVaultChoice.TERMUX in
                allowedVaultChoices(JetpacsEmacsHomeChoice.TERMUX_SHARED),
        )
    }

    @Test
    fun remoteSnippetCarriesTheCredentialAcceptedByTheCompanion() {
        val snippet = remoteInitSnippet()
        assertTrue(snippet.contains(JETPACS_PAIRING_ID))
        assertTrue(snippet.contains(JETPACS_PAIRING_TOKEN))
        assertTrue(snippet.endsWith("(require 'jetpacs)"))
        assertTrue(!snippet.contains("load-path"))
    }

    @Test
    fun packageVcInstallIsSeparateFromTheInitRequire() {
        assertTrue(PACKAGE_VC_INSTALL_SNIPPET.startsWith("(package-vc-install"))
        assertTrue(PACKAGE_VC_INSTALL_SNIPPET.contains(":lisp-dir \"emacs\""))
        assertTrue(!PACKAGE_VC_INSTALL_SNIPPET.contains("(require 'jetpacs)"))
    }

    @Test
    fun termuxBranchShowsBothStartupFiles() {
        assertTrue(TERMUX_EARLY_INIT_SNIPPET.contains("(setenv \"HOME\""))
        assertTrue(
            TERMUX_EARLY_INIT_SNIPPET.contains(
                "/data/data/com.termux/files/home/.emacs.d/",
            ),
        )
        assertTrue(INIT_SEAM_SNIPPET.contains("(require 'jetpacs)"))
    }

    @Test
    fun appShipsTheExactTermuxPathClipboardSnippet() {
        assertEquals(
            "(setenv \"PATH\" (format \"%s:%s\" " +
                "\"/data/data/com.termux/files/usr/bin\"\n" +
                "\t\t       (getenv \"PATH\")))\n" +
                "(push \"/data/data/com.termux/files/usr/bin\" exec-path)",
            TERMUX_PATH_SNIPPET,
        )
    }

    @Test
    fun recommendedPackageEntryIsLocalEmacsOnly() {
        assertTrue(RECOMMENDED_INIT_SNIPPET.contains("user-emacs-directory"))
        assertTrue(RECOMMENDED_INIT_SNIPPET.contains("\"jetpacs/emacs\""))
        assertTrue(RECOMMENDED_INIT_SNIPPET.contains("install-recommended.el"))
        assertTrue(RECOMMENDED_INIT_SNIPPET.contains("(require 'jetpacs)"))
        assertTrue(RECOMMENDED_INIT_SNIPPET.lines().size == 5)
        assertTrue(!RECOMMENDED_INIT_SNIPPET.contains("termux", ignoreCase = true))
    }
}
