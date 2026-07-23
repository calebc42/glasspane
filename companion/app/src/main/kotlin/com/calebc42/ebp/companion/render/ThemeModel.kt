// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC 18.4 theme mirroring: a theme.set `colors` role map overlays a base
// Material scheme so token-colored nodes wear the running Emacs theme; a `null`
// colors map (or none) keeps the Companion's native scheme. Every role is
// optional and merged with a legible platform fallback (§18.4). `dark` present
// forces polarity; absent follows the system (amendment #36). The two roles
// with no Material slot — `success` and `warning` — ride an ExtendedColors
// holder exposed through LocalExtendedColors and resolved by ColorModel.
package com.calebc42.ebp.companion.render

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.luminance
import org.json.JSONObject

/** SPEC 18.4: the `success`/`warning` roles, which Material has no slot for. */
data class ExtendedColors(
    val success: Color,
    val onSuccess: Color,
    val warning: Color,
    val onWarning: Color,
) {
    companion object {
        /** Legible platform defaults (§18.4) for each polarity. */
        fun defaults(dark: Boolean) = ExtendedColors(
            success = if (dark) Color(0xFF7FB77E) else Color(0xFF2E7D32),
            onSuccess = if (dark) Color(0xFF10281A) else Color.White,
            warning = if (dark) Color(0xFFE0B44C) else Color(0xFFB26A00),
            onWarning = if (dark) Color(0xFF2A1F00) else Color.White,
        )
    }
}

/** Falls back to the light defaults before any EbpTheme provides real ones. */
val LocalExtendedColors = staticCompositionLocalOf { ExtendedColors.defaults(false) }

private fun JSONObject.role(key: String): Color? =
    optString(key).takeIf { it.isNotEmpty() }
        ?.let { parseHexColor(it)?.let(::Color) }

/** A legible on-color for a pushed extension role that arrived without one. */
private fun legibleOn(bg: Color): Color =
    if (bg.luminance() < 0.5f) Color.White else Color(0xFF1A1A1A)

/**
 * [base] with every §18.4 role present in [colors] overlaid. The
 * `surface_container*` tones — which no Emacs theme names — are re-derived from
 * the pushed surface/surface_variant pair so token-colored nodes sit on the
 * pushed surface, not the base's.
 */
fun buildColorScheme(colors: JSONObject?, base: ColorScheme): ColorScheme {
    val c = colors ?: return base
    val surface = c.role("surface") ?: base.surface
    val surfaceVariant = c.role("surface_variant") ?: base.surfaceVariant
    return base.copy(
        primary = c.role("primary") ?: base.primary,
        onPrimary = c.role("on_primary") ?: base.onPrimary,
        primaryContainer = c.role("primary_container") ?: base.primaryContainer,
        onPrimaryContainer = c.role("on_primary_container") ?: base.onPrimaryContainer,
        secondary = c.role("secondary") ?: base.secondary,
        onSecondary = c.role("on_secondary") ?: base.onSecondary,
        secondaryContainer = c.role("secondary_container") ?: base.secondaryContainer,
        onSecondaryContainer = c.role("on_secondary_container") ?: base.onSecondaryContainer,
        tertiary = c.role("tertiary") ?: base.tertiary,
        onTertiary = c.role("on_tertiary") ?: base.onTertiary,
        tertiaryContainer = c.role("tertiary_container") ?: base.tertiaryContainer,
        onTertiaryContainer = c.role("on_tertiary_container") ?: base.onTertiaryContainer,
        error = c.role("error") ?: base.error,
        onError = c.role("on_error") ?: base.onError,
        errorContainer = c.role("error_container") ?: base.errorContainer,
        onErrorContainer = c.role("on_error_container") ?: base.onErrorContainer,
        background = c.role("background") ?: c.role("surface") ?: base.background,
        onBackground = c.role("on_background") ?: c.role("on_surface") ?: base.onBackground,
        surface = surface,
        onSurface = c.role("on_surface") ?: base.onSurface,
        surfaceVariant = surfaceVariant,
        onSurfaceVariant = c.role("on_surface_variant") ?: base.onSurfaceVariant,
        outline = c.role("outline") ?: base.outline,
        surfaceContainerLow = lerp(surface, surfaceVariant, 0.25f),
        surfaceContainer = lerp(surface, surfaceVariant, 0.5f),
        surfaceContainerHigh = lerp(surface, surfaceVariant, 0.75f),
    )
}

/** The ExtendedColors a theme selects: pushed success/warning over defaults. */
fun buildExtendedColors(colors: JSONObject?, dark: Boolean): ExtendedColors {
    val d = ExtendedColors.defaults(dark)
    val c = colors ?: return d
    val success = c.role("success") ?: d.success
    val warning = c.role("warning") ?: d.warning
    return ExtendedColors(
        success = success,
        onSuccess = if (c.has("success")) legibleOn(success) else d.onSuccess,
        warning = warning,
        onWarning = if (c.has("warning")) legibleOn(warning) else d.onWarning,
    )
}

/**
 * The one theme entry point. [payload] is the persisted §18.4 theme
 * (`{dark, colors, syntax}`) or null for the native scheme. `dark` decides
 * polarity (present forces it, absent follows the system); `colors` mirrors
 * the Emacs palette. `syntax` is read separately by the editor (W9-h2).
 */
@Composable
fun EbpTheme(payload: JSONObject?, content: @Composable () -> Unit) {
    val dark = when (val d = payload?.opt("dark")) {
        is Boolean -> d
        else -> isSystemInDarkTheme()
    }
    val colors = payload?.optJSONObject("colors")
    val scheme = buildColorScheme(colors, if (dark) darkColorScheme() else lightColorScheme())
    val extended = buildExtendedColors(colors, dark)
    CompositionLocalProvider(LocalExtendedColors provides extended) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}
