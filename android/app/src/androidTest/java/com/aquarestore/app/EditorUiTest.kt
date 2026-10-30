package com.aquarestore.app

import android.content.ContentValues
import android.graphics.Bitmap
import android.net.Uri
import android.provider.MediaStore
import android.view.View
import android.view.ViewGroup
import androidx.compose.ui.geometry.Offset
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
        Exports.status.value.batch?.saved?.let { uris += it }
        uris.forEach { ui.activity.contentResolver.delete(it, null, null) }
        ui.runOnUiThread { model.preference("language", "system"); model.preference("theme", "system") }
    }
    @Test fun batchLongPressDragSelectsDeselectsAndScrollsTo100PhotoLimit() {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        val permission = if (android.os.Build.VERSION.SDK_INT >= 33) "android.permission.READ_MEDIA_IMAGES" else "android.permission.READ_EXTERNAL_STORAGE"
        automation.executeShellCommand("pm grant ${ui.activity.packageName} $permission").use { fd ->
            java.io.FileInputStream(fd.fileDescriptor).use { it.readBytes() }
        }
        val album = "Pictures/BatchDrag-${System.nanoTime()}"
        val names = List(MAX_BATCH_PHOTOS + 30) { "drag-${it.toString().padStart(3, '0')}.png" }
        val bitmap = Bitmap.createBitmap(32, 32, Bitmap.Config.ARGB_8888).apply { eraseColor(0xff205f9f.toInt()) }
        names.forEach { name ->
            val uri = ui.activity.contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, "image/png")
                put(MediaStore.MediaColumns.RELATIVE_PATH, album)
            })!!
            uris += uri
            ui.activity.contentResolver.openOutputStream(uri)!!.use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        }
        bitmap.recycle()
        ui.runOnUiThread {
            ui.activity.getSharedPreferences("preferences", 0).edit()
                .putString("library_photos_section", "albums").putString("library_photos_album", album)
                .putString("library_photos_sort", LibrarySort.NAME_AZ.name).apply()
        }
        ui.onNodeWithText("Batch restore photos").performScrollTo().performClick()
        ui.waitUntil(15_000) { ui.onAllNodesWithTag("libraryPhotos").fetchSemanticsNodes().isNotEmpty() }
        fun center(index: Int): Offset = ui.onNodeWithText(names[index]).fetchSemanticsNode().boundsInRoot.center -
            ui.onNodeWithTag("libraryPhotos").fetchSemanticsNode().boundsInRoot.topLeft
        fun check(index: Int, selected: Boolean) {
            ui.onNodeWithTag("libraryPhotos").performScrollToNode(hasText(names[index]))
            if (selected) ui.onNodeWithText(names[index]).assertIsSelected() else ui.onNodeWithText(names[index]).assertIsNotSelected()
        }
        val hold = android.view.ViewConfiguration.getLongPressTimeout().toLong() + 150
        // Keep an unrelated selection; reverse the drag before lifting to shrink its range.
        ui.onNodeWithText(names[6]).performClick()
        var start = center(0); val second = center(1); val fourth = center(3)
        ui.onNodeWithTag("libraryPhotos").performTouchInput {
            down(start); advanceEventTime(hold); moveTo(fourth, 250); moveTo(second, 250); up()
        }
        ui.onNodeWithText("Continue (3)").assertIsEnabled()
        check(0, true); check(1, true); check(2, false); check(3, false); check(6, true)
        start = center(0)
        val end = center(1)
        ui.onNodeWithTag("libraryPhotos").performTouchInput {
            down(start); advanceEventTime(hold); moveTo(end, 250); up()
        }
        ui.onNodeWithText("Continue (1)").assertIsEnabled()
        check(0, false); check(1, false); check(6, true)
        // A swipe without a hold still scrolls without altering the selection.
        ui.onNodeWithTag("libraryPhotos").performTouchInput { swipeUp() }
        ui.onNodeWithText("Continue (1)").assertIsEnabled()
        check(6, true)
        ui.onNodeWithText(names[6]).performClick()
        ui.onNodeWithTag("libraryPhotos").performScrollToNode(hasText(names[0]))
        start = center(0)
        ui.onNodeWithTag("libraryPhotos").performTouchInput {
            down(start); advanceEventTime(hold)
            moveTo(Offset(start.x, height - 2f), 350)
            // Deliver frames while the finger stays near the edge, as on a real touchscreen.
            repeat(400) { moveBy(Offset.Zero, 16) }
            up()
        }
        ui.onNodeWithText("Continue (", substring = true).assertTextEquals("Continue (100)").assertIsEnabled()
        check(99, true)
        check(100, false)
        ui.onNodeWithText(names[100]).assertIsNotEnabled()
        ui.onNodeWithText("Continue (100)").performClick()
        ui.onNodeWithText("Export 100 photos").assertIsDisplayed()
        ui.onNodeWithText("Cancel").performClick()
        ui.onNodeWithText("Continue (100)").assertIsEnabled()
        check(99, true)
        ui.onNodeWithText("Continue (100)").performClick()
        ui.onNodeWithText("Start export").performClick()
        ui.waitUntil(60_000) { !Exports.status.value.busy && Exports.status.value.batch?.completed == 100 }
        ui.runOnIdle {
            assertEquals(100, Exports.status.value.batch!!.saved.size)
            assertTrue(Exports.status.value.batch!!.failures.isEmpty())
        }
        ui.onNodeWithText("Choose photos").assertDoesNotExist()
    }
    @Test fun batchExportOptionsDismissalKeepsSelectionAndQualitySettings() {
        val selectionCount = 5
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        val permission = if (android.os.Build.VERSION.SDK_INT >= 33) "android.permission.READ_MEDIA_IMAGES" else "android.permission.READ_EXTERNAL_STORAGE"
        automation.executeShellCommand("pm grant ${ui.activity.packageName} $permission").use { fd ->
            java.io.FileInputStream(fd.fileDescriptor).use { it.readBytes() }
        }
        val names = (0..selectionCount).map { "batch-ui-${System.nanoTime()}-$it.png" }
        val bitmap = Bitmap.createBitmap(32, 32, Bitmap.Config.ARGB_8888).apply { eraseColor(0xff205f9f.toInt()) }
        names.forEach { name ->
            val uri = ui.activity.contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, "image/png")
                put(MediaStore.MediaColumns.RELATIVE_PATH, "Pictures/BatchUi")
                put(MediaStore.MediaColumns.DATE_TAKEN, System.currentTimeMillis())
            })!!
            uris += uri
            ui.activity.contentResolver.openOutputStream(uri)!!.use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        }
        bitmap.recycle()
        ui.runOnUiThread {
            ui.activity.getSharedPreferences("preferences", 0).edit().putString("library_photos_section", "recent").apply()
            model.setExportSelection(false, ExportSelection())
        }
        ui.onNodeWithText("Batch restore photos").performScrollTo().performClick()
        ui.onNodeWithText("Choose photos").assertIsDisplayed()
        ui.onNodeWithText("Continue (0)").assertIsNotEnabled()
        fun pick(name: String) {
            ui.onNodeWithTag("libraryPhotos").performScrollToNode(hasText(name))
            ui.onNodeWithText(name).performClick()
        }
        names.take(selectionCount).forEach(::pick)
        ui.onNodeWithText("Continue ($selectionCount)").assertIsEnabled()
        ui.onNodeWithTag("libraryPhotos").performScrollToNode(hasText(names.last()))
        ui.onNodeWithText(names.last()).assertIsNotSelected()
        pick(names.first())
        pick(names.last())
        ui.activityRule.scenario.recreate()
        ui.onNodeWithText("Continue ($selectionCount)").performClick()
        ui.onNodeWithText("Export $selectionCount photos").assertIsDisplayed()
        ui.onNodeWithTag("estimatedSize").assertDoesNotExist()
        ui.onNodeWithText("Custom").performClick()
        ui.onNodeWithText("Quality", substring = true).performScrollTo().assertIsDisplayed()
        ui.onNodeWithText("PNG").performScrollTo().performClick()
        ui.onNodeWithText("Quality", substring = true).assertDoesNotExist()
        ui.onNodeWithText("Original").performScrollTo().performClick()
        ui.onNodeWithText("JPEG").performClick()
        ui.onNodeWithTag("estimatedSize").assertDoesNotExist()
        ui.onNodeWithText("Cancel").performClick()
        fun assertSelectionKept() {
            ui.onNodeWithText("Choose photos").assertIsDisplayed()
            ui.onNodeWithText("Continue ($selectionCount)").assertIsEnabled()
            names.drop(1).forEach { name ->
                ui.onNodeWithTag("libraryPhotos").performScrollToNode(hasText(name))
                ui.onNodeWithText(name).assertIsSelected()
            }
            ui.onNodeWithTag("libraryPhotos").performScrollToNode(hasText(names.first()))
            ui.onNodeWithText(names.first()).assertIsNotSelected()
        }
        assertSelectionKept()
        ui.onNodeWithText("Continue ($selectionCount)").performClick()
        // The left edge is outside the centered export dialog and inside the photo picker behind it.
        val time = android.os.SystemClock.uptimeMillis()
        listOf(android.view.MotionEvent.ACTION_DOWN, android.view.MotionEvent.ACTION_UP).forEach { action ->
            android.view.MotionEvent.obtain(time, time + if (action == android.view.MotionEvent.ACTION_UP) 50 else 0,
                action, 2f, ui.activity.resources.displayMetrics.heightPixels / 2f, 0).also { event ->
                event.source = android.view.InputDevice.SOURCE_TOUCHSCREEN
                automation.injectInputEvent(event, true)
                event.recycle()
            }
        }
        ui.waitForIdle()
        assertSelectionKept()
        ui.onNodeWithText("Continue ($selectionCount)").performClick()
        ui.activityRule.scenario.recreate()
        ui.onNodeWithText("Export $selectionCount photos").assertIsDisplayed()
        listOf(android.view.KeyEvent.ACTION_DOWN, android.view.KeyEvent.ACTION_UP).forEach { action ->
            automation.injectInputEvent(android.view.KeyEvent(action, android.view.KeyEvent.KEYCODE_BACK), true)
        }
        ui.waitForIdle()
        assertSelectionKept()
        ui.onNodeWithContentDescription("Close").performClick()
        ui.onNodeWithText("Batch restore photos").assertExists()
        ui.runOnUiThread {
            model = ViewModelProvider(ui.activity)[EditorModel::class.java]
            assertTrue(model.batchPhotos.value.isEmpty())
            assertNull(model.source.value)
        }
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
        ui.onNodeWithText("Compare").performTouchInput { down(center) }
        ui.waitForIdle()
        ui.runOnIdle { assertTrue(model.compare.value) }
        ui.onNodeWithText("ORIGINAL").assertIsDisplayed()
        ui.onNodeWithText("Compare").performTouchInput { up() }
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
        ui.onNodeWithText("Compare").performTouchInput { down(center) }
        ui.runOnIdle { assertTrue(model.compare.value) }
        ui.onNodeWithText("Compare").performTouchInput { up() }
        ui.runOnIdle { assertFalse(model.compare.value) }
        ui.onNode(SemanticsMatcher.keyIsDefined(SemanticsActions.SetProgress)).performSemanticsAction(SemanticsActions.SetProgress) { it(0f) }
        ui.waitUntil(10_000) { model.previewOriginal.value!!.getPixel(50, 50) == model.previewGraded.value!!.getPixel(50, 50) }
        ui.runOnIdle { assertFalse(model.compare.value) }
        ui.onNodeWithText("RESTORED").assertIsDisplayed()
        ui.onNodeWithText("Advanced adjustments").performScrollTo().performClick()
        ui.onNodeWithText("Shadows").performScrollTo().assertIsDisplayed()
        ui.onNodeWithTag("mediaPreview").assertIsDisplayed()
        ui.onNodeWithText("Compare").performTouchInput { down(center) }
        ui.runOnIdle { assertTrue(model.compare.value) }
        ui.onNodeWithText("Compare").performTouchInput { cancel() }
        ui.runOnIdle { assertFalse(model.compare.value) }
        ui.onNodeWithContentDescription("Export").performClick()
        ui.onNodeWithText("Original").assertIsDisplayed()
        ui.onNodeWithText("Custom").performClick()
        ui.onNodeWithText("Cancel").performClick()
        ui.onNodeWithContentDescription("Export").performClick()
        ui.onNodeWithText("Custom").assertIsSelected()
        ui.onNodeWithText("Original").performClick()
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
        ui.onNodeWithText("Compare").performTouchInput { down(center) }
        val uncorrected = sampledScreen()
        ui.onNodeWithText("Compare").performTouchInput { up() }
        ui.runOnUiThread { model.setGrade(Grade.Blue) }
        val corrected = sampledScreen()
        val difference = corrected.indices.sumOf { i ->
            listOf(0, 8, 16).sumOf { shift -> kotlin.math.abs((corrected[i] ushr shift and 255) - (uncorrected[i] ushr shift and 255)) }
        }.toDouble() / (corrected.size * 3)
        assertTrue("Paused video pixels did not update: mean difference $difference", difference > 3.0)
        ui.onNodeWithContentDescription("Video speed").performClick()
        ui.onNodeWithContentDescription("Video speed").assertDoesNotExist()
        ui.onNodeWithTag("mediaPreview").performTouchInput { click(center) }
        ui.onNodeWithContentDescription("Video speed").assertExists()
        ui.onNodeWithContentDescription("Video speed").performClick()
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
        ui.onNodeWithContentDescription("Trim range").performTouchInput { click(center) }
        ui.onNodeWithContentDescription("Set start").assertExists()
        ui.onNodeWithContentDescription("Set end").assertExists()
        ui.onNodeWithContentDescription("Video speed").assertDoesNotExist()
        ui.runOnIdle { assertFalse(findPlayer(ui.activity.window.decorView)!!.player!!.playWhenReady) }
        // A second tap seeks immediately, even while the trim actions are visible.
        ui.onNodeWithContentDescription("Trim range").performTouchInput {
            click(Offset(width * 0.75f, height / 2f))
        }
        val threeQuarters = model.source.value!!.durationMs * 3 / 4
        ui.waitUntil(10_000) {
            var position = 0L
            ui.runOnUiThread { position = findPlayer(ui.activity.window.decorView)!!.player!!.currentPosition }
            position in (threeQuarters - 150)..(threeQuarters + 150)
        }
        ui.runOnIdle { assertFalse(findPlayer(ui.activity.window.decorView)!!.player!!.playWhenReady) }
        ui.onNodeWithContentDescription("Trim range").performTouchInput {
            down(Offset(width * 0.75f, height / 2f))
            moveTo(Offset(width * 0.25f, height / 2f))
            up()
        }
        val oneQuarter = model.source.value!!.durationMs / 4
        ui.waitUntil(10_000) {
            var position = 0L
            ui.runOnUiThread { position = findPlayer(ui.activity.window.decorView)!!.player!!.currentPosition }
            position in (oneQuarter - 150)..(oneQuarter + 150)
        }
        ui.runOnIdle { assertFalse(findPlayer(ui.activity.window.decorView)!!.player!!.playWhenReady) }
        ui.onNodeWithTag("mediaPreview").performTouchInput { click(center) }
        ui.onNodeWithContentDescription("Video speed").assertExists()
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
