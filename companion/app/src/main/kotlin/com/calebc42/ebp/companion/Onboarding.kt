// SPDX-License-Identifier: GPL-3.0-or-later
package com.calebc42.ebp.companion

import android.content.ClipData
import android.content.ClipboardManager
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.os.Environment
import android.provider.MediaStore
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private const val ONBOARDING_PREFS = "jetpacs-onboarding"
private const val ONBOARDING_VERSION = "version"
private const val CURRENT_ONBOARDING_VERSION = 8
private const val ASSET_ROOT = "jetpacs-onboarding"
private const val KIT_DIRECTORY = "jetpacs-installer"
private const val KIT_PATH = "/sdcard/Documents/$KIT_DIRECTORY"

/** The user-requested manual early-init snippet, copied byte-for-byte. */
internal const val TERMUX_PATH_SNIPPET =
    "(setenv \"PATH\" (format \"%s:%s\" \"/data/data/com.termux/files/usr/bin\"\n" +
        "\t\t       (getenv \"PATH\")))\n" +
        "(push \"/data/data/com.termux/files/usr/bin\" exec-path)"

internal const val INIT_SEAM_SNIPPET =
    ";;; >>> Jetpacs managed: composition root >>>\n" +
        "(add-to-list 'load-path (expand-file-name \"jetpacs/emacs\" user-emacs-directory))\n" +
        "(require 'jetpacs)\n" +
        ";;; <<< Jetpacs managed: composition root <<<"

internal const val RECOMMENDED_INIT_SNIPPET =
    ";;; >>> Jetpacs managed: composition root >>>\n" +
        "(load \"/sdcard/Documents/jetpacs-installer/install-recommended.el\" t t t)\n" +
        "(add-to-list 'load-path (expand-file-name \"jetpacs/emacs\" user-emacs-directory))\n" +
        "(require 'jetpacs)\n" +
        ";;; <<< Jetpacs managed: composition root <<<"

internal const val PACKAGE_VC_INSTALL_SNIPPET =
    "(package-vc-install\n" +
        " '(jetpacs :url \"https://github.com/calebc42/jetpacs\"\n" +
        "            :lisp-dir \"emacs\"))"

internal const val TERMUX_EARLY_INIT_SNIPPET =
    ";;; >>> Jetpacs managed: Android Emacs HOME >>>\n" +
        "(setenv \"HOME\" \"/data/data/com.termux/files/home\")\n" +
        "(setq default-directory \"/data/data/com.termux/files/home/\")\n" +
        "(setq user-emacs-directory \"/data/data/com.termux/files/home/.emacs.d/\")\n" +
        "(setq abbreviated-home-dir nil)\n\n" +
        TERMUX_PATH_SNIPPET + "\n" +
        ";;; <<< Jetpacs managed: Android Emacs HOME <<<"

internal fun remoteInitSnippet(): String =
    "(setq jetpacs-pairing-id \"$JETPACS_PAIRING_ID\"\n" +
        "      jetpacs-pairing-token \"$JETPACS_PAIRING_TOKEN\")\n" +
        "(require 'jetpacs)"

internal enum class JetpacsVaultChoice {
    SDCARD,
    EMACS,
    TERMUX,
    REMOTE,
}

internal enum class JetpacsEmacsHomeChoice {
    LOCAL,
    TERMUX_SHARED,
    REMOTE,
}

internal enum class JetpacsSetupPath {
    RECOMMENDED,
    ADVANCED,
}

private enum class OnboardingStep {
    CHOOSE,
    HOME,
    VAULT,
    INSTALL,
    FINISH,
}

internal fun selectedVault(choice: JetpacsVaultChoice): String = when (choice) {
    JetpacsVaultChoice.SDCARD -> "/sdcard"
    JetpacsVaultChoice.EMACS -> "/data/data/org.gnu.emacs/files"
    JetpacsVaultChoice.TERMUX -> "/data/data/com.termux/files/home"
    JetpacsVaultChoice.REMOTE -> "~/"
}

