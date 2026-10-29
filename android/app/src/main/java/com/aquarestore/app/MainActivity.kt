package com.aquarestore.app

import android.Manifest
import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.*
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.OpenInNew
import androidx.compose.material.icons.rounded.*
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import kotlinx.coroutines.launch
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.positionInRoot
import android.graphics.Bitmap
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.SeekParameters
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.ui.PlayerView
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.conflate
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.roundToLong

class MainActivity : ComponentActivity() {
    private val playUpdateLauncher = registerForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { result ->
        updates?.onPlayResult(result.resultCode)
    }
    internal val updates: AppUpdates? by lazy {
        if (BuildConfig.UPDATE_CHANNEL == "none") null else AppUpdates(this, playUpdateLauncher)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        CacheCleanup.onProcessStart(this)
        enableEdgeToEdge()
        setContent { AquaApp() }
    }

    override fun onResume() {
        super.onResume()
        updates?.onResume()
    }

    override fun onDestroy() {
        updates?.close()
        super.onDestroy()
    }
}

private val Aqua = Color(0xFF45DDC2)
private val Night = Color(0xFF09191F)

@Composable
private fun AquaApp(model: EditorModel = viewModel()) {
    val language by model.language.collectAsStateWithLifecycle()
    val theme by model.theme.collectAsStateWithLifecycle()
    val systemChinese = LocalConfiguration.current.locales[0].language == "zh"
    val s = Strings(language == "zh" || (language == "system" && systemChinese))
    val dark = theme == "dark" || (theme == "system" && isSystemInDarkTheme())
    val scheme = if (dark) darkColorScheme(primary = Aqua, onPrimary = Night,
        background = Night, surface = Color(0xFF10252D), surfaceVariant = Color(0xFF1B333C),
        onSurface = Color(0xFFE3F1F2), onSurfaceVariant = Color(0xFF9EB6BC))
    else lightColorScheme(primary = Color(0xFF007D70), onPrimary = Color.White,
        background = Color(0xFFF2F7F6), surface = Color.White, surfaceVariant = Color(0xFFE2EEEB),
        onSurface = Color(0xFF102D35), onSurfaceVariant = Color(0xFF526E73))
    val activity = androidx.activity.compose.LocalActivity.current
    SideEffect {
        activity?.window?.let { window ->
            androidx.core.view.WindowCompat.getInsetsController(window, window.decorView).apply {
                isAppearanceLightStatusBars = !dark
                isAppearanceLightNavigationBars = !dark
            }
        }
    }
    MaterialTheme(colorScheme = scheme) {
        Surface(Modifier.fillMaxSize(), color = scheme.background) { Editor(model, s) }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Editor(model: EditorModel, s: Strings) {
    val context = LocalContext.current
    val activity = androidx.activity.compose.LocalActivity.current
    val updates = (activity as? MainActivity)?.updates
    val updateUi = updates?.ui
    val source by model.source.collectAsStateWithLifecycle()
    val grade by model.grade.collectAsStateWithLifecycle()
    val speed by model.speed.collectAsStateWithLifecycle()
    val photoExportSelection by model.photoExportSelection.collectAsStateWithLifecycle()
    val videoExportSelection by model.videoExportSelection.collectAsStateWithLifecycle()
    val trim by model.trim.collectAsStateWithLifecycle()
    val filmstrip by model.filmstrip.collectAsStateWithLifecycle()
    // Kept as State and read only while drawing, so playback ticks redraw the trim bar without recomposing.
    val playhead = model.playhead.collectAsStateWithLifecycle()
    val analysis by model.analysis.collectAsStateWithLifecycle()
    val phase by model.phase.collectAsStateWithLifecycle()
    val progress by model.progress.collectAsStateWithLifecycle()
    val error by model.error.collectAsStateWithLifecycle()
    val export by Exports.status.collectAsStateWithLifecycle()
    val preparingPreview by model.previewPreparing.collectAsStateWithLifecycle()
    var settings by rememberSaveable { mutableStateOf(false) }
    var showExport by rememberSaveable { mutableStateOf(false) }
    var showProgress by rememberSaveable { mutableStateOf(false) }
    var speedExpanded by rememberSaveable { mutableStateOf(false) }
    var trimPicked by remember { mutableStateOf<Long?>(null) }
    var overlayBounds by remember { mutableStateOf<Rect?>(null) }
    var trimBarBounds by remember { mutableStateOf<Rect?>(null) }
    var scaffoldOrigin by remember { mutableStateOf(Offset.Zero) }
    LaunchedEffect(source?.uri) { speedExpanded = false; trimPicked = null; overlayBounds = null; trimBarBounds = null }
    var mediaLibrary by rememberSaveable { mutableStateOf(false) }
    var musicLibrary by rememberSaveable { mutableStateOf(false) }
    var editorPlayer by remember { mutableStateOf<Player?>(null) }
    val compare = remember { MutableInteractionSource() }
    val comparing by compare.collectIsPressedAsState()
    LaunchedEffect(comparing) { model.setCompare(comparing) }
    DisposableEffect(model) { onDispose { model.setCompare(false) } }
    var restoreExpanded by rememberSaveable { mutableStateOf(false) }
    var audioExpanded by rememberSaveable { mutableStateOf(false) }
    var confirmClose by rememberSaveable { mutableStateOf(false) }
    // While exporting, closing just leaves the editor: the export continues in the background.
    fun requestClose() { if (export.busy) model.closeMedia() else confirmClose = true }
    BackHandler(enabled = source != null && phase == null, onBack = ::requestClose)
    // Full-screen viewer: the same preview (and player) grows to fill the screen. Registered later, so Back exits it first.
    var maximized by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(source, phase) { if (source == null || phase != null) maximized = false }
    BackHandler(enabled = maximized) { maximized = false }
    BackHandler(enabled = speedExpanded || trimPicked != null) {
        speedExpanded = false
        trimPicked = null
    }
    DisposableEffect(maximized) {
        val window = activity?.window
        val bars = window?.let { androidx.core.view.WindowCompat.getInsetsController(it, it.decorView) }
        if (maximized) {
            bars?.systemBarsBehavior = androidx.core.view.WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            bars?.hide(androidx.core.view.WindowInsetsCompat.Type.systemBars())
        }
        onDispose { bars?.show(androidx.core.view.WindowInsetsCompat.Type.systemBars()) }
    }
    val originalVolume by model.originalVolume.collectAsStateWithLifecycle()
    val music by model.music.collectAsStateWithLifecycle()
    val musicStart by model.musicStartMs.collectAsStateWithLifecycle()
    val musicVolume by model.musicVolume.collectAsStateWithLifecycle()
    val musicEnvelope by model.musicEnvelope.collectAsStateWithLifecycle()
    val musicLoading by model.musicLoading.collectAsStateWithLifecycle()
    val compact = LocalConfiguration.current.screenHeightDp < 500
    val editorScroll = rememberScrollState()
    LaunchedEffect(source?.uri, phase) { editorScroll.scrollTo(0) }
    fun openExport() {
        val uri = export.uri ?: return
        try {
            context.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, context.contentResolver.getType(uri))
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
        } catch (_: Exception) { model.error.value = "openFailed" }
    }
    LaunchedEffect(export.busy) { if (export.busy) showProgress = true }
    fun pickMedia() { mediaLibrary = true }
    val notifications = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }
    val busy = phase != null || export.busy
    DisposableEffect(source?.keepsHdr) {
        val window = activity?.window
        val previous = window?.colorMode
        window?.colorMode = if (source?.keepsHdr == true) android.content.pm.ActivityInfo.COLOR_MODE_HDR else android.content.pm.ActivityInfo.COLOR_MODE_DEFAULT
        onDispose { if (previous != null) window.colorMode = previous }
    }
    Scaffold(modifier = Modifier.onGloballyPositioned { scaffoldOrigin = it.positionInRoot() }
        .pointerInput(speedExpanded, trimPicked, overlayBounds, trimBarBounds, scaffoldOrigin) {
            if (!speedExpanded && trimPicked == null) return@pointerInput
            awaitEachGesture {
                val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                val at = down.position + scaffoldOrigin
                // The trim bar closes these itself when it picks a frame, so the play row never flashes in between.
                val onTrimBar = trimBarBounds?.contains(at) == true
                if (overlayBounds?.contains(at) != true && !onTrimBar) {
                    speedExpanded = false
                    trimPicked = null
                }
            }
        }, containerColor = if (maximized) Color.Black else Color.Transparent, topBar = {
        if (!maximized) CenterAlignedTopAppBar(title = {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                AppLogo(Modifier.size(30.dp))
                Text("AquaRestore", fontWeight = FontWeight.Bold, fontSize = 22.sp)
            }
        }, navigationIcon = {
            // Editing actions live in the bar so the editor keeps the full height for preview and controls.
            if (source != null && phase == null) IconButton(onClick = ::requestClose) {
                Icon(Icons.Rounded.Close, s.text("Close", "關閉"))
            }
        }, actions = {
            if (source != null && phase == null) IconButton(onClick = ::pickMedia, enabled = !busy) {
                Icon(Icons.Rounded.SwapHoriz, s.text("Change media", "更換素材"))
            }
            if (source != null && phase == null) FilledIconButton(onClick = { showExport = true }, enabled = !busy) {
                Icon(Icons.Rounded.FileDownload, s.text("Export", "匯出"))
            }
            Box {
                IconButton(onClick = { settings = true }) { Icon(Icons.Rounded.Settings, s.text("Settings", "設定")) }
                if (updateUi?.hasUpdate == true) Box(Modifier.align(Alignment.TopEnd).padding(5.dp)
                    .size(8.dp).background(MaterialTheme.colorScheme.error, CircleShape))
            }
        },
            colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent))
    }) { inset ->
        Column(Modifier.padding(inset).fillMaxSize().then(if (source == null || phase != null) Modifier.verticalScroll(editorScroll) else Modifier).padding(horizontal = if (maximized) 0.dp else 20.dp),
            verticalArrangement = Arrangement.spacedBy(if (compact) 4.dp else 12.dp)) {
            if (source == null && phase == null) {
                Welcome(s, enabled = !busy, onImport = ::pickMedia)
            } else if (phase != null) {
                Spacer(Modifier.height(36.dp))
                OceanArt(Modifier.fillMaxWidth().height(210.dp))
                Text(s[phase!!], style = MaterialTheme.typography.titleLarge)
                Text(if (phase == "preparing") s.text("This device cannot decode this video's frame size in hardware, so a playable copy is made in software first. This can take a few minutes. Your original stays untouched.",
                    "此裝置的硬體無法解碼這個畫面尺寸，會先以軟體製作可播放的副本，可能需要幾分鐘；原始檔案會完整保留。")
                    else s.text("We sample colors across your media to recommend a restoration. Your original stays untouched.",
                    "正在分析素材色彩以推薦還原設定；原始檔案會完整保留。"), color = MaterialTheme.colorScheme.onSurfaceVariant)
                Progress(progress)
                OutlinedButton(onClick = model::cancelImport) { Text(s.text("Cancel", "取消")) }
            } else if (source != null) {
                Preview(model, s, export.busy, maximized, { maximized = it }, { editorPlayer = it }, compare,
                    speedExpanded, { speedExpanded = it }, trimPicked, { trimPicked = it },
                    { overlayBounds = it }, { trimBarBounds = it }, if (maximized) Modifier.weight(1f) else Modifier)
                if (!maximized) Column(Modifier.weight(1f).verticalScroll(editorScroll).testTag("adjustments"), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                if (source!!.video && source!!.durationMs > 0) Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    val duration = source!!.durationMs
                    ClipControls(editorPlayer, filmstrip, duration, trim, playhead, speed, !export.busy, s, compare,
                        speedExpanded, { speedExpanded = it }, { model.speed.value = it },
                        trimPicked, { trimPicked = it }, { overlayBounds = it }, { trimBarBounds = it },
                        onChange = { model.trimming.value = true; model.trim.value = it },
                        onDone = { model.trimming.value = false },
                        onScrub = { position, play -> model.scrub.tryEmit(position to play) },
                        canPlay = preparingPreview == null)
                }
                if (source!!.video) Panel {
                    Row(Modifier.fillMaxWidth().clickable { audioExpanded = !audioExpanded }, verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.MusicNote, null, Modifier.size(20.dp)); Spacer(Modifier.width(10.dp))
                        Text(s.text("Audio", "音訊"), fontWeight = FontWeight.Medium)
                        Spacer(Modifier.width(12.dp))
                        Text(music?.name ?: if (originalVolume == 0f) s.text("Muted", "已靜音") else s.text("Original sound", "原聲"),
                            Modifier.weight(1f), textAlign = TextAlign.End, maxLines = 1, overflow = TextOverflow.Ellipsis, fontSize = 13.sp,
                            color = if (music != null) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                        Icon(if (audioExpanded) Icons.Rounded.ExpandLess else Icons.Rounded.ExpandMore, null)
                    }
                    AnimatedVisibility(audioExpanded) {
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Volume(s.text("Original sound", "原聲"), originalVolume, !export.busy) { model.originalVolume.value = it }
                            val current = music
                            if (current == null) {
                                OutlinedButton(onClick = { musicLibrary = true }, enabled = !export.busy && !musicLoading, modifier = Modifier.fillMaxWidth()) {
                                    if (musicLoading) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                                    else Icon(Icons.Rounded.LibraryMusic, null, Modifier.size(18.dp))
                                    Spacer(Modifier.width(8.dp)); Text(s.text("Add music", "加入音樂"))
                                }
                            } else {
                                Volume(s.text("Music", "音樂"), musicVolume, !export.busy) { model.musicVolume.value = it }
                                val outputMs = ((trim.last - trim.first) / speed).toLong()
                                val window = musicWindow(current.durationMs, musicStart, outputMs)
                                MusicBar(musicEnvelope, current.durationMs, window, !export.busy && current.durationMs > outputMs,
                                    s.text("Music section", "音樂片段"),
                                    onMove = { model.musicStartMs.value = it }, onDone = { model.audition.tryEmit(Unit) })
                                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                                    Text(if (current.durationMs <= outputMs) s.text("Song is shorter than the video, so it repeats", "音樂比影片短，會重複播放")
                                        else s.text("Plays ${clock(window.first)}–${clock(window.last)}", "播放 ${clock(window.first)}–${clock(window.last)}"),
                                        Modifier.weight(1f), fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    TextButton(onClick = { musicLibrary = true }, enabled = !export.busy) { Text(s.text("Replace", "更換")) }
                                    TextButton(onClick = model::removeMusic, enabled = !export.busy) { Text(s.text("Remove", "移除")) }
                                }
                            }
                        }
                    }
                }
                analysis?.let { result ->
                    Panel {
                        Row(Modifier.fillMaxWidth().clickable { restoreExpanded = !restoreExpanded }, verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Rounded.AutoAwesome, null, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.primary); Spacer(Modifier.width(10.dp))
                            Text(s.text("Intelligent restore", "智慧色彩還原"), Modifier.weight(1f), fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text("${(grade.strength * 100).roundToInt()}%", color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Bold)
                            TextButton(onClick = model::reset, enabled = !export.busy) { Text(s.text("Reset", "重設")) }
                            Icon(if (restoreExpanded) Icons.Rounded.ExpandLess else Icons.Rounded.ExpandMore, null)
                        }
                        Slider(value = grade.strength, onValueChange = { model.setGrade(grade.copy(strength = it)) }, enabled = !export.busy, valueRange = 0f..1f,
                            modifier = Modifier.semantics { contentDescription = s.text("Restore intensity", "還原強度") })
                        if (result.confidence < 0.25f) Text(s.text("Low-light or limited color detail: use a gentle strength and check the result.",
                            "光線或色彩資訊不足：建議使用較低強度並確認效果。"), color = MaterialTheme.colorScheme.tertiary, fontSize = 12.sp)
                        AnimatedVisibility(restoreExpanded) {
                            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                Text(s[result.cast], color = MaterialTheme.colorScheme.primary, fontSize = 12.sp)
                                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                    Text(s.text("0% · Original colors", "0% · 原始色彩"), fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    Text(s.text("100% · Full restore", "100% · 完整還原"), fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                                Text(s.text("Scales every correction together; the advanced sliders below follow it.",
                                    "同時等比例調整所有校正，下方進階滑桿會跟著變化。"),
                                    color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp)
                            }
                        }
                    }
                }
                Advanced(model, grade, s, !export.busy)
                Spacer(Modifier.height(8.dp))
                }
            }
            if (export.busy) Panel {
                Text(s[export.stage], fontWeight = FontWeight.SemiBold)
                Progress(export.progress)
                Text(s.text("You can leave the app. Export continues in the background.", "可以離開 App，匯出會在背景繼續。"), fontSize = 12.sp)
                TextButton(onClick = { Exports.cancel(context) }) { Text(s.text("Cancel export", "取消匯出")) }
            }
            Spacer(Modifier.height(8.dp))
        }
    }
    if (export.busy && showProgress) AlertDialog(
        onDismissRequest = { showProgress = false },
        title = { Text(s[export.stage]) },
        text = { Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Progress(export.progress)
            Text(s.text("Processing the original file. You can continue in the background.", "正在處理原始檔案，可切換至背景繼續匯出。"))
        } },
        confirmButton = { TextButton(onClick = { showProgress = false }) { Text(s.text("Continue in background", "在背景繼續")) } },
        dismissButton = { TextButton(onClick = { Exports.cancel(context) }) { Text(s.text("Cancel export", "取消匯出")) } },
    )
    if (error != null) AlertDialog(onDismissRequest = { model.error.value = null },
        title = { Text(s.text("Unable to continue", "無法完成操作")) }, text = { Text(s[error!!]) },
        confirmButton = { TextButton(onClick = { model.error.value = null }) { Text(s.text("OK", "知道了")) } })
    if (!export.busy && (export.uri != null || export.error != null || export.stage == "cancelled")) {
        fun dismissResult() { Exports.status.value = ExportStatus() }
        AlertDialog(onDismissRequest = ::dismissResult,
            title = { Text(if (export.error != null) s.text("Export failed", "匯出失敗") else s[export.stage]) },
            text = { Text(export.error?.let { s[it] } ?: if (export.uri != null)
                s.text("Find your restored media in Gallery / AquaRestore.", "還原作品已儲存至相簿／AquaRestore。")
                else s.text("No unfinished file was added to your gallery.", "相簿不會留下未完成的檔案。")) },
            confirmButton = { TextButton(onClick = ::dismissResult) { Text(s.text("Done", "完成")) } },
            dismissButton = { if (export.uri != null) TextButton(onClick = { openExport(); dismissResult() }) { Text(s.text("Open", "開啟")) } })
    }
    if (settings) SettingsDialog(model, s, updateUi, { updates?.check(true) }, { updates?.update() }) { settings = false }
    if (confirmClose) AlertDialog(onDismissRequest = { confirmClose = false },
        title = { Text(s.text("Discard this edit?", "放棄這次編輯？")) },
        text = { Text(s.text("Your color, trim and music settings will be lost. The original file is not changed.",
            "調色、剪輯與音樂設定將不會保留，原始檔案不受影響。")) },
        confirmButton = { TextButton(onClick = { confirmClose = false; model.closeMedia() }) { Text(s.text("Discard", "放棄")) } },
        dismissButton = { TextButton(onClick = { confirmClose = false }) { Text(s.text("Keep editing", "繼續編輯")) } })
    if (showExport && source != null) ExportDialog(source!!, grade, s, speed, trim, model.audioMix(),
        if (source!!.video) videoExportSelection else photoExportSelection,
        onSelectionChange = { model.setExportSelection(source!!.video, it) },
        onResetCustom = { model.resetCustomExport(source!!.video) }, onDismiss = { showExport = false }) { options, estimatedBytes ->
        showExport = false
        if (Build.VERSION.SDK_INT >= 33) notifications.launch(Manifest.permission.POST_NOTIFICATIONS)
        Exports.start(context, ExportRequest(source!!, grade, options.copy(speed = speed), s.chinese, model.audioMix(), estimatedBytes))
    }
    if (mediaLibrary) MediaLibrary(s, onDismiss = { mediaLibrary = false }) { uri ->
        mediaLibrary = false
        model.import(uri)
    }
    if (musicLibrary) MediaLibrary(s, audioOnly = true, onDismiss = { musicLibrary = false }) { uri ->
        musicLibrary = false
        model.addMusic(uri)
    }
}

