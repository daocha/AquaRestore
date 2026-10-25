package com.aquarestore.app

import android.content.Context
import android.content.Intent
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Hidden developer tools, unlocked by tapping the version in Settings ten times: this app's own recent log,
 * to read, copy or share when reporting a problem. Nothing leaves the device unless the user shares it.
 * Unlocking lasts until the next update.
 */
object DevTools {
    const val UNLOCK_TAPS = 10
    private const val KEY = "dev_tools_install"
    /** Sharing and the clipboard pass text through a binder transaction, which fails above about 1 MB. */
    private const val SHARE_LIMIT = 400_000

    private fun prefs(context: Context) = context.getSharedPreferences("preferences", 0)
    /** Changes with every install or update, including debug builds, whose BuildConfig version code stays fixed. */
    private fun installed(context: Context) = context.packageManager.getPackageInfo(context.packageName, 0).lastUpdateTime
    fun enabled(context: Context) = runCatching { prefs(context).getLong(KEY, -1L) == installed(context) }.getOrDefault(false)
    fun enable(context: Context) = prefs(context).edit().putLong(KEY, installed(context)).apply()

    /** When the log was last cleared, in epoch milliseconds; lines before it are left out. */
    private var clearedAt = 0L

    /** An app cannot erase the system log, so clearing hides everything written before now. */
    fun clear() { clearedAt = System.currentTimeMillis() }

    /** The app's own log lines since it last started. An app may read its own log without any permission. */
    suspend fun log(): String = withContext(Dispatchers.IO) {
        runCatching {
            val since = if (clearedAt > 0) listOf("-T", "%d.%03d".format(clearedAt / 1000, clearedAt % 1000)) else listOf("-t", "3000")
            val process = ProcessBuilder(listOf("logcat", "-d", "-v", "time", "--pid=${android.os.Process.myPid()}") + since + listOf("-s", "AquaRestore"))
                .redirectErrorStream(true).start()
            process.inputStream.bufferedReader().use { it.readText() }.also { process.waitFor() }
        }.getOrElse { "Could not read the log: $it" }
    }

    /** The end of [log], short enough to share or copy. */
    fun shareable(log: String): String {
        val header = "AquaRestore ${BuildConfig.VERSION_NAME} · ${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL} · " +
            "Android ${android.os.Build.VERSION.RELEASE} (API ${android.os.Build.VERSION.SDK_INT})\n\n"
        return header + log.takeLast(SHARE_LIMIT)
    }
}

@Composable
fun DevLogPanel(s: Strings, dismiss: () -> Unit) {
    val context = LocalContext.current
    val clipboard = LocalClipboard.current
    val scope = rememberCoroutineScope()
    var log by remember { mutableStateOf<String?>(null) }
    val vertical = rememberScrollState()
    suspend fun refresh() {
        log = DevTools.log()
        vertical.scrollTo(Int.MAX_VALUE)
    }
    LaunchedEffect(Unit) { refresh() }
    Dialog(dismiss, DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize()) {
            Column(Modifier.fillMaxSize().systemBarsPadding().padding(12.dp)) {
                Text(s.text("Developer logs", "開發者日誌"), fontWeight = FontWeight.SemiBold, fontSize = 18.sp)
                Text("AquaRestore ${BuildConfig.VERSION_NAME} · ${android.os.Build.MODEL} · Android ${android.os.Build.VERSION.RELEASE}",
                    fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(8.dp))
                Surface(Modifier.weight(1f).fillMaxWidth(), color = MaterialTheme.colorScheme.surfaceVariant, shape = MaterialTheme.shapes.small) {
                    SelectionContainer {
                        Text(log?.takeIf { it.lines().any { line -> line.isNotBlank() && !line.startsWith("-----") } }
                            ?: if (log == null) s.text("Reading…", "讀取中…") else s.text("No log lines yet.", "尚無日誌。"),
                            Modifier.verticalScroll(vertical).horizontalScroll(rememberScrollState()).padding(8.dp),
                            fontFamily = FontFamily.Monospace, fontSize = 9.sp, lineHeight = 11.sp, softWrap = false)
                    }
                }
                Spacer(Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    TextButton(onClick = { scope.launch { refresh() } }) { Text(s.text("Refresh", "重新整理")) }
                    TextButton(onClick = { DevTools.clear(); scope.launch { refresh() } }) { Text(s.text("Clear", "清除")) }
                    TextButton(onClick = { log?.let { scope.launch { clipboard.setClipEntry(ClipEntry(android.content.ClipData.newPlainText("AquaRestore log", DevTools.shareable(it)))) } } }, enabled = log != null) {
                        Text(s.text("Copy", "複製"))
                    }
                    TextButton(onClick = {
                        val text = log ?: return@TextButton
                        context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain")
                            .putExtra(Intent.EXTRA_SUBJECT, "AquaRestore log")
                            .putExtra(Intent.EXTRA_TEXT, DevTools.shareable(text)), null))
                    }, enabled = log != null) { Text(s.text("Share", "分享")) }
                    Spacer(Modifier.weight(1f))
                    TextButton(onClick = dismiss) { Text(s.text("Close", "關閉")) }
                }
            }
        }
    }
}
