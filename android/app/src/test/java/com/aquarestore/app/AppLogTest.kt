package com.aquarestore.app

import org.junit.Assert.assertThrows
import org.junit.Test

/** In unit tests `android.util.Log` throws when called, which shows whether a line reached it. */
class AppLogTest {
    @Test fun nothingIsWrittenWhileDeveloperToolsAreOff() {
        AppLog.enabled = false
        AppLog.i("line")
        AppLog.w("line", IllegalStateException())
        AppLog.e("line", IllegalStateException())
    }

    @Test fun linesAreWrittenWhileDeveloperToolsAreOn() {
        AppLog.enabled = true
        try {
            assertThrows(RuntimeException::class.java) { AppLog.i("line") }
            assertThrows(RuntimeException::class.java) { AppLog.w("line") }
            assertThrows(RuntimeException::class.java) { AppLog.e("line") }
        } finally { AppLog.enabled = false }
    }
}