@Composable
private fun Panel(content: @Composable ColumnScope.() -> Unit) {
    Surface(shape = RoundedCornerShape(22.dp), color = MaterialTheme.colorScheme.surface) {
        Column(Modifier.fillMaxWidth().padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp), content = content)
    }
}

@Composable
private fun Welcome(s: Strings, enabled: Boolean = true, onImport: () -> Unit) {
    Spacer(Modifier.height(16.dp))
    Text(s.text("Your underwater studio", "你的水下影像工作室"), color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold)
    Text(s.text("Bring the ocean’s\ntrue colors back.", "讓海底的真實色彩\n再次浮現。"), fontSize = 36.sp, lineHeight = 43.sp, fontWeight = FontWeight.Bold)
    Text(s.text("Less blue. More life. Intelligent color restoration for your underwater videos and photos.",
        "找回被海水吸收的紅色，還原你的水下影片與照片。"), color = MaterialTheme.colorScheme.onSurfaceVariant, lineHeight = 23.sp)
    OceanArt(Modifier.fillMaxWidth().height(230.dp))
    Button(onClick = onImport, enabled = enabled, modifier = Modifier.fillMaxWidth().height(56.dp), shape = RoundedCornerShape(16.dp)) {
        Icon(Icons.Rounded.AddPhotoAlternate, null); Spacer(Modifier.width(10.dp)); Text(s.text("Import video or photo", "匯入影片或照片"), fontSize = 16.sp)
    }
    Panel {
        listOf(
            Icons.Rounded.AutoAwesome to s.text("Automatic color recommendations", "自動分析並推薦調色"),
            Icons.Rounded.Tune to s.text("One slider. Your perfect balance.", "一條強度滑桿，調出自然效果"),
            Icons.Rounded.HighQuality to s.text("Smooth preview · original-quality export", "流暢預覽 · 原始畫質匯出"),
        ).forEach { (icon, label) -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(icon, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp)); Text(label, fontSize = 13.sp)
        } }
    }
    Text(s.text("On-device processing. Your memories stay with you.", "所有處理都在裝置上完成，素材無需上傳。"), modifier = Modifier.fillMaxWidth(), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable
private fun OceanArt(modifier: Modifier) {
    Canvas(modifier.clip(RoundedCornerShape(24.dp)).background(Brush.verticalGradient(listOf(Color(0xFF124A60), Color(0xFF071E31))))) {
        val w = size.width; val h = size.height
        for (i in 0..5) {
            val ray = Path().apply { moveTo(w * (0.08f + i * 0.15f), 0f); lineTo(w * (0.3f + i * 0.15f), h); lineTo(w * (0.42f + i * 0.15f), h); close() }
            drawPath(ray, Color(0xFF8BECE3).copy(alpha = 0.04f))
        }
        for (i in 0..3) {
            val wave = Path().apply { moveTo(0f, h * (0.64f + i * 0.09f)); cubicTo(w * 0.3f, h * (0.35f + i * 0.12f), w * 0.55f, h * (1.05f - i * 0.06f), w, h * (0.6f + i * 0.08f)); lineTo(w, h); lineTo(0f, h); close() }
            drawPath(wave, listOf(Color(0xFF145C69), Color(0xFF167C7E), Color(0xFF20A39A), Color(0xFF46C9AC))[i])
        }
        for (i in 0..13) drawCircle(Color.White.copy(alpha = 0.18f), (2 + i % 3).dp.toPx(), Offset(w * ((i * 37 % 93) / 100f), h * ((i * 19 % 58 + 8) / 100f)))
    }
}

@Composable
private fun Preview(model: EditorModel, s: Strings, exporting: Boolean, maximized: Boolean,
    onMaximize: (Boolean) -> Unit, onPlayer: (Player?) -> Unit, interaction: MutableInteractionSource, speedExpanded: Boolean,
    expandSpeed: (Boolean) -> Unit, trimPicked: Long?, setTrimPicked: (Long?) -> Unit,
    onOverlayBounds: (Rect) -> Unit, onTrimBarBounds: (Rect) -> Unit, modifier: Modifier = Modifier) {
    val uri by model.previewUri.collectAsStateWithLifecycle()
    val original by model.previewOriginal.collectAsStateWithLifecycle()
    val corrected by model.previewGraded.collectAsStateWithLifecycle()
    val compare by model.compare.collectAsStateWithLifecycle()
    val source by model.source.collectAsStateWithLifecycle()
    val grade by model.grade.collectAsStateWithLifecycle()
    val detailOriginal by model.detailOriginal.collectAsStateWithLifecycle()
    val detailGraded by model.detailGraded.collectAsStateWithLifecycle()
    val preparingPreview by model.previewPreparing.collectAsStateWithLifecycle()
    // Full screen zooms in up to 5×, so it shows a sharper copy once that is graded with the current settings.
    LaunchedEffect(maximized, source?.uri) { model.setDetailWanted(maximized) }
    var adjusting by rememberSaveable { mutableStateOf(false) }
    var player by remember { mutableStateOf<Player?>(null) }
    var buttonsHeight by remember { mutableIntStateOf(0) }
    var previewScale by remember { mutableFloatStateOf(1f) }
    var previewPan by remember { mutableStateOf(Offset.Zero) }
    var previewSize by remember { mutableStateOf(IntSize.Zero) }
    LaunchedEffect(maximized, source?.uri) {
        previewScale = 1f
        previewPan = Offset.Zero
    }
    val fullScreenSpeed by model.speed.collectAsStateWithLifecycle()
    val fullScreenTrim by model.trim.collectAsStateWithLifecycle()
    val fullScreenFrames by model.filmstrip.collectAsStateWithLifecycle()
    val fullScreenPlayhead = model.playhead.collectAsStateWithLifecycle()
    val clipControls = maximized && uri != null && player != null && (source?.durationMs ?: 0L) > 0
    var clipHeight by remember { mutableIntStateOf(0) }
    // Full screen: centre the fitted media in the space above the controls instead of the whole screen, so the
    // controls (and the adjust panel) cover as little of it as possible. Media as tall as the screen stays at the top.
    val controls = buttonsHeight + if (clipControls) clipHeight + with(LocalDensity.current) { 12.dp.toPx() } else 0f
    val fitted = source?.takeIf { it.width > 0 && it.height > 0 && previewSize.width > 0 }?.let {
        minOf(previewSize.height.toFloat(), previewSize.width.toFloat() * it.height / it.width)
    } ?: previewSize.height.toFloat()
    val lift by animateFloatAsState(if (!maximized) 0f
        else ((previewSize.height - controls - fitted) / 2).coerceAtLeast(0f) - (previewSize.height - fitted) / 2, label = "lift")
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.testTag("mediaPreview").fillMaxWidth()
            .then(if (maximized) Modifier.weight(1f)
                else Modifier.height((LocalConfiguration.current.screenHeightDp * 0.24f).coerceIn(72f, 250f).dp).clip(RoundedCornerShape(20.dp)))
            .background(Color.Black), contentAlignment = Alignment.Center) {
            Box(Modifier.matchParentSize().clipToBounds(), contentAlignment = Alignment.Center) {
                Box(Modifier.fillMaxSize().graphicsLayer {
                    scaleX = if (maximized) previewScale else 1f
                    scaleY = if (maximized) previewScale else 1f
                    translationX = if (maximized) previewPan.x else 0f
                    translationY = if (maximized) previewPan.y + lift else 0f
                }, contentAlignment = Alignment.Center) {
                    if (uri != null) VideoPreview(model, exporting, maximized) { player = it; onPlayer(it) }
                    else (if (compare) (if (maximized) detailOriginal else null) ?: original
                        else detailGraded?.takeIf { maximized && it.first == grade }?.second ?: corrected ?: original)?.let {
                        Image(it.asImageBitmap(), s.text("Media preview", "素材預覽"), Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
                    }
                }
            }
            if (maximized) Box(Modifier.matchParentSize().onSizeChanged { previewSize = it }
                .pointerInput(source?.uri) {
                    detectTransformGestures { centroid, pan, zoom, _ ->
                        val nextScale = (previewScale * zoom).coerceIn(1f, 5f)
                        val ratio = nextScale / previewScale
                        val center = Offset(previewSize.width / 2f, previewSize.height / 2f + lift)
                        val nextPan = previewPan * ratio + (centroid - center) * (1f - ratio) + pan
                        val maxX = (nextScale - 1f) * previewSize.width / 2f
                        val maxY = (nextScale - 1f) * previewSize.height / 2f
                        previewScale = nextScale
                        previewPan = if (nextScale == 1f) Offset.Zero else Offset(
                            nextPan.x.coerceIn(-maxX, maxX), nextPan.y.coerceIn(-maxY, maxY))
                    }
                })
            Row(Modifier.align(Alignment.TopStart).padding(12.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                source?.let { PreviewTag(if (it.video) s.text("VIDEO", "影片") else s.text("PHOTO", "照片")) }
                PreviewTag(if (compare) s.text("ORIGINAL", "原色") else s.text("RESTORED", "還原後"))
                preparingPreview?.let { PreviewTag(s.text("Preparing smooth preview… $it%", "正在準備流暢預覽… $it%")) }
            }
            if (!maximized) source?.let { MediaInfo(it, s, Modifier.align(Alignment.BottomEnd).padding(8.dp)) }
            Surface(onClick = { onMaximize(!maximized) }, modifier = Modifier.align(Alignment.TopEnd).padding(8.dp).size(36.dp),
                shape = CircleShape, color = Color.Black.copy(alpha = 0.65f), contentColor = Color.White) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(if (maximized) Icons.Rounded.FullscreenExit else Icons.Rounded.Fullscreen,
                        if (maximized) s.text("Exit full screen", "結束全螢幕") else s.text("Full screen", "全螢幕"), Modifier.size(22.dp))
                }
            }
            if (maximized) Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth().navigationBarsPadding()
                .onSizeChanged { buttonsHeight = it.height },
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    // A video's Compare is in its play row.
                    if (!clipControls) CompareButton(interaction, s)
                    Button(onClick = { adjusting = !adjusting }, Modifier.testTag("fullScreenAdjust"),
                        colors = ButtonDefaults.buttonColors(containerColor = Color.Black.copy(alpha = 0.65f), contentColor = Color.White)) {
                        Icon(if (adjusting) Icons.Rounded.ExpandMore else Icons.Rounded.Tune, null, Modifier.size(16.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(if (adjusting) s.text("Hide", "收起") else s.text("Adjust", "調整"))
                    }
                }
                // The panel floats over the video so it keeps its size.
                if (adjusting) FullScreenAdjustments(model, s, !exporting,
                    Modifier.heightIn(max = (LocalConfiguration.current.screenHeightDp * 0.4f).dp))
                else Spacer(Modifier.height(16.dp))
            }
            if (clipControls) {
                val shown = player
                val duration = source?.durationMs ?: 0L
                Column(Modifier.align(Alignment.BottomCenter)
                    .padding(bottom = with(LocalDensity.current) { buttonsHeight.toDp() } + 12.dp)
                    .fillMaxWidth().padding(horizontal = 12.dp).onSizeChanged { clipHeight = it.height },
                    verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    ClipControls(shown, fullScreenFrames, duration, fullScreenTrim, fullScreenPlayhead,
                        fullScreenSpeed, !exporting, s, interaction, speedExpanded,
                        expandSpeed, { model.speed.value = it }, trimPicked, setTrimPicked, onOverlayBounds, onTrimBarBounds,
                        onChange = { model.trimming.value = true; model.trim.value = it },
                        onDone = { model.trimming.value = false },
                        onScrub = { position, play -> model.scrub.tryEmit(position to play) },
                        canPlay = preparingPreview == null)
                }
            }
        }
        // A video's Compare is in its play row, under the preview.
        if (!maximized && source?.let { it.video && it.durationMs > 0 } != true)
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) { CompareButton(interaction, s) }
    }
}

