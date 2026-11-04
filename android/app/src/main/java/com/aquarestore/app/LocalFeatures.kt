package com.aquarestore.app

import android.app.Activity
import android.content.Context
import com.google.android.play.core.review.ReviewManagerFactory
object BatchAccess {
    val gateConfigured: Boolean get() = ReferralCampaign.active
    private fun key(video: Boolean) = if (video) "batchVideoUnlocked" else "batchPhotoUnlocked"
    fun enabled(context: Context, video: Boolean = false): Boolean {
        val prefs = context.getSharedPreferences("localFeatures", 0)
        return !gateConfigured || prefs.getBoolean(key(video), false) || prefs.getBoolean("batchUnlocked", false)
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