internal fun allowedVaultChoices(
    homeChoice: JetpacsEmacsHomeChoice,
): List<JetpacsVaultChoice> = when (homeChoice) {
    JetpacsEmacsHomeChoice.LOCAL ->
        listOf(JetpacsVaultChoice.SDCARD, JetpacsVaultChoice.EMACS)
    JetpacsEmacsHomeChoice.TERMUX_SHARED ->
        listOf(
            JetpacsVaultChoice.SDCARD,
            JetpacsVaultChoice.EMACS,
            JetpacsVaultChoice.TERMUX,
        )
    JetpacsEmacsHomeChoice.REMOTE -> listOf(JetpacsVaultChoice.REMOTE)
}

internal fun selectedConfigHome(choice: JetpacsEmacsHomeChoice): String? = when (choice) {
    JetpacsEmacsHomeChoice.LOCAL -> "/data/data/org.gnu.emacs/files"
    JetpacsEmacsHomeChoice.TERMUX_SHARED -> "/data/data/com.termux/files/home"
    JetpacsEmacsHomeChoice.REMOTE -> null
}

internal fun termuxInstallCommand(
    vaultChoice: JetpacsVaultChoice,
    homeChoice: JetpacsEmacsHomeChoice,
): String? {
    val vaultMode = when (vaultChoice) {
        JetpacsVaultChoice.SDCARD -> "shared"
        JetpacsVaultChoice.EMACS -> "emacs"
        JetpacsVaultChoice.TERMUX -> "termux"
        JetpacsVaultChoice.REMOTE -> return null
    }
    val homeMode = when (homeChoice) {
        JetpacsEmacsHomeChoice.LOCAL -> "emacs"
        JetpacsEmacsHomeChoice.TERMUX_SHARED -> "termux"
        JetpacsEmacsHomeChoice.REMOTE -> return null
    }
    val kit = "~/storage/shared/Documents/$KIT_DIRECTORY"
    return "termux-setup-storage\n" +
        "bash $kit/install-jetpacs.sh install $vaultMode $homeMode $kit/payload && " +
        "rm -rf $kit"
}

internal fun isCurrentOnboardingComplete(context: Context): Boolean =
    context.getSharedPreferences(ONBOARDING_PREFS, Context.MODE_PRIVATE)
        .getInt(ONBOARDING_VERSION, 0) >= CURRENT_ONBOARDING_VERSION

internal fun markCurrentOnboardingComplete(context: Context) {
    context.getSharedPreferences(ONBOARDING_PREFS, Context.MODE_PRIVATE)
        .edit()
        .putInt(ONBOARDING_VERSION, CURRENT_ONBOARDING_VERSION)
        .apply()
}

private fun copyText(context: Context, label: String, text: String) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    clipboard.setPrimaryClip(ClipData.newPlainText(label, text))
}

/** Return every file below [path] in the generated AssetManager tree. */
private fun assetFiles(context: Context, path: String): List<String> {
    val children = context.assets.list(path).orEmpty()
    if (children.isEmpty()) return listOf(path)
    return children.flatMap { assetFiles(context, "$path/$it") }
}

/**
 * Stage the generated setup kit in shared Documents through MediaStore.
 *
 * The Companion has a different UID from Emacs and Termux and has no ambient
 * access to either private home. Documents is only transport: Recommended asks
 * the user to paste the copied package entry into Emacs, which then consumes
 * this payload into private storage. Advanced uses the Termux command.
 */
private fun stageSetupKit(context: Context): Int {
    val resolver = context.contentResolver
    val collection = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
    val kitRelativePath = "${Environment.DIRECTORY_DOCUMENTS}/$KIT_DIRECTORY/"
    var count = 0

    // This directory is explicitly a disposable transport cache. Clear every
    // file from the app's previous stage first, otherwise a module removed by
    // a newer APK could survive beside the fresh payload and be reinstalled.
    resolver.query(
        collection,
        arrayOf(MediaStore.MediaColumns._ID),
        "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ?",
        arrayOf("$kitRelativePath%"),
        null,
    )?.use { cursor ->
        val id = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
        while (cursor.moveToNext()) {
            resolver.delete(
                ContentUris.withAppendedId(collection, cursor.getLong(id)),
                null,
                null,
            )
        }
    }

    assetFiles(context, ASSET_ROOT).forEach { assetPath ->
        val relative = assetPath.removePrefix("$ASSET_ROOT/")
        val name = relative.substringAfterLast('/')
        val parent = relative.substringBeforeLast('/', missingDelimiterValue = "")
        val relativePath = buildString {
            append(Environment.DIRECTORY_DOCUMENTS)
            append('/')
            append(KIT_DIRECTORY)
            if (parent.isNotEmpty()) {
                append('/')
                append(parent)
            }
            append('/')
        }

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            // Text MIME types invite file managers to append .txt. The exact
            // .el and .sh names are part of the installer contract.
            put(MediaStore.MediaColumns.MIME_TYPE, "application/octet-stream")
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values)
            ?: error("Android refused to create $relative")
        try {
            resolver.openOutputStream(uri, "w")?.use { output ->
                context.assets.open(assetPath).use { input -> input.copyTo(output) }
            } ?: error("Android could not open $relative for writing")
            resolver.update(
                uri,
                ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) },
                null,
                null,
            )
            count += 1
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            throw error
        }
    }
    return count
}

