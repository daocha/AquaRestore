package com.aquarestore.app

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.Font
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

@Composable
internal fun BatchQuestDialog(s: Strings, video: Boolean, onUnlocked: () -> Unit, dismiss: () -> Unit) {
    val context = LocalContext.current
    var checking by remember { mutableStateOf(ReferralCampaign.active) }
    var error by remember { mutableStateOf(false) }
    var count by remember { mutableIntStateOf(ReferralCampaign.count(context)) }
    var invited by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        if (BatchAccess.enabled(context, video)) { onUnlocked(); return@LaunchedEffect }
        if (ReferralCampaign.active) {
            try {
                ReferralCampaign.request(context)
                count = ReferralCampaign.count(context)
                if (BatchAccess.enabled(context, video)) onUnlocked()
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { error = true }
            finally { checking = false }
        }
    }
    AlertDialog(onDismissRequest = dismiss, title = { Text(s.text("Unlock batch processing", "解鎖批次處理")) }, text = {
        Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (ReferralCampaign.active) {
                Text(s.text("Complete the app quest: invite friends to use AquaRestore. They enter your referral code in Settings.",
                    "完成 App 任務：邀請朋友使用 AquaRestore，並請他們在設定中輸入你的推薦碼。"))
                Text(s.text("Invite 5 friends → unlock batch photo processing", "邀請 5 位朋友 → 解鎖批次照片處理"))
                Text(s.text("Invite 10 friends → unlock batch video processing", "邀請 10 位朋友 → 解鎖批次影片處理"))
                runCatching { ReferralCampaign.code(context) }.getOrNull()?.let { code ->
                    OwnReferralCode(s, code) { invited = true }
                }
                if (invited) Text(s.text("Invite copied.", "邀請內容已複製。"))
                Text(s.text("Friends invited: $count", "已邀請朋友：$count"))
                if (checking) LinearProgressIndicator(Modifier.fillMaxWidth())
                if (error) Text(s.text("Could not check quest progress. Check your connection and tap the batch button again.",
                    "無法查詢任務進度。請檢查網路，然後再次點選批次按鈕。"), color = MaterialTheme.colorScheme.error)
            } else Text(s.text("This feature is locked. Enter an unlock code in Settings → Developer tools.",
                "此功能尚未解鎖。請在「設定 → 開發者工具」中輸入解鎖碼。"))
        }
    }, confirmButton = { TextButton(onClick = dismiss) { Text(s.text("Done", "完成")) } })
}

/** Shows each `backtick-quoted` run in the referral code font, so the look-alike characters it names can be told apart. */
private fun codeFontRuns(text: String): AnnotatedString = buildAnnotatedString {
    text.split('`').forEachIndexed { index, run ->
        if (index % 2 == 1) withStyle(SpanStyle(fontFamily = referralCodeFont, fontWeight = FontWeight.SemiBold)) { append(run) }
        else append(run)
    }
}

private val referralCodeFont = FontFamily(Font(R.font.roboto_mono))

/** Use the same bundled code face on every device. */
@Composable
private fun ReferralCode(label: String, code: String, modifier: Modifier = Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(label)
        SelectionContainer {
            Text(code, fontFamily = referralCodeFont, fontWeight = FontWeight.SemiBold, fontSize = 22.sp, letterSpacing = 1.sp, maxLines = 1)
        }
    }
}

/** Copies first, so the invite is still on the clipboard if the share sheet is dismissed. */
private fun shareInvite(context: Context, s: Strings, code: String) {
    val fromPlay = BuildConfig.UPDATE_CHANNEL == "play" || installedViaPlay(context)
    val invite = ReferralInvite.message(s, code, ReferralInvite.appUrl(fromPlay, context.packageName))
    context.getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("AquaRestore", invite))
    context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, invite), null))
}

@Composable
private fun OwnReferralCode(s: Strings, code: String, onInvited: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var copied by remember(code) { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(s.text("Your referral code", "你的推薦碼"))
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            BoxWithConstraints(Modifier.weight(1f)) {
                val codeSize = (maxWidth.value / 7f).coerceIn(12f, 22f).sp
                SelectionContainer {
                    Text(code, fontFamily = referralCodeFont, fontWeight = FontWeight.SemiBold, fontSize = codeSize, letterSpacing = 1.sp, maxLines = 1)
                }
            }
            OutlinedIconButton(onClick = {
                context.getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText(s.text("Referral code", "推薦碼"), code))
                copied = true
            }) { Icon(Icons.Outlined.ContentCopy, s.text("Copy code", "複製推薦碼")) }
            OutlinedButton(onClick = {
                shareInvite(context, s, code)
                onInvited()
                // A device that was offline at launch must exist on the server before a friend tries this code.
                scope.launch { ReferralCampaign.registerIfNeeded(context) }
            }) { Text(s.text("Invite", "邀請")) }
        }
        if (copied) Text(s.text("Code copied.", "推薦碼已複製。"), style = MaterialTheme.typography.bodySmall)
    }
}

