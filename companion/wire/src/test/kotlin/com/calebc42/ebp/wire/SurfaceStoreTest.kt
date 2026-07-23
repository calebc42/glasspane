// SPDX-License-Identifier: GPL-3.0-or-later
// W4 conformance: revisioned surfaces (SPEC 13.2-13.3), the update/remove/
// update race (SPEC 24.6 item 7), surface limits (13.1), validation
// taxonomy (16-17), and the 13.6 draft-reconciliation matrix.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File

class SurfaceStoreTest {

    private fun store(maxSurfaces: Long = 16, maxIds: Long = 1024) =
        SurfaceStore(maxSurfaces, maxIds)

    private fun textSpec(text: String = "hi"): JSONObject =
        JSONObject().put("t", "column").put("children", JSONArray()
            .put(JSONObject().put("t", "text").put("text", text)))

    private fun inputSpec(value: String = "draft", singleLine: Boolean = false): JSONObject =
        JSONObject().put("t", "column").put("children", JSONArray()
            .put(JSONObject().put("t", "text_input").put("id", "title")
                .put("value", value)
                .also { if (singleLine) it.put("single_line", true)
                    .put("min_lines", 1).put("max_lines", 1) }))

    private fun update(s: SurfaceStore, surface: String, rev: Long,
                       spec: JSONObject = textSpec(),
                       resetIds: JSONArray? = null): SurfaceResult =
        s.update(surface, rev, spec, null, null, resetIds)

    // ----------------------------------------------- idempotency (13.2-3)

    @Test
    fun appliedAndStaleIdempotency() {
        val s = store()
        assertEquals(SurfaceResult("applied", 42, true), update(s, "app:main", 42))
        // Equal and older revisions are benign stale results, state unchanged.
        assertEquals(SurfaceResult("stale", 42, true), update(s, "app:main", 42))
        assertEquals(SurfaceResult("stale", 42, true), update(s, "app:main", 7))
        assertEquals(SurfaceResult("applied", 43, true), update(s, "app:main", 43))
    }

    @Test
    fun updateRemoveUpdateRace() {
        // SPEC 24.6 item 7: a delayed older update never resurrects a
        // removed surface; a genuinely newer one legitimately does.
        val s = store()
        update(s, "app:main", 10)
        assertEquals(SurfaceResult("applied", 20, false), s.remove("app:main", 20))
        // The delayed rev-15 update lost the race: tombstone floor holds.
        assertEquals(SurfaceResult("stale", 20, false), update(s, "app:main", 15))
        // The welcome reports the tombstone, not absence.
        val snap = s.snapshot().getJSONObject("app:main")
        assertEquals(20, snap.getLong("revision"))
        assertFalse(snap.getBoolean("present"))
        // A newer update reactivates past the tombstone.
        assertEquals(SurfaceResult("applied", 30, true), update(s, "app:main", 30))
        // And a stale remove after that is refused.
        assertEquals(SurfaceResult("stale", 30, true), s.remove("app:main", 25))
    }

    @Test
    fun removeOfNeverSeenSurfaceTombstones() {
        val s = store()
        // Conceptual floor -1: any non-negative revision is newer.
        assertEquals(SurfaceResult("applied", 0, false), s.remove("app:gone", 0))
        assertEquals(SurfaceResult("stale", 0, false), update(s, "app:gone", 0))
    }

    // ------------------------------------------------------- limits (13.1)

    @Test
    fun surfaceLimitsGateGrowthNotUpdates() {
        val s = store(maxSurfaces = 2, maxIds = 3)
        update(s, "app:a", 1)
        update(s, "app:b", 1)
        // Third present surface: refused.
        try { update(s, "app:c", 1); fail("max_surfaces ignored") }
        catch (e: ContentInvalid) { assertEquals("surface-limit", e.reason) }
        // Updating a present surface at the limit stays legal.
        assertEquals("applied", update(s, "app:a", 2).status)
        // Tombstoning frees a present slot but keeps the history slot.
        s.remove("app:b", 5)
        assertEquals("applied", update(s, "app:c", 1).status)
        // max_surface_ids: a fourth distinct history is refused.
        try { update(s, "app:d", 1); fail("max_surface_ids ignored") }
        catch (e: ContentInvalid) { assertEquals("surface-limit", e.reason) }
        // Reactivating the tombstone at max_surfaces is invalid too.
        try { update(s, "app:b", 6); fail("tombstone reactivation at limit") }
        catch (e: ContentInvalid) { assertEquals("surface-limit", e.reason) }
    }