@Composable
internal fun WaitingForEmacs(onRepair: () -> Unit) {
    Column(
        Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        Text("Waiting for Emacs", style = MaterialTheme.typography.headlineMedium)
        Text(
            "The EBP Companion is listening on 127.0.0.1:8765.",
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.padding(top = 8.dp, bottom = 20.dp),
        )
        OutlinedButton(onClick = onRepair, modifier = Modifier.fillMaxWidth()) {
            Text("Set up or repair Jetpacs")
        }
    }
}

@Composable
internal fun OnboardingFlow(onDone: () -> Unit, onCancel: (() -> Unit)? = null) {
    var step by remember { mutableStateOf(OnboardingStep.CHOOSE) }
    var setupPath by remember { mutableStateOf(JetpacsSetupPath.RECOMMENDED) }
    var vaultChoice by remember { mutableStateOf(JetpacsVaultChoice.SDCARD) }
    var homeChoice by remember { mutableStateOf(JetpacsEmacsHomeChoice.LOCAL) }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
    ) {
        if (step != OnboardingStep.CHOOSE) {
            TextButton(onClick = {
                step = when (step) {
                    OnboardingStep.HOME -> OnboardingStep.CHOOSE
                    OnboardingStep.VAULT -> OnboardingStep.HOME
                    OnboardingStep.INSTALL ->
                        if (setupPath == JetpacsSetupPath.RECOMMENDED)
                            OnboardingStep.CHOOSE
                        else OnboardingStep.VAULT
                    OnboardingStep.FINISH -> OnboardingStep.INSTALL
                    OnboardingStep.CHOOSE -> OnboardingStep.CHOOSE
                }
            }) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                Text("Back", modifier = Modifier.padding(start = 6.dp))
            }
        } else if (onCancel != null) {
            TextButton(onClick = onCancel) { Text("Close") }
        }
        val advanced = setupPath == JetpacsSetupPath.ADVANCED
        val progress = when (step) {
            OnboardingStep.CHOOSE -> 1
            OnboardingStep.HOME -> 2
            OnboardingStep.VAULT -> 3
            OnboardingStep.INSTALL -> if (advanced) 4 else 2
            OnboardingStep.FINISH -> if (advanced) 5 else 3
        }
        Text(
            "Step $progress of ${if (advanced) 5 else 3}",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.primary,
        )
        Spacer(Modifier.height(8.dp))
        when (step) {
            OnboardingStep.CHOOSE -> ChooseSetupPathStep(
                choice = setupPath,
                onChoice = { setupPath = it },
                onNext = {
                    if (setupPath == JetpacsSetupPath.RECOMMENDED) {
                        homeChoice = JetpacsEmacsHomeChoice.LOCAL
                        vaultChoice = JetpacsVaultChoice.SDCARD
                        step = OnboardingStep.INSTALL
                    } else {
                        step = OnboardingStep.HOME
                    }
                },
            )
            OnboardingStep.HOME -> ChooseHomeStep(
                homeChoice = homeChoice,
                onChoice = {
                    homeChoice = it
                    vaultChoice = allowedVaultChoices(it).first()
                },
                onNext = {
                    if (vaultChoice !in allowedVaultChoices(homeChoice)) {
                        vaultChoice = allowedVaultChoices(homeChoice).first()
                    }
                    step = OnboardingStep.VAULT
                },
            )
            OnboardingStep.VAULT -> ChooseAdvancedVaultStep(
                homeChoice = homeChoice,
                vaultChoice = vaultChoice,
                onChoice = { vaultChoice = it },
                onNext = { step = OnboardingStep.INSTALL },
            )
            OnboardingStep.INSTALL -> InstallStep(
                setupPath = setupPath,
                vaultChoice = vaultChoice,
                homeChoice = homeChoice,
                onNext = { step = OnboardingStep.FINISH },
            )
            OnboardingStep.FINISH -> FinishStep(
                setupPath = setupPath,
                vaultChoice = vaultChoice,
                homeChoice = homeChoice,
                onDone = onDone,
            )
        }
    }
}

