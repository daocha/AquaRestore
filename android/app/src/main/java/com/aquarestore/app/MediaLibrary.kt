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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items as listItems
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.Sort
import androidx.compose.material.icons.rounded.ArrowDropDown
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Folder
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.core.content.ContextCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** [date] is when a photo or video was taken, or when the file was added if that is unknown, in milliseconds. */
private data class LibraryItem(val uri: Uri, val name: String, val video: Boolean, val audio: Boolean,
    val albumId: String, val albumName: String, val date: Long)
private data class LibraryAlbum(val id: String, val name: String, val cover: LibraryItem, val count: Int,
    val newest: Long, val oldest: Long)

internal enum class LibrarySort { NEWEST, OLDEST, NAME_AZ, NAME_ZA }

/** Sorts files or albums; equal names fall back to the newest first, equal dates to the name. */
internal fun <T> librarySorted(entries: List<T>, sort: LibrarySort, name: (T) -> String, date: (T) -> Long): List<T> {
    val byName = compareBy(String.CASE_INSENSITIVE_ORDER, name)
    val byDate = compareByDescending(date)
    return entries.sortedWith(when (sort) {
        LibrarySort.NEWEST -> byDate.then(byName)
        LibrarySort.OLDEST -> byDate.reversed().then(byName)
        LibrarySort.NAME_AZ -> byName.then(byDate)
        LibrarySort.NAME_ZA -> byName.reversed().then(byDate)
    })
}

private fun mediaPermissions(audioOnly: Boolean, photosOnly: Boolean): Array<String> = when {
    audioOnly && Build.VERSION.SDK_INT >= 33 -> arrayOf(Manifest.permission.READ_MEDIA_AUDIO)
    photosOnly && Build.VERSION.SDK_INT >= 34 -> arrayOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
    photosOnly && Build.VERSION.SDK_INT >= 33 -> arrayOf(Manifest.permission.READ_MEDIA_IMAGES)
    Build.VERSION.SDK_INT >= 34 -> arrayOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VIDEO,
        Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
    Build.VERSION.SDK_INT >= 33 -> arrayOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VIDEO)
    else -> arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
}

private fun hasMediaAccess(context: Context, audioOnly: Boolean, photosOnly: Boolean) = mediaPermissions(audioOnly, photosOnly).any {
    ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
}

private fun loadLibrary(context: Context, audioOnly: Boolean, photosOnly: Boolean): List<LibraryItem> {
    val collection = MediaStore.Files.getContentUri("external")
    val id = MediaStore.Files.FileColumns._ID
    val type = MediaStore.Files.FileColumns.MEDIA_TYPE
    val name = MediaStore.MediaColumns.DISPLAY_NAME
    val path = MediaStore.MediaColumns.RELATIVE_PATH
    val taken = MediaStore.MediaColumns.DATE_TAKEN
    val added = MediaStore.MediaColumns.DATE_ADDED
    val selection = if (audioOnly || photosOnly) "$type=?" else "($type=? OR $type=?)"
    val args = if (audioOnly) arrayOf(MediaStore.Files.FileColumns.MEDIA_TYPE_AUDIO.toString())
        else if (photosOnly) arrayOf(MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE.toString())
        else arrayOf(MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE.toString(), MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO.toString())
    val result = mutableListOf<LibraryItem>()
    context.contentResolver.query(collection, arrayOf(id, type, name, path, taken, added), selection, args,
        "$added DESC")?.use { cursor ->
        val idColumn = cursor.getColumnIndexOrThrow(id)
        val typeColumn = cursor.getColumnIndexOrThrow(type)
        val nameColumn = cursor.getColumnIndexOrThrow(name)
        val pathColumn = cursor.getColumnIndexOrThrow(path)
        val takenColumn = cursor.getColumnIndexOrThrow(taken)
        val addedColumn = cursor.getColumnIndexOrThrow(added)
        while (cursor.moveToNext()) {
            val albumId = cursor.getString(pathColumn)?.trim('/')?.ifEmpty { "Other" } ?: "Other"
            // Copied-in camera clips are added long after they were taken; audio has no date taken.
            val date = cursor.getLong(takenColumn).takeIf { it > 0 } ?: (cursor.getLong(addedColumn) * 1000)
            result += LibraryItem(ContentUris.withAppendedId(collection, cursor.getLong(idColumn)),
                cursor.getString(nameColumn).orEmpty(), cursor.getInt(typeColumn) == MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO,
                cursor.getInt(typeColumn) == MediaStore.Files.FileColumns.MEDIA_TYPE_AUDIO,
                albumId, albumId.substringAfterLast('/'), date)
        }
    }
    return result
}

