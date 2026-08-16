// SPDX-License-Identifier: GPL-3.0-or-later
// S11: what the system back gesture is allowed to run. The two positive
// fixtures are VERBATIM canonical JSON from the authors themselves —
// `jetpacs-chrome-screen' and the m3 catalog's center-aligned bar — so this
// pins the reader to what Emacs actually ships, not to a hand-built guess.
// The negatives are the hijack cases: `view.switch' lives on drawer rows,
// body buttons and trailing bar actions too, and none of them is back.
// Pure Kotlin, no Compose harness — the DialogCaptureTest shape.
package com.calebc42.ebp.companion.render

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ChromeBackTest {

    private fun spec(json: String): JsonObject =
        Json.parseToJsonElement(json) as JsonObject

    private fun viewSwitch(view: String) = buildJsonObject {
        put("builtin", "view.switch")
        put("view", view)
    }

    @Test
    fun aDrilledChromeScreenOffersItsArrowToTheSystemGesture() {
        // (jetpacs-chrome-screen "Files" body :back (jetpacs-view-switch "hub"))
        val view = spec("""
            {"body":{"t":"text","text":"body"},"t":"scaffold",
             "top_bar":{"align":"center","children":[
               {"content_description":"back","icon":"arrow_back",
                "on_tap":{"builtin":"view.switch","view":"hub"},
                "t":"icon_button"},
               {"style":"title","t":"text","text":"Files","weight":1}],
              "spacing":4,"t":"row"},
             "top_bar_style":"small"}""")
        assertEquals(viewSwitch("hub"), chromeBackDescriptor(view))
    }

    @Test
    fun theStackBottomHasNoBackAndKeepsTheSystemDefault() {
        // (jetpacs-chrome-screen "Hub" body) — the root wears the hamburger,
        // never an arrow, so back must still finish the Activity.
        val view = spec("""
            {"body":{"t":"text","text":"body"},"t":"scaffold",
             "top_bar":{"align":"center","children":[
               {"style":"title","t":"text","text":"Hub","weight":1}],
              "spacing":4,"t":"row"},
             "top_bar_style":"small"}""")
        assertNull(chromeBackDescriptor(view))
    }

    @Test
    fun aCenterAlignedBarKeepsItsArrowOnTheLeadingSpine() {
        // jetpacs-m3-top-app-bar--centered-bar: the icon row is wrapped in a
        // box so the title can center OVER it. The arrow is still leading.
        val view = spec("""
            {"body":{"t":"text","text":"b"},"t":"scaffold",
             "top_bar":{"alignment":"center","children":[
               {"align":"center","children":[
                 {"content_description":"back","icon":"arrow_back",
                  "on_tap":{"builtin":"view.switch","view":"examples"},
                  "t":"icon_button"},
                 {"children":[{"content_description":"Menu","icon":"menu",
                   "on_tap":{"action":"m3catalog.demo"},"t":"icon_button"}],
                  "t":"tooltip","text":"Menu"},
                 {"t":"spacer","weight":1}],
                "fill":true,"spacing":4,"t":"row"},
               {"max_lines":1,"style":"title","t":"text",
                "text":"Center TopAppBar"}],
              "fill_fraction":1.0,"t":"box"},
             "top_bar_style":"center"}""")
        assertEquals(viewSwitch("examples"), chromeBackDescriptor(view))
    }

    @Test
    fun aDrawerRowNeverClaimsBack() {
        // S8 hangs the drawer on the stack BOTTOM — the one screen with no
        // arrow — and its rows are `view.switch` destinations. Back there must
        // leave the app, not silently jump to a drawer destination.
        val view = spec("""
            {"t":"scaffold","body":{"t":"text","text":"b"},
             "top_bar":{"t":"row","children":[
               {"style":"title","t":"text","text":"Hub","weight":1}]},
             "drawer":{"t":"column","children":[
               {"t":"card","on_tap":{"builtin":"view.switch","view":"files"},
                "children":[{"t":"text","text":"Files"}]}]}}""")
        assertNull(chromeBackDescriptor(view))
    }

    @Test
    fun aBodyButtonNeverClaimsBack() {
        val view = spec("""
            {"t":"scaffold",
             "top_bar":{"t":"row","children":[
               {"style":"title","t":"text","text":"Hub","weight":1}]},
             "body":{"t":"column","children":[
               {"t":"button","label":"Open files",
                "on_tap":{"builtin":"view.switch","view":"files"}}]}}""")
        assertNull(chromeBackDescriptor(view))
    }

    @Test
    fun aTrailingBarActionNeverClaimsBack() {
        // Same node, same builtin, second in the row: a bar ACTION that
        // switches views is not the back affordance and must not become one.
        val view = spec("""
            {"t":"scaffold","body":{"t":"text","text":"b"},
             "top_bar":{"t":"row","children":[
               {"style":"title","t":"text","text":"Files","weight":1},
               {"icon":"arrow_back","content_description":"back",
                "on_tap":{"builtin":"view.switch","view":"hub"},
                "t":"icon_button"}]}}""")
        assertNull(chromeBackDescriptor(view))
    }

    @Test
    fun aNonScaffoldRootHasNoBack() {
        // A welcome/error/plain document view: no chrome, nothing to pop.
        val view = spec("""
            {"t":"column","children":[
              {"t":"icon_button","icon":"arrow_back",
               "on_tap":{"builtin":"view.switch","view":"hub"}}]}""")
        assertNull(chromeBackDescriptor(view))
    }

    @Test
    fun aRemoteArrowIsNotACompanionLocalBack() {
        // jetpacs-hypertext's document nav wears "arrow_back" over a REMOTE
        // descriptor (Emacs runs eww-back-url). S11 is the offline-safe local
        // pop only; a remote arrow keeps the system default.
        val view = spec("""
            {"t":"scaffold","body":{"t":"text","text":"b"},
             "top_bar":{"t":"row","children":[
               {"t":"icon_button","icon":"arrow_back",
                "content_description":"Back",
                "on_tap":{"action":"hypertext.nav","args":{"op":"back"}}}]}}""")
        assertNull(chromeBackDescriptor(view))
    }

    @Test
    fun aTippedArrowStillOwnsTheGesture() {
        // The house style wraps bar icons in `jetpacs-tooltip', whose anchor
        // is its first child (the badge shape). A tipped back arrow must not
        // silently lose the system gesture while still drawing the button.
        val view = spec("""
            {"t":"scaffold","body":{"t":"text","text":"b"},
             "top_bar":{"t":"row","children":[
               {"t":"tooltip","text":"Back","children":[
                 {"t":"icon_button","icon":"arrow_back",
                  "on_tap":{"builtin":"view.switch","view":"hub"}}]},
               {"style":"title","t":"text","text":"Files","weight":1}]}}""")
        assertEquals(viewSwitch("hub"), chromeBackDescriptor(view))
    }

    @Test
    fun aDisabledArrowKeepsTheSystemDefault() {
        // The gesture must not out-tap the button it mirrors: a spec-disabled
        // arrow is untappable on screen, so back is the system default.
        val view = spec("""
            {"t":"scaffold","body":{"t":"text","text":"b"},
             "top_bar":{"t":"row","children":[
               {"t":"icon_button","icon":"arrow_back","enabled":false,
                "on_tap":{"builtin":"view.switch","view":"hub"}}]}}""")
        assertNull(chromeBackDescriptor(view))
    }

    @Test
    fun theSpineIsBoundedAndTotal() {
        // Four nested containers: deeper than any authored bar, so the walk
        // refuses rather than wandering into content. And the two degenerate
        // container shapes — no children at all, a non-object first child —
        // exit null instead of throwing.
        val deep = spec("""
            {"t":"scaffold","body":{"t":"text","text":"b"},
             "top_bar":{"t":"box","children":[
               {"t":"box","children":[
                 {"t":"box","children":[
                   {"t":"row","children":[
                     {"t":"icon_button","icon":"arrow_back",
                      "on_tap":{"builtin":"view.switch","view":"hub"}}]}]}]}]}}""")
        assertNull(chromeBackDescriptor(deep))
        val childless = spec("""
            {"t":"scaffold","body":{"t":"text","text":"b"},
             "top_bar":{"t":"row"}}""")
        assertNull(chromeBackDescriptor(childless))
        val scalarChild = spec("""
            {"t":"scaffold","body":{"t":"text","text":"b"},
             "top_bar":{"t":"row","children":["not a node"]}}""")
        assertNull(chromeBackDescriptor(scalarChild))
    }

    @Test
    fun aViewSwitchNamingNoViewIsRefused() {
        // CompanionEngine.executeBuiltin returns early without a `view`, so
        // enabling the handler here would swallow back and do NOTHING — worse
        // than the system default it displaced.
        val view = spec("""
            {"t":"scaffold","body":{"t":"text","text":"b"},
             "top_bar":{"t":"row","children":[
               {"t":"icon_button","icon":"arrow_back",
                "on_tap":{"builtin":"view.switch"}}]}}""")
        assertNull(chromeBackDescriptor(view))
    }
}