@Composable
private fun ClipControls(player: Player?, frames: List<Bitmap>, duration: Long, range: LongRange,
    playhead: State<Long>, speed: Float, enabled: Boolean, s: Strings, compare: MutableInteractionSource,
    speedExpanded: Boolean, expandSpeed: (Boolean) -> Unit, setSpeed: (Float) -> Unit, picked: Long?, setPicked: (Long?) -> Unit,
    onOverlayBounds: (Rect) -> Unit, onTrimBarBounds: (Rect) -> Unit, onChange: (LongRange) -> Unit,
    onDone: () -> Unit, onScrub: (Long, Boolean) -> Unit, canPlay: Boolean = true) {
    val trimTarget = picked?.takeIf { it in range }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        VideoControls(player, playhead, duration, range, speed, enabled, s, compare, speedExpanded,
            { expandSpeed(it); if (it) setPicked(null) }, setSpeed, trimTarget, onOverlayBounds,
            onFullClip = { onChange(0L..duration); onDone(); setPicked(null) },
            onSetStart = { at ->
                onChange(at..range.last); onDone(); setPicked(null)
            }, onSetEnd = { at ->
                onChange(range.first..at); onDone(); setPicked(null)
            }, canPlay = canPlay)
        TrimBar(frames, duration, range, playhead, enabled, s.text("Trim range", "剪輯範圍"),
            picked = trimTarget, onPick = { setPicked(it); expandSpeed(false) }, onBounds = onTrimBarBounds,
            onChange = { expandSpeed(false); onChange(it) }, onDone = onDone, onScrub = onScrub)
    }
}

