package com.aquarestore.app

import android.Manifest
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Size
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.ArrowDropDown
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.PlayCircle
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.core.content.ContextCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private data class LibraryItem(val uri: Uri, val name: String, val video: Boolean, val audio: Boolean,
    val albumId: String, val albumName: String)
private data class LibraryAlbum(val id: String, val name: String, val cover: LibraryItem, val count: Int)

private fun mediaPermissions(audioOnly: Boolean): Array<String> = when {
    audioOnly && Build.VERSION.SDK_INT >= 33 -> arrayOf(Manifest.permission.READ_MEDIA_AUDIO)
    Build.VERSION.SDK_INT >= 34 -> arrayOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VIDEO,
        Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
    Build.VERSION.SDK_INT >= 33 -> arrayOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VIDEO)
    else -> arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
}

private fun hasMediaAccess(context: Context, audioOnly: Boolean) = mediaPermissions(audioOnly).any {
    ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
}

private fun loadLibrary(context: Context, audioOnly: Boolean): List<LibraryItem> {
    val collection = MediaStore.Files.getContentUri("external")
    val id = MediaStore.Files.FileColumns._ID
    val type = MediaStore.Files.FileColumns.MEDIA_TYPE
    val name = MediaStore.MediaColumns.DISPLAY_NAME
    val path = MediaStore.MediaColumns.RELATIVE_PATH
    val selection = if (audioOnly) "$type=?" else "($type=? OR $type=?)"
    val args = if (audioOnly) arrayOf(MediaStore.Files.FileColumns.MEDIA_TYPE_AUDIO.toString())
        else arrayOf(MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE.toString(), MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO.toString())
    val result = mutableListOf<LibraryItem>()
    context.contentResolver.query(collection, arrayOf(id, type, name, path), selection, args,
        "${MediaStore.MediaColumns.DATE_ADDED} DESC")?.use { cursor ->
        val idColumn = cursor.getColumnIndexOrThrow(id)
        val typeColumn = cursor.getColumnIndexOrThrow(type)
        val nameColumn = cursor.getColumnIndexOrThrow(name)
        val pathColumn = cursor.getColumnIndexOrThrow(path)
        while (cursor.moveToNext()) {
            val albumId = cursor.getString(pathColumn)?.trim('/')?.ifEmpty { "Other" } ?: "Other"
            result += LibraryItem(ContentUris.withAppendedId(collection, cursor.getLong(idColumn)),
                cursor.getString(nameColumn).orEmpty(), cursor.getInt(typeColumn) == MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO,
                cursor.getInt(typeColumn) == MediaStore.Files.FileColumns.MEDIA_TYPE_AUDIO,
                albumId, albumId.substringAfterLast('/'))
        }
    }
    return result
}

