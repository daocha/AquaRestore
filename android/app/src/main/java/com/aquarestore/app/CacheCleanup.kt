package com.aquarestore.app

import android.content.Context
import java.io.File

/**
 * Removes cache files an earlier process left behind. Preview copies and export files are deleted when they are
 * done with, but not when the system ends the app first; an update APK is not needed once the installer has it.
 */
object CacheCleanup {
    private var done = false

    /** Runs once per process, before anything in it can be using these files. */
    fun onProcessStart(context: Context) {
        if (done) return
        done = true
        context.cacheDir.listFiles { file -> file.isFile && (file.name.startsWith("preview-") || file.name.startsWith("export-")) }
            ?.forEach(File::delete)
        // An APK waiting for the install permission is kept; AppUpdates installs it on resume.
        val pending = context.getSharedPreferences("updates", Context.MODE_PRIVATE).getString("pending_apk", null)
        File(context.cacheDir, "updates").listFiles { file -> file.name != pending }?.forEach(File::delete)
    }
}
