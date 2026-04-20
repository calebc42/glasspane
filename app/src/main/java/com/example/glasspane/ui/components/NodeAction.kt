package com.example.glasspane.ui.components

import com.example.glasspane.ui.viewmodels.OrgTask

/**
 * Sealed class representing all actions that can be performed on an Org node.
 * Replaces the 22+ individual callback lambdas that were threaded through TaskCard.
 *
 * Actions are grouped by concern:
 *   - Structure: tree manipulation (move, promote, demote, insert, refile, archive)
 *   - Metadata:  editing node properties (title, TODO, priority, tags, properties)
 *   - Planning:  scheduling, clocking, focus
 *   - Body:      editing the node's body text
 */
sealed class NodeAction {

    // ── Structure ────────────────────────────────────────────────────────────
    data class MoveUp(val nodeId: String) : NodeAction()
    data class MoveDown(val nodeId: String) : NodeAction()
    data class Promote(val nodeId: String) : NodeAction()
    data class Demote(val nodeId: String) : NodeAction()
    data class InsertChild(val nodeId: String) : NodeAction()
    data class InsertBelow(val nodeId: String) : NodeAction()   // "Add Sibling" in org terms
    data class Refile(val nodeId: String) : NodeAction()
    data class Focus(val task: OrgTask) : NodeAction()
    data class Delete(val nodeId: String) : NodeAction()

    // ── Metadata ─────────────────────────────────────────────────────────────
    data class EditTitle(val task: OrgTask) : NodeAction()
    data class CycleTodo(val nodeId: String, val currentState: String) : NodeAction()
    data class PickTodo(val task: OrgTask) : NodeAction()
    data class SetPriority(val task: OrgTask) : NodeAction()
    data class SetTags(val task: OrgTask) : NodeAction()
    data class AddProperty(val task: OrgTask) : NodeAction()

    // ── Planning ─────────────────────────────────────────────────────────────
    data class Schedule(val nodeId: String, val initialDate: String) : NodeAction()
    data class ClockIn(val nodeId: String) : NodeAction()

    // ── Body ─────────────────────────────────────────────────────────────────
    data class EditBodyFullScreen(val task: OrgTask) : NodeAction()
    data class InlineUpdateBody(val nodeId: String, val newBody: String) : NodeAction()
}
