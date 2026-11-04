package com.aquarestore.app

import android.content.Context
import android.provider.Settings
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import java.math.BigInteger
import java.net.HttpURLConnection
import java.net.URI
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

internal object ReferralIdentity {
    private const val alphabet = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    fun deviceId(packageName: String, deviceId: String): String = MessageDigest.getInstance("SHA-256")
        .digest("referral-v1\n$packageName\n$deviceId".toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
    fun code(deviceId: String): String {
        var value = BigInteger(deviceId.take(14), 16)
        val base = BigInteger.valueOf(62)
        var result = ""
        while (value > BigInteger.ZERO) { val parts = value.divideAndRemainder(base); result = alphabet[parts[1].toInt()] + result; value = parts[0] }
        return result.padStart(10, '0')
    }
    /** Whether a friend's code is worth sending: well formed and not this device's own code. */
    fun acceptable(code: String, ownCode: String): Boolean = Regex("[0-9a-zA-Z]{10}").matches(code) && code != ownCode
    private val labelledCode = Regex("(?:code|推薦碼)\\s*[:：]\\s*([0-9a-zA-Z]{10})(?![0-9a-zA-Z])", RegexOption.IGNORE_CASE)
    /** Pasting a whole invite, or the "Your referral code" line, enters just the code. */
    fun codeIn(entered: String): String = labelledCode.find(entered)?.groupValues?.get(1) ?: entered
}

internal object ReferralInvite {
    /** The fixed-name APK the release script publishes next to the versioned one (see latest_apk_asset). */
    const val githubApkUrl = "https://github.com/daocha/AquaRestore/releases/latest/download/AquaRestore.apk"
    fun appUrl(fromPlay: Boolean, packageName: String): String =
        if (fromPlay) "https://play.google.com/store/apps/details?id=$packageName" else githubApkUrl
    /** The code stays on a line of its own so the recipient can select just the code. */
    fun message(s: Strings, code: String, appUrl: String): String = s.text(
        "Try AquaRestore: it brings back the natural colors of underwater photos and videos.\n\n" +
            "My referral code:\n$code\n\nGet the app: $appUrl\nThen enter the code in Settings → Invite friends.",
        "試試 AquaRestore：還原水下照片與影片的自然色彩。\n\n" +
            "我的推薦碼：\n$code\n\n下載 App：$appUrl\n然後在「設定 → 邀請朋友」輸入推薦碼。")
}

internal data class ReferralState(val count: Int, val referredBy: String?, val photo: Boolean, val video: Boolean) {
    companion object {
        fun parse(json: JSONObject): ReferralState {
            val count = json.getInt("referralCount")
            require(count >= 0)
            val unlocks = json.getJSONObject("unlocked")
            return ReferralState(count, if (json.isNull("referredByCode")) null else json.getString("referredByCode"),
                unlocks.getBoolean("batchPhoto"), unlocks.getBoolean("batchVideo"))
        }
    }
}

internal class ReferralApiException(val errorCode: String) : Exception(errorCode)

object ReferralCampaign {
    val active: Boolean get() = BuildConfig.REFERRAL_BACKEND_URL.isNotEmpty()
    /** Bumped when server state lands, so open screens read the saved referral state again. */
    var revision by mutableIntStateOf(0)
        private set
    private val registering = AtomicBoolean(false)
    private fun prefs(context: Context) = context.getSharedPreferences("localFeatures", 0)
    private fun deviceUrl(context: Context) = BuildConfig.REFERRAL_BACKEND_URL + "/v1/apps/${context.packageName}/devices/${identity(context)}"
    fun identity(context: Context): String {
        val id = Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
        check(!id.isNullOrBlank()) { "Device identity unavailable" }
        return ReferralIdentity.deviceId(context.packageName, id)
    }
    fun code(context: Context) = ReferralIdentity.code(identity(context))
    fun referredBy(context: Context): String? = prefs(context).getString("referredByCode", null)
    fun count(context: Context) = prefs(context).getInt("referralCount", 0)
    /**
     * Registers this device once so friends can use its code. The response also restores any referrer and grants
     * after cleared app data. Silent: a failure leaves the device unregistered, so the next launch tries again.
     */
    suspend fun registerIfNeeded(context: Context) {
        if (!active || !registering.compareAndSet(false, true)) return
        try {
            val changed = withContext(Dispatchers.IO) {
                // Tied to the backend and identity: a new backend or device has not seen this registration.
                val registration = BuildConfig.REFERRAL_BACKEND_URL + "\n" + identity(context)
                if (prefs(context).getString("referralRegistration", null) == registration) return@withContext false
                val state = ReferralState.parse(exchange(deviceUrl(context) + "/register", JSONObject()).second)
                save(context, state, prefs(context).edit().putString("referralRegistration", registration))
                true
            }
            if (changed) revision++
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (failure: Exception) { Log.w("AquaRestore", "Referral registration deferred: ${failure.javaClass.simpleName}") }
        finally { registering.set(false) }
    }
    private fun save(context: Context, state: ReferralState, edit: android.content.SharedPreferences.Editor = prefs(context).edit()) {
        edit.putInt("referralCount", state.count)
        state.referredBy?.let { edit.putString("referredByCode", it) }
        if (state.photo) edit.putBoolean("batchPhotoUnlocked", true)
        if (state.video) edit.putBoolean("batchVideoUnlocked", true)
        check(edit.commit())
    }
    // Called only by a locked batch action or explicit referral submission. Never on launch/settings open.
    internal suspend fun request(context: Context, referralCode: String? = null, unlockCode: String? = null): Boolean {
        val accepted = submit(context, referralCode, unlockCode)
        revision++
        return accepted
    }
    private suspend fun submit(context: Context, referralCode: String?, unlockCode: String?): Boolean = withContext(Dispatchers.IO) {
        check(active)
        require(referralCode == null || unlockCode == null)
        val base = deviceUrl(context)
        val submittedCode = unlockCode ?: referralCode
        val payload = if (submittedCode != null) {
            val verifier = ReferralProof(context)
            val challenge = exchange(base + "/challenge", JSONObject()
                .put("action", if (unlockCode == null) "referral" else "unlock")
                .put(if (unlockCode == null) "referralCode" else "unlockCode", submittedCode)
                .put("platform", verifier.platform).put("keyId", verifier.keyId)).second
            JSONObject().put("challengeId", challenge.getString("challengeId"))
                .put("proof", verifier.proof(challenge.getString("clientData")))
        } else null
        val (status, response) = exchange(base + when { payload == null -> ""; unlockCode != null -> "/unlock"; else -> "/referral" }, payload)
        val state = ReferralState.parse(response)
        if (referralCode != null) check(state.referredBy != null)
        save(context, state)
        status == 200
    }
    private fun exchange(url: String, payload: JSONObject?): Pair<Int, JSONObject> {
        val uri = URI(url)
        val connection = uri.toURL().openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 8000
            connection.readTimeout = if (payload == null) 8000 else 30_000
            connection.instanceFollowRedirects = false
            connection.useCaches = false
            connection.setRequestProperty("Accept", "application/json")
            if (payload != null) {
                connection.requestMethod = "POST"; connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")
                connection.outputStream.use { it.write(payload.toString().toByteArray(Charsets.UTF_8)) }
            }
            val status = connection.responseCode
            val stream = (if (status == 200) connection.inputStream else connection.errorStream)
                ?: throw ReferralApiException("unavailable")
            val raw = stream.use { input ->
                val output = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(4096)
                while (true) {
                    val size = input.read(buffer)
                    if (size < 0) break
                    check(output.size() + size <= 65536)
                    output.write(buffer, 0, size)
                }
                output.toByteArray()
            }
            val response = JSONObject(String(raw, Charsets.UTF_8))
            if (response.has("error")) throw ReferralApiException(response.optString("error", "unavailable"))
            check(status == 200 || (payload != null && status == 409)) { "Referral service unavailable" }
            return status to response
        } finally { connection.disconnect() }
    }
}
