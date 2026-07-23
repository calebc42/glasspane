// SPDX-License-Identifier: GPL-3.0-or-later
// The SPEC 16.6 color model: a Color is a theme-role identifier or one of
// #rgb / #rgba / #rrggbb / #rrggbbaa (case-insensitive). Unknown roles get a
// LEGIBLE platform fallback — never transparent. The hex parser is pure and
// JVM-tested; role resolution reads the active MaterialTheme, which EbpTheme
// (ThemeModel) builds from the pushed §18.4 palette, plus the success/warning
// extension roles from LocalExtendedColors.
package com.calebc42.ebp.companion.render

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

/** Parse a §16.6 hex form to ARGB, or null when it is not one. Pure. */
fun parseHexColor(spec: String): Long? {
    if (!spec.startsWith("#")) return null
    val h = spec.substring(1)
    if (!h.all { it.isDigit() || it.lowercaseChar() in 'a'..'f' }) return null
    fun d(c: Char) = c.digitToInt(16).toLong()
    fun wide(c: Char) = d(c) * 17 // 0xF -> 0xFF
    return when (h.length) {
        3 -> 0xFF000000L or (wide(h[0]) shl 16) or (wide(h[1]) shl 8) or wide(h[2])
        4 -> (wide(h[3]) shl 24) or (wide(h[0]) shl 16) or (wide(h[1]) shl 8) or wide(h[2])
        6 -> 0xFF000000L or h.toLong(16)
        8 -> // #rrggbbaa: alpha is the LAST byte on the wire, first in ARGB.
            ((h.substring(6).toLong(16)) shl 24) or h.substring(0, 6).toLong(16)
        else -> null
    }
}

/**
 * Resolve a §16.6 Color member against the active theme. Null/empty means
 * "not specified" (caller keeps its default); an unknown role resolves to a
 * legible fallback (onSurface), never transparent.
 */
@Composable
fun resolveColor(spec: String?): Color? =
    resolveColorIn(MaterialTheme.colorScheme, spec, LocalExtendedColors.current)

/** Non-composable form for span builders that capture the scheme once.
 * [extended] resolves the §18.4 success/warning roles that have no Material
 * slot; when absent they take the legible fallback like any unknown role. */
fun resolveColorIn(scheme: androidx.compose.material3.ColorScheme,
                   spec: String?,
                   extended: ExtendedColors? = null): Color? {
    if (spec.isNullOrEmpty()) return null
    parseHexColor(spec)?.let { return Color(it) } // Color(Long) takes ARGB
    when (spec) {
        "success" -> extended?.let { return it.success }
        "on_success" -> extended?.let { return it.onSuccess }
        "warning" -> extended?.let { return it.warning }
        "on_warning" -> extended?.let { return it.onWarning }
    }
    return when (spec) {
        "primary" -> scheme.primary
        "on_primary" -> scheme.onPrimary
        "primary_container" -> scheme.primaryContainer
        "on_primary_container" -> scheme.onPrimaryContainer
        "secondary" -> scheme.secondary
        "on_secondary" -> scheme.onSecondary
        "secondary_container" -> scheme.secondaryContainer
        "on_secondary_container" -> scheme.onSecondaryContainer
        "tertiary" -> scheme.tertiary
        "on_tertiary" -> scheme.onTertiary
        "surface" -> scheme.surface
        "on_surface" -> scheme.onSurface
        "surface_variant" -> scheme.surfaceVariant
        "on_surface_variant" -> scheme.onSurfaceVariant
        "background" -> scheme.background
        "on_background" -> scheme.onBackground
        "error" -> scheme.error
        "on_error" -> scheme.onError
        "error_container" -> scheme.errorContainer
        "on_error_container" -> scheme.onErrorContainer
        "outline" -> scheme.outline
        "outline_variant" -> scheme.outlineVariant
        "inverse_surface" -> scheme.inverseSurface
        "inverse_on_surface" -> scheme.inverseOnSurface
        // success/warning are handled above from ExtendedColors when supplied;
        // without it (e.g. a span builder that captured only the scheme) they
        // fall through to the legible fallback like any unknown role.
        else -> scheme.onSurface // SPEC 16.6: legible, never transparent
    }
}
