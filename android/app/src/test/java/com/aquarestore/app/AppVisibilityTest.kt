package com.aquarestore.app

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.ViewModelStore
import org.junit.Assert.*
import org.junit.Test

class AppVisibilityTest {
    @Test fun stoppingTheOriginalActivityDoesNotHideTheNotificationActivity() {
        val activities = StartedActivities()
        val original = ActivityVisibilityModel(activities)
        val notification = ActivityVisibilityModel(activities)
        original.started()
        notification.started()
        original.stopped(false)
        assertTrue(activities.visible)
        notification.stopped(false)
        assertFalse(activities.visible)
    }

    @Test fun goingBackKeepsTheResumedOriginalVisible() {
        val activities = StartedActivities()
        val original = ActivityVisibilityModel(activities)
        val notification = ActivityVisibilityModel(activities)
        original.started()
        notification.started()
        original.stopped(false)
        original.started()
        notification.stopped(false)
        // A late stop/clear for the same instance must also be harmless.
        notification.stopped(false)
        assertTrue(activities.visible)
        original.stopped(false)
        assertFalse(activities.visible)
    }

    @Test fun rotationKeepsVisibilityAndDoesNotCountTheSameActivityTwice() {
        val activities = StartedActivities()
        val model = ActivityVisibilityModel(activities)
        repeat(3) {
            model.started()
            model.stopped(true)
            assertTrue(activities.visible)
        }
        model.started()
        model.stopped(false)
        assertFalse(activities.visible)
    }

    @Test fun clearingTheViewModelReleasesAnUnfinishedConfigurationHandoff() {
        val activities = StartedActivities()
        val model = ActivityVisibilityModel(activities)
        val store = ViewModelStore()
        val factory = object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(modelClass: Class<T>): T = model as T
        }
        assertSame(model, ViewModelProvider(store, factory)[ActivityVisibilityModel::class.java])
        model.started()
        model.stopped(true)
        assertTrue(activities.visible)
        store.clear()
        assertFalse(activities.visible)
    }
}
