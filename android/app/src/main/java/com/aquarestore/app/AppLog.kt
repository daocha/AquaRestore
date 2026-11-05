package com.aquarestore.app

import android.util.Log

/** This app's log, which the developer tools read. Nothing is written unless they are on, as on iOS. */
object AppLog {
    private const val TAG = "AquaRestore"

    /** Follows [DevTools]. Check it first where working out a line takes real work. */
    @Volatile var enabled = false

    fun i(message: String) { if (enabled) Log.i(TAG, message) }
    fun w(message: String, error: Throwable? = null) { if (enabled) Log.w(TAG, message, error) }
    fun e(message: String, error: Throwable? = null) { if (enabled) Log.e(TAG, message, error) }
}