    // -------------------------------------------------- validation (16-17)

    @Test
    fun validationTaxonomy() {
        val s = store()
        fun rejects(spec: JSONObject, fragment: String) {
            try { update(s, "app:v", 99, spec); fail("accepted: $fragment") }
            catch (e: ContentInvalid) {
                assertTrue("${e.reason} !~ $fragment", e.reason.contains(fragment)
                    || e.path.contains(fragment))
            }
        }
        // Missing required member.
        rejects(JSONObject().put("t", "text"), "missing required text")
        // Duplicate authored IDs (16.1).
        rejects(JSONObject().put("t", "row").put("children", JSONArray()
            .put(JSONObject().put("t", "checkbox").put("id", "x"))
            .put(JSONObject().put("t", "switch").put("id", "x"))), "duplicate")
        // Invalid action: both discriminators (14.2).
        rejects(JSONObject().put("t", "button").put("label", "b")
            .put("on_tap", JSONObject().put("action", "a.b").put("builtin", "view.switch")),
            "exactly one")
        // Unknown builtin rejects the document (14.2).
        rejects(JSONObject().put("t", "button").put("label", "b")
            .put("on_tap", JSONObject().put("builtin", "no.such")), "unknown builtin")
        // queue without ttl_s (14.1).
        rejects(JSONObject().put("t", "button").put("label", "b")
            .put("on_tap", JSONObject().put("action", "a.b").put("when_offline", "queue")),
            "requires ttl_s")
        // Authored single_line value with U+000A (17.4, P1 #3).
        rejects(inputSpec("two\nlines", singleLine = true), "U+000A")
        // Password seeding (17.4).
        rejects(JSONObject().put("t", "text_input").put("id", "pw")
            .put("password", true).put("value", "secret"), "password")
        // But unknown node types and unknown fields are tolerated (16.2-16.3).
        assertEquals("applied", update(s, "app:v", 100, JSONObject()
            .put("t", "hologram").put("children", JSONArray())
            .put("mystery_field", 7)).status)
        assertEquals("applied", update(s, "app:v", 101, JSONObject()
            .put("t", "text").put("text", "hi").put("future_field", true)).status)
    }

    @Test
    fun multiViewRules() {
        val s = store()
        val spec = JSONObject()
            .put("views", JSONObject()
                .put("list", textSpec("l")).put("detail", textSpec("d")))
            .put("initial_view", "list")
        assertEquals("applied", s.update("app:m", 1, spec, null, null, null).status)
        // current_view naming a missing view is invalid (13.4).
        try {
            s.update("app:m", 2, spec, null, "nope", null)
            fail("bad current_view accepted")
        } catch (e: ContentInvalid) { assertTrue(e.path.contains("current_view")) }
        // stale_spec must not carry stateful nodes (13.5).
        try {
            s.update("app:m", 3, textSpec(), inputSpec(), null, null)
            fail("stateful stale_spec accepted")
        } catch (e: ContentInvalid) { assertTrue(e.path.contains("stale_spec")) }
    }

    // ------------------------------------------------------ drafts (13.6)

    @Test
    fun draftReconciliationMatrix() {
        val s = store()
        update(s, "app:d", 1, inputSpec("authored"))
        s.putDraft("app:d", "title", "user typed")
        // A refresh with the same authored value preserves the dirty draft.
        update(s, "app:d", 2, inputSpec("authored"))
        assertEquals("user typed", s.draft("app:d", "title"))
        // A snapshot acknowledging the draft's exact value clears it.
        update(s, "app:d", 3, inputSpec("user typed"))
        assertFalse(s.hasDraft("app:d", "title"))
        // Type change erases: same ID as a checkbox.
        s.putDraft("app:d", "title", "again")
        update(s, "app:d", 4, JSONObject().put("t", "checkbox").put("id", "title"))
        assertFalse(s.hasDraft("app:d", "title"))
        // reset_input_ids discards explicitly (13.2).
        update(s, "app:d", 5, inputSpec("authored"))
        s.putDraft("app:d", "title", "rejected draft")
        update(s, "app:d", 6, inputSpec("authored"),
            resetIds = JSONArray().put("title"))
        assertFalse(s.hasDraft("app:d", "title"))
        // A now-illegal single_line draft with U+000A is incompatible.
        update(s, "app:d", 7, inputSpec("authored"))
        s.putDraft("app:d", "title", "multi\nline")
        update(s, "app:d", 8, inputSpec("authored", singleLine = true))
        assertFalse(s.hasDraft("app:d", "title"))
        // Tombstoning erases every draft for the surface (13.3).
        update(s, "app:d", 9, inputSpec("authored"))
        s.putDraft("app:d", "title", "doomed")
        s.remove("app:d", 10)
        assertFalse(s.hasDraft("app:d", "title"))
    }