@Composable
fun MediaLibrary(s: Strings, audioOnly: Boolean = false, onDismiss: () -> Unit, onChoose: (Uri) -> Unit) {
    val context = LocalContext.current
    var allowed by remember(audioOnly) { mutableStateOf(hasMediaAccess(context, audioOnly)) }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        allowed = hasMediaAccess(context, audioOnly)
    }
    LaunchedEffect(audioOnly) { if (!allowed) permission.launch(mediaPermissions(audioOnly)) }
    val items by produceState<List<LibraryItem>?>(null, allowed) {
        value = if (allowed) withContext(Dispatchers.IO) { runCatching { loadLibrary(context, audioOnly) }.getOrDefault(emptyList()) }
            else emptyList()
    }
    // Opens where it was last left (Recent or an album), separately for media and music.
    val prefs = remember { context.getSharedPreferences("preferences", 0) }
    val key = if (audioOnly) "library_music_" else "library_media_"
    var section by rememberSaveable(audioOnly) { mutableStateOf(prefs.getString(key + "section", null) ?: "recent") }
    var selectedAlbum by rememberSaveable(audioOnly) { mutableStateOf(prefs.getString(key + "album", null)) }
    LaunchedEffect(section, selectedAlbum) {
        prefs.edit().putString(key + "section", section).putString(key + "album", selectedAlbum).apply()
    }
    var menuExpanded by remember { mutableStateOf(false) }
    val albums = remember(items) {
        items.orEmpty().groupBy { it.albumId }.map { (id, members) ->
            LibraryAlbum(id, members.first().albumName, members.first(), members.size)
        }
    }
    // A remembered album that is gone (deleted or emptied) falls back to Recent.
    LaunchedEffect(albums) {
        if (items != null && selectedAlbum != null && albums.none { it.id == selectedAlbum }) {
            section = "recent"
            selectedAlbum = null
        }
    }
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            Column {
                Row(Modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(if (audioOnly) s.text("Choose music", "選擇音樂") else s.text("Choose video or photo", "選擇影片或照片"),
                        Modifier.weight(1f), style = MaterialTheme.typography.titleLarge)
                    IconButton(onClick = onDismiss) { Icon(Icons.Rounded.Close, s.text("Close", "關閉")) }
                }
                Box(Modifier.padding(horizontal = 12.dp)) {
                    TextButton(onClick = { menuExpanded = true }) {
                        Text(if (section == "recent") s.text("Recent", "最近") else s.text("Albums", "相簿"))
                        Icon(Icons.Rounded.ArrowDropDown, null)
                    }
                    DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                        DropdownMenuItem(text = { Text(s.text("Recent", "最近")) }, onClick = {
                            section = "recent"; selectedAlbum = null; menuExpanded = false
                        })
                        DropdownMenuItem(text = { Text(s.text("Albums", "相簿")) }, onClick = {
                            section = "albums"; selectedAlbum = null; menuExpanded = false
                        })
                    }
                }
                if (section == "albums" && selectedAlbum != null) Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = { selectedAlbum = null }) {
                        Icon(Icons.AutoMirrored.Rounded.ArrowBack, s.text("All albums", "所有相簿"))
                    }
                    Text(albums.firstOrNull { it.id == selectedAlbum }?.name.orEmpty(), style = MaterialTheme.typography.titleMedium)
                }
                when {
                    !allowed -> Column(Modifier.fillMaxSize().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center) {
                        Text(if (audioOnly) s.text("Allow access to your audio files to browse them here.", "允許存取音訊檔案，才能在此瀏覽。")
                            else s.text("Allow access to your videos and photos to browse them here.", "允許存取影片和照片，才能在此瀏覽。"))
                        Spacer(Modifier.height(16.dp))
                        Button(onClick = { permission.launch(mediaPermissions(audioOnly)) }) { Text(s.text("Allow access", "允許存取")) }
                    }
                    items == null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                    items!!.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(if (audioOnly) s.text("No audio files found", "找不到音訊檔案")
                            else s.text("No videos or photos found", "找不到影片或照片"))
                    }
                    section == "albums" && selectedAlbum == null -> LazyVerticalGrid(GridCells.Adaptive(110.dp), Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(albums, key = { it.id }) { album ->
                            LibraryCell(album.cover, "${album.name} · ${album.count}") { selectedAlbum = album.id }
                        }
                    }
                    else -> LazyVerticalGrid(GridCells.Adaptive(110.dp), Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(items!!.filter { section == "recent" || it.albumId == selectedAlbum }, key = { it.uri.toString() }) { item ->
                            LibraryCell(item) { onChoose(item.uri) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun LibraryCell(item: LibraryItem, label: String = item.name, onClick: () -> Unit) {
    val context = LocalContext.current
    val thumbnail by produceState<Bitmap?>(null, item.uri) {
        value = if (item.audio) null else withContext(Dispatchers.IO) {
            runCatching { context.contentResolver.loadThumbnail(item.uri, Size(260, 260), null) }.getOrNull()
        }
    }
    Column(Modifier.clip(RoundedCornerShape(10.dp)).clickable(onClick = onClick)) {
        Box(Modifier.fillMaxWidth().aspectRatio(1f), contentAlignment = Alignment.Center) {
            if (item.audio) Icon(Icons.Rounded.MusicNote, null, Modifier.size(48.dp))
            else thumbnail?.let { Image(it.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop) }
            if (item.video) Icon(Icons.Rounded.PlayCircle, null, Modifier.align(Alignment.BottomEnd).padding(6.dp))
        }
        Text(label, Modifier.padding(horizontal = 4.dp, vertical = 3.dp), maxLines = 1, overflow = TextOverflow.Ellipsis,
            style = MaterialTheme.typography.labelSmall)
    }
}
