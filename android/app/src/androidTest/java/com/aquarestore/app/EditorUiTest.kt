package com.aquarestore.app

import android.content.ContentValues
import android.graphics.Bitmap
import android.net.Uri
import android.provider.MediaStore
import android.view.View
import android.view.ViewGroup
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.media3.common.Player
import androidx.media3.ui.PlayerView
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.Assert.*
import java.io.File

class EditorUiTest {
    @get:Rule val ui = createAndroidComposeRule<MainActivity>()
    private lateinit var model: EditorModel
    private val uris = mutableListOf<Uri>()
    @Before fun setup() {
        if (android.os.Build.VERSION.SDK_INT >= 33) {
            InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(
                "pm grant ${ui.activity.packageName} android.permission.POST_NOTIFICATIONS"
            ).use { fd -> java.io.FileInputStream(fd.fileDescriptor).use { it.readBytes() } }
        }
        ui.runOnUiThread {
            model = ViewModelProvider(ui.activity)[EditorModel::class.java]
            model.preference("language", "en"); model.preference("theme", "light")
            Exports.status.value = ExportStatus()
        }
    }
    @After fun cleanup() {
        Exports.status.value.uri?.let { uris += it }
        uris.forEach { ui.activity.contentResolver.delete(it, null, null) }
        ui.runOnUiThread { model.preference("language", "system"); model.preference("theme", "system") }
    }
    @Test fun languageAndThemeChangeOnScreenAndSurviveRecreation() {
        ui.onNodeWithContentDescription("Settings").performClick()
        ui.onNodeWithText("中文").performClick()
        ui.onNodeWithText("外觀").assertIsDisplayed()
        ui.onNodeWithText("深色").performClick()
        ui.onNodeWithText("完成").performClick()
        ui.onNodeWithText("匯入影片或照片").assertIsDisplayed()
        ui.activityRule.scenario.recreate()
        ui.onNodeWithContentDescription("設定").assertIsDisplayed()
        ui.runOnUiThread {
            model = ViewModelProvider(ui.activity)[EditorModel::class.java]
            assertEquals("zh", model.language.value)
            assertEquals("dark", model.theme.value)
        }
    }
    @Test fun fullScreenKeepsThePlayerAndCompareThenBackRestoresTheEditor() {
        val uri = ui.activity.contentResolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, "ui-full-${System.nanoTime()}.mp4")
            put(MediaStore.MediaColumns.MIME_TYPE, "video/mp4")
        })!!
        uris += uri
        ui.activity.contentResolver.openOutputStream(uri)!!.use { output ->
            InstrumentationRegistry.getInstrumentation().context.assets.open("audit-video.mp4").use { it.copyTo(output) }
        }
        ui.runOnUiThread { model.import(uri) }
        ui.waitUntil(30_000) { var found = false; ui.runOnUiThread { found = findPlayer(ui.activity.window.decorView)?.player != null }; found }
        var before: Any? = null
        ui.runOnUiThread { before = findPlayer(ui.activity.window.decorView)!!.player }
        ui.onNodeWithContentDescription("Full screen").performClick()
        ui.onNodeWithContentDescription("Exit full screen").assertIsDisplayed()
        ui.onNodeWithTag("adjustments").assertDoesNotExist()
        ui.onNodeWithContentDescription("Export").assertDoesNotExist()
        ui.runOnIdle { assertSame("Full screen must reuse the running player", before, findPlayer(ui.activity.window.decorView)!!.player) }
        ui.onNodeWithText("Hold to compare").performTouchInput { down(center) }
        ui.waitForIdle()
        ui.runOnIdle { assertTrue(model.compare.value) }
        ui.onNodeWithText("ORIGINAL").assertIsDisplayed()
        ui.onNodeWithText("Hold to compare").performTouchInput { up() }
        ui.waitForIdle()
        ui.runOnIdle { assertFalse(model.compare.value) }
        ui.runOnUiThread { ui.activity.onBackPressedDispatcher.onBackPressed() }
        ui.onNodeWithContentDescription("Full screen").assertIsDisplayed()
        ui.onNodeWithTag("adjustments").assertExists()
        ui.runOnIdle { assertSame(before, findPlayer(ui.activity.window.decorView)!!.player) }
    }

    @Test fun closeAsksBeforeDiscardingAndReturnsHome() {
        val file = File(ui.activity.cacheDir, "ui-close.png")
        val bitmap = Bitmap.createBitmap(320, 180, Bitmap.Config.ARGB_8888).apply { eraseColor(0xff205f9f.toInt()) }
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }; bitmap.recycle()
        ui.runOnUiThread { model.import(Uri.fromFile(file)) }
        ui.waitUntil(15_000) { model.previewGraded.value != null }
        ui.onNodeWithContentDescription("Close").performClick()
        ui.onNodeWithText("Keep editing").performClick()
        ui.onNodeWithTag("mediaPreview").assertIsDisplayed()
        ui.onNodeWithContentDescription("Close").performClick()
        ui.onNodeWithText("Discard").performClick()
        ui.onNodeWithText("Import video or photo").assertIsDisplayed()
        ui.runOnIdle { assertNull(model.source.value) }
    }

    @Test fun primarySliderCompareAndExportWorkThroughVisibleControls() {
        val file = File(ui.activity.cacheDir, "ui-photo.png")
        val bitmap = Bitmap.createBitmap(640, 360, Bitmap.Config.ARGB_8888).apply { eraseColor(0xff205f9f.toInt()) }
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }; bitmap.recycle()
        ui.runOnUiThread { model.import(Uri.fromFile(file)) }
        ui.waitUntil(15_000) { model.previewGraded.value != null }
        ui.onNode(SemanticsMatcher.keyIsDefined(SemanticsActions.SetProgress)).assertIsDisplayed()
        ui.onNodeWithText("Hold to compare").performTouchInput { down(center) }
        ui.runOnIdle { assertTrue(model.compare.value) }
        ui.onNodeWithText("Hold to compare").performTouchInput { up() }
        ui.runOnIdle { assertFalse(model.compare.value) }
        ui.onNode(SemanticsMatcher.keyIsDefined(SemanticsActions.SetProgress)).performSemanticsAction(SemanticsActions.SetProgress) { it(0f) }
        ui.waitUntil(10_000) { model.previewOriginal.value!!.getPixel(50, 50) == model.previewGraded.value!!.getPixel(50, 50) }
        ui.runOnIdle { assertFalse(model.compare.value) }
        ui.onNodeWithText("RESTORED").assertIsDisplayed()
        ui.onNodeWithText("Advanced adjustments").performScrollTo().performClick()
        ui.onNodeWithText("Shadows").performScrollTo().assertIsDisplayed()
        ui.onNodeWithTag("mediaPreview").assertIsDisplayed()
        ui.onNodeWithText("Hold to compare").performTouchInput { down(center) }
        ui.runOnIdle { assertTrue(model.compare.value) }
        ui.onNodeWithText("Hold to compare").performTouchInput { cancel() }
        ui.runOnIdle { assertFalse(model.compare.value) }
        ui.onNodeWithContentDescription("Export").performClick()
        ui.onNodeWithText("Original").assertIsDisplayed()
        ui.onNodeWithText("Start export").performClick()
        // A notification permission sheet is not required for foreground export completion.
        ui.waitUntil(20_000) { Exports.status.value.uri != null }
        val saved = Exports.status.value.uri!!
        uris += saved
        ui.onNodeWithText("Saved to your gallery", useUnmergedTree = true).assertExists()
        // The result is a dialog; no scrolling to discover whether export succeeded.
        ui.onNodeWithText("Done").performClick()
        ui.runOnIdle { assertNull(Exports.status.value.uri) }
        file.delete()
    }
    private fun findPlayer(view: View): PlayerView? {
        if (view is PlayerView) return view
        if (view is ViewGroup) for (i in 0 until view.childCount) findPlayer(view.getChildAt(i))?.let { return it }
        return null
    }
    @Test fun pausedVideoPositionAndPlayIntentSurviveRecreation() {
        val uri = ui.activity.contentResolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, "ui-video-${System.nanoTime()}.mp4")
            put(MediaStore.MediaColumns.MIME_TYPE, "video/mp4")
        })!!
        uris += uri
        ui.activity.contentResolver.openOutputStream(uri)!!.use { output ->
            InstrumentationRegistry.getInstrumentation().context.assets.open("audit-video.mp4").use { it.copyTo(output) }
        }
        ui.runOnUiThread { model.import(uri) }
        ui.waitUntil(30_000) { model.previewUri.value != null }
        fun playerReady(): Boolean {
            var ready = false
            ui.runOnUiThread { ready = findPlayer(ui.activity.window.decorView)?.player?.playbackState == Player.STATE_READY }
            return ready
        }
        ui.waitUntil(20_000) { playerReady() }
        ui.runOnUiThread { findPlayer(ui.activity.window.decorView)!!.player!!.apply { pause(); seekTo(800) } }
        ui.waitUntil(10_000) { playerReady() }
        fun sampledScreen(): IntArray {
            // Effects such as the compare press and the paused-frame refresh run on Compose's test clock,
            // which sleeping does not advance: move it past the refresh throttle first.
            ui.waitForIdle()
            ui.mainClock.advanceTimeBy(300)
            ui.waitForIdle()
            val origin = IntArray(2)
            var width = 0; var height = 0
            ui.runOnUiThread {
                findPlayer(ui.activity.window.decorView)!!.apply {
                    hideController(); getLocationOnScreen(origin); width = this.width; height = this.height
                }
            }
            // Wait for the seek, GL rendering and SurfaceView composition, not just Compose state.
            Thread.sleep(250)
            val screen = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
            assertNotNull(screen)
            return IntArray(200) { i ->
                screen.getPixel(origin[0] + width * (10 + (i % 20) * 4) / 100,
                    origin[1] + height * (30 + (i / 20) * 4) / 100)
            }.also { screen.recycle() }
        }
        ui.onNodeWithText("Hold to compare").performTouchInput { down(center) }
        val uncorrected = sampledScreen()
        ui.onNodeWithText("Hold to compare").performTouchInput { up() }
        ui.runOnUiThread { model.setGrade(Grade.Blue) }
        val corrected = sampledScreen()
        val difference = corrected.indices.sumOf { i ->
            listOf(0, 8, 16).sumOf { shift -> kotlin.math.abs((corrected[i] ushr shift and 255) - (uncorrected[i] ushr shift and 255)) }
        }.toDouble() / (corrected.size * 3)
        assertTrue("Paused video pixels did not update: mean difference $difference", difference > 3.0)
        ui.onNodeWithText("Video speed").performClick()
        ui.onNodeWithText("2×").performClick()
        ui.runOnIdle { assertEquals(2f, findPlayer(ui.activity.window.decorView)!!.player!!.playbackParameters.speed, 0f) }
        ui.activityRule.scenario.recreate()
        ui.waitUntil(20_000) { playerReady() }
        ui.runOnUiThread {
            model = ViewModelProvider(ui.activity)[EditorModel::class.java]
            val player = findPlayer(ui.activity.window.decorView)!!.player!!
            assertEquals(2f, player.playbackParameters.speed, 0f)
            assertFalse(player.playWhenReady)
            assertTrue("Position was reset to ${player.currentPosition}", player.currentPosition in 750..850)
        }
        ui.onNodeWithContentDescription("Export").performClick()
        ui.onNodeWithTag("estimatedSize").performScrollTo().assertIsDisplayed()
        ui.onNodeWithText("Custom").performScrollTo().performClick()
        ui.onNodeWithTag("estimatedSize").performScrollTo().assertIsDisplayed()
        val before = ui.onNodeWithTag("estimatedSize").fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsProperties.Text].toString()
        ui.onNodeWithText("Quality", substring = true).performScrollTo()
        // Select the quality slider in the dialog, excluding the editor's intensity slider.
        ui.onAllNodes(SemanticsMatcher.keyIsDefined(SemanticsActions.SetProgress)).onLast()
            .performSemanticsAction(SemanticsActions.SetProgress) { it(10f) }
        ui.onNodeWithTag("estimatedSize").performScrollTo()
        val after = ui.onNodeWithTag("estimatedSize").fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsProperties.Text].toString()
        assertNotEquals(before, after)
        ui.onNodeWithText("Cancel").performClick()

    }
}
