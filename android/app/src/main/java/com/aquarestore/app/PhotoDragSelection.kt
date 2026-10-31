package com.aquarestore.app

import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.awaitLongPressOrCancellation
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.isActive

/** Keep the selection from before the gesture so reversing direction restores photos outside its range. */
internal class PhotoRangeSelection(private val photos: List<String>, selected: List<String>, private val anchor: Int,
    private val limit: Int = MAX_BATCH_PHOTOS) {
    private val original = selected.toSet()
    private val selecting = photos[anchor] !in original

    fun through(index: Int): ArrayList<String> {
        val result = original.toMutableSet()
        val range = if (index >= anchor) anchor..index else anchor downTo index
        for (i in range) {
            if (selecting) {
                if (result.size >= limit) break
                result += photos[i]
            } else result -= photos[i]
        }
        return ArrayList(result)
    }
}

internal val PHOTO_GRID_PADDING = 8.dp

/** [padding] is the grid's content padding: item offsets exclude it, while pointer positions include it. */
private fun LazyGridState.photoAt(touch: Offset, padding: Float, nearest: Boolean = false): Int? {
    val visible = layoutInfo.visibleItemsInfo
    val point = touch - Offset(padding, padding)
    fun distance(index: Int): Float {
        val item = visible[index]
        val dx = maxOf(item.offset.x - point.x, 0f, point.x - item.offset.x - item.size.width)
        val dy = maxOf(item.offset.y - point.y, 0f, point.y - item.offset.y - item.size.height)
        return dx * dx + dy * dy
    }
    val closest = visible.indices.minByOrNull(::distance) ?: return null
    return visible[closest].index.takeIf { nearest || distance(closest) == 0f }
}

/** A normal swipe scrolls; a swipe after holding a photo selects or deselects a range. */
@Composable
internal fun Modifier.photoDragSelection(state: LazyGridState, photos: List<String>, selected: List<String>,
    contentPadding: Dp, limit: Int = MAX_BATCH_PHOTOS, onSelectionChange: (ArrayList<String>) -> Unit): Modifier {
    val latestSelected by rememberUpdatedState(selected)
    val changeSelection by rememberUpdatedState(onSelectionChange)
    val haptic = LocalHapticFeedback.current
    val padding = with(LocalDensity.current) { contentPadding.toPx() }
    val edge = with(LocalDensity.current) { 56.dp.toPx() }
    val scrollSpeed = with(LocalDensity.current) { 900.dp.toPx() }
    var gesture by remember(photos) { mutableStateOf<PhotoRangeSelection?>(null) }
    var position by remember(photos) { mutableStateOf(Offset.Zero) }
    val scrollDirection by remember(state, edge, photos) {
        derivedStateOf {
            val height = state.layoutInfo.viewportSize.height
            when {
                gesture == null -> 0f
                position.y < edge -> ((position.y - edge) / edge).coerceIn(-1f, 0f)
                position.y > height - edge -> ((position.y - height + edge) / edge).coerceIn(0f, 1f)
                else -> 0f
            }
        }
    }

    fun updateRange() {
        val active = gesture ?: return
        val index = state.photoAt(position, padding, nearest = true) ?: return
        changeSelection(active.through(index))
    }

    // Keep extending the range as rows scroll underneath a stationary finger near either edge.
    // Keyed on whether to scroll, not the speed, so finger jitter does not restart it and drop frames.
    LaunchedEffect(scrollDirection != 0f) {
        var previousFrame = 0L
        while (isActive && scrollDirection != 0f) {
            val frame = withFrameNanos { it }
            val seconds = if (previousFrame == 0L) 0f else ((frame - previousFrame) / 1_000_000_000f).coerceAtMost(0.032f)
            previousFrame = frame
            if (state.scrollBy(scrollDirection * scrollSpeed * seconds) != 0f) updateRange()
        }
    }
    return pointerInput(photos, state, padding, limit) {
        awaitEachGesture {
            val down = awaitFirstDown(requireUnconsumed = false)
            val held = awaitLongPressOrCancellation(down.id) ?: return@awaitEachGesture
            val index = state.photoAt(held.position, padding) ?: return@awaitEachGesture
            if (latestSelected.size >= limit && photos[index] !in latestSelected) return@awaitEachGesture
            position = held.position
            gesture = PhotoRangeSelection(photos, latestSelected, index, limit)
            updateRange()
            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
            try {
                while (true) {
                    // Claim held drags before the grid's scroll handler sees the movement.
                    val event = awaitPointerEvent(PointerEventPass.Initial)
                    val change = event.changes.firstOrNull { it.id == held.id } ?: break
                    change.consume()
                    if (!change.pressed) break
                    position = change.position
                    updateRange()
                }
            } finally { gesture = null }
        }
    }
}