    @Test
    fun enumAndSliderCompatibility() {
        val s = store()
        val enumSpec = JSONObject().put("t", "enum_list").put("id", "state")
            .put("options", JSONArray()
                .put(JSONObject().put("label", "Todo").put("value", "TODO"))
                .put(JSONObject().put("label", "Done").put("value", "DONE")))
        update(s, "app:e", 1, enumSpec)
        s.putDraft("app:e", "state", "DONE")
        // Retained value still legal under the new options: survives.
        update(s, "app:e", 2, enumSpec)
        assertEquals("DONE", s.draft("app:e", "state"))
        // Option vanishes: draft is incompatible and erased.
        val shrunk = JSONObject().put("t", "enum_list").put("id", "state")
            .put("options", JSONArray()
                .put(JSONObject().put("label", "Todo").put("value", "TODO")))
        update(s, "app:e", 3, shrunk)
        assertFalse(s.hasDraft("app:e", "state"))
        // Slider: retained number outside the new range is erased.
        val slider = JSONObject().put("t", "slider").put("id", "vol")
            .put("on_change", JSONObject().put("action", "vol.set"))
            .put("min", 0).put("max", 10).put("value", 5)
        update(s, "app:s", 1, slider)
        s.putDraft("app:s", "vol", 9)
        update(s, "app:s", 2, JSONObject().put("t", "slider").put("id", "vol")
            .put("on_change", JSONObject().put("action", "vol.set"))
            .put("min", 0).put("max", 5).put("value", 2))
        assertFalse(s.hasDraft("app:s", "vol"))
    }

    @Test
    fun passwordDraftsAreNeverRetained() {
        val s = store()
        update(s, "app:p", 1, JSONObject().put("t", "text_input").put("id", "pw")
            .put("password", true))
        s.putDraft("app:p", "pw", "secret")
        assertFalse(s.hasDraft("app:p", "pw"))
        assertNull(s.inputState().optJSONObject("app:p"))
    }

    @Test
    fun welcomeInputStateCoversPresentSurfacesOnly() {
        val s = store()
        update(s, "app:a", 1, inputSpec("authored"))
        s.putDraft("app:a", "title", "kept")
        val state = s.inputState()
        assertEquals("kept", state.getJSONObject("app:a").getString("title"))
        s.remove("app:a", 2)
        assertEquals(0, s.inputState().length())
    }

    // ------------------------------------------ completeness pass (16-17)

    /** A spec whose update MUST be refused with a recoverable 1201. */
    private fun rejects(s: SurfaceStore, spec: JSONObject, fragment: String) {
        try { s.update("app:x", 1, spec, null, null, null); fail("accepted: $fragment") }
        catch (e: ContentInvalid) {
            assertTrue("${e.reason} @ ${e.path} !~ $fragment",
                e.reason.contains(fragment) || e.path.contains(fragment))
        }
    }

    private fun button(action: JSONObject): JSONObject =
        JSONObject().put("t", "button").put("label", "b").put("on_tap", action)

    @Test
    fun malformedNodeRejectsInsteadOfCrashing() {
        // SPEC 16.1: a wrong-typed required member is a recoverable 1201,
        // never a thrown getter that tears the session down (audit P1 #3).
        val s = store()
        rejects(s, JSONObject().put("t", "enum_list").put("id", "e")
            .put("options", "not-an-array"), "options must be an array")
        // SPEC 17.1: an on_* member must be an ActionDescriptor object.
        rejects(s, JSONObject().put("t", "button").put("label", "b")
            .put("on_tap", "nope"), "action descriptor must be an object")
        // SPEC 16.1: a single-view root must itself be a node.
        rejects(s, JSONObject().put("foo", 1), "surface root must be a node")
        // SPEC 17.1: children are Nodes — a scalar or a t-less object rejects.
        rejects(s, JSONObject().put("t", "column")
            .put("children", JSONArray().put("scalar")), "child must be a node object")
        rejects(s, JSONObject().put("t", "column")
            .put("children", JSONArray().put(JSONObject().put("no", "t"))),
            "child node missing discriminator t")
        // SPEC 16.1: each view of a multi-view spec is a node.
        rejects(s, JSONObject()
            .put("views", JSONObject().put("v", JSONObject().put("no", "t")))
            .put("initial_view", "v"), "each view must be a node")
    }

