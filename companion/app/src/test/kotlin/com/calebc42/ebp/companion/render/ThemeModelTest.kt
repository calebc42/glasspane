// SPDX-License-Identifier: GPL-3.0-or-later
// W9-h SPEC 18.4: the color-scheme builder overlays only the roles a theme
// pushes onto the base scheme, merges the rest with the legible platform
// fallback, derives the surface-container tones from the pushed surface pair,
// and routes success/warning (no Material slot) into ExtendedColors.
package com.calebc42.ebp.companion.render

import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.ui.graphics.Color
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ThemeModelTest {

    @Test
    fun overlaysPushedRolesAndKeepsBaseForTheRest() {
        val base = lightColorScheme()
        val colors = buildJsonObject {
            put("primary", "#ff0000")
            put("surface", "#101010")
            put("surface_variant", "#303030")
        }
        val scheme = buildColorScheme(colors, base)
        // Pushed roles win.
        assertEquals(Color(0xFFFF0000), scheme.primary)
        assertEquals(Color(0xFF101010), scheme.surface)
        // Un-pushed roles keep the base (legible fallback).
        assertEquals(base.onPrimary, scheme.onPrimary)
        assertEquals(base.tertiary, scheme.tertiary)
        // surface_container* are re-derived from the pushed surface pair, not
        // left at the base tones (a token node sits on the pushed surface).
        assertNotEquals(base.surfaceContainer, scheme.surfaceContainer)
        assertTrue(scheme.surfaceContainer.red < scheme.surfaceVariant.red)
    }

    @Test
    fun missingOnColorIsDerivedFromThePushedRoleNotTheBase() {
        // A LIGHT primary pushed without on_primary: the on-color must be
        // derived contrast-legible from the pushed color (dark), NOT the light
        // scheme's white onPrimary (amendment #56).
        val base = lightColorScheme()
        val scheme = buildColorScheme(
            buildJsonObject { put("primary", "#fffff0") }, base)
        assertEquals(Color(0xFFFFFFF0), scheme.primary)
        assertEquals(Color(0xFF1A1A1A), scheme.onPrimary) // legible dark, not base white
        assertNotEquals(base.onPrimary, scheme.onPrimary)
        // An un-pushed role keeps the base on-color.
        assertEquals(base.onTertiary, scheme.onTertiary)
    }

    @Test
    fun nullColorsIsTheNativeScheme() {
        val base = darkColorScheme()
        assertEquals(base, buildColorScheme(null, base))
    }

    @Test
    fun successWarningRideExtendedColorsWithLegibleOnColor() {
        // Absent: the polarity defaults.
        val d = buildExtendedColors(null, dark = true)
        assertEquals(ExtendedColors.defaults(true), d)
        // Pushed: the authored color plus a legible derived on-color.
        val ext = buildExtendedColors(
            buildJsonObject {
                put("success", "#eaffea")
                put("warning", "#402000")
            },
            dark = false)
        assertEquals(Color(0xFFEAFFEA), ext.success)
        // A light success gets a dark on-color; a dark warning gets white.
        assertEquals(Color(0xFF1A1A1A), ext.onSuccess)
        assertEquals(Color.White, ext.onWarning)
    }

    @Test
    fun resolveColorResolvesSuccessWarningFromExtended() {
        val ext = ExtendedColors.defaults(false)
        assertEquals(ext.success,
            resolveColorIn(lightColorScheme(), "success", ext))
        assertEquals(ext.warning,
            resolveColorIn(lightColorScheme(), "warning", ext))
        // Without an ExtendedColors, they take the legible fallback, never null.
        assertEquals(lightColorScheme().onSurface,
            resolveColorIn(lightColorScheme(), "success"))
    }
}
