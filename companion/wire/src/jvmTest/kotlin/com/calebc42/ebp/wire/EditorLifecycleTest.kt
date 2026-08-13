// SPDX-License-Identifier: GPL-3.0-or-later
// W7 conformance: editor session lifecycle (SPEC 19) — sessions open from
// synchronized editor nodes in a pushed surface, preserve across refreshes,
// close on removal/document-change/tombstone, wait for READY when accepted
// during SYNCING, respect max_editor_sessions, and edit.complete round-trips.
package com.calebc42.ebp.wire

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EditorLifecycleTest {

    private fun engine(out: MutableList<JsonObject>, maxEditors: Long = 8,
                       toReady: Boolean = true): CompanionEngine {
        val engine = CompanionEngine(CompanionConfig(
            serverName = "kat", serverVersion = "1",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("editor.sync", "surfaces.dialog"),
            surfaceProfiles = buildJsonObject {
                putJsonObject("app") {
                    put("node_types", JsonArray(listOf("text", "column", "editor").map(::JsonPrimitive)))
                    put("builtins", JsonArray(emptyList()))
                    put("features", JsonArray(emptyList()))
                }
                putJsonObject("dialog") {
                    put("node_types", JsonArray(listOf("text", "column", "editor").map(::JsonPrimitive)))
                    put("builtins", JsonArray(emptyList()))
                    put("features", JsonArray(emptyList()))
                }
            },
            limits = testLimits("max_editor_sessions" to maxEditors,
                "max_editor_bytes" to 65_536),
            nonceSource = { katSn })) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes) { out.add(it) } }
        }
        engine.feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn,
                listOf("editor.sync", "surfaces.dialog")))))
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        if (toReady) engine.feed(frame(request("r1", "session.ready", JsonObject(emptyMap()))))
        return engine
    }

    private fun editorNode(id: String, document: String, value: String = "") =
        buildJsonObject {
            put("t", "editor"); put("id", id); put("document", document)
            put("publish_state", false)
            if (value.isNotEmpty()) put("value", value)
        }

    private fun push(engine: CompanionEngine, out: MutableList<JsonObject>,
                     surface: String, revision: Long, spec: JsonObject): JsonObject {
        val rid = "s$revision-${surface.hashCode()}"
        engine.feed(frame(request(rid, "surface.update", buildJsonObject {
            put("surface", surface); put("revision", revision); put("spec", spec)
        })))
        return out.replyTo(rid)
    }

    private fun List<JsonObject>.method(m: String) = filter { it.stringOrNull("method") == m }

    @Test
    fun editorNodeOpensAndSurviveRefreshThenCloses() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        // A surface with a synchronized editor opens one session (edit.open).
        push(engine, out, "app:main", 1, editorNode("body", "doc:1", "hello"))
        val open = out.method("edit.open").single().reqObj("params")
        assertEquals("hello", open.reqString("text"))
        assertEquals("doc:1", open.reqString("document"))
        val session = open.reqString("session")
        // A refresh with the same document+editor_id preserves the session
        // (no second edit.open, no edit.close).
        push(engine, out, "app:main", 2, editorNode("body", "doc:1", "ignored seed"))
        assertEquals(1, out.method("edit.open").size)
        assertEquals(0, out.method("edit.close").size)
        // Removing the editor node from the surface closes it.
        push(engine, out, "app:main", 3,
            buildJsonObject { put("t", "text"); put("text", "gone") })
        val close = out.method("edit.close").single().reqObj("params")
        assertEquals(session, close.reqString("session"))
    }

    @Test
    fun documentChangeReopens() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        push(engine, out, "app:main", 1, editorNode("body", "doc:1", "a"))
        val first = out.method("edit.open").single().reqObj("params").reqString("session")
        // Same editor_id, different document: close the old, open the new.
        push(engine, out, "app:main", 2, editorNode("body", "doc:2", "b"))
        assertEquals(1, out.method("edit.close").size)
        assertEquals(2, out.method("edit.open").size)
        val second = out.method("edit.open").last().reqObj("params")
        assertEquals("doc:2", second.reqString("document"))
        assertTrue(second.reqString("session") != first)
    }

    @Test
    fun acceptedDuringSyncingOpensOnReady() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out, toReady = false) // SYNCING
        // The editor node is accepted, but no edit.open yet (not READY).
        engine.feed(frame(request("q0", "queue.replay", JsonObject(emptyMap()))))
        push(engine, out, "app:main", 1, editorNode("body", "doc:1", "seed"))
        assertEquals(0, out.method("edit.open").size)
        // session.ready opens it.
        engine.feed(frame(request("r1", "session.ready", JsonObject(emptyMap()))))
        assertEquals("seed", out.method("edit.open").single()
            .reqObj("params").reqString("text"))
    }

    @Test
    fun maxEditorSessionsRejectsBeforeApplying() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out, maxEditors = 1)
        push(engine, out, "app:a", 1, editorNode("body", "doc:1"))
        // A second surface with another editor exceeds the limit: rejected.
        val r = push(engine, out, "app:b", 1, editorNode("body2", "doc:2"))
        assertEquals("editor-session-limit", r.reqObj("error")
            .reqObj("data").reqString("reason"))
        // The first surface's editor is untouched; a same-surface refresh at
        // the limit (still one editor) stays legal.
        assertEquals("applied", push(engine, out, "app:a", 2,
            editorNode("body", "doc:1")).reqObj("result").reqString("status"))
    }

    @Test
    fun completionRoundTripReplacesPrefix() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        val s = engine.openEditor("doc:1", "body", "pri", cursor = ScalarPos(3))
        var got: Pair<String, JsonArray>? = null
        engine.requestCompletion("doc:1", "body") { prefix, cands, _, _, _ ->
            got = prefix to cands }
        // The Companion sent edit.complete as a request; answer it.
        val req = out.method("edit.complete").single()
        engine.feed(frame(buildJsonObject {
            put("jsonrpc", "2.0")
            put("id", req["id"]!!)
            put("result", buildJsonObject {
                put("prefix", "pri")
                put("candidates", buildJsonArray {
                    addJsonObject { put("label", "print"); put("insert", "print()") }
                })
            })
        }))
        assertEquals("pri", got!!.first)
        // Selecting the candidate replaces the prefix with insert as one
        // edit whose delta carries the #170 provenance marker (THE FUNNEL:
        // only this path can stamp).
        assertTrue(engine.selectCompletion("doc:1", "body", "print", "print()",
            CompletionNarrowing.STRICT))
        assertEquals("print()", s.shadow)
        assertEquals(1, s.seq) // one advancing edit.delta
        val accepts = out.method("edit.delta")
        assertEquals(1, accepts.size)
        assertEquals(true,
            (accepts[0]["params"] as JsonObject)["accept"]
                ?.let { it == JsonPrimitive(true) })
        // The accept consumed the offer: a second tap has nothing to
        // validate against and is discarded without changing text.
        assertFalse(engine.selectCompletion("doc:1", "body", "print",
            "print()", CompletionNarrowing.STRICT))
        // And a TYPED delta never carries the member - the other funnel pin.
        assertTrue(engine.localEditorEdit("doc:1", "body", ScalarPos(7), 0, "x"))
        val typed = out.method("edit.delta")[1]
        assertFalse("accept" in (typed["params"] as JsonObject))
    }

    @Test
    fun offerSurvivesTypingAndReprovesAtEmission() {
        // Amendment #171 end to end: qualifying extensions keep the offer
        // alive and narrow it; the tap replaces the EXTENDED region with
        // accept:true; the emission-time re-proof discards a tap whose
        // candidate the extension no longer matches (the stale-row race);
        // any foreign advance kills the offer outright.
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        val s = engine.openEditor("doc:1", "body", "pri", cursor = ScalarPos(3))
        engine.requestCompletion("doc:1", "body") { _, _, _, _, _ -> }
        val req = out.method("edit.complete").single()
        engine.feed(frame(buildJsonObject {
            put("jsonrpc", "2.0")
            put("id", req["id"]!!)
            put("result", buildJsonObject {
                put("prefix", "pri")
                put("candidates", buildJsonArray {
                    addJsonObject { put("label", "printing") }
                    addJsonObject { put("label", "primes") }
                })
            })
        }))
        // The user types "n": del 0 at the region's end - qualifying.
        assertTrue(engine.localEditorEdit("doc:1", "body", ScalarPos(3), 0, "n"))
        // Strict re-proof: "primes" no longer matches "prin" - discarded.
        assertFalse(engine.selectCompletion("doc:1", "body", "primes",
            "primes", CompletionNarrowing.STRICT))
        // The failed re-proof cleared the offer (SPEC: MUST discard) - a
        // fresh reply re-arms for the surviving candidate's tap.
        engine.requestCompletion("doc:1", "body") { _, _, _, _, _ -> }
        val req2 = out.method("edit.complete")[1]
        engine.feed(frame(buildJsonObject {
            put("jsonrpc", "2.0")
            put("id", req2["id"]!!)
            put("result", buildJsonObject {
                put("prefix", "prin")
                put("candidates", buildJsonArray {
                    addJsonObject { put("label", "printing") }
                })
            })
        }))
        // Another qualifying extension, then the tap against "print-".
        assertTrue(engine.localEditorEdit("doc:1", "body", ScalarPos(4), 0, "t"))
        assertTrue(engine.selectCompletion("doc:1", "body", "printing",
            "printing", CompletionNarrowing.STRICT))
        // The accept replaced the EXTENDED region: prefix "prin" + ext "t".
        assertEquals("printing", s.shadow)
        val accept = out.method("edit.delta").last()
        val p = accept["params"] as JsonObject
        assertEquals(JsonPrimitive(0), p["start"])
        assertEquals(JsonPrimitive(5), p["del"])
        assertEquals(JsonPrimitive(true), p["accept"])
    }

    @Test
    fun foreignAdvanceAndNonQualifyingEditsKillTheOffer() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        val s = engine.openEditor("doc:1", "body", "pri", cursor = ScalarPos(3))
        fun arm(prefix: String) {
            engine.requestCompletion("doc:1", "body") { _, _, _, _, _ -> }
            val rq = out.method("edit.complete").last()
            engine.feed(frame(buildJsonObject {
                put("jsonrpc", "2.0")
                put("id", rq["id"]!!)
                put("result", buildJsonObject {
                    put("prefix", prefix)
                    put("candidates", buildJsonArray {
                        addJsonObject { put("label", "printing") }
                    })
                })
            }))
        }
        // A deletion is never qualifying.
        arm("pri")
        assertTrue(engine.localEditorEdit("doc:1", "body", ScalarPos(2), 1, ""))
        assertFalse(engine.selectCompletion("doc:1", "body", "printing",
            "printing", CompletionNarrowing.STRICT))
        assertTrue(engine.localEditorEdit("doc:1", "body", ScalarPos(2), 0, "i"))
        // An insertion NOT at the region's end is never qualifying.
        arm("pri")
        assertTrue(engine.localEditorEdit("doc:1", "body", ScalarPos(0), 0, "x"))
        assertFalse(engine.selectCompletion("doc:1", "body", "printing",
            "printing", CompletionNarrowing.STRICT))
        // A remote apply is a foreign advance.
        arm("xpri".let { _ -> "pri" })
        engine.feed(frame(buildJsonObject {
            put("jsonrpc", "2.0")
            put("id", JsonPrimitive("ap1"))
            put("method", "edit.apply")
            put("params", buildJsonObject {
                put("document", "doc:1"); put("editor_id", "body")
                put("session", s.sessionId); put("seq", s.seq + 1)
                put("start", 0); put("del", 0); put("text", "z")
                put("len", s.shadow.codePointCount(0, s.shadow.length) + 1)
                put("cursor", 1)
            })
        }))
        assertFalse(engine.selectCompletion("doc:1", "body", "printing",
            "printing", CompletionNarrowing.STRICT))
        // CONTAINS accepts what STRICT refused: re-arm, extend past the
        // prefix with a substring-only match.
        engine.feed(frame(buildJsonObject {
            put("jsonrpc", "2.0")
            put("id", JsonPrimitive("rs1"))
            put("method", "edit.resync")
            put("params", buildJsonObject {
                put("document", "doc:1"); put("editor_id", "body")
                put("session", s.sessionId)
            })
        }))
        val s2 = engine.withEditor("doc:1", "body") { it }!!
        engine.localEditorEdit("doc:1", "body", ScalarPos(0),
            s2.shadow.codePointCount(0, s2.shadow.length), "rin")
        engine.withEditor("doc:1", "body") { it.cursor = 3 }
        arm("rin")
        assertFalse(engine.selectCompletion("doc:1", "body", "printing",
            "printing", CompletionNarrowing.STRICT))
    }

    @Test
    fun candidateKindAcceptedUnknownValueSurvivesUnknownMemberRejects() {
        // Amendment #169: `kind` is a legal candidate member whose TYPE is
        // checked at the loop; an unrecognized VALUE is presentation (the
        // render map decorates or not), never a discard - while an unknown
        // MEMBER still discards the reply whole (the candidate stays a
        // closed object).
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        engine.openEditor("doc:1", "body", "pri", cursor = ScalarPos(3))
        var got: JsonArray? = null
        engine.requestCompletion("doc:1", "body") { _, cands, _, _, _ ->
            got = cands }
        val req = out.method("edit.complete").single()
        engine.feed(frame(buildJsonObject {
            put("jsonrpc", "2.0")
            put("id", req["id"]!!)
            put("result", buildJsonObject {
                put("prefix", "pri")
                put("candidates", buildJsonArray {
                    addJsonObject { put("label", "print"); put("kind", "function") }
                    addJsonObject {
                        put("label", "primes")
                        put("kind", "kind-from-the-future")
                    }
                })
            })
        }))
        assertEquals(2, got!!.size)
        // The closed object still rejects an unknown MEMBER whole.
        var got2: JsonArray? = null
        engine.requestCompletion("doc:1", "body") { _, cands, _, _, _ ->
            got2 = cands }
        val req2 = out.method("edit.complete")[1]
        engine.feed(frame(buildJsonObject {
            put("jsonrpc", "2.0")
            put("id", req2["id"]!!)
            put("result", buildJsonObject {
                put("prefix", "pri")
                put("candidates", buildJsonArray {
                    addJsonObject { put("label", "print"); put("detail", "x") }
                })
            })
        }))
        assertNull(got2)
    }

    // ------------------------------- audit §3: lifecycle conformance (P1 1-5)

    @Test
    fun anEditorInsideActionArgsOpensNothing() {
        // Audit §3.1: the scan walked EVERY JSON object in a spec, so an
        // editor-shaped object inside an action's free-form `args` (§14.1
        // leaves args opaque) opened a real session for a node that does not
        // exist — burning a max_editor_sessions slot for the connection, and
        // able to shadow a real editor's identity via member order.
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        val node = buildJsonObject {
            put("t", "text"); put("text", "go")
            putJsonObject("on_tap") {
                put("action", "demo.go")
                putJsonObject("args") {
                    put("t", "editor")
                    put("id", "ghost"); put("document", "doc:ghost")
                }
            }
        }
        push(engine, out, "app:main", 1, node)
        assertTrue(out.method("edit.open").isEmpty())
    }

    @Test
    fun aReconnectOverCachedSurfacesOpensSessions() {
        // Audit §3.2: sessions only ever opened from surface.update, so a
        // reconnect that receives none — legal, the cached snapshot is
        // unchanged and still rendered per §13.5 — opened NOTHING and left
        // every rendered editor permanently read-only with no diagnostic.
        val out = mutableListOf<JsonObject>()
        val store = SurfaceStore(16, 1024)
        fun connect(): CompanionEngine {
            val e = CompanionEngine(CompanionConfig(
                serverName = "kat", serverVersion = "1",
                pairings = mapOf(katPid to katToken),
                supportedCapabilities = setOf("editor.sync", "surfaces.dialog"),
                surfaceProfiles = buildJsonObject {
                    putJsonObject("app") {
                        put("node_types", JsonArray(listOf("text", "column", "editor").map(::JsonPrimitive)))
                        put("builtins", JsonArray(emptyList()))
                        put("features", JsonArray(emptyList()))
                    }
                },
                limits = testLimits("max_editor_sessions" to 8,
                    "max_editor_bytes" to 65_536),
                nonceSource = { katSn }), store) { bytes ->
                FrameDecoder().let { d -> d.feed(bytes) { out.add(it) } }
            }
            e.feed(frame(request("h1", "session.hello",
                EbpAuth.helloParams("t", "1", katPid, katCn,
                listOf("editor.sync", "surfaces.dialog")))))
            e.feed(frame(request("h2", "auth.response",
                EbpAuth.authParams(katPid, katCn, katSn, katToken))))
            return e
        }
        val first = connect()
        first.feed(frame(request("r1", "session.ready", JsonObject(emptyMap()))))
        push(first, out, "app:main", 1, editorNode("body", "doc:1", "hello"))
        assertEquals(1, out.method("edit.open").size)
        first.close("transport closed")
        // Second connection: no surface.update at all, just session.ready.
        out.clear()
        val second = connect()
        second.feed(frame(request("r1", "session.ready", JsonObject(emptyMap()))))
        val reopened = out.method("edit.open").single().reqObj("params")
        assertEquals("doc:1", reopened.reqString("document"))
        assertEquals("hello", reopened.reqString("text"))
        // ...and it is a live session, not a bare notification.
        assertTrue(second.localEditorEdit("doc:1", "body", ScalarPos(5), 0, "!"))
    }

    @Test
    fun aSecondSurfaceClaimingTheSameEditorIsRefused() {
        // Audit §3.3 (amendment #104): the second claim silently overwrote
        // the first surface's session with NO edit.close — Emacs then got
        // editor-stale for a session it was never told died, edit.resync
        // could not recover it, and removing either surface closed the
        // survivor.
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        push(engine, out, "app:a", 1, editorNode("body", "doc:1", "A"))
        val session = out.method("edit.open").single()
            .reqObj("params").reqString("session")
        val refused = push(engine, out, "app:b", 1, editorNode("body", "doc:1", "B"))
        assertEquals("editor-duplicate",
            refused.reqObj("error").reqObj("data").reqString("reason"))
        // The original session is untouched: still one open, none closed.
        assertEquals(1, out.method("edit.open").size)
        assertTrue(out.method("edit.close").isEmpty())
        assertEquals(session, out.method("edit.open").single()
            .reqObj("params").reqString("session"))
    }

    @Test
    fun anEditorRemovedDuringSyncingNeverOpens() {
        // Audit §3.4 (LD-6): pendingEditors was appended to but never pruned,
        // so an editor accepted during SYNCING and then removed still opened
        // on READY — a session no close path could reach, invisible to the
        // max_editor_sessions count.
        val out = mutableListOf<JsonObject>()
        val engine = engine(out, toReady = false)
        push(engine, out, "app:main", 1, editorNode("body", "doc:1", "seed"))
        assertTrue(out.method("edit.open").isEmpty()) // waits for READY
        engine.feed(frame(request("x1", "surface.remove", buildJsonObject {
            put("surface", "app:main"); put("revision", 2)
        })))
        engine.feed(frame(request("r1", "session.ready", JsonObject(emptyMap()))))
        assertTrue(out.method("edit.open").isEmpty())
    }

    @Test
    fun aDialogEditorIsCountedOpenedAndClosedWithTheDialog() {
        // Audit §3.8: §19 counts identities across "accepted surface OR
        // DIALOG documents", but handleDialogShow had no count, no limit
        // check, and never opened sessions — so a dialog's editor rendered
        // as synchronized and was never synchronized, and the limit could
        // never fire from a dialog at all.
        val out = mutableListOf<JsonObject>()
        val engine = engine(out, maxEditors = 1)
        engine.feed(frame(request("d1", "dialog.show", buildJsonObject {
            put("dialog_id", "dlg"); put("spec", editorNode("body", "doc:2", "hi"))
        })))
        // The dialog's editor got a real session.
        val open = out.method("edit.open").single().reqObj("params")
        assertEquals("doc:2", open.reqString("document"))
        // It counts: a surface editor now exceeds max_editor_sessions of 1.
        val refused = push(engine, out, "app:main", 1, editorNode("other", "doc:3"))
        assertEquals("editor-session-limit",
            refused.reqObj("error").reqObj("data").reqString("reason"))
        // Completing the dialog closes its session and frees the slot.
        engine.completeDialogDismiss("dlg")
        assertEquals(1, out.method("edit.close").size)
        val accepted = push(engine, out, "app:main", 2, editorNode("other", "doc:3"))
        assertEquals("applied", accepted.reqObj("result").reqString("status"))
    }

    @Test
    fun aSynchronizedEditorNeverBecomesADraft() {
        // Audit §3.7 / SPEC 13.6: "a local editor draft requires
        // publish_state: true and no document ... A synchronized editor never
        // participates in draft reconciliation." Registering it as stateful
        // let publishState write a DURABLE draft — the offline draft §19
        // forbids, reportable in the next welcome's input_state.
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        push(engine, out, "app:main", 1, editorNode("body", "doc:1", "seed")
            .with("publish_state", JsonPrimitive(true)))
        engine.publishState("app:main", "body", JsonPrimitive("typed offline"))
        assertFalse(engine.surfaces.hasDraft("app:main", "body"))
        // A LOCAL editor (publish_state, no document) still drafts normally.
        push(engine, out, "app:local", 1, buildJsonObject {
            put("t", "editor")
            put("id", "note"); put("publish_state", true)
        })
        engine.publishState("app:local", "note", JsonPrimitive("kept"))
        assertTrue(engine.surfaces.hasDraft("app:local", "note"))
    }

    @Test
    fun aPresentationKeyChangeClosesAndReopens() {
        // Audit §3.5: §16.1 makes `key` the presentation identity when
        // present and §19 closes the session when identity changes, but the
        // scan keyed on `id` alone — so a key change neither closed the old
        // session nor opened a new one, leaving a live shadow on text the
        // renderer had already replaced.
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        push(engine, out, "app:main", 1,
            editorNode("body", "doc:1", "A").with("key", JsonPrimitive("k1")))
        assertEquals(1, out.method("edit.open").size)
        push(engine, out, "app:main", 2,
            editorNode("body", "doc:1", "B").with("key", JsonPrimitive("k2")))
        assertEquals(1, out.method("edit.close").size)
        assertEquals(2, out.method("edit.open").size)
        assertEquals("B", out.method("edit.open").last()
            .reqObj("params").reqString("text"))
    }
}
