// SPDX-License-Identifier: GPL-3.0-or-later
// Icon-name → vector map (SPEC 17.1: `icon` fields are identifiers), ported
// from poc-v1: a pre-seeded cache of the common names plus a reflective
// snake_case → PascalCase lookup over the material-icons-extended artifact
// (Outlined, AutoMirrored.Outlined, then Filled). SPEC 17.2: an unresolved
// name renders a harmless placeholder — HelpOutline — never an error.
package com.calebc42.ebp.companion.render

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Redo
import androidx.compose.material.icons.automirrored.outlined.Undo
import androidx.compose.material.icons.outlined.*
import androidx.compose.ui.graphics.vector.ImageVector
import java.util.concurrent.ConcurrentHashMap

object IconMap {
    private val cache = ConcurrentHashMap<String, ImageVector>()

    init {
        // Pre-populate common icons: skips reflection for the standard set.
        cache["add"] = Icons.Outlined.Add
        cache["arrow_upward"] = Icons.Outlined.ArrowUpward
        cache["arrow_downward"] = Icons.Outlined.ArrowDownward
        cache["refresh"] = Icons.Outlined.Refresh
        cache["search"] = Icons.Outlined.Search
        cache["more_vert"] = Icons.Outlined.MoreVert
        cache["more_horiz"] = Icons.Outlined.MoreHoriz
        cache["close"] = Icons.Outlined.Close
        cache["check"] = Icons.Outlined.Check
        cache["edit"] = Icons.Outlined.Edit
        cache["visibility"] = Icons.Outlined.Visibility
        cache["play_arrow"] = Icons.Outlined.PlayArrow
        cache["stop"] = Icons.Outlined.Stop
        cache["event"] = Icons.Outlined.Event
        cache["checklist"] = Icons.Outlined.Checklist
        cache["folder"] = Icons.Outlined.Folder
        cache["folder_open"] = Icons.Outlined.FolderOpen
        cache["description"] = Icons.Outlined.Description
        cache["schedule"] = Icons.Outlined.Schedule
        cache["done"] = Icons.Outlined.Done
        cache["keyboard_arrow_down"] = Icons.Outlined.KeyboardArrowDown
        cache["keyboard_arrow_up"] = Icons.Outlined.KeyboardArrowUp
        cache["chevron_left"] = Icons.Outlined.ChevronLeft
        cache["chevron_right"] = Icons.Outlined.ChevronRight
        cache["view_list"] = Icons.Outlined.ViewList
        cache["archive"] = Icons.Outlined.Archive
        cache["note_add"] = Icons.Outlined.NoteAdd
        cache["terminal"] = Icons.Outlined.Terminal
        cache["code"] = Icons.Outlined.Code
        cache["send"] = Icons.Outlined.Send
        cache["info"] = Icons.Outlined.Info
        cache["delete"] = Icons.Outlined.Delete
        cache["content_copy"] = Icons.Outlined.ContentCopy
        cache["menu"] = Icons.Outlined.Menu
        cache["save"] = Icons.Outlined.Save
        cache["sync"] = Icons.Outlined.Sync
        cache["settings"] = Icons.Outlined.Settings
        cache["home"] = Icons.Outlined.Home
        cache["inbox"] = Icons.Outlined.Inbox
        cache["task_alt"] = Icons.Outlined.TaskAlt
        cache["today"] = Icons.Outlined.Today
        cache["history"] = Icons.Outlined.History
        cache["label"] = Icons.Outlined.Label
        cache["flag"] = Icons.Outlined.Flag
        cache["image"] = Icons.Outlined.Image
        cache["access_time"] = Icons.Outlined.AccessTime
        cache["keyboard"] = Icons.Outlined.Keyboard
        cache["format_bold"] = Icons.Outlined.FormatBold
        cache["format_italic"] = Icons.Outlined.FormatItalic
        cache["format_list_bulleted"] = Icons.Outlined.FormatListBulleted
        cache["format_list_numbered"] = Icons.Outlined.FormatListNumbered
        cache["title"] = Icons.Outlined.Title
        cache["link"] = Icons.Outlined.Link
        cache["circle"] = Icons.Outlined.Circle
        cache["check_box"] = Icons.Outlined.CheckBox
        cache["check_box_outline_blank"] = Icons.Outlined.CheckBoxOutlineBlank
        cache["format_indent_decrease"] = Icons.Outlined.FormatIndentDecrease
        cache["format_indent_increase"] = Icons.Outlined.FormatIndentIncrease
        cache["undo"] = Icons.AutoMirrored.Outlined.Undo
        cache["redo"] = Icons.AutoMirrored.Outlined.Redo
        cache["swap_vert"] = Icons.Outlined.SwapVert
        cache["drag_handle"] = Icons.Outlined.DragHandle
        cache["timer"] = Icons.Outlined.Timer
        cache["star"] = Icons.Outlined.StarOutline
        cache["tune"] = Icons.Outlined.Tune
        cache["help_outline"] = Icons.Outlined.HelpOutline
    }

    fun get(name: String): ImageVector = cache[name] ?: run {
        // A `_filled` suffix asks for the Filled vector of the base name —
        // the checked-state glyph swap (Outlined at rest, Filled while
        // checked) that every wire name resolved Outlined-first could not
        // spell. Falls through to the normal chain if no Filled exists.
        val filled = name.endsWith("_filled")
        val base = if (filled) name.removeSuffix("_filled") else name
        val pascal = base.split('_').joinToString("") { part ->
            part.replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }
        }
        val resolved = (if (filled)
            resolve("androidx.compose.material.icons.filled.${pascal}Kt",
                "get$pascal", Icons.Filled)
                ?: resolve("androidx.compose.material.icons.automirrored.filled.${pascal}Kt",
                    "get$pascal", Icons.AutoMirrored.Filled)
            else null)
            ?: resolve("androidx.compose.material.icons.outlined.${pascal}Kt",
                "get$pascal", Icons.Outlined)
            ?: resolve("androidx.compose.material.icons.automirrored.outlined.${pascal}Kt",
                "get$pascal", Icons.AutoMirrored.Outlined)
            ?: resolve("androidx.compose.material.icons.filled.${pascal}Kt",
                "get$pascal", Icons.Filled)
        // LD-19: cache only a RESOLVED vector. The success set is finite (the
        // material catalog), so the map is bounded by construction; getOrPut
        // of the placeholder grew one entry per distinct unknown wire string
        // for the process lifetime.
        if (resolved != null) { cache[name] = resolved; resolved }
        else Icons.Outlined.HelpOutline // SPEC 17.2: harmless placeholder
    }

    private fun resolve(className: String, methodName: String, receiver: Any): ImageVector? =
        try {
            Class.forName(className).getMethod(methodName, receiver.javaClass)
                .invoke(null, receiver) as? ImageVector
        } catch (_: Exception) {
            null
        }
}