@Composable
private fun VideoControls(player: Player?, playhead: State<Long>, duration: Long, range: LongRange, speed: Float,
    enabled: Boolean, s: Strings, compare: MutableInteractionSource, speedExpanded: Boolean, expandSpeed: (Boolean) -> Unit,
    setSpeed: (Float) -> Unit, trimTarget: Long?, onOverlayBounds: (Rect) -> Unit, onFullClip: () -> Unit,
    onSetStart: (Long) -> Unit, onSetEnd: (Long) -> Unit, canPlay: Boolean) {
    var playing by remember(player) { mutableStateOf(player?.playWhenReady == true) }
    LaunchedEffect(player) {
        while (true) { playing = player?.playWhenReady == true; delay(100) }
    }
    Box(Modifier.fillMaxWidth().height(48.dp), contentAlignment = Alignment.Center) {
        if (!speedExpanded && trimTarget == null) Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            // Whatever room the buttons leave; "Full clip" shortens rather than pushing them off the row.
            Box(Modifier.weight(1f)) {
                if (range.first > 0 || range.last < duration) TextButton(onClick = onFullClip, enabled = enabled,
                    contentPadding = PaddingValues(horizontal = 8.dp)) {
                    Text(s.text("Full clip", "完整長度"), maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            Surface(shape = CircleShape, color = Color.Black.copy(alpha = 0.88f), contentColor = Color.White) {
                Row(Modifier.height(40.dp).padding(end = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = { if (player?.playWhenReady == true) player.pause() else player?.play() },
                        enabled = enabled && canPlay && player != null, modifier = Modifier.size(40.dp)) {
                        Icon(if (playing) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                            if (playing) s.text("Pause", "暫停") else s.text("Play", "播放"), Modifier.size(22.dp))
                    }
                    Text("${clock(playhead.value)} / ${clock(duration)}", fontWeight = FontWeight.SemiBold, fontSize = 12.sp)
                }
            }
            Surface(onClick = { expandSpeed(true) }, enabled = enabled, shape = CircleShape,
                color = Color.Black.copy(alpha = 0.88f), contentColor = Color.White,
                modifier = Modifier.size(40.dp).semantics { contentDescription = s.text("Video speed", "影片速度") }) {
                Box(contentAlignment = Alignment.Center) { Icon(Icons.Rounded.Speed, null, Modifier.size(21.dp)) }
            }
            CompareButton(compare, s)
        }
        if (speedExpanded) {
            Surface(Modifier.onGloballyPositioned { onOverlayBounds(it.boundsInRoot()) },
                shape = CircleShape, color = Color(0xFF171717), contentColor = Color.White, shadowElevation = 8.dp) {
                Row(Modifier.padding(3.dp), verticalAlignment = Alignment.CenterVertically) {
                    listOf(0.5f, 1f, 2f, 4f).forEach { value ->
                        val label = if (value == 0.5f) "0.5×" else "${value.toInt()}×"
                        Surface(onClick = { setSpeed(value); expandSpeed(false) }, enabled = enabled,
                            shape = CircleShape, color = if (speed == value) Color.White else Color.Transparent,
                            contentColor = if (speed == value) Color.Black else Color.White,
                            modifier = Modifier.size(40.dp)) {
                            Box(contentAlignment = Alignment.Center) { Text(label, fontSize = 13.sp, fontWeight = FontWeight.SemiBold) }
                        }
                    }
                }
            }
        }
        if (trimTarget != null && !speedExpanded) {
            // Centred over the cursor, using the trim bar's geometry (14dp handles), kept inside the row.
            Surface(Modifier.layout { measurable, constraints ->
                val pill = measurable.measure(constraints)
                val handle = 14.dp.toPx()
                val track = (constraints.maxWidth - 2 * handle).coerceAtLeast(1f)
                val cursor = handle + (if (duration > 0) trimTarget.toFloat() / duration else 0f) * track
                val left = (cursor - pill.width / 2f).roundToInt().coerceIn(0, (constraints.maxWidth - pill.width).coerceAtLeast(0))
                layout(constraints.maxWidth, pill.height) { pill.place(left, 0) }
            }.onGloballyPositioned { onOverlayBounds(it.boundsInRoot()) },
                shape = CircleShape, color = Color(0xFF171717), contentColor = Color.White, shadowElevation = 8.dp) {
                Row(Modifier.padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    val minimum = min(500L, duration)
                    IconButton(onClick = { onSetStart(trimTarget) }, enabled = enabled && trimTarget <= range.last - minimum,
                        modifier = Modifier.size(48.dp)) {
                        TrimEdgeIcon(true, s.text("Set start", "設為起點"))
                    }
                    IconButton(onClick = { onSetEnd(trimTarget) }, enabled = enabled && trimTarget >= range.first + minimum,
                        modifier = Modifier.size(48.dp)) {
                        TrimEdgeIcon(false, s.text("Set end", "設為終點"))
                    }
                }
            }
        }
    }
}

@Composable
private fun CompareButton(interaction: MutableInteractionSource, s: Strings, modifier: Modifier = Modifier) {
    // Shows the original while held; styled like the play and speed buttons beside it.
    Surface(onClick = {}, modifier.height(40.dp).semantics { contentDescription = s.text("Hold to compare", "按住對比原片") },
        shape = CircleShape, color = Color.Black.copy(alpha = 0.88f), contentColor = Color.White, interactionSource = interaction) {
        Row(Modifier.padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.Compare, null, Modifier.size(16.dp))
            Spacer(Modifier.width(5.dp))
            Text(s.text("Compare", "對比"), fontWeight = FontWeight.SemiBold, fontSize = 12.sp)
        }
    }
}

/**
 * Filmstrip trim bar: original (uncorrected) thumbnails, a framed selection with a handle on each side, dimmed
 * footage outside it, and the playhead. Dragging near a handle moves it; a tap or drag elsewhere
 * places the cursor, which stays until a touch outside the bar; the trim actions replace the playback controls above this bar, over the cursor.
 */
@Composable
private fun TrimBar(frames: List<Bitmap>, duration: Long, range: LongRange, playhead: State<Long>,
    enabled: Boolean, description: String, picked: Long?, onPick: (Long) -> Unit, onBounds: (Rect) -> Unit,
    onChange: (LongRange) -> Unit, onDone: () -> Unit, onScrub: (Long, Boolean) -> Unit) {
    val primary = MaterialTheme.colorScheme.primary
    val latest by rememberUpdatedState(range)
    // Keep at least half a second (or the whole clip, if shorter) between the handles.
    val minimum = min(500L, duration)
    BoxWithConstraints(Modifier.fillMaxWidth().onGloballyPositioned { onBounds(it.boundsInRoot()) }) {
        val handle = with(LocalDensity.current) { 14.dp.toPx() }
        val barWidth = constraints.maxWidth
        val track = (barWidth - 2 * handle).coerceAtLeast(1f)
        fun x(t: Long) = handle + t.toFloat() / duration * track
        Box(Modifier.fillMaxWidth().height(56.dp).semantics { contentDescription = description }) {
        Row(Modifier.fillMaxSize().padding(horizontal = 14.dp).clip(RoundedCornerShape(4.dp)).background(MaterialTheme.colorScheme.surfaceVariant)) {
            frames.forEach { Image(it.asImageBitmap(), null, Modifier.weight(1f).fillMaxHeight(), contentScale = ContentScale.Crop) }
        }
        // A touch within reach of a handle moves it; anywhere else picks a preview frame inside the range.
        val reach = with(LocalDensity.current) { 24.dp.toPx() }
        fun time(px: Float) = ((px - handle) / track * duration).roundToLong()
        Canvas(Modifier.fillMaxSize().pointerInput(enabled, duration, track) {
            if (!enabled) return@pointerInput
            detectTapGestures { touch ->
                val at = time(touch.x).coerceIn(latest)
                onPick(at)
                onScrub(at, true)
            }
        }.pointerInput(enabled, duration, track) {
            if (!enabled) return@pointerInput
            var target = 0 // -1 start handle, 1 end handle, 0 playhead
            var position = 0f
            fun finish() {
                if (target != 0) onDone()
                else onScrub(position.roundToLong().coerceIn(latest), true)
            }
            detectHorizontalDragGestures(
                onDragStart = { touch ->
                    val toStart = kotlin.math.abs(touch.x - (x(latest.first) - handle / 2))
                    val toEnd = kotlin.math.abs(touch.x - (x(latest.last) + handle / 2))
                    target = if (min(toStart, toEnd) > reach) 0 else if (toStart <= toEnd) -1 else 1
                    position = when (target) { -1 -> latest.first.toFloat(); 1 -> latest.last.toFloat(); else -> time(touch.x).toFloat() }
                    if (target == 0) position.roundToLong().coerceIn(latest).let { onPick(it); onScrub(it, false) }
                },
                onDragEnd = ::finish, onDragCancel = ::finish,
            ) { change, delta ->
                change.consume()
                position += delta / track * duration
                val r = latest
                val t = position.roundToLong()
                when (target) {
                    -1 -> onChange(t.coerceIn(0, r.last - minimum)..r.last)
                    1 -> onChange(r.first..t.coerceIn(r.first + minimum, duration))
                    else -> t.coerceIn(r).let { onPick(it); onScrub(it, false) }
                }
            }
        }) {
            val s = x(range.first); val e = x(range.last)
            val dim = Color.Black.copy(alpha = 0.6f)
            drawRect(dim, Offset(handle, 0f), Size((s - handle).coerceAtLeast(0f), size.height))
            drawRect(dim, Offset(e, 0f), Size((size.width - handle - e).coerceAtLeast(0f), size.height))
            val border = 3.dp.toPx()
            drawRect(Color.White, Offset(s, 0f), Size(e - s, border))
            drawRect(Color.White, Offset(s, size.height - border), Size(e - s, border))
            val corner = CornerRadius(4.dp.toPx())
            drawRoundRect(Color.White, Offset(s - handle, 0f), Size(handle, size.height), corner)
            drawRoundRect(Color.White, Offset(e, 0f), Size(handle, size.height), corner)
            for (grip in listOf(s - handle / 2, e + handle / 2))
                drawLine(Color.DarkGray, Offset(grip, size.height * 0.35f), Offset(grip, size.height * 0.65f), 2.dp.toPx(), StrokeCap.Round)
            picked?.takeIf { it in range }?.let { at ->
                drawLine(primary, Offset(x(at), 0f), Offset(x(at), size.height), 2.dp.toPx())
                drawCircle(primary, 4.dp.toPx(), Offset(x(at), 4.dp.toPx()))
            }
            val now = playhead.value
            if (now in range) drawLine(Color.White, Offset(x(now), border), Offset(x(now), size.height - border), 2.dp.toPx())
        }
        }
    }
}

@Composable
private fun TrimEdgeIcon(start: Boolean, description: String) {
    Canvas(Modifier.size(28.dp).semantics { contentDescription = description }) {
        fun point(x: Float, y: Float) = Offset(size.width * (if (start) x else 1f - x), size.height * y)
        val stroke = 2.5.dp.toPx()
        for (i in 0..4) drawCircle(Color.White, 1.2.dp.toPx(), point(.16f, .14f + i * .18f))
        drawLine(Color.White, point(.39f, .14f), point(.39f, .86f), stroke, StrokeCap.Round)
        drawLine(Color.White, point(.39f, .14f), point(.69f, .14f), stroke, StrokeCap.Round)
        drawLine(Color.White, point(.39f, .86f), point(.69f, .86f), stroke, StrokeCap.Round)
        drawLine(Color.White, point(.74f, .22f), point(.74f, .78f), stroke, StrokeCap.Round)
    }
}

@Composable
private fun Volume(label: String, value: Float, enabled: Boolean, change: (Float) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.width(96.dp), fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Slider(value, change, Modifier.weight(1f), enabled = enabled, valueRange = 0f..2f)
        Text("${(value * 100).roundToInt()}%", Modifier.width(44.dp), textAlign = TextAlign.End, fontSize = 12.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/**
 * The whole song as a loudness envelope, with a window as long as the video's output. Dragging
 * slides the window to choose which part of the song plays; a tap centres it on that spot.
 */
@Composable
private fun MusicBar(envelope: FloatArray?, songMs: Long, window: LongRange, movable: Boolean, description: String,
    onMove: (Long) -> Unit, onDone: () -> Unit) {
    val primary = MaterialTheme.colorScheme.primary
    val idle = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.35f)
    val latest by rememberUpdatedState(window)
    val length = window.last - window.first
    Canvas(Modifier.fillMaxWidth().height(48.dp).clip(RoundedCornerShape(6.dp)).background(MaterialTheme.colorScheme.surfaceVariant)
        .semantics { contentDescription = description }
        .pointerInput(movable, songMs, length) {
            if (!movable) return@pointerInput
            detectTapGestures { touch -> onMove((touch.x / size.width * songMs - length / 2).roundToLong().coerceIn(0, songMs - length)); onDone() }
        }
        .pointerInput(movable, songMs, length) {
            if (!movable) return@pointerInput
            var start = 0f
            detectHorizontalDragGestures(onDragStart = { start = latest.first.toFloat() }, onDragEnd = onDone, onDragCancel = onDone) { change, delta ->
                change.consume()
                start += delta / size.width * songMs
                onMove(start.roundToLong().coerceIn(0, songMs - length))
            }
        }) {
        val left = window.first.toFloat() / songMs * size.width
        val right = window.last.toFloat() / songMs * size.width
        val bars = envelope ?: FloatArray(0)
        val step = if (bars.isEmpty()) 0f else size.width / bars.size
        bars.forEachIndexed { i, level ->
            val x = i * step + step / 2
            val h = (0.12f + 0.88f * level) * size.height * 0.8f
            drawLine(if (x in left..right) primary else idle, Offset(x, (size.height - h) / 2), Offset(x, (size.height + h) / 2),
                (step * 0.6f).coerceAtLeast(1f), StrokeCap.Round)
        }
        drawRoundRect(primary, Offset(left, 0f), Size(right - left, size.height), CornerRadius(6.dp.toPx()), style = Stroke(3.dp.toPx()))
    }
}

private fun clock(ms: Long): String {
    val tenths = (ms.coerceAtLeast(0) + 50) / 100
    return "%d:%02d.%d".format(tenths / 600, tenths / 10 % 60, tenths % 10)
}

/** The launcher icon's own layers, cropped to its visible circle (the middle 72 of 108 units). */
@Composable
private fun AppLogo(modifier: Modifier) {
    Box(modifier.clip(CircleShape), contentAlignment = Alignment.Center) {
        for (layer in listOf(R.drawable.ic_launcher_background, R.drawable.ic_launcher_foreground))
            Image(painterResource(layer), null, Modifier.requiredSize(45.dp))
    }
}

/** The file name and HDR format, kept behind a small button so they take no room on the editor. */
@Composable
private fun MediaInfo(source: SourceMedia, s: Strings, modifier: Modifier = Modifier) {
    var open by remember { mutableStateOf(false) }
    Box(modifier) {
        Surface(onClick = { open = true }, Modifier.size(32.dp), shape = CircleShape,
            color = Color.Black.copy(alpha = 0.65f), contentColor = Color.White) {
            Box(contentAlignment = Alignment.Center) { Icon(Icons.Rounded.Info, s.text("File details", "檔案資訊"), Modifier.size(20.dp)) }
        }
        DropdownMenu(open, { open = false }, Modifier.widthIn(max = 300.dp)) {
            Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(source.name, fontSize = 13.sp, fontWeight = FontWeight.Medium)
                if (source.isHdr) Text("${source.hdrName} · 10-bit · BT.2020 · " +
                    (if (source.keepsHdr) s.text("HDR preserved", "保留 HDR") else s.text("Exported as SDR", "匯出為 SDR")),
                    color = MaterialTheme.colorScheme.primary, fontSize = 12.sp)
            }
        }
    }
}

@Composable
private fun PreviewTag(text: String, modifier: Modifier = Modifier) {
    Surface(modifier, shape = RoundedCornerShape(6.dp), color = Color.Black.copy(alpha = 0.65f)) {
        Text(text, Modifier.padding(horizontal = 9.dp, vertical = 5.dp), color = Color.White, fontSize = 10.sp)
    }
}

private const val PREVIEW_FPS = 30f

private fun boostablePlayer(context: android.content.Context, boost: VolumeProcessor): ExoPlayer =
    ExoPlayer.Builder(context, object : DefaultRenderersFactory(context) {
        override fun buildAudioSink(context: android.content.Context, enableFloatOutput: Boolean, enableAudioTrackPlaybackParams: Boolean): AudioSink =
            DefaultAudioSink.Builder(context).setEnableFloatOutput(enableFloatOutput)
                .setEnableAudioTrackPlaybackParams(enableAudioTrackPlaybackParams).setAudioProcessors(arrayOf(boost)).build()
    }).build()

@Composable
private fun VideoPreview(model: EditorModel, exporting: Boolean, maximized: Boolean, onPlayer: (Player?) -> Unit) {
    val context = LocalContext.current
    val uri by model.previewUri.collectAsStateWithLifecycle()
    val preparing by model.previewPreparing.collectAsStateWithLifecycle()
    val held = exporting || preparing != null
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    // Volumes above 100% go through a boost stage in the audio output; ExoPlayer's own volume stops at 1.
    val originalBoost = remember(uri) { VolumeProcessor() }
    val player = remember(uri) {
        boostablePlayer(context, originalBoost).apply {
            setSeekParameters(SeekParameters.EXACT)
            setVideoEffects(listOf(UnderwaterEffect(model.gradeState)))
            repeatMode = Player.REPEAT_MODE_ONE
            setMediaItem(MediaItem.fromUri(uri!!))
            seekTo(model.playbackPositionMs)
            prepare(); playWhenReady = model.playbackWanted && !held
        }
    }
    DisposableEffect(player) { onPlayer(player); onDispose { onPlayer(null) } }
    val speed by model.speed.collectAsStateWithLifecycle()
    LaunchedEffect(player, speed) {
        // At most 30 frames a second on screen at any speed: 60 fps footage keeps every frame at 0.5×, and
        // high-resolution footage grades half as many frames at 1×. Export keeps its own frame rate.
        model.gradeState.frameRate = PREVIEW_FPS / speed
        player.setPlaybackSpeed(speed)
    }
    val originalVolume by model.originalVolume.collectAsStateWithLifecycle()
    LaunchedEffect(player, originalVolume) { player.volume = min(originalVolume, 1f); originalBoost.gain = maxOf(originalVolume, 1f) }
    // Background music plays on its own player at normal speed, following the video's output time.
    val music by model.music.collectAsStateWithLifecycle()
    val musicBoost = remember(music?.uri) { VolumeProcessor() }
    val musicPlayer = remember(music?.uri) {
        music?.let { boostablePlayer(context, musicBoost).apply { setMediaItem(MediaItem.fromUri(it.uri)); repeatMode = Player.REPEAT_MODE_ONE; prepare() } }
    }
    DisposableEffect(musicPlayer) { onDispose { musicPlayer?.release() } }
    val musicVolume by model.musicVolume.collectAsStateWithLifecycle()
    LaunchedEffect(musicPlayer, musicVolume) { musicPlayer?.volume = min(musicVolume, 1f); musicBoost.gain = maxOf(musicVolume, 1f) }
    LaunchedEffect(player, musicPlayer) {
        val songPlayer = musicPlayer ?: return@LaunchedEffect
        try {
            while (true) {
                val track = model.music.value
                val range = model.trim.value
                val speedNow = model.speed.value
                val elapsed = ((player.currentPosition - range.first) / speedNow).toLong()
                val window = track?.let { musicWindow(it.durationMs, model.musicStartMs.value, ((range.last - range.first) / speedNow).toLong()) }
                val target = if (track == null || window == null || !player.isPlaying || model.trimming.value) null
                    else musicPosition(track.durationMs, window, elapsed)
                if (target == null) { if (songPlayer.playWhenReady) songPlayer.pause() }
                else {
                    // Re-sync only on real drift (seeks, loops), not on normal clock jitter.
                    if (kotlin.math.abs(songPlayer.currentPosition - target) > 250) songPlayer.seekTo(target)
                    if (!songPlayer.playWhenReady) songPlayer.play()
                }
                delay(50)
            }
        } finally { songPlayer.pause() }
    }
    LaunchedEffect(player) {
        // After the song window moves, replay from the trim start so the new section can be heard.
        model.audition.collect { player.seekTo(model.trim.value.first); if (model.previewPreparing.value == null) player.play() }
    }
    DisposableEffect(player, lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) {
                if (player.playWhenReady) model.playbackWanted = true
                model.playbackPositionMs = player.currentPosition
                player.pause()
            }
            if (event == Lifecycle.Event.ON_START && !Exports.status.value.busy && model.previewPreparing.value == null &&
                model.playbackWanted) player.play()
        }
        // Removed before release: releasing a busy 4K player can time out, which is reported as an error.
        val listener = object : Player.Listener {
            override fun onPlayerError(error: PlaybackException) {
                android.util.Log.e("AquaRestore", "Preview playback failed", error)
                model.error.value = "playbackFailed"
            }
            override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
                if (lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED) && !Exports.status.value.busy &&
                    model.previewPreparing.value == null) model.playbackWanted = playWhenReady
            }
        }
        player.addListener(listener)
        lifecycle.addObserver(observer)
        onDispose {
            if (model.previewUri.value == uri) model.playbackPositionMs = player.currentPosition
            player.removeListener(listener)
            lifecycle.removeObserver(observer)
            player.release()
        }
    }
    LaunchedEffect(held) {
        if (held) player.pause()
        else if (model.playbackWanted && lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) player.play()
    }
    LaunchedEffect(player) {
        // Loop inside the trim range; REPEAT_MODE_ONE alone would replay the whole clip.
        while (true) {
            val range = model.trim.value
            val position = player.currentPosition
            model.playhead.value = position
            if (!model.trimming.value && range.last > range.first && player.playbackState == Player.STATE_READY &&
                (position < range.first - 50 || (player.isPlaying && position >= range.last))) player.seekTo(range.first)
            delay(30)
        }
    }
    LaunchedEffect(player) {
        // Seeking exactly to the end would make the looping player wrap; 1 ms earlier shows the last frame.
        fun seek(position: Long) {
            val target = if (player.duration > 0) min(position, player.duration - 1) else position
            model.playhead.value = target
            player.seekTo(target)
        }
        launch {
            var dragging = false
            var resumeAfterDrag = false
            model.scrub.collect { (position, finished) ->
                if (!finished) {
                    if (!dragging) { resumeAfterDrag = player.playWhenReady; dragging = true }
                    if (player.playWhenReady) player.pause()
                }
                seek(position)
                if (finished && dragging) {
                    if (resumeAfterDrag) player.play()
                    dragging = false
                }
            }
        }
        // While a trim handle moves, pause on the frame under it; resume from the new start afterwards.
        var previous = model.trim.value
        var resume = false
        combine(model.trim, model.trimming) { range, active -> range to active }.collect { (range, active) ->
            if (active) {
                if (!resume && player.isPlaying) { resume = true; player.pause() }
                if (range != previous) seek(if (range.first != previous.first) range.first else range.last)
            } else if (resume) {
                // Playback was running before the drag: carry on from the new start.
                seek(range.first)
                player.play()
                resume = false
            } else if (range != previous) {
                // A new end pauses on the last kept frame (exports keep frames before the end), a new start plays on.
                if (range.first == previous.first) { player.pause(); seek(range.last - 1) } else seek(range.first)
            }
            previous = range
        }
    }
    LaunchedEffect(player) {
        // Playing frames read atomic uniforms. Throttle paused seeks without starving continuous drags.
        combine(model.grade, model.compare) { _, _ -> Unit }.conflate().collect {
            // A previous refresh seek still in flight would swallow this one; let it land first.
            while (player.playbackState == Player.STATE_BUFFERING) delay(16)
            if (player.playbackState == Player.STATE_READY && !player.isPlaying) {
                player.seekTo(if (player.currentPosition > 0) player.currentPosition - 1 else 1)
            }
            delay(80)
        }
    }
    // The effects pipeline renders at the surface's buffer size. Left to follow the view, the buffer changes
    // when entering or leaving full screen, and frames still drawn at the old size show unscaled in a corner.
    // A fixed buffer (the video fitted to the screen) never changes with the view; the display scales it.
    var playerView by remember { mutableStateOf<PlayerView?>(null) }
    val source by model.source.collectAsStateWithLifecycle()
    val orientation = LocalConfiguration.current.orientation
    LaunchedEffect(playerView, source?.width, source?.height, orientation) {
        val surface = playerView?.videoSurfaceView as? android.view.SurfaceView ?: return@LaunchedEffect
        val media = source ?: return@LaunchedEffect
        if (media.width <= 0 || media.height <= 0) return@LaunchedEffect
        val screen = context.resources.displayMetrics
        val scale = min(1f, min(screen.widthPixels.toFloat() / media.width, screen.heightPixels.toFloat() / media.height))
        surface.holder.setFixedSize(maxOf(2, (media.width * scale).roundToInt()), maxOf(2, (media.height * scale).roundToInt()))
        // A paused player draws nothing by itself; redraw the current frame into the new buffer.
        delay(100)
        if (player.playbackState == Player.STATE_READY && !player.isPlaying)
            player.seekTo(if (player.currentPosition > 0) player.currentPosition - 1 else 1)
    }
    // With video effects the player reports no video size, so its own frame can't keep the aspect ratio. Fit the
    // view to the video here, matching the fixed buffer's shape so it is scaled evenly at every size.
    val aspect = source?.let { if (it.width > 0 && it.height > 0) it.width.toFloat() / it.height else null }
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        // The paused-frame refresh above is a seek; with auto-show, every grade change would pop up the controls.
        AndroidView(factory = { PlayerView(it).apply { this.player = player; useController = false; setShowBuffering(PlayerView.SHOW_BUFFERING_WHEN_PLAYING) }.also { playerView = it } },
            update = { it.player = player; it.useController = false }, modifier = if (aspect != null) Modifier.aspectRatio(aspect) else Modifier.fillMaxSize())
    }
}