@Composable
private fun ChoiceCard(
    selected: Boolean,
    title: String,
    subtitle: String,
    badge: String? = null,
    onClick: () -> Unit,
) {
    Card(onClick = onClick, modifier = Modifier.fillMaxWidth().padding(bottom = 10.dp)) {
        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.Top) {
            RadioButton(selected = selected, onClick = onClick)
            Column(Modifier.padding(start = 8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(title, style = MaterialTheme.typography.titleMedium)
                    badge?.let {
                        Text(
                            it,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onPrimaryContainer,
                            modifier = Modifier
                                .padding(start = 8.dp)
                                .background(
                                    MaterialTheme.colorScheme.primaryContainer,
                                    RoundedCornerShape(8.dp),
                                )
                                .padding(horizontal = 7.dp, vertical = 3.dp),
                        )
                    }
                }
                Text(
                    subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
        }
    }
}

@Composable
private fun ChooseSetupPathStep(
    choice: JetpacsSetupPath,
    onChoice: (JetpacsSetupPath) -> Unit,
    onNext: () -> Unit,
) {
    Text(
        "Where should your HOME directory/Vault be?",
        style = MaterialTheme.typography.headlineSmall,
    )
    Text(
        "Recommended uses the standard device layout. Advanced lets you choose " +
            "the Emacs host first, then offers only the Vault locations that fit it.",
        style = MaterialTheme.typography.bodyMedium,
        modifier = Modifier.padding(top = 8.dp, bottom = 18.dp),
    )
    ChoiceCard(
        selected = choice == JetpacsSetupPath.RECOMMENDED,
        title = "Recommended",
        badge = "Local Org Mode",
        subtitle = "Use Local Emacs's private HOME for .emacs.d/jetpacs and " +
            "/sdcard as the Vault. Org files survive uninstalling Emacs, but " +
            "apps with “All files” access can read them.",
        onClick = { onChoice(JetpacsSetupPath.RECOMMENDED) },
    )
    ChoiceCard(
        selected = choice == JetpacsSetupPath.ADVANCED,
        title = "Advanced",
        subtitle = "Choose Local Emacs, Remote Emacs, or Termux as the host; review " +
            "the exact startup snippets; then choose an eligible Vault.",
        onClick = { onChoice(JetpacsSetupPath.ADVANCED) },
    )
    Button(onClick = onNext, modifier = Modifier.fillMaxWidth().padding(top = 8.dp)) {
        Text("Continue")
    }
}

@Composable
private fun ChooseHomeStep(
    homeChoice: JetpacsEmacsHomeChoice,
    onChoice: (JetpacsEmacsHomeChoice) -> Unit,
    onNext: () -> Unit,
) {
    Text("Where should your HOME directory be?", style = MaterialTheme.typography.headlineSmall)
    Text(
        "Choose the Emacs host first. The next screen will offer the Vault " +
            "locations that make sense for that host.",
        style = MaterialTheme.typography.bodyMedium,
        modifier = Modifier.padding(top = 8.dp, bottom = 18.dp),
    )
    ChoiceCard(
        selected = homeChoice == JetpacsEmacsHomeChoice.LOCAL,
        title = "Local Emacs",
        badge = "Default",
        subtitle = "Use Android Emacs's private Unix HOME. .emacs.d and Jetpacs are " +
            "deleted when Emacs is uninstalled or its data is cleared.",
        onClick = { onChoice(JetpacsEmacsHomeChoice.LOCAL) },
    )
    ChoiceCard(
        selected = homeChoice == JetpacsEmacsHomeChoice.REMOTE,
        title = "Remote Emacs",
        subtitle = "Leave Android Emacs untouched. A desktop Emacs's existing Unix " +
            "HOME owns Jetpacs and the Vault. You will receive the pairing " +
            "credential and a remote init snippet.",
        onClick = { onChoice(JetpacsEmacsHomeChoice.REMOTE) },
    )
    ChoiceCard(
        selected = homeChoice == JetpacsEmacsHomeChoice.TERMUX_SHARED,
        title = "Termux",
        badge = "Development workflows",
        subtitle = "Redirect Android Emacs to Termux's private HOME so Emacs and " +
            "Termux share .emacs.d and command-line tooling.",
        onClick = { onChoice(JetpacsEmacsHomeChoice.TERMUX_SHARED) },
    )
    Button(
        onClick = onNext,
        modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
    ) {
        Text("Continue")
    }
}

@Composable
private fun ChooseAdvancedVaultStep(
    homeChoice: JetpacsEmacsHomeChoice,
    vaultChoice: JetpacsVaultChoice,
    onChoice: (JetpacsVaultChoice) -> Unit,
    onNext: () -> Unit,
) {
    val allowed = allowedVaultChoices(homeChoice)
    Text("Where should your Vault be?", style = MaterialTheme.typography.headlineSmall)
    Text(
        when (homeChoice) {
            JetpacsEmacsHomeChoice.LOCAL ->
                "Local Emacs can use /sdcard or its own private home. Termux home " +
                    "is intentionally not offered for this host."
            JetpacsEmacsHomeChoice.TERMUX_SHARED ->
                "Termux can use shared storage, Local Emacs storage, or its own home."
            JetpacsEmacsHomeChoice.REMOTE ->
                "The Vault belongs to the remote host; Android-local storage is " +
                    "not offered as an ordinary remote filesystem."
        },
        style = MaterialTheme.typography.bodyMedium,
        modifier = Modifier.padding(top = 8.dp, bottom = 18.dp),
    )
    if (JetpacsVaultChoice.SDCARD in allowed) {
        ChoiceCard(
            selected = vaultChoice == JetpacsVaultChoice.SDCARD,
            title = "/sdcard",
            badge = "Persistent",
            subtitle = "User content survives uninstalling Emacs or Termux, but " +
                "apps with Android “All files” access can read it.",
            onClick = { onChoice(JetpacsVaultChoice.SDCARD) },
        )
    }
    if (JetpacsVaultChoice.EMACS in allowed) {
        ChoiceCard(
            selected = vaultChoice == JetpacsVaultChoice.EMACS,
            title = "Local Emacs home",
            subtitle = "Keep the Vault in Android Emacs's private storage. It is " +
                "deleted with Emacs app data.",
            onClick = { onChoice(JetpacsVaultChoice.EMACS) },
        )
    }
    if (JetpacsVaultChoice.TERMUX in allowed) {
        ChoiceCard(
            selected = vaultChoice == JetpacsVaultChoice.TERMUX,
            title = "Termux home",
            subtitle = "Keep the Vault beside Termux tooling in private storage. " +
                "It is deleted with Termux app data.",
            onClick = { onChoice(JetpacsVaultChoice.TERMUX) },
        )
    }
    if (JetpacsVaultChoice.REMOTE in allowed) {
        ChoiceCard(
            selected = true,
            title = "Remote Emacs home",
            subtitle = "Use the remote Emacs user's home as the initial Vault. " +
                "It can be customized from that Emacs later.",
            onClick = { onChoice(JetpacsVaultChoice.REMOTE) },
        )
    }
    Button(onClick = onNext, modifier = Modifier.fillMaxWidth().padding(top = 8.dp)) {
        Text("Continue")
    }
}

@Composable
private fun CodeBlock(text: String, copyLabel: String, showCopy: Boolean = true) {
    val context = LocalContext.current
    Card(Modifier.fillMaxWidth().padding(vertical = 10.dp)) {
        Column(Modifier.padding(14.dp)) {
            Text(text, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall)
            if (showCopy) {
                TextButton(
                    onClick = { copyText(context, copyLabel, text) },
                    modifier = Modifier.align(Alignment.End),
                ) {
                    Icon(Icons.Default.ContentCopy, contentDescription = null)
                    Text("Copy", modifier = Modifier.padding(start = 6.dp))
                }
            }
        }
    }
}

@Composable
private fun RecommendedInstallStep(onNext: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var preparing by remember { mutableStateOf(false) }
    var staged by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    Text("Set up Android Emacs", style = MaterialTheme.typography.headlineSmall)
    Text(
        "Jetpacs will prepare its bundled files and copy one small setup block. " +
            "You will paste it at the bottom of Android Emacs's " +
            "~/.emacs.d/init.el. Keep everything already in that file above it so " +
            "your existing configuration runs first. Nothing is downloaded, and " +
            "this path does not use Termux.",
        modifier = Modifier.padding(top = 8.dp, bottom = 16.dp),
    )

    FilledTonalButton(
        enabled = !preparing,
        onClick = {
            preparing = true
            staged = false
            errorMessage = null
            scope.launch {
                runCatching {
                    val fileCount = withContext(Dispatchers.IO) {
                        stageSetupKit(context)
                    }
                    copyText(
                        context,
                        "Jetpacs init.el package entry",
                        RECOMMENDED_INIT_SNIPPET,
                    )
                    fileCount
                }.onSuccess {
                    staged = true
                }.onFailure { error ->
                    errorMessage =
                        error.message ?: "Android could not prepare the bundled files."
                }
                preparing = false
            }
        },
        modifier = Modifier.fillMaxWidth(),
    ) {
        Icon(
            if (staged) Icons.Default.Check else Icons.Default.Folder,
            contentDescription = null,
        )
        Text(
            if (preparing) "Preparing Jetpacs…"
            else if (staged) "Prepare files and copy again"
            else "Prepare files and copy setup",
            modifier = Modifier.padding(start = 8.dp),
        )
    }

    if (preparing) {
        LinearProgressIndicator(Modifier.fillMaxWidth())
    }
    errorMessage?.let { error ->
        Text(
            "Could not prepare Jetpacs: $error",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.error,
            modifier = Modifier.padding(bottom = 8.dp),
        )
    }

    if (staged) {
        Text(
            "Copied. Now, in Android Emacs:\n\n" +
                "1. Open ~/.emacs.d/init.el (create it if it does not exist).\n" +
                "2. Paste the copied block at the very bottom. Do not replace your " +
                "existing configuration.\n" +
                "3. Save init.el, then return here.",
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.padding(top = 14.dp),
        )
        CodeBlock(RECOMMENDED_INIT_SNIPPET, "Jetpacs init.el package entry")
        Text(
            "On Emacs's next full restart, this creates ~/.emacs.d/jetpacs, " +
                "creates /sdcard/org, removes the temporary handoff files, and " +
                "loads Jetpacs.",
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier.padding(bottom = 16.dp),
        )
    }

    Button(
        enabled = staged,
        onClick = onNext,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Text(if (staged) "I pasted and saved it" else "Continue")
    }
}

@Composable
private fun InstallStep(
    setupPath: JetpacsSetupPath,
    vaultChoice: JetpacsVaultChoice,
    homeChoice: JetpacsEmacsHomeChoice,
    onNext: () -> Unit,
) {
    if (setupPath == JetpacsSetupPath.RECOMMENDED) {
        RecommendedInstallStep(onNext)
        return
    }

    if (homeChoice == JetpacsEmacsHomeChoice.REMOTE) {
        Text("Pair Remote Emacs", style = MaterialTheme.typography.headlineSmall)
        Text(
            "No Android Emacs HOME or init file will be changed. Forward the " +
                "Companion port, install Jetpacs once with Emacs's package manager, " +
                "and add the small require block to that Emacs's init.el.",
            modifier = Modifier.padding(top = 8.dp, bottom = 8.dp),
        )
        Text("Pairing ID", style = MaterialTheme.typography.titleSmall)
        CodeBlock(JETPACS_PAIRING_ID, "Jetpacs pairing ID")
        Text("Pairing token", style = MaterialTheme.typography.titleSmall)
        CodeBlock(JETPACS_PAIRING_TOKEN, "Jetpacs pairing token")
        Text(
            "Install once in Remote Emacs",
            style = MaterialTheme.typography.titleSmall,
            modifier = Modifier.padding(top = 8.dp),
        )
        Text(
            "Until Jetpacs is published in a package archive, package-vc installs " +
                "it directly from the repository. This step requires Git and is not " +
                "part of init.el.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        CodeBlock(PACKAGE_VC_INSTALL_SNIPPET, "Install Jetpacs with package-vc")
        Text(
            "Remote ~/.emacs.d/init.el",
            style = MaterialTheme.typography.titleSmall,
            modifier = Modifier.padding(top = 8.dp),
        )
        CodeBlock(remoteInitSnippet(), "Remote Emacs Jetpacs init")
        Text("Forward the device listener", style = MaterialTheme.typography.titleSmall)
        CodeBlock("adb forward tcp:8765 tcp:8765", "Jetpacs adb port forward")
        Text(
            "This POC still uses its fixed development pairing credential. A later " +
                "pairing implementation should replace it with a generated, " +
                "keystore-backed token.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Button(onClick = onNext, modifier = Modifier.fillMaxWidth()) { Text("Continue") }
        return
    }

    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var staging by remember { mutableStateOf(false) }
    var result by remember { mutableStateOf<String?>(null) }
    val command = termuxInstallCommand(vaultChoice, homeChoice)!!

    Text("Install the advanced setup", style = MaterialTheme.typography.headlineSmall)
    Text(
        "The Companion first stages its bundled files in Documents. That folder is " +
            "transport only; the Termux command installs Jetpacs into the selected " +
            "private .emacs.d, records your Vault, and removes the temporary files after " +
            "a successful install.",
        modifier = Modifier.padding(top = 8.dp, bottom = 16.dp),
    )
    FilledTonalButton(
        enabled = !staging,
        onClick = {
            staging = true
            result = null
            scope.launch {
                result = runCatching {
                    val count = withContext(Dispatchers.IO) { stageSetupKit(context) }
                    "Installation files ready at $KIT_PATH ($count files)."
                }.getOrElse { error ->
                    "Could not prepare the installation files: ${error.message}. Delete the old " +
                        "Documents/$KIT_DIRECTORY folder and try again."
                }
                staging = false
            }
        },
        modifier = Modifier.fillMaxWidth(),
    ) {
        Icon(
            if (result?.startsWith("Installation files ready") == true) Icons.Default.Check
            else Icons.Default.Folder,
            contentDescription = null,
        )
        Text(
            if (staging) "Preparing installation files…" else "Prepare installation files",
            modifier = Modifier.padding(start = 8.dp),
        )
    }
    if (staging) LinearProgressIndicator(Modifier.fillMaxWidth().padding(top = 8.dp))
    result?.let {
        Text(
            it,
            style = MaterialTheme.typography.bodySmall,
            color = if (it.startsWith("Installation files ready")) MaterialTheme.colorScheme.primary
            else MaterialTheme.colorScheme.error,
            modifier = Modifier.padding(top = 8.dp),
        )
    }

    Text(
        "Launch Android Emacs once so its private home exists, then force-stop " +
            "Emacs. Open Termux and run both lines:",
        style = MaterialTheme.typography.titleSmall,
        modifier = Modifier.padding(top = 18.dp),
    )
    CodeBlock(command, "Jetpacs install command")
    if (setupPath == JetpacsSetupPath.ADVANCED &&
        homeChoice == JetpacsEmacsHomeChoice.LOCAL) {
        Text(
            "/data/data/org.gnu.emacs/files/.emacs.d/init.el",
            style = MaterialTheme.typography.titleSmall,
            modifier = Modifier.padding(top = 8.dp),
        )
        Text(
            "The installer adds this marked block without replacing your other init forms:",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        CodeBlock(INIT_SEAM_SNIPPET, "Local Emacs init.el snippet")
    }
    if (homeChoice == JetpacsEmacsHomeChoice.TERMUX_SHARED) {
        Text(
            "/data/data/org.gnu.emacs/files/.emacs.d/early-init.el",
            style = MaterialTheme.typography.titleSmall,
            modifier = Modifier.padding(top = 8.dp),
        )
        Text(
            "This bootstrap redirects Android Emacs to Termux before normal init lookup:",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        CodeBlock(TERMUX_EARLY_INIT_SNIPPET, "Termux HOME early-init.el snippet")
        Text(
            "/data/data/com.termux/files/home/.emacs.d/init.el",
            style = MaterialTheme.typography.titleSmall,
            modifier = Modifier.padding(top = 8.dp),
        )
        CodeBlock(INIT_SEAM_SNIPPET, "Termux init.el snippet")
    }
    Text(
        "Termux PATH snippet",
        style = MaterialTheme.typography.titleSmall,
        modifier = Modifier.padding(top = 8.dp),
    )
    Text(
        "The automated setup puts these exact forms in early-init.el. They are " +
            "also shipped here for users who maintain that file manually:",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(top = 4.dp),
    )
    CodeBlock(TERMUX_PATH_SNIPPET, "Termux PATH for early-init.el")
    Text(
        "Approve Termux's Files prompt. If you chose /sdcard, also grant Android " +
            "Emacs “All files” access. The installer preserves existing init files, " +
            "adds marked blocks, and creates a one-time recovery copy.",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Button(onClick = onNext, modifier = Modifier.fillMaxWidth().padding(top = 18.dp)) {
        Text("I ran the installer")
    }
}

@Composable
private fun FinishStep(
    setupPath: JetpacsSetupPath,
    vaultChoice: JetpacsVaultChoice,
    homeChoice: JetpacsEmacsHomeChoice,
    onDone: () -> Unit,
) {
    if (setupPath == JetpacsSetupPath.RECOMMENDED) {
        Text("Finish in Android Emacs", style = MaterialTheme.typography.headlineSmall)
        Text(
            "After pasting and saving the block in init.el, tap Finish. Then restart " +
                "both apps: open the Companion first, followed by Android Emacs. " +
                "The package entry installs and loads Jetpacs from the private " +
                "configuration directory while keeping your user content in the " +
                "/sdcard Vault.",
            modifier = Modifier.padding(top = 8.dp),
        )
        CodeBlock(
            "Emacs init:\n~/.emacs.d/init.el\n\n" +
                "Jetpacs files:\n~/.emacs.d/jetpacs/\n\n" +
                "Vault:\n/sdcard\nOrg files:\n/sdcard/org/",
            "Jetpacs recommended paths",
        )
        Text(
            "After Emacs connects, return to the Companion and the Jetpacs " +
                "interface will replace the waiting screen.",
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.padding(bottom = 16.dp),
        )
        Button(onClick = onDone, modifier = Modifier.fillMaxWidth()) {
            Text("Finish")
        }
        Text(
            "You can reopen setup from the waiting screen. To remove this setup, " +
                "delete ~/.emacs.d/jetpacs and the marked Jetpacs block from init.el. " +
                "Your Vault is never deleted.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 12.dp),
        )
        return
    }

    Text(
        "Advanced layout ready",
        style = MaterialTheme.typography.headlineSmall,
    )
    if (homeChoice == JetpacsEmacsHomeChoice.REMOTE) {
        Text(
            "Start the desktop Emacs after forwarding the Companion port. Keep the " +
                "local Android Emacs stopped so only one session dials the Companion.",
            modifier = Modifier.padding(top = 8.dp, bottom = 16.dp),
        )
    } else {
        val vault = selectedVault(vaultChoice)
        val home = selectedConfigHome(homeChoice)!!
        Text(
            "Android Emacs starts through its private early-init.el and naturally " +
                "loads the selected private config below. Org files and other user " +
                "content live in your Vault: $vault",
            modifier = Modifier.padding(top = 8.dp),
        )
        CodeBlock(
            "Private config:\n$home/.emacs.d/init.el\n" +
                "$home/.emacs.d/jetpacs/\n\nVault:\n$vault\n" +
                "Org files:\n$vault/org/",
            "Jetpacs installed paths",
        )
        Text(
            "Force-stop and relaunch Android Emacs, then return here. The screen " +
                "changes as soon as Emacs connects and pushes Jetpacs.",
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.padding(bottom = 16.dp),
        )
    }
    Button(onClick = onDone, modifier = Modifier.fillMaxWidth()) {
        Text("Finish")
    }
    Text(
        if (homeChoice == JetpacsEmacsHomeChoice.REMOTE)
            "You can reopen setup from the waiting screen to copy the pairing " +
                "credential again."
        else
            "You can reopen this setup from the waiting screen. Removing Jetpacs " +
                "deletes only the private ~/.emacs.d/jetpacs tree and its marked " +
                "init seam. The Vault is never deleted.",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(top = 12.dp),
    )
}
