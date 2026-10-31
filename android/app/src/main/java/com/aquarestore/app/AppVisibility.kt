package com.aquarestore.app

import androidx.lifecycle.ViewModel

/** Tracks logical activity instances, so stopping one does not hide another that's still started. */
internal class StartedActivities {
    private val tokens = mutableSetOf<Any>()
    @Volatile var visible = false
        private set

    @Synchronized fun start(token: Any) { tokens += token; visible = tokens.isNotEmpty() }
    @Synchronized fun stop(token: Any) { tokens -= token; visible = tokens.isNotEmpty() }
}

/** The same token is reused after rotation; clearing the ViewModel also releases a pending handoff. */
internal class ActivityVisibilityModel(private val activities: StartedActivities = Exports.activities) : ViewModel() {
    private val token = Any()
    fun started() { activities.start(token) }
    fun stopped(changingConfigurations: Boolean) { if (!changingConfigurations) activities.stop(token) }
    override fun onCleared() { activities.stop(token); super.onCleared() }
}
