// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC 18.2.1: the one pending event-driven snackbar. The engine's
// snackbarListener (DeviceBridge) posts here; whichever RenderScaffold is on
// screen consumes it, shows it in ITS host — the surface currently presented,
// which on a multi-view surface is the view being shown — and answers the
// pending request with how the snackbar concluded.
package com.calebc42.ebp.companion.render

import kotlinx.coroutines.flow.MutableStateFlow

object SnackbarRaises {
    data class Raise(
        val message: String,
        val actionLabel: String?,
        val duration: String?,
        val respond: (String) -> Unit,
    )

    val flow = MutableStateFlow<Raise?>(null)
}