@Composable
fun MediaLibrary(s: Strings, audioOnly: Boolean = false, photosOnly: Boolean = false,
    onChoosePhotos: ((List<Uri>) -> Unit)? = null, onDismiss: () -> Unit, onChoose: (Uri) -> Unit = {}) {
    val context = LocalContext.current
    val multiple = onChoosePhotos != null
    var chosen by rememberSaveable { mutableStateOf(arrayListOf<String>()) }
    var allowed by remember(audioOnly, photosOnly) { mutableStateOf(hasMediaAccess(context, audioOnly, photosOnly)) }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        allowed = hasMediaAccess(context, audioOnly, photosOnly)
    }
    LaunchedEffect(audioOnly, photosOnly) { if (!allowed) permission.launch(mediaPermissions(audioOnly, photosOnly)) }
    val items by produceState<List<LibraryItem>?>(null, allowed, audioOnly, photosOnly) {
        value = if (allowed) withContext(Dispatchers.IO) { runCatching { loadLibrary(context, audioOnly, photosOnly) }.getOrDefault(emptyList()) }
            else emptyList()
    }
    // Opens where it was last left, separately for media and music.
    val prefs = remember { context.getSharedPreferences("preferences", 0) }
    val key = if (audioOnly) "library_music_" else if (photosOnly) "library_photos_" else "library_media_"
    var section by rememberSaveable(audioOnly) { mutableStateOf(prefs.getString(key + "section", null) ?: "recent") }
    var selectedAlbum by rememberSaveable(audioOnly) { mutableStateOf(prefs.getString(key + "album", null)) }
    var sort by rememberSaveable(audioOnly) {
        mutableStateOf(runCatching { LibrarySort.valueOf(prefs.getString(key + "sort", null)!!) }.getOrDefault(LibrarySort.NEWEST))
    }
    LaunchedEffect(section, selectedAlbum, sort) {
        prefs.edit().putString(key + "section", section).putString(key + "album", selectedAlbum)
            .putString(key + "sort", sort.name).apply()
    }
    var menuExpanded by remember { mutableStateOf(false) }
    var sortExpanded by remember { mutableStateOf(false) }
    val albums = remember(items, sort) {
        val grouped = items.orEmpty().groupBy { it.albumId }.map { (id, members) ->
            LibraryAlbum(id, members.first().albumName, members.first(), members.size,
                members.maxOf { it.date }, members.minOf { it.date })
        }
        librarySorted(grouped, sort, { it.name }, { if (sort == LibrarySort.OLDEST) it.oldest else it.newest })
    }
    val shown = remember(items, sort, section, selectedAlbum) {
        librarySorted(items.orEmpty().filter { section == "recent" || it.albumId == selectedAlbum }, sort, { it.name }, { it.date })
    }
    val photoGrid = key(section, selectedAlbum, sort) { rememberLazyGridState() }
    val photoKeys = remember(shown) { shown.map { it.uri.toString() } }
    // A remembered folder or album that is gone falls back to Recent.
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
                    Text(if (audioOnly) s.text("Choose music", "選擇音樂") else if (photosOnly) s.text("Choose photos", "選擇照片") else s.text("Choose video or photo", "選擇影片或照片"),
                        Modifier.weight(1f), style = MaterialTheme.typography.titleLarge)
                    IconButton(onClick = onDismiss) { Icon(Icons.Rounded.Close, s.text("Close", "關閉")) }
                }
                if (multiple) Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
                    Text(s.text("${chosen.size} / $MAX_BATCH_PHOTOS selected · Photos only", "已選 ${chosen.size}／$MAX_BATCH_PHOTOS 張 · 僅限照片"),
                        style = MaterialTheme.typography.labelLarge)
                    Text(s.text("Select up to $MAX_BATCH_PHOTOS photos per batch.", "每批最多選擇 $MAX_BATCH_PHOTOS 張照片。"),
                        style = MaterialTheme.typography.bodySmall)
                    Text(s.text("Hold a photo, then drag to select or deselect more.", "長按照片後滑動，即可選取或取消選取多張照片。"),
                        style = MaterialTheme.typography.bodySmall)
                    Button(onClick = { onChoosePhotos?.invoke(chosen.map(Uri::parse)) }, enabled = chosen.isNotEmpty(),
                        modifier = Modifier.fillMaxWidth()) { Text(s.text("Continue (${chosen.size})", "繼續（${chosen.size}）")) }
                }
                Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.weight(1f)) {
                        TextButton(onClick = { menuExpanded = true }) {
                            Text(if (section == "recent") s.text("Recent", "最近") else if (audioOnly) s.text("Folders", "資料夾") else s.text("Albums", "相簿"))
                            Icon(Icons.Rounded.ArrowDropDown, null)
                        }
                        DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                            DropdownMenuItem(text = { Text(s.text("Recent", "最近")) }, onClick = {
                                section = "recent"; selectedAlbum = null; menuExpanded = false
                            })
                            DropdownMenuItem(text = { Text(if (audioOnly) s.text("Folders", "資料夾") else s.text("Albums", "相簿")) }, onClick = {
                                section = "albums"; selectedAlbum = null; menuExpanded = false
                            })
                        }
                    }
                    Box {
                        IconButton(onClick = { sortExpanded = true }) { Icon(Icons.AutoMirrored.Rounded.Sort, s.text("Sort", "排序")) }
                        DropdownMenu(expanded = sortExpanded, onDismissRequest = { sortExpanded = false }) {
                            listOf(LibrarySort.NEWEST to s.text("Date: newest first", "日期：由新到舊"),
                                LibrarySort.OLDEST to s.text("Date: oldest first", "日期：由舊到新"),
                                LibrarySort.NAME_AZ to s.text("Name: A to Z", "名稱：A 到 Z"),
                                LibrarySort.NAME_ZA to s.text("Name: Z to A", "名稱：Z 到 A")).forEach { (option, label) ->
                                DropdownMenuItem(text = { Text(label) }, onClick = { sort = option; sortExpanded = false },
                                    leadingIcon = { if (option == sort) Icon(Icons.Rounded.Check, null) else Spacer(Modifier.size(24.dp)) })
                            }
                        }
                    }
                }
                if (section == "albums" && selectedAlbum != null) Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = { selectedAlbum = null }) {
                        Icon(Icons.AutoMirrored.Rounded.ArrowBack, if (audioOnly) s.text("All folders", "所有資料夾") else s.text("All albums", "所有相簿"))
                    }
                    Text(albums.firstOrNull { it.id == selectedAlbum }?.name.orEmpty(), style = MaterialTheme.typography.titleMedium)
                }
                when {
                    !allowed -> Column(Modifier.fillMaxSize().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center) {
                        Text(if (audioOnly) s.text("Allow access to your audio files to browse them here.", "允許存取音訊檔案，才能在此瀏覽。")
                            else if (photosOnly) s.text("Allow access to your photos to browse them here.", "允許存取照片，才能在此瀏覽。")
                            else s.text("Allow access to your videos and photos to browse them here.", "允許存取影片和照片，才能在此瀏覽。"))
                        Spacer(Modifier.height(16.dp))
                        Button(onClick = { permission.launch(mediaPermissions(audioOnly, photosOnly)) }) { Text(s.text("Allow access", "允許存取")) }
                    }
                    items == null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                    items!!.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(if (audioOnly) s.text("No audio files found", "找不到音訊檔案")
                            else if (photosOnly) s.text("No photos found", "找不到照片")
                            else s.text("No videos or photos found", "找不到影片或照片"))
                    }
                    audioOnly -> LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp)) {
                        if (section == "albums" && selectedAlbum == null) {
                            listItems(albums, key = { it.id }) { folder ->
                                ListItem(headlineContent = { Text(folder.name, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                                    supportingContent = { Text(s.text("${folder.count} files", "${folder.count} 個檔案")) },
                                    leadingContent = { Icon(Icons.Rounded.Folder, null) },
                                    modifier = Modifier.clickable { selectedAlbum = folder.id })
                            }
                        } else {
                            listItems(shown, key = { it.uri.toString() }) { item ->
                                ListItem(headlineContent = { Text(item.name, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                                    supportingContent = { Text(item.albumName, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                                    leadingContent = { Icon(Icons.Rounded.MusicNote, null) },
                                    modifier = Modifier.clickable { onChoose(item.uri) })
                            }
                        }
                    }
                    section == "albums" && selectedAlbum == null -> LazyVerticalGrid(GridCells.Adaptive(110.dp), Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(albums, key = { it.id }) { album ->
                            LibraryCell(album.cover, "${album.name} · ${album.count}") { selectedAlbum = album.id }
                        }
                    }
                    else -> LazyVerticalGrid(GridCells.Adaptive(110.dp), Modifier.fillMaxSize().testTag("libraryPhotos")
                        .then(if (multiple) Modifier.photoDragSelection(photoGrid, photoKeys, chosen) { chosen = it } else Modifier),
                        state = photoGrid,
                        contentPadding = PaddingValues(8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(shown, key = { it.uri.toString() }) { item ->
                            val picked = item.uri.toString() in chosen
                            LibraryCell(item, selection = if (multiple) picked else null,
                                enabled = !multiple || picked || chosen.size < MAX_BATCH_PHOTOS) {
                                if (!multiple) onChoose(item.uri)
                                else {
                                    val uri = item.uri.toString()
                                    if (uri in chosen) chosen = ArrayList(chosen - uri)
                                    else if (chosen.size < MAX_BATCH_PHOTOS) chosen = ArrayList(chosen + uri)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun LibraryCell(item: LibraryItem, label: String = item.name, selection: Boolean? = null,
    enabled: Boolean = true, onClick: () -> Unit) {
    val context = LocalContext.current
    val thumbnail by produceState<Bitmap?>(null, item.uri) {
        value = if (item.audio) null else withContext(Dispatchers.IO) {
            runCatching { context.contentResolver.loadThumbnail(item.uri, Size(260, 260), null) }.getOrNull()
        }
    }
    Column(Modifier.clip(RoundedCornerShape(10.dp)).clickable(enabled = enabled, onClick = onClick)
        .semantics { if (selection != null) selected = selection }) {
        Box(Modifier.fillMaxWidth().aspectRatio(1f), contentAlignment = Alignment.Center) {
            if (item.audio) Icon(Icons.Rounded.MusicNote, null, Modifier.size(48.dp))
            else thumbnail?.let { Image(it.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop) }
            if (item.video) Icon(Icons.Rounded.PlayCircle, null, Modifier.align(Alignment.BottomEnd).padding(6.dp))
            if (selection != null) Checkbox(checked = selection, onCheckedChange = null, enabled = enabled,
                modifier = Modifier.align(Alignment.TopEnd))
        }
        Text(label, Modifier.padding(horizontal = 4.dp, vertical = 3.dp), maxLines = 1, overflow = TextOverflow.Ellipsis,
            style = MaterialTheme.typography.labelSmall)
    }
}