@Composable
private fun Advanced(model: EditorModel, p: Grade, s: Strings, enabled: Boolean) {
    var expanded by rememberSaveable { mutableStateOf(false) }
    Panel {
        Row(Modifier.fillMaxWidth().clickable { expanded = !expanded }, verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.Tune, null, Modifier.size(20.dp)); Spacer(Modifier.width(10.dp))
            Text(s.text("Advanced adjustments", "進階調整"), Modifier.weight(1f), fontWeight = FontWeight.Medium)
            Icon(if (expanded) Icons.Rounded.ExpandLess else Icons.Rounded.ExpandMore, null)
        }
        AnimatedVisibility(expanded) { AdvancedSliders(model, p, s, enabled) }
    }
}

/** Intensity and advanced sliders over the full-screen preview, so corrections can be judged at full size. */
@Composable
private fun FullScreenAdjustments(model: EditorModel, s: Strings, enabled: Boolean, modifier: Modifier = Modifier) {
    val grade by model.grade.collectAsStateWithLifecycle()
    val analysis by model.analysis.collectAsStateWithLifecycle()
    Surface(modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(bottom = 8.dp).testTag("fullScreenAdjustments"),
        shape = RoundedCornerShape(20.dp), color = MaterialTheme.colorScheme.surface.copy(alpha = 0.85f),
        contentColor = MaterialTheme.colorScheme.onSurface) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp)) {
            if (analysis != null) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(s.text("Restore intensity", "還原強度"), Modifier.weight(1f), fontSize = 13.sp, fontWeight = FontWeight.Medium)
                    Text("${(grade.strength * 100).roundToInt()}%", color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Bold)
                    TextButton(onClick = model::reset, enabled = enabled) { Text(s.text("Reset", "重設")) }
                }
                Slider(value = grade.strength, onValueChange = { model.setGrade(grade.copy(strength = it)) }, enabled = enabled, valueRange = 0f..1f,
                    modifier = Modifier.semantics { contentDescription = s.text("Restore intensity", "還原強度") })
            }
            AdvancedSliders(model, grade, s, enabled)
        }
    }
}