@Composable
internal fun ReferralSettings(s: Strings) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val bound = remember(ReferralCampaign.revision) { ReferralCampaign.referredBy(context) }
    var code by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    val invalidCode = s.text("This referral code is invalid. Codes are case-sensitive and some characters look alike, such as `l` and `I` or `O` and `0`. Paste the code if you can.",
        "此推薦碼無效。推薦碼區分大小寫，部分字元外觀相近（如 `l` 與 `I`、`O` 與 `0`），建議直接貼上。")
    // In a popup: the submit button can sit at the bottom of the scrolling settings, with anything below it out of view.
    error?.let { text ->
        AlertDialog(onDismissRequest = { error = null }, title = { Text(s.text("Referral code", "推薦碼")) }, text = { Text(codeFontRuns(text)) },
            confirmButton = { TextButton(onClick = { error = null }) { Text(s.text("OK", "知道了")) } })
    }
    HorizontalDivider()
    Text(s.text("Invite friends", "邀請朋友"), fontWeight = FontWeight.SemiBold)
    val ownCode = remember(ReferralCampaign.revision) { runCatching { ReferralCampaign.code(context) }.getOrNull() }
    if (ownCode != null) OwnReferralCode(s, ownCode) { message = s.text("Invite copied.", "邀請內容已複製。") }
    else Text(s.text("Device identity unavailable. Try reopening the app.", "無法取得裝置識別碼，請重新開啟 App。"))
    Text(s.text("Invite 5 friends for batch photos; 10 for batch videos.", "邀請 5 位朋友解鎖批次照片；10 位解鎖批次影片。"))
    if (bound != null) {
        ReferralCode(s.text("Friend’s referral code", "朋友的推薦碼"), bound)
        Text(s.text("Referral code saved. It cannot be changed.", "推薦碼已儲存，無法變更。"))
    } else {
        OutlinedTextField(value = code, onValueChange = { code = ReferralIdentity.codeIn(it); message = null },
            label = { Text(s.text("Friend’s referral code", "朋友的推薦碼")) }, singleLine = true, enabled = !busy,
            textStyle = LocalTextStyle.current.copy(fontFamily = referralCodeFont, fontSize = 20.sp, letterSpacing = 1.sp),
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false))
        Text(s.text("You can submit a friend’s code only once.", "朋友的推薦碼只能提交一次。"))
        OutlinedButton(onClick = {
            val entered = code.trim()
            if (!ReferralIdentity.acceptable(entered, ownCode.orEmpty())) { error = invalidCode; return@OutlinedButton }
            busy = true; message = null
            scope.launch {
                try {
                    val accepted = ReferralCampaign.request(context, entered)
                    code = ""
                    message = if (accepted) s.text("Referral code saved.", "推薦碼已儲存。")
                    else s.text("This device already used a referral code. The original code has been restored.", "此裝置已使用推薦碼，已還原原本的推薦碼。")
                } catch (cancelled: CancellationException) { throw cancelled }
                catch (failure: Exception) {
                    error = if ((failure as? ReferralApiException)?.errorCode == "invalid_referral_code") invalidCode
                    else s.referralFailure(failure, redeem = false)
                }
                finally { busy = false }
            }
        }, enabled = !busy && ownCode != null && code.isNotBlank()) {
            Text(if (busy) s.text("Submitting…", "正在提交…") else s.text("Submit referral code", "提交推薦碼"))
        }
    }
    message?.let { Text(it) }
}

/** Why a code submission failed. A rejected proof or a failed device check is not a connection problem. */
internal fun Strings.referralFailure(failure: Exception, redeem: Boolean): String = when {
    failure is ReferralApiException && failure.errorCode != "unavailable" ->
        text("The server could not verify this device. Try again later.", "伺服器無法驗證此裝置，請稍後再試。")
    failure is java.io.IOException || failure is ReferralApiException ->
        if (redeem) text("Could not redeem the code. Check your connection and try again.", "無法兌換解鎖碼。請檢查網路連線後重試。")
        else text("Could not submit the code. Check your connection and try again.", "無法提交推薦碼。請檢查網路連線後重試。")
    else -> text("This device could not complete verification. Try again, or update the app.", "此裝置無法完成驗證。請重試或更新 App。")
}