    @Test
    fun resourceLimitsEnforced() {
        val s = store()
        // SPEC 4.5: at most 10,000 children of one node.
        val manyChildren = JSONArray()
        repeat(10_001) { manyChildren.put(JSONObject().put("t", "spacer")) }
        rejects(s, JSONObject().put("t", "column").put("children", manyChildren),
            "max_children_per_node")
        // SPEC 4.5: at most 10,000 nodes in one snapshot — nested so that no
        // single node trips the children limit first.
        val outer = JSONArray()
        repeat(101) {
            val inner = JSONArray()
            repeat(100) { inner.put(JSONObject().put("t", "spacer")) }
            outer.put(JSONObject().put("t", "column").put("children", inner))
        }
        rejects(s, JSONObject().put("t", "column").put("children", outer),
            "max_nodes_per_snapshot")
    }

    @Test
    fun captureFieldsRules() {
        val s = store()
        // SPEC 14.1: each name resolves to exactly one stateful node.
        rejects(s, button(JSONObject().put("action", "a.b")
            .put("capture_fields", JSONArray().put("ghost"))),
            "must name a stateful node in the document")
        // A named non-stateful node (a `text` with an id) does not resolve.
        rejects(s, JSONObject().put("t", "column").put("children", JSONArray()
            .put(JSONObject().put("t", "text").put("id", "note").put("text", "x"))
            .put(button(JSONObject().put("action", "a.b")
                .put("capture_fields", JSONArray().put("note"))))),
            "must name a stateful node in the document")
        // Distinct IDs only.
        rejects(s, button(JSONObject().put("action", "a.b")
            .put("capture_fields", JSONArray().put("title").put("title"))),
            "duplicate capture field")
        // An array of IDs — not a bare value.
        rejects(s, button(JSONObject().put("action", "a.b")
            .put("capture_fields", "title")), "must be an array")
        // SPEC 4.5: length must not exceed max_capture_fields (default 64).
        val over = JSONArray().also { repeat(65) { i -> it.put("f$i") } }
        rejects(s, button(JSONObject().put("action", "a.b")
            .put("capture_fields", over)), "exceeds max_capture_fields")
        // A resolving capture is accepted.
        val ok = JSONObject().put("t", "column").put("children", JSONArray()
            .put(JSONObject().put("t", "text_input").put("id", "title"))
            .put(button(JSONObject().put("action", "save.it")
                .put("capture_fields", JSONArray().put("title")))))
        assertEquals("applied", s.update("app:ok", 1, ok, null, null, null).status)
    }

    @Test
    fun ttlAndConfirmValidation() {
        val s = store()
        // SPEC 14.1: ttl_s is an integer 1..604800.
        rejects(s, button(JSONObject().put("action", "a.b")
            .put("when_offline", "queue").put("ttl_s", 0)), "1..604800")
        rejects(s, button(JSONObject().put("action", "a.b")
            .put("when_offline", "queue").put("ttl_s", 604801)), "1..604800")
        rejects(s, button(JSONObject().put("action", "a.b")
            .put("when_offline", "queue").put("ttl_s", "86400")), "1..604800")
        rejects(s, button(JSONObject().put("action", "a.b")
            .put("when_offline", "queue").put("ttl_s", 86400.5)), "1..604800")
        // SPEC 14.1: confirm is a non-empty string.
        rejects(s, button(JSONObject().put("action", "a.b").put("confirm", "")),
            "non-empty string")
        rejects(s, button(JSONObject().put("action", "a.b").put("confirm", 5)),
            "non-empty string")
        // Valid queue descriptor with confirm is accepted.
        assertEquals("applied", s.update("app:ok", 1,
            button(JSONObject().put("action", "a.b").put("when_offline", "queue")
                .put("ttl_s", 86400).put("confirm", "Sure?")),
            null, null, null).status)
    }

