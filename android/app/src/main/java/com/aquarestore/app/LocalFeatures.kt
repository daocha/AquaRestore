package com.aquarestore.app

import android.app.Activity
import android.content.Context
import com.google.android.play.core.review.ReviewManagerFactory
import java.security.MessageDigest
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec

object BatchAccess {
    private fun verifier(video: Boolean) = if (video) BuildConfig.BATCH_VIDEO_VERIFIER else BuildConfig.BATCH_PHOTO_VERIFIER
    private fun key(video: Boolean) = if (video) "batchVideoUnlocked" else "batchPhotoUnlocked"
    fun enabled(context: Context, video: Boolean = false): Boolean {
        val prefs = context.getSharedPreferences("localFeatures", 0)
        return verifier(video).isEmpty() || prefs.getBoolean(key(video), false) || prefs.getBoolean("batchUnlocked", false)
    }
    suspend fun unlock(context: Context, code: String): Boolean = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) {
        val (photo, video) = matchingFeatures(code, BuildConfig.BATCH_PHOTO_SALT, BuildConfig.BATCH_PHOTO_VERIFIER,
            BuildConfig.BATCH_VIDEO_SALT, BuildConfig.BATCH_VIDEO_VERIFIER)
        if (photo || video) {
            val edit = context.getSharedPreferences("localFeatures", 0).edit()
            if (photo) edit.putBoolean(key(false), true)
            if (video) edit.putBoolean(key(true), true)
            edit.commit()
        }
        photo || video
    }
    internal fun matchingFeatures(code: String, photoSalt: String, photoVerifier: String,
                                  videoSalt: String, videoVerifier: String): Pair<Boolean, Boolean> {
        val photo = photoVerifier.isNotEmpty() && verify(code, photoSalt, photoVerifier)
        val video = videoVerifier.isNotEmpty() && verify(code, videoSalt, videoVerifier)
        return photo to video
    }
    internal fun verify(code: String, saltHex: String, verifierHex: String): Boolean {
        val salt = saltHex.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        val spec = PBEKeySpec(code.toCharArray(), salt, 120_000, 256)
        val actual = try { SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded } finally { spec.clearPassword() }
        val expected = verifierHex.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        return MessageDigest.isEqual(actual, expected)
    }
}

object RatingReminder {
    @Synchronized fun saved(context: Context, video: Boolean) {
        val prefs = context.getSharedPreferences("ratingReminder", 0)
        val key = if (video) "videos" else "photos"
        prefs.edit().putInt(key, (prefs.getInt(key, 0) + 1).coerceAtMost(10)).commit()
    }
    fun requestIfEligible(activity: Activity) {
        if (BuildConfig.UPDATE_CHANNEL != "play") return
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            if (!Exports.appVisible || Exports.status.value.busy || activity.isFinishing || activity.isDestroyed) return@postDelayed
            requestNow(activity)
        }, 1500)
    }
    private fun requestNow(activity: Activity) {
        val prefs = activity.getSharedPreferences("ratingReminder", 0)
        if (prefs.getBoolean("requested", false) || !SharingPlan.eligible(prefs.getInt("videos", 0), prefs.getInt("photos", 0))) return
        // This means requested, never that a review was shown or submitted.
        prefs.edit().putBoolean("requested", true).apply()
        val manager = ReviewManagerFactory.create(activity)
        manager.requestReviewFlow().addOnSuccessListener { info ->
            if (!activity.isFinishing && !activity.isDestroyed) manager.launchReviewFlow(activity, info)
        }
    }
}