@Composable
private fun AdvancedSliders(model: EditorModel, p: Grade, s: Strings, enabled: Boolean) {
    // Sliders show what is applied at the current intensity, so they move with it. Edits are stored
    // relative to the intensity; at 0% the (all-zero) applied values become the new base at 100%.
    val k = p.strength
    val e = p.effective().copy(strength = 1f)
    fun edit(value: Float, update: Grade.(Float) -> Grade) = model.setGrade(if (k > 0f) p.update(value / k) else e.update(value))
    Column {
        Adjustment(s.text("Auto levels", "自動色階"), e.levels, 0f..1f, enabled) { edit(it) { v -> copy(levels = v) } }
        Adjustment(s.text("Red recovery", "紅色補償"), e.red, 0f..1f, enabled) { edit(it) { v -> copy(red = v) } }
        Adjustment(s.text("Protect cool water", "保護冷色水域"), e.coolProtection, 0f..1f, enabled) { edit(it) { v -> copy(coolProtection = v) } }
        Adjustment(s.text("Warmth", "色溫"), e.temperature, -1f..1f, enabled) { edit(it) { v -> copy(temperature = v) } }
        Adjustment(s.text("Green → magenta tint", "綠 → 洋紅色偏"), e.tint, -1f..1f, enabled) { edit(it) { v -> copy(tint = v) } }
        Adjustment(s.text("Exposure (EV)", "曝光（EV）"), e.exposure, -2f..2f, enabled) { edit(it) { v -> copy(exposure = v) } }
        Adjustment(s.text("Dehaze", "去霧"), e.haze, 0f..1f, enabled) { edit(it) { v -> copy(haze = v) } }
        Adjustment(s.text("Clarity", "清晰度"), e.clarity, 0f..1f, enabled) { edit(it) { v -> copy(clarity = v) } }
        Adjustment(s.text("Contrast", "對比"), e.contrast, -0.5f..0.5f, enabled) { edit(it) { v -> copy(contrast = v) } }
        Adjustment(s.text("Saturation", "飽和度"), e.saturation, -1f..1f, enabled) { edit(it) { v -> copy(saturation = v) } }
        Adjustment(s.text("Shadows", "陰影"), e.shadows, -1f..1f, enabled) { edit(it) { v -> copy(shadows = v) } }
    }
}