    @Test
    fun nodeTypeChangeErasesCompatibleDraft() {
        val s = store()
        // checkbox -> switch: identical boolean value schema, different type.
        update(s, "app:t", 1, JSONObject().put("t", "checkbox").put("id", "flag")
            .put("checked", false))
        s.putDraft("app:t", "flag", true)
        assertTrue(s.hasDraft("app:t", "flag"))
        update(s, "app:t", 2, JSONObject().put("t", "switch").put("id", "flag")
            .put("checked", false))
        assertFalse(s.hasDraft("app:t", "flag")) // SPEC 13.6/16.1: new identity
        // text_input -> local editor: both hold a string, still a type change.
        update(s, "app:e", 1, JSONObject().put("t", "text_input").put("id", "note")
            .put("value", "x"))
        s.putDraft("app:e", "note", "typed")
        update(s, "app:e", 2, JSONObject().put("t", "editor").put("id", "note")
            .put("publish_state", true).put("value", "x"))
        assertFalse(s.hasDraft("app:e", "note"))
        // Control: a same-type refresh keeps a compatible unacknowledged draft.
        update(s, "app:c", 1, JSONObject().put("t", "switch").put("id", "flag")
            .put("checked", false))
        s.putDraft("app:c", "flag", true)
        update(s, "app:c", 2, JSONObject().put("t", "switch").put("id", "flag")
            .put("checked", false))
        assertTrue(s.hasDraft("app:c", "flag"))
    }

    @Test
    fun durableStoreSurvivesProcessDeath() {
        // SPEC 13.1/15.1: surface histories, tombstones, and the input_state
        // draft outlive process death — a fresh store on the same file.
        val file = File.createTempFile("ebp-surfaces", ".json").also { it.deleteOnExit() }
        val s1 = SurfaceStore(16, 1024, backing = FileSurfaceBacking(file))
        s1.update("app:main", 5, inputSpec("authored"), null, null, null)
        s1.putDraft("app:main", "title", "offline edit")
        s1.remove("app:gone", 3)
        // A wholly new store reads the same file (the process died).
        val s2 = SurfaceStore(16, 1024, backing = FileSurfaceBacking(file))
        // The dirty draft survived and is reported for the present surface.
        assertEquals("offline edit",
            s2.inputState().getJSONObject("app:main").getString("title"))
        assertEquals("offline edit", s2.currentValue("app:main", "title"))
        // The revision floor survived — a stale update is refused.
        assertEquals("stale", s2.update("app:main", 5, inputSpec("authored"),
            null, null, null).status)
        // The tombstone survived, reported not-present (SPEC 13.1).
        val snap = s2.snapshot().getJSONObject("app:gone")
        assertEquals(3L, snap.getLong("revision"))
        assertFalse(snap.getBoolean("present"))
    }

    @Test
    fun injectedMemberConflictRejects() {
        // SPEC 14.3: a remote descriptor on a value-producing hook must not
        // author the injected member; on hooks that inject nothing it may.
        val s = store()
        rejects(s, JSONObject().put("t", "text_input").put("id", "t")
            .put("on_change", JSONObject().put("action", "x.y")
                .put("args", JSONObject().put("value", "preset"))),
            "conflicts with the value injected by on_change")
        // on_tap injects nothing — an authored args.value is fine.
        assertEquals("applied", s.update("app:ok", 1,
            button(JSONObject().put("action", "x.y")
                .put("args", JSONObject().put("value", 1))),
            null, null, null).status)
    }
}

class VocabularyDriftTest {
    private val ebpDir = File(System.getProperty("ebp.dir")
        ?: error("ebp.dir system property not set"))

    @Test
    fun generatedVocabularyMatchesContract() {
        val contract = JSONObject(ebpDir.resolve("contract.json").readText())
        assertEquals(contract.getInt("contract_format"), CONTRACT_FORMAT)
        assertEquals(contract.getString("spec_version"), SPEC_VERSION)
        val schema = contract.getJSONObject("node_schema")
        assertEquals(schema.keySet(), NODE_SCHEMA.keys)
        for (name in schema.keySet()) {
            val row = schema.getJSONObject(name)
            fun set(k: String) = row.getJSONArray(k).let { a ->
                (0 until a.length()).map { a.getString(it) }.toSet()
            }
            assertEquals("$name required", set("required"), NODE_SCHEMA.getValue(name).required)
            assertEquals("$name optional", set("optional"), NODE_SCHEMA.getValue(name).optional)
        }
        val universal = contract.getJSONArray("universal_node_attributes").let { a ->
            (0 until a.length()).map { a.getString(it) }.toSet()
        }
        assertEquals(universal, UNIVERSAL_NODE_ATTRIBUTES)
        val actions = contract.getJSONObject("actions").getJSONObject("schema")
        assertEquals(actions.keySet(), ACTION_SCHEMA.keys)
    }
}
