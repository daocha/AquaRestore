package com.aquarestore.app

import android.content.ClipData
import android.content.Intent
import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.launch

@Composable
fun SharePreview(items: List<ShareMedia>, s: Strings, busyChanged: (Boolean) -> Unit) {
    val context = LocalContext.current
    val pager = rememberPagerState { items.size }
    val scope = rememberCoroutineScope()
    var working by remember { mutableStateOf(false) }
    var notice by remember { mutableStateOf<String?>(null) }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        HorizontalPager(state = pager, modifier = Modifier.fillMaxWidth().height(230.dp).testTag("comparisonPager"), userScrollEnabled = !working) { page ->
            val item = items[page]
            if (item.video) {
                val player = remember(item.file) { ExoPlayer.Builder(context).build().apply {
                    setMediaItem(MediaItem.fromUri(android.net.Uri.fromFile(item.file)))
                    repeatMode = Player.REPEAT_MODE_ONE; volume = 0f; prepare()
                } }
                LaunchedEffect(pager.currentPage) { player.playWhenReady = pager.currentPage == page }
                val lifecycle = androidx.lifecycle.compose.LocalLifecycleOwner.current.lifecycle
                DisposableEffect(player, lifecycle) {
                    val observer = androidx.lifecycle.LifecycleEventObserver { _, event ->
                        if (event == androidx.lifecycle.Lifecycle.Event.ON_PAUSE) player.pause()
                        if (event == androidx.lifecycle.Lifecycle.Event.ON_RESUME && pager.currentPage == page) player.play()
                    }
                    lifecycle.addObserver(observer)
                    onDispose { lifecycle.removeObserver(observer); player.release() }
                }
                AndroidView(factory = { PlayerView(it).apply { useController = false; this.player = player } },
                    modifier = Modifier.fillMaxSize())
            } else {
                val bitmap by produceState<android.graphics.Bitmap?>(null, item.file) {
                    value = withContext(Dispatchers.IO) { BitmapFactory.decodeFile(item.file.path, BitmapFactory.Options().apply { inSampleSize = 2 }) }
                }
                bitmap?.let { Image(it.asImageBitmap(), s.text("Original and restored", "原始與還原比較"), Modifier.fillMaxSize(), contentScale = ContentScale.Fit) }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
            items.indices.forEach { index -> TextButton(onClick = { scope.launch { pager.animateScrollToPage(index) } }, enabled = !working,
                contentPadding = PaddingValues(2.dp), modifier = Modifier.size(28.dp)) { Text(if (index == pager.currentPage) "●" else "○") } }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            fun save(share: Boolean) {
                working = true; busyChanged(true); notice = null
                scope.launch {
                    try {
                        val item = items[pager.currentPage]
                        val uri = ShareMediaMaker.save(context, item)
                        if (share) context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
                            type = item.mime
                            putExtra(Intent.EXTRA_STREAM, uri); clipData = ClipData.newRawUri("AquaRestore", uri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }, null))
                        else notice = s.text("Saved to your gallery", "已儲存至相簿")
                    } catch (_: Exception) { notice = s.text("Could not save or share. Please try again.", "無法儲存或分享，請再試一次。") }
                    finally { working = false; busyChanged(false) }
                }
            }
            TextButton(onClick = { save(false) }, enabled = !working) { Text(s.text("Download", "下載")) }
            Button(onClick = { save(true) }, enabled = !working) { Text(s.text("Share", "分享")) }
            if (working) CircularProgressIndicator(Modifier.padding(8.dp).size(20.dp))
        }
        notice?.let { Text(it) }
    }
}