@Composable
private fun Adjustment(label: String, value: Float, range: ClosedFloatingPointRange<Float>, enabled: Boolean, change: (Float) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, fontSize = 13.sp)
        Text("%.2f".format(value), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    Slider(value.coerceIn(range), change, enabled = enabled, valueRange = range)
}

@Composable
private fun Progress(value: Int?) {
    if (value == null) LinearProgressIndicator(Modifier.fillMaxWidth())
    else {
        LinearProgressIndicator(progress = { value / 100f }, modifier = Modifier.fillMaxWidth())
        Text("$value%", color = MaterialTheme.colorScheme.primary, fontSize = 13.sp)
    }
}

@Composable
private fun Message(message: String, error: Boolean, dismiss: () -> Unit) {
    Surface(color = if (error) MaterialTheme.colorScheme.errorContainer else MaterialTheme.colorScheme.surfaceVariant, shape = RoundedCornerShape(16.dp)) {
        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(message, Modifier.weight(1f), fontSize = 13.sp)
            IconButton(onClick = dismiss) { Icon(Icons.Rounded.Close, "OK") }
        }
    }
}

@Composable
private fun SettingsDialog(model: EditorModel, s: Strings, update: UpdateUi?, check: () -> Unit, install: () -> Unit, dismiss: () -> Unit) {
    val language by model.language.collectAsStateWithLifecycle()
    val theme by model.theme.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var devTools by remember { mutableStateOf(DevTools.enabled(context)) }
    var versionTaps by remember { mutableIntStateOf(0) }
    var showLog by remember { mutableStateOf(false) }
    val source by model.source.collectAsStateWithLifecycle()
    var savingFrames by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    // Like Android's build number: ten taps on the version unlock the developer tools.
    val versionModifier = Modifier.clickable(interactionSource = null, indication = null) {
        if (devTools) return@clickable
        if (++versionTaps >= DevTools.UNLOCK_TAPS) {
            DevTools.enable(context)
            devTools = true
            android.widget.Toast.makeText(context, s.text("Developer tools enabled", "已啟用開發者工具"), android.widget.Toast.LENGTH_SHORT).show()
        }
    }
    if (showLog) DevLogPanel(s) { showLog = false }
    AlertDialog(onDismissRequest = dismiss, title = { Text(s.text("Make it yours", "個人化設定")) }, text = {
        Column(Modifier.heightIn(max = 480.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(s.text("Language", "語言"), fontWeight = FontWeight.SemiBold)
            Choices(listOf("system" to s.text("System", "跟隨系統"), "zh" to "中文", "en" to "English"), language) { model.preference("language", it) }
            Text(s.text("Appearance", "外觀"), fontWeight = FontWeight.SemiBold)
            Choices(listOf("system" to s.text("System", "跟隨系統"), "light" to s.text("Light", "淺色"), "dark" to s.text("Dark", "深色")), theme) { model.preference("theme", it) }
            if (update != null) {
                HorizontalDivider()
                Text(s.text("Updates", "更新"), fontWeight = FontWeight.SemiBold)
                Text("AquaRestore ${BuildConfig.VERSION_NAME} · " +
                    when (update.source) {
                        UpdateSource.PLAY -> "Google Play"
                        UpdateSource.LAN -> s.text("Local network", "區域網路")
                        UpdateSource.GITHUB -> "GitHub"
                    },
                    versionModifier, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                val status = when (update.phase) {
                    UpdatePhase.IDLE -> s.text("Check for a newer version", "檢查是否有新版本")
                    UpdatePhase.CHECKING -> s.text("Checking for updates…", "正在檢查更新…")
                    UpdatePhase.CURRENT -> s.text("You're up to date", "已是最新版本")
                    UpdatePhase.AVAILABLE -> if (update.source == UpdateSource.PLAY)
                        s.text("An update is available on Google Play", "Google Play 有可用更新")
                    else s.text("Version ${update.version ?: ""} is available", "有新版本 ${update.version ?: ""}")
                    UpdatePhase.DOWNLOADING -> s.text("Downloading update… ${update.percent}%", "正在下載更新… ${update.percent}%")
                    UpdatePhase.PERMISSION -> s.text("Allow installs from AquaRestore, then return here.", "允許 AquaRestore 安裝應用程式，然後返回。")
                    UpdatePhase.INSTALLING -> s.text("Confirm the installation in Android.", "請在 Android 中確認安裝。")
                    UpdatePhase.ERROR -> s.text("Could not check or install the update. Please try again.", "無法檢查或安裝更新，請再試一次。")
                }
                Text(status, fontSize = 12.sp)
                Button(onClick = if (update.phase in setOf(UpdatePhase.AVAILABLE, UpdatePhase.PERMISSION) ||
                    (update.phase == UpdatePhase.ERROR && update.version != null)) install else check,
                    enabled = update.phase !in setOf(UpdatePhase.CHECKING, UpdatePhase.DOWNLOADING, UpdatePhase.INSTALLING)) {
                    Text(when (update.phase) {
                        UpdatePhase.AVAILABLE -> s.text("Update now", "立即更新")
                        UpdatePhase.PERMISSION -> s.text("Continue installation", "繼續安裝")
                        UpdatePhase.ERROR -> if (update.version != null) s.text("Retry update", "重試更新")
                            else s.text("Check for updates", "檢查更新")
                        else -> s.text("Check for updates", "檢查更新")
                    })
                }
            }
            if (update == null) Text("AquaRestore ${BuildConfig.VERSION_NAME}", versionModifier,
                fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (devTools) {
                HorizontalDivider()
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(s.text("Developer tools", "開發者工具"), Modifier.weight(1f), fontWeight = FontWeight.SemiBold)
                    // Turning them off locks them again; ten taps on the version unlock them.
                    Switch(true, { DevTools.disable(context); devTools = false; versionTaps = 0 })
                }
                OutlinedButton(onClick = { showLog = true }) { Text(s.text("Developer logs", "開發者日誌")) }
                OutlinedButton(onClick = { scope.launch { saveLogToast(context, s) } }) { Text(s.text("Save logs", "儲存日誌")) }
                OutlinedButton(onClick = {
                    val media = source ?: return@OutlinedButton
                    savingFrames = true
                    scope.launch {
                        val saved = try {
                            runCatching { MediaIO.saveAnalysisFrames(context, media) }
                                .onFailure { android.util.Log.w("AquaRestore", "Analysis frames not saved", it) }.getOrDefault(0)
                        } finally { savingFrames = false }
                        android.widget.Toast.makeText(context, if (saved > 0)
                            s.text("Saved $saved frames to Download/${DevTools.FOLDER}/frames", "已儲存 $saved 張畫面至 Download/${DevTools.FOLDER}/frames")
                        else s.text("Could not save the frames", "無法儲存畫面"), android.widget.Toast.LENGTH_LONG).show()
                    }
                }, enabled = source?.video == true && !savingFrames) { Text(s.text("Save analysis frames", "儲存分析畫面")) }
                if (source?.video != true) Text(s.text("Open a video to save the six frames its grade is analyzed from.",
                    "開啟影片後，可儲存用於分析調色的六張畫面。"), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }, confirmButton = { TextButton(onClick = dismiss) { Text(s.text("Done", "完成")) } })
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun <T> Choices(items: List<Pair<T, String>>, selected: T, select: (T) -> Unit) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        items.forEach { (value, label) -> FilterChip(selected == value, { select(value) }, label = { Text(label, fontSize = 12.sp) }) }
    }
}

/** A photo export's size measured from graded samples, null while measuring; [failed] when it cannot be sampled. */
private data class PhotoSizeMeasurement(val bytes: Long?, val failed: Boolean)

@Composable
private fun measurePhotoSize(source: SourceMedia, grade: Grade, options: ExportOptions, dimensions: Pair<Int, Int>): PhotoSizeMeasurement {
    val context = LocalContext.current
    // Patches are graded once per output size; quality and format changes only encode them again.
    // An empty list means the photo could not be sampled.
    val samples by produceState<List<Bitmap>?>(null, source.uri, grade, dimensions) {
        value = null
        value = try {
            withContext(Dispatchers.Default) {
                MediaIO.sizeSamples(context, source.uri, dimensions.first, dimensions.second, grade)
            }
        } catch (e: Exception) { if (e is CancellationException) throw e; emptyList() }
    }
    // JPEG is measured once at every quality on the curve, so moving the slider only reads it off.
    val curve by produceState<DoubleArray?>(null, samples) {
        value = null
        val tiles = samples?.takeIf { it.isNotEmpty() } ?: return@produceState
        value = withContext(Dispatchers.Default) {
            DoubleArray(SIZE_CURVE_QUALITIES.size).also { values ->
                SIZE_CURVE_QUALITIES.forEachIndexed { i, quality ->
                    ensureActive()
                    values[i] = MediaIO.sampleBytesPerPixel(tiles, false, quality)
                }
            }
        }
    }
    val pngBytesPerPixel by produceState<Double?>(null, samples, options.png) {
        value = null
        val tiles = samples?.takeIf { it.isNotEmpty() && options.png } ?: return@produceState
        value = withContext(Dispatchers.Default) { MediaIO.sampleBytesPerPixel(tiles, true, 100) }
    }
    val bytesPerPixel = if (options.png) pngBytesPerPixel else curve?.let { interpolateBytesPerPixel(it, options.quality) }
    return PhotoSizeMeasurement(bytesPerPixel?.let { (dimensions.first.toLong() * dimensions.second * it).roundToLong() },
        samples?.isEmpty() == true)
}

@Composable
private fun ExportDialog(source: SourceMedia, grade: Grade, s: Strings, speed: Float, trim: LongRange, audio: AudioMix,
    selection: ExportSelection, onSelectionChange: (ExportSelection) -> Unit, onResetCustom: () -> Unit,
    onDismiss: () -> Unit, export: (ExportOptions, Long?) -> Unit) {
    // Only a real cut is passed on, so an untrimmed export keeps the source's exact end.
    val startMs = trim.first
    val endMs = if (trim.last in 1 until source.durationMs) trim.last else 0L
    val lengthMs = ExportOptions(startMs = startMs, endMs = endMs).trimmedMs(source.durationMs)
    val recommended = remember(source.width, source.height, source.fps, source.video, source.mime) {
        if (source.video) ExportRecommendation.video(source.width, source.height, source.fps)
        else ExportRecommendation.photo(source.width, source.height, source.mime)
    }
    val sourceFps = source.fps * min(speed, 1f)
    val customFps = selection.fps.takeIf { it == 0 || it <= sourceFps } ?: 0
    val options = when (selection.mode) {
        ExportMode.RECOMMENDED -> recommended
        ExportMode.ORIGINAL -> ExportOptions(quality = ORIGINAL_JPEG_QUALITY, png = selection.png)
        ExportMode.CUSTOM -> ExportOptions(original = false, longEdge = selection.longEdge, fps = customFps,
            quality = selection.quality, png = selection.png)
    }.copy(speed = speed, startMs = startMs, endMs = endMs)
    val dimensions = if (options.original) source.width to source.height
        else ExportSizing.dimensions(source.width, source.height, options.longEdge, source.video)
    val photoSize = if (source.video) null else measurePhotoSize(source, grade, options, dimensions)
    AlertDialog(onDismissRequest = onDismiss, title = { Text(s.text("Export your restoration", "匯出還原作品")) }, text = {
        Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Choices(listOf(ExportMode.RECOMMENDED to s.text("Recommended", "建議"),
                ExportMode.ORIGINAL to s.text("Original", "原始"), ExportMode.CUSTOM to s.text("Custom", "自訂")),
                selection.mode) { onSelectionChange(selection.copy(mode = it)) }
            if (source.isHdr) Text("${source.hdrName} · 10-bit · BT.2020\n" + (if (source.keepsHdr)
                s.text("HDR is preserved in every mode. Preview brightness depends on your display.", "所有模式均保留 HDR，預覽亮度取決於螢幕能力。")
                else s.text("This device has no 10-bit HDR encoder, so the video is tone-mapped and exported as SDR.", "此裝置沒有 10-bit HDR 編碼器，影片會經色調映射後匯出為 SDR。")),
                color = MaterialTheme.colorScheme.primary, fontSize = 12.sp)
            if (source.video) Text(s.text("Speed: ${speed}× · duration: ${"%.1f".format(lengthMs / speed / 1000)} s", "速度：${speed}× · 時長：${"%.1f".format(lengthMs / speed / 1000)} 秒") +
                (if (endMs > 0 || startMs > 0) s.text(" · trimmed ${clock(startMs)}–${clock(startMs + lengthMs)}", " · 已剪輯 ${clock(startMs)}–${clock(startMs + lengthMs)}") else ""), fontSize = 12.sp)
            if (source.video && audio.changesAudio) Text(s.text("Audio: original ${(audio.originalVolume * 100).roundToInt()}%", "音訊：原聲 ${(audio.originalVolume * 100).roundToInt()}%") +
                (if (audio.hasMusic) s.text(" + music ${(audio.musicVolume * 100).roundToInt()}%", " ＋ 音樂 ${(audio.musicVolume * 100).roundToInt()}%") else ""), fontSize = 12.sp)
            if (selection.mode != ExportMode.CUSTOM) {
                val shownFps = if (options.fps == 0) sourceFps else min(sourceFps, options.fps.toFloat())
                Text("${dimensions.first} × ${dimensions.second}" + if (source.video) " · ${shownFps.roundToInt()} fps"
                    else if (options.png) " · PNG" else " · JPEG ${options.quality}%", fontWeight = FontWeight.SemiBold)
                if (selection.mode == ExportMode.ORIGINAL && !source.video)
                    Choices(listOf(false to "JPEG", true to "PNG"), selection.png) { onSelectionChange(selection.copy(png = it)) }
                if (selection.mode == ExportMode.RECOMMENDED) Text(
                    if (options.original) {
                        if (source.video) s.text("This video is already within the suggested size and frame-rate limits, so source settings are kept.",
                            "影片的尺寸與幀率已在建議範圍內，因此保留原始設定。")
                        else s.text("This photo is already within the suggested size range, so source settings are kept.",
                            "照片的尺寸已在建議範圍內，因此保留原始設定。")
                    }
                    else if (source.video) s.text("Keeps lower source dimensions and frame rates; caps larger video at 1080p and 30 fps with a balanced bitrate.",
                        "保留較低的原始尺寸與幀率；較大的影片最多輸出 1080p、30 幀，並平衡位元率。")
                    else if (options.png) s.text("Large PNG photos are resized while keeping their lossless format.",
                        "高解析度 PNG 照片會縮小尺寸，同時保留無損格式。")
                    else s.text("Large photos use a smaller, high-quality JPEG to balance detail and file size.",
                        "高解析度照片使用較小的高畫質 JPEG，兼顧細節與檔案大小。"), fontSize = 12.sp)
                else Text(if (source.video) s.text("Keeps source dimensions, frames and codec. Selected speed retimes frames and audio. Targets the source video bitrate, adjusted for speed; estimates it only when unavailable. Color correction requires re-encoding, so it is not bit-for-bit lossless.",
                    "保留原尺寸、影格與編碼格式；所選速度會調整影格及音訊時間。優先沿用來源影片位元率並依速度調整，缺少資料時才估算。色彩校正需要重新編碼，無法完全無損。")
                else if (options.png) s.text("Full source dimensions, saved as lossless PNG after color correction. Files are several times larger than JPEG. Metadata is not copied.",
                    "保留原始尺寸，調色後儲存為無損 PNG。檔案比 JPEG 大數倍，不複製中繼資料。")
                else s.text("Full source dimensions, saved as full-quality JPEG after color correction. Metadata is not copied.",
                    "保留原始尺寸，調色後儲存為最高畫質 JPEG，不複製中繼資料。"), fontSize = 12.sp)
            } else {
                // Sits at the end of the photo format row, or of the video frame-rate heading, to save a row.
                val reset = @Composable {
                    TextButton(onClick = onResetCustom, enabled = selection != ExportSelection(mode = ExportMode.CUSTOM)) {
                        Text(s.text("Reset to defaults", "恢復預設值"), fontSize = 12.sp)
                    }
                }
                Text(s.text("Resolution · longest edge", "解析度 · 最長邊"), fontWeight = FontWeight.SemiBold)
                Choices(listOf(0 to s.text("Source", "原尺寸"), 3840 to "3840", 2560 to "2560", 1920 to "1920", 1280 to "1280", 960 to "960", 640 to "640"), selection.longEdge) {
                    onSelectionChange(selection.copy(longEdge = it))
                }
                val size = ExportSizing.dimensions(source.width, source.height, selection.longEdge, source.video)
                Text("${size.first} × ${size.second} px", fontSize = 12.sp, color = MaterialTheme.colorScheme.primary)
                if (source.video) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(s.text("Frame rate", "幀率"), Modifier.weight(1f), fontWeight = FontWeight.SemiBold)
                        reset()
                    }
                    Choices(listOf(0 to s.text("Original", "原始")) + listOf(24, 25, 30, 50, 60).filter { it <= sourceFps }.map { it to "$it fps" }, customFps) {
                        onSelectionChange(selection.copy(fps = it))
                    }
                    Text(s.text("Lower frame rates drop frames; no interpolation. Output is H.264 for SDR or 10-bit HEVC for HDR, with source audio where compatible.",
                        "較低幀率會抽幀，不插幀。SDR 輸出為 H.264，HDR 為 10-bit HEVC，音訊相容時保留。"), fontSize = 11.sp)
                } else {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.weight(1f)) { Choices(listOf(false to "JPEG", true to "PNG"), selection.png) { onSelectionChange(selection.copy(png = it)) } }
                        reset()
                    }
                }
                if (source.video || !selection.png) {
                    Text(s.text("Quality", "畫質") + " · ${selection.quality}%", fontWeight = FontWeight.SemiBold)
                    Slider(selection.quality.toFloat(), { onSelectionChange(selection.copy(quality = it.roundToInt())) }, valueRange = 10f..100f)
                    Text(if (source.video) s.text("Controls target bitrate; higher values create larger files. 100% at source resolution and frame rate matches Original.", "調整目標位元率，數值越高，檔案越大。原尺寸、原幀率配合 100% 等同「原始」。")
                        else s.text("JPEG compression quality.", "JPEG 壓縮畫質。"), fontSize = 11.sp)
                }
            }
            if (source.video) {
                val plan = videoExportPlan(source.width, source.height, source.fps, source.bitrate,
                    source.audioBitrate, source.durationMs, options, audio.changesAudio)
                val size = plan.estimatedBytes?.let { bytes ->
                    if (bytes >= 1_000_000_000L) "%.2f GB".format(bytes / 1_000_000_000.0)
                    else "%.1f MB".format(bytes / 1_000_000.0)
                } ?: s.text("Unavailable", "無法估算")
                Text(s.text("Estimated file size", "預估檔案大小") + " · ≈ " + size,
                    Modifier.testTag("estimatedSize"), fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
                Text(s.text("Based on target bitrate, audio and duration. Actual size varies with the encoder and scene detail; this is not a size limit.",
                        "依目標位元率、音訊與時長估算；實際大小受編碼器及畫面複雜度影響，不是檔案大小上限。"), fontSize = 11.sp)
            } else {
                val context = LocalContext.current
                val correction = remember(options.png) { Exports.sizeCorrection(context, Exports.photoSizeKey(options.png)) }
                val measured = photoSize!!
                val bytes = measured.bytes?.let { (it * correction).roundToLong() }
                    ?: if (measured.failed) photoEstimatedBytes(source.width, source.height, options) else null
                val size = if (bytes == null) s.text("measuring…", "測量中…")
                    else if (bytes >= 1_000_000_000L) "≈ %.2f GB".format(bytes / 1_000_000_000.0)
                    else if (bytes >= 1_000_000L) "≈ %.1f MB".format(bytes / 1_000_000.0)
                    else "≈ %.0f KB".format(bytes / 1_000.0)
                Text(s.text("Estimated file size", "預估檔案大小") + " · " + size,
                    Modifier.testTag("estimatedSize"), fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
                Text(if (!measured.failed) s.text("Measured by encoding samples of this photo with these settings", "以所選設定編碼此照片的取樣測得") +
                        (if (correction != 1.0) s.text(", corrected by this phone's earlier exports", "，並按此手機先前的匯出結果校正") else "") +
                        s.text(". Actual size may differ slightly.", "；實際大小可能略有差異。")
                    else s.text("Based on resolution, format and quality. Actual size varies with image detail.",
                        "依解析度、格式與畫質估算；實際大小會隨影像細節而變。"), fontSize = 11.sp)
            }
            Text(s.text("Saved to Gallery / AquaRestore. The original file is never overwritten.", "儲存至相簿／AquaRestore，不覆蓋原始檔案。"), fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }, confirmButton = { Button(onClick = { export(options, photoSize?.bytes) }) { Text(s.text("Start export", "開始匯出")) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(s.text("Cancel", "取消")) } })
}
