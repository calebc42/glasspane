package com.calebc42.jetpacs.core.navigation

import androidx.navigation3.runtime.NavKey
import kotlinx.serialization.Serializable

@Serializable
sealed interface JetpacsNavKey : NavKey {
    @Serializable
    data object Pairing : JetpacsNavKey

    @Serializable
    data class Catalog(
        val pairingId: String,
        val surfaceId: String,
    ) : JetpacsNavKey

    @Serializable
    data object Settings : JetpacsNavKey
}
