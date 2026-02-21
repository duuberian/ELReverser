package com.duuberian.elreverser

import java.io.File
import android.Manifest
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.delay
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

// ─────────────────────────────────────────────
// TERMINAL DESIGN TOKENS
// ─────────────────────────────────────────────

object T {
    val bg = Color(0xFF0A0A0A)
    val accent = Color(0xFFFF4444)
    val accentDim = Color(0x99FF4444) // 60%
    val textBright = Color(0xFFF5F5F5)
    val textPrimary = Color(0xFFE0E0E0)
    val textSecondary = Color(0xFF888888)
    val textMuted = Color(0xFF555555)
    val divider = Color(0xFF1A1A1A)
    val mono = FontFamily.Monospace
}

// ─────────────────────────────────────────────
// ACTIVITY
// ─────────────────────────────────────────────

class MainActivity : ComponentActivity() {
    @Suppress("DEPRECATION")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = 0xFF0A0A0A.toInt()
        window.navigationBarColor = 0xFF0A0A0A.toInt()
        setContent {
            TerminalApp()
        }
    }
}

// ─────────────────────────────────────────────
// BLINKING CURSOR
// ─────────────────────────────────────────────

@Composable
fun BlinkingCursor(color: Color = T.accent) {
    val visible = remember { mutableStateOf(true) }
    LaunchedEffect(Unit) {
        while (true) {
            visible.value = true
            delay(500)
            visible.value = false
            delay(500)
        }
    }
    Text(
        "▌",
        color = if (visible.value) color else Color.Transparent,
        fontFamily = T.mono,
        fontSize = 14.sp
    )
}

// ─────────────────────────────────────────────
// BLINKING STATUS BULLET
// ─────────────────────────────────────────────

@Composable
fun BlinkingBullet() {
    val visible = remember { mutableStateOf(true) }
    LaunchedEffect(Unit) {
        while (true) {
            visible.value = true
            delay(500)
            visible.value = false
            delay(500)
        }
    }
    Text(
        "▪",
        color = if (visible.value) T.accent else Color.Transparent,
        fontFamily = T.mono,
        fontSize = 16.sp
    )
}

// ─────────────────────────────────────────────
// TYPEWRITER TEXT
// ─────────────────────────────────────────────

@Composable
fun TypewriterText(
    text: String,
    color: Color = T.textPrimary,
    fontSize: Int = 12,
    delayPerChar: Long = 10L,
    onComplete: () -> Unit = {}
) {
    var displayed by remember { mutableStateOf("") }
    LaunchedEffect(text) {
        displayed = ""
        for (i in text.indices) {
            displayed = text.substring(0, i + 1)
            delay(delayPerChar)
        }
        onComplete()
    }
    Text(
        displayed,
        color = color,
        fontFamily = T.mono,
        fontSize = fontSize.sp,
        lineHeight = (fontSize + 4).sp
    )
}

// ─────────────────────────────────────────────
// TAPPABLE (scale bounce)
// ─────────────────────────────────────────────

@Composable
fun Tappable(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (isPressed) 1.04f else 1f,
        animationSpec = tween(80),
        label = "tap"
    )

    Box(
        modifier = modifier
            .scale(scale)
            .clickable(
                interactionSource = interactionSource,
                indication = null,
                onClick = onClick
            )
    ) {
        content()
    }
}

// ─────────────────────────────────────────────
// SECTION LABEL  (─ LABEL)
// ─────────────────────────────────────────────

@Composable
fun SectionLabel(label: String) {
    Text(
        "─ $label",
        color = T.textMuted,
        fontFamily = T.mono,
        fontSize = 9.sp,
        fontWeight = FontWeight.Bold,
        letterSpacing = 1.5.sp,
        modifier = Modifier.padding(vertical = 8.dp)
    )
}

// ─────────────────────────────────────────────
// THIN DIVIDER
// ─────────────────────────────────────────────

@Composable
fun ThinDivider(modifier: Modifier = Modifier) {
    Box(
        modifier
            .fillMaxWidth()
            .height(1.dp)
            .background(T.divider)
    )
}

// ─────────────────────────────────────────────
// PROGRESS BAR (2px)
// ─────────────────────────────────────────────

@Composable
fun TerminalProgressBar(progress: Float, modifier: Modifier = Modifier) {
    Box(
        modifier
            .fillMaxWidth()
            .height(2.dp)
            .background(T.textMuted.copy(alpha = 0.2f))
    ) {
        Box(
            Modifier
                .fillMaxHeight()
                .fillMaxWidth(progress.coerceIn(0f, 1f))
                .background(T.accent)
        )
    }
}

// ─────────────────────────────────────────────
// TERMINAL ICON BUTTON
// ─────────────────────────────────────────────

@Composable
fun TermIcon(
    icon: ImageVector,
    label: String? = null,
    tint: Color = T.accentDim,
    onClick: () -> Unit
) {
    Tappable(onClick = onClick) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 4.dp)
        ) {
            Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(16.dp))
            if (label != null) {
                Spacer(Modifier.width(4.dp))
                Text("> $label", color = T.textSecondary, fontFamily = T.mono, fontSize = 10.sp)
            }
        }
    }
}

// ─────────────────────────────────────────────
// MAIN APP
// ─────────────────────────────────────────────

@Composable
fun TerminalApp(vm: AudioReverserViewModel = viewModel()) {
    val state by vm.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var bootComplete by remember { mutableStateOf(false) }

    val audioPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) vm.startRecording(context)
    }

    val filePickerLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        uri?.let { vm.importFile(context, it) }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(T.bg)
            .systemBarsPadding()
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .widthIn(max = 480.dp)
                .align(Alignment.TopCenter)
                .padding(horizontal = 16.dp)
        ) {
            // ── BOOT SEQUENCE ──
            if (!bootComplete) {
                BootSequence(onComplete = { bootComplete = true })
            } else {
                // ── HEADER ──
                Spacer(Modifier.height(12.dp))
                TerminalHeader(itemCount = state.items.size)
                ThinDivider(Modifier.padding(top = 8.dp))

                // ── RECORDING BANNER ──
                AnimatedVisibility(
                    visible = state.isRecording,
                    enter = slideInVertically(initialOffsetY = { -it }) + expandVertically(),
                    exit = slideOutVertically(targetOffsetY = { -it }) + shrinkVertically()
                ) {
                    RecordingBanner(
                        time = vm.formattedRecordingTime,
                        onStop = { vm.stopRecording() }
                    )
                }

                // ── ACTIONS BAR ──
                SectionLabel("COMMANDS")
                ActionBar(
                    isRecording = state.isRecording,
                    onRecord = {
                        if (state.isRecording) {
                            vm.stopRecording()
                        } else {
                            if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO)
                                == PackageManager.PERMISSION_GRANTED
                            ) {
                                vm.startRecording(context)
                            } else {
                                audioPermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                            }
                        }
                    },
                    onAddFile = { filePickerLauncher.launch(arrayOf("audio/*")) }
                )
                ThinDivider()

                // ── ITEMS ──
                if (state.items.isEmpty() && !state.isRecording) {
                    EmptyState()
                } else {
                    SectionLabel("TRACKS")
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        verticalArrangement = Arrangement.spacedBy(0.dp)
                    ) {
                        items(state.items, key = { it.id }) { item ->
                            val depth = vm.depth(item)
                            TerminalAudioRow(
                                item = item,
                                vm = vm,
                                state = state,
                                depth = depth,
                                context = context
                            )
                            ThinDivider()
                        }
                        item {
                            Spacer(Modifier.height(80.dp))
                        }
                    }
                }
            }
        }
    }
}

// ─────────────────────────────────────────────
// BOOT SEQUENCE
// ─────────────────────────────────────────────

@Composable
fun BootSequence(onComplete: () -> Unit) {
    val lines = listOf(
        "el_reverser v1.0.0",
        "initializing audio engine...",
        "codec: aac mp3 wav ogg [ok]",
        "sample_rate: 44100hz",
        "channels: mono/stereo",
        "scramble_engine: SCR1 protocol ready",
        "system ready."
    )
    var currentLine by remember { mutableIntStateOf(0) }
    var allDone by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        delay(200)
        for (i in lines.indices) {
            currentLine = i
            delay((lines[i].length * 10L) + 150L)
        }
        delay(400)
        allDone = true
        onComplete()
    }

    Column(modifier = Modifier.padding(top = 24.dp)) {
        for (i in 0..min(currentLine, lines.lastIndex)) {
            Row {
                Text(
                    "$ ",
                    color = T.accent,
                    fontFamily = T.mono,
                    fontSize = 12.sp
                )
                if (i == currentLine && !allDone) {
                    TypewriterText(
                        text = lines[i],
                        color = if (i == lines.lastIndex) T.accent else T.textSecondary,
                        fontSize = 12,
                        delayPerChar = 10L
                    )
                    BlinkingCursor()
                } else {
                    Text(
                        lines[i],
                        color = if (i == lines.lastIndex) T.accent else T.textSecondary,
                        fontFamily = T.mono,
                        fontSize = 12.sp
                    )
                }
            }
            Spacer(Modifier.height(2.dp))
        }
    }
}

// ─────────────────────────────────────────────
// HEADER
// ─────────────────────────────────────────────

@Composable
fun TerminalHeader(itemCount: Int) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        BlinkingBullet()
        Spacer(Modifier.width(6.dp))
        Text(
            "el_reverser",
            color = T.textBright,
            fontFamily = T.mono,
            fontSize = 16.sp,
            fontWeight = FontWeight.Bold
        )
        Spacer(Modifier.weight(1f))
        if (itemCount > 0) {
            Text(
                "$itemCount track${if (itemCount == 1) "" else "s"}",
                color = T.textMuted,
                fontFamily = T.mono,
                fontSize = 10.sp
            )
        }
    }
}

// ─────────────────────────────────────────────
// RECORDING BANNER
// ─────────────────────────────────────────────

@Composable
fun RecordingBanner(time: String, onStop: () -> Unit) {
    Column {
        ThinDivider()
        Tappable(onClick = onStop) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                BlinkingBullet()
                Spacer(Modifier.width(8.dp))
                Text("REC", color = T.accent, fontFamily = T.mono, fontSize = 10.sp,
                    fontWeight = FontWeight.Bold, letterSpacing = 1.sp)
                Spacer(Modifier.width(12.dp))
                Text(
                    time,
                    color = T.textBright,
                    fontFamily = T.mono,
                    fontSize = 32.sp,
                    fontWeight = FontWeight.Light
                )
                Spacer(Modifier.weight(1f))
                Text("> stop", color = T.accentDim, fontFamily = T.mono, fontSize = 11.sp)
            }
        }
        // 2px recording progress (indeterminate pulse)
        val infiniteTransition = rememberInfiniteTransition(label = "rec")
        val offset by infiniteTransition.animateFloat(
            initialValue = 0f, targetValue = 1f,
            animationSpec = infiniteRepeatable(tween(1500, easing = LinearEasing)),
            label = "rec_bar"
        )
        Box(
            Modifier
                .fillMaxWidth()
                .height(2.dp)
                .drawBehind {
                    drawRect(T.textMuted.copy(alpha = 0.15f))
                    val w = size.width * 0.3f
                    val x = (offset * (size.width + w)) - w
                    drawRect(T.accent, topLeft = Offset(x, 0f), size = Size(w, size.height))
                }
        )
    }
}

// ─────────────────────────────────────────────
// ACTION BAR
// ─────────────────────────────────────────────

@Composable
fun ActionBar(isRecording: Boolean, onRecord: () -> Unit, onAddFile: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Tappable(onClick = onRecord) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (isRecording) {
                    Icon(Icons.Outlined.Stop, null, tint = T.accent, modifier = Modifier.size(16.dp))
                } else {
                    Icon(Icons.Outlined.FiberManualRecord, null, tint = T.accent, modifier = Modifier.size(16.dp))
                }
                Spacer(Modifier.width(4.dp))
                Text(
                    if (isRecording) "> stop" else "> record",
                    color = T.textPrimary,
                    fontFamily = T.mono,
                    fontSize = 12.sp
                )
            }
        }

        Tappable(onClick = onAddFile) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.Add, null, tint = T.accentDim, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(4.dp))
                Text("> add file", color = T.textPrimary, fontFamily = T.mono, fontSize = 12.sp)
            }
        }
    }
}

// ─────────────────────────────────────────────
// EMPTY STATE
// ─────────────────────────────────────────────

@Composable
fun EmptyState() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 48.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            "~",
            color = T.textMuted,
            fontFamily = T.mono,
            fontSize = 36.sp
        )
        Spacer(Modifier.height(12.dp))
        Text(
            "> no tracks loaded",
            color = T.textSecondary,
            fontFamily = T.mono,
            fontSize = 12.sp
        )
        Spacer(Modifier.height(4.dp))
        Text(
            "wav / m4a / mp3 / ogg",
            color = T.textMuted,
            fontFamily = T.mono,
            fontSize = 10.sp
        )
    }
}

// ─────────────────────────────────────────────
// AUDIO ROW
// ─────────────────────────────────────────────

@Composable
fun TerminalAudioRow(
    item: AudioItem,
    vm: AudioReverserViewModel,
    state: AudioReverserState,
    depth: Int,
    context: Context
) {
    val isPlaying = state.playingItemID == item.id
    val isExpanded = state.expandedItemID == item.id
    val isDecodeShown = state.showDecodeForItemID == item.id
    val isChild = depth > 0

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = (depth * 16).dp)
    ) {
        // ── MAIN ROW ──
        Tappable(
            onClick = {
                if (!item.isLoading) {
                    if (isPlaying) vm.stop() else vm.play(item)
                }
            }
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 10.dp),
                verticalAlignment = Alignment.Top
            ) {
                // Status icon column
                Column(
                    modifier = Modifier.width(20.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    if (item.isLoading) {
                        BlinkingCursor()
                    } else if (isPlaying) {
                        PlayingIndicator()
                    } else {
                        Text(
                            when {
                                isChild && item.isDecoded -> "◇"
                                isChild -> "├"
                                else -> "▸"
                            },
                            color = when {
                                item.isDecoded -> Color(0xFF4CAF50)
                                item.isReversed -> T.accent
                                else -> T.textMuted
                            },
                            fontFamily = T.mono,
                            fontSize = 12.sp
                        )
                    }
                }

                Spacer(Modifier.width(8.dp))

                // Info column
                Column(modifier = Modifier.weight(1f)) {
                    // Name
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            if (isChild) item.shortName.lowercase() else item.name.lowercase(),
                            color = if (isChild) T.textSecondary else T.textPrimary,
                            fontFamily = T.mono,
                            fontSize = 12.sp,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f, fill = false)
                        )

                        if (item.isLoading) {
                            Spacer(Modifier.width(4.dp))
                            Text("processing", color = T.textMuted, fontFamily = T.mono, fontSize = 10.sp)
                            BlinkingCursor(T.textMuted)
                        }
                    }

                    // Metadata line
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        if (item.duration > 0) {
                            Text(
                                vm.formatDuration(item.duration),
                                color = T.textMuted,
                                fontFamily = T.mono,
                                fontSize = 10.sp
                            )
                        }

                        if (item.isDecoded) {
                            Text(
                                "[decoded]",
                                color = Color(0xFF4CAF50).copy(alpha = 0.7f),
                                fontFamily = T.mono,
                                fontSize = 10.sp
                            )
                        } else if (item.steps.isNotEmpty()) {
                            Text(
                                "${item.steps.size}x scrambled",
                                color = T.accent.copy(alpha = 0.6f),
                                fontFamily = T.mono,
                                fontSize = 10.sp
                            )
                        }

                        if (item.operationSummary != null && !item.isLoading) {
                            Text(
                                item.operationSummary,
                                color = T.textMuted,
                                fontFamily = T.mono,
                                fontSize = 9.sp
                            )
                        }
                    }

                    // Waveform bar
                    val waveform = vm.waveformSamples(item)
                    if (waveform.isNotEmpty() && !item.isLoading) {
                        Spacer(Modifier.height(4.dp))
                        TerminalWaveform(
                            samples = waveform,
                            color = when {
                                item.isDecoded -> Color(0xFF4CAF50)
                                item.isReversed -> T.accent
                                else -> T.accentDim
                            },
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(16.dp)
                        )
                    }
                }

                Spacer(Modifier.width(4.dp))

                // Actions column
                if (!item.isLoading) {
                    Row {
                        TermIcon(Icons.Outlined.Shuffle, onClick = { vm.toggleExpanded(item) },
                            tint = if (isExpanded) T.accent else T.textMuted)
                        TermIcon(Icons.Outlined.LockOpen, onClick = { vm.toggleDecode(item) },
                            tint = if (isDecodeShown) Color(0xFF4CAF50) else T.textMuted)
                        TermIcon(Icons.Outlined.MoreVert, onClick = {}, tint = T.textMuted)
                    }
                }
            }
        }

        // ── OVERFLOW ACTIONS (inline, terminal-style) ──
        // We show share/copy/delete as a single row on long-press alternative
        // For now, make the more button show an inline action row
        var showActions by remember { mutableStateOf(false) }

        // Override the MoreVert icon above — we need actual state handling
        // This is handled within the action buttons already; let me add inline actions

        // ── DECODE PANEL ──
        AnimatedVisibility(
            visible = isDecodeShown,
            enter = slideInVertically(initialOffsetY = { -it / 2 }) + expandVertically(),
            exit = slideOutVertically(targetOffsetY = { -it / 2 }) + shrinkVertically()
        ) {
            TerminalDecodePanel(
                item = item,
                vm = vm,
                context = context,
                onDismiss = { vm.toggleDecode(item) }
            )
        }

        // ── REVERSE PANEL ──
        AnimatedVisibility(
            visible = isExpanded && !item.isLoading,
            enter = slideInVertically(initialOffsetY = { -it / 2 }) + expandVertically(),
            exit = slideOutVertically(targetOffsetY = { -it / 2 }) + shrinkVertically()
        ) {
            TerminalReversePanel(
                item = item,
                vm = vm,
                context = context,
                onDismiss = { vm.toggleExpanded(item) }
            )
        }

        // ── INLINE ACTIONS ROW ──
        // Shown at bottom of each item for quick access
        if (!item.isLoading) {
            InlineActionsRow(item = item, vm = vm, context = context)
        }
    }
}

// ─────────────────────────────────────────────
// INLINE ACTIONS ROW
// ─────────────────────────────────────────────

@Composable
fun InlineActionsRow(item: AudioItem, vm: AudioReverserViewModel, context: Context) {
    var codeCopied by remember { mutableStateOf(false) }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Spacer(Modifier.width(20.dp)) // align with content

        if (item.scrambleCode != null) {
            Tappable(onClick = {
                val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                clipboard.setPrimaryClip(ClipData.newPlainText("code", item.scrambleCode))
                codeCopied = true
                Toast.makeText(context, "code copied", Toast.LENGTH_SHORT).show()
            }) {
                Text(
                    if (codeCopied) "> copied" else "> copy code",
                    color = if (codeCopied) Color(0xFF4CAF50) else T.textMuted,
                    fontFamily = T.mono,
                    fontSize = 10.sp
                )
            }
        }

        Tappable(onClick = { shareFile(context, item.file) }) {
            Text("> share", color = T.textMuted, fontFamily = T.mono, fontSize = 10.sp)
        }

        Tappable(onClick = { vm.delete(item) }) {
            Text("> delete", color = T.accent.copy(alpha = 0.4f), fontFamily = T.mono, fontSize = 10.sp)
        }
    }
}

// ─────────────────────────────────────────────
// PLAYING INDICATOR (animated bars as text)
// ─────────────────────────────────────────────

@Composable
fun PlayingIndicator() {
    val infiniteTransition = rememberInfiniteTransition(label = "play")
    val frame by infiniteTransition.animateFloat(
        initialValue = 0f, targetValue = 3f,
        animationSpec = infiniteRepeatable(tween(600, easing = LinearEasing)),
        label = "play_frame"
    )
    val chars = listOf("▁", "▃", "▅", "▇")
    Text(
        chars[frame.toInt().coerceIn(0, 3)],
        color = T.accent,
        fontFamily = T.mono,
        fontSize = 12.sp
    )
}

// ─────────────────────────────────────────────
// TERMINAL WAVEFORM (block characters)
// ─────────────────────────────────────────────

@Composable
fun TerminalWaveform(samples: FloatArray, color: Color, modifier: Modifier = Modifier) {
    Box(modifier = modifier.drawBehind {
        val barCount = min(samples.size, (size.width / 2.5f).toInt())
        val step = max(1, samples.size / barCount)
        val barWidth = size.width / barCount

        for (i in 0 until barCount) {
            val idx = min(i * step, samples.size - 1)
            val amp = samples[idx] * size.height
            val barHeight = max(amp, 0.5f)
            val x = i * barWidth
            val y = size.height - barHeight

            drawRect(
                color = color.copy(alpha = 0.3f + samples[idx] * 0.5f),
                topLeft = Offset(x, y),
                size = Size(max(barWidth - 0.5f, 0.5f), barHeight)
            )
        }
    })
}

// ─────────────────────────────────────────────
// DECODE PANEL
// ─────────────────────────────────────────────

@Composable
fun TerminalDecodePanel(
    item: AudioItem,
    vm: AudioReverserViewModel,
    context: Context,
    onDismiss: () -> Unit
) {
    var code by remember { mutableStateOf("") }

    Column(modifier = Modifier.padding(start = 28.dp, bottom = 8.dp)) {
        Text("─ DECODE", color = T.textMuted, fontFamily = T.mono, fontSize = 9.sp,
            letterSpacing = 1.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(6.dp))

        Text("> enter scramble code:", color = T.textSecondary, fontFamily = T.mono, fontSize = 10.sp)
        Spacer(Modifier.height(4.dp))

        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("$ ", color = T.accent, fontFamily = T.mono, fontSize = 12.sp)
            BasicTextField(
                value = code,
                onValueChange = { code = it },
                textStyle = TextStyle(
                    color = T.textBright,
                    fontFamily = T.mono,
                    fontSize = 12.sp
                ),
                cursorBrush = SolidColor(T.accent),
                singleLine = true,
                modifier = Modifier.weight(1f),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Go),
                keyboardActions = KeyboardActions(onGo = {
                    val c = code.trim().ifEmpty {
                        val cb = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                        cb.primaryClip?.getItemAt(0)?.text?.toString()?.trim() ?: ""
                    }
                    if (c.isNotEmpty()) vm.decode(context, item, c)
                }),
                decorationBox = { inner ->
                    Box {
                        if (code.isEmpty()) {
                            Text("SCR1:R-C0.5-R", color = T.textMuted, fontFamily = T.mono, fontSize = 12.sp)
                        }
                        inner()
                    }
                }
            )
            BlinkingCursor()
        }

        Spacer(Modifier.height(8.dp))

        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Tappable(onClick = {
                val cb = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                code = cb.primaryClip?.getItemAt(0)?.text?.toString() ?: ""
            }) {
                Text("> paste", color = T.accentDim, fontFamily = T.mono, fontSize = 10.sp)
            }

            Tappable(onClick = {
                var c = code.trim()
                if (c.isEmpty()) {
                    val cb = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    c = cb.primaryClip?.getItemAt(0)?.text?.toString()?.trim() ?: ""
                    code = c
                }
                if (c.isNotEmpty()) vm.decode(context, item, c)
            }) {
                Text("> run decode", color = T.accent, fontFamily = T.mono, fontSize = 10.sp)
            }

            Spacer(Modifier.weight(1f))

            Tappable(onClick = onDismiss) {
                Text("> cancel", color = T.textMuted, fontFamily = T.mono, fontSize = 10.sp)
            }
        }

        Spacer(Modifier.height(4.dp))
        ThinDivider()
    }
}

// ─────────────────────────────────────────────
// REVERSE PANEL
// ─────────────────────────────────────────────

@Composable
fun TerminalReversePanel(
    item: AudioItem,
    vm: AudioReverserViewModel,
    context: Context,
    onDismiss: () -> Unit
) {
    var trimStart by remember { mutableStateOf(0.0) }
    var trimEnd by remember { mutableStateOf(0.0) }
    var useChunks by remember { mutableStateOf(false) }
    var chunkSize by remember { mutableStateOf(0.5) }
    var chunkSizeText by remember { mutableStateOf("0.5") }
    val waveform = vm.waveformSamples(item)

    Column(modifier = Modifier.padding(start = 28.dp, bottom = 8.dp)) {
        Text("─ REVERSE", color = T.textMuted, fontFamily = T.mono, fontSize = 9.sp,
            letterSpacing = 1.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(6.dp))

        // ── TRIM ──
        if (item.duration > 0) {
            Text("> trim range:", color = T.textSecondary, fontFamily = T.mono, fontSize = 10.sp)
            Spacer(Modifier.height(4.dp))

            // Waveform with trim overlay
            if (waveform.isNotEmpty()) {
                TerminalTrimWaveform(
                    waveform = waveform,
                    trimStartFrac = if (item.duration > 0) (trimStart / item.duration).toFloat() else 0f,
                    trimEndFrac = if (item.duration > 0) (trimEnd / item.duration).toFloat() else 0f,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(24.dp)
                )
                Spacer(Modifier.height(4.dp))
            }

            // Trim values
            Row {
                Text(
                    "start=${vm.formatDuration(trimStart)}",
                    color = T.textMuted, fontFamily = T.mono, fontSize = 10.sp
                )
                Spacer(Modifier.weight(1f))
                val kept = max(0.0, item.duration - trimStart - trimEnd)
                Text(
                    "> ${vm.formatDuration(kept)} selected",
                    color = T.textPrimary, fontFamily = T.mono, fontSize = 10.sp
                )
                Spacer(Modifier.weight(1f))
                Text(
                    "end=${vm.formatDuration(item.duration - trimEnd)}",
                    color = T.textMuted, fontFamily = T.mono, fontSize = 10.sp
                )
            }

            // Trim start slider
            Spacer(Modifier.height(2.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("  start ", color = T.textMuted, fontFamily = T.mono, fontSize = 9.sp)
                Box(Modifier.weight(1f)) {
                    TerminalSlider(
                        value = trimStart.toFloat(),
                        onValueChange = { trimStart = it.toDouble().coerceAtMost(item.duration - trimEnd - 0.05) },
                        valueRange = 0f..item.duration.toFloat()
                    )
                }
            }
            // Trim end slider
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("  end   ", color = T.textMuted, fontFamily = T.mono, fontSize = 9.sp)
                Box(Modifier.weight(1f)) {
                    TerminalSlider(
                        value = trimEnd.toFloat(),
                        onValueChange = { trimEnd = it.toDouble().coerceAtMost(item.duration - trimStart - 0.05) },
                        valueRange = 0f..item.duration.toFloat()
                    )
                }
            }

            Spacer(Modifier.height(8.dp))
        }

        // ── CHUNKS ──
        Tappable(onClick = { useChunks = !useChunks }) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    if (useChunks) "[x]" else "[ ]",
                    color = if (useChunks) T.accent else T.textMuted,
                    fontFamily = T.mono,
                    fontSize = 12.sp
                )
                Spacer(Modifier.width(6.dp))
                Text("> chunked mode", color = T.textPrimary, fontFamily = T.mono, fontSize = 11.sp)
            }
        }

        AnimatedVisibility(
            visible = useChunks,
            enter = slideInVertically(initialOffsetY = { -it / 2 }) + expandVertically(),
            exit = slideOutVertically(targetOffsetY = { -it / 2 }) + shrinkVertically()
        ) {
            Column {
                Spacer(Modifier.height(4.dp))
                Text("  chunk_size:", color = T.textSecondary, fontFamily = T.mono, fontSize = 10.sp)
                Spacer(Modifier.height(4.dp))

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Spacer(Modifier.width(4.dp))
                    listOf(0.25, 0.5, 1.0, 2.0).forEach { v ->
                        val selected = abs(chunkSize - v) < 0.01
                        Tappable(onClick = { chunkSize = v; chunkSizeText = v.toString() }) {
                            Text(
                                if (v < 1) "${"%.2g".format(v)}s" else "${v.toInt()}s",
                                color = if (selected) T.accent else T.textMuted,
                                fontFamily = T.mono,
                                fontSize = 11.sp
                            )
                        }
                    }

                    // Custom input
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        BasicTextField(
                            value = chunkSizeText,
                            onValueChange = {
                                chunkSizeText = it
                                it.toDoubleOrNull()?.let { v -> if (v > 0) chunkSize = v }
                            },
                            textStyle = TextStyle(color = T.textBright, fontFamily = T.mono, fontSize = 11.sp),
                            cursorBrush = SolidColor(T.accent),
                            singleLine = true,
                            modifier = Modifier.width(36.dp),
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                            decorationBox = { inner ->
                                Box(
                                    Modifier
                                        .background(T.divider)
                                        .padding(horizontal = 4.dp, vertical = 2.dp)
                                ) {
                                    inner()
                                }
                            }
                        )
                        Text("s", color = T.textMuted, fontFamily = T.mono, fontSize = 10.sp)
                    }
                }
            }
        }

        // ── STEP CHAIN ──
        if (item.steps.isNotEmpty()) {
            Spacer(Modifier.height(8.dp))
            Row(
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("  chain:", color = T.textMuted, fontFamily = T.mono, fontSize = 10.sp)
                item.steps.forEach { step ->
                    Text(
                        "[${step.token}]",
                        color = T.accent.copy(alpha = 0.6f),
                        fontFamily = T.mono,
                        fontSize = 10.sp
                    )
                }
                Text("→", color = T.textMuted, fontFamily = T.mono, fontSize = 10.sp)
                Text(
                    "[${if (useChunks) "C${"%.2g".format(chunkSize)}" else "R"}]",
                    color = Color(0xFFFF9800).copy(alpha = 0.7f),
                    fontFamily = T.mono,
                    fontSize = 10.sp
                )
            }
        }

        Spacer(Modifier.height(10.dp))

        // ── ACTIONS ──
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            Tappable(onClick = onDismiss) {
                Text("> cancel", color = T.textMuted, fontFamily = T.mono, fontSize = 11.sp)
            }

            Spacer(Modifier.weight(1f))

            if (useChunks) {
                Text(
                    "${"%.2g".format(chunkSize)}s chunks",
                    color = T.textMuted,
                    fontFamily = T.mono,
                    fontSize = 9.sp
                )
            }

            Tappable(onClick = {
                vm.reverseItem(context, item, ReverseOptions(trimStart, trimEnd, useChunks, chunkSize))
            }) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("> ", color = T.accent, fontFamily = T.mono, fontSize = 11.sp)
                    Text("reverse", color = T.accent, fontFamily = T.mono, fontSize = 11.sp,
                        fontWeight = FontWeight.Bold)
                }
            }
        }

        Spacer(Modifier.height(6.dp))
        ThinDivider()
    }
}

// ─────────────────────────────────────────────
// TERMINAL SLIDER (minimal, 2px track)
// ─────────────────────────────────────────────

@Composable
fun TerminalSlider(
    value: Float,
    onValueChange: (Float) -> Unit,
    valueRange: ClosedFloatingPointRange<Float>
) {
    Slider(
        value = value,
        onValueChange = onValueChange,
        valueRange = valueRange,
        modifier = Modifier
            .fillMaxWidth()
            .height(24.dp),
        colors = SliderDefaults.colors(
            thumbColor = T.accent,
            activeTrackColor = T.accent,
            inactiveTrackColor = T.textMuted.copy(alpha = 0.2f),
            activeTickColor = Color.Transparent,
            inactiveTickColor = Color.Transparent
        )
    )
}

// ─────────────────────────────────────────────
// TRIM WAVEFORM
// ─────────────────────────────────────────────

@Composable
fun TerminalTrimWaveform(
    waveform: FloatArray,
    trimStartFrac: Float,
    trimEndFrac: Float,
    modifier: Modifier = Modifier
) {
    Box(modifier = modifier.drawBehind {
        val barCount = min(waveform.size, (size.width / 2.5f).toInt())
        val step = max(1, waveform.size / barCount)
        val barWidth = size.width / barCount

        for (i in 0 until barCount) {
            val idx = min(i * step, waveform.size - 1)
            val amp = waveform[idx] * size.height
            val barHeight = max(amp, 0.5f)
            val x = i * barWidth
            val y = size.height - barHeight

            val frac = i.toFloat() / barCount
            val inSelection = frac >= trimStartFrac && frac <= (1f - trimEndFrac)

            drawRect(
                color = if (inSelection)
                    T.accent.copy(alpha = 0.3f + waveform[idx] * 0.4f)
                else
                    T.textMuted.copy(alpha = 0.1f),
                topLeft = Offset(x, y),
                size = Size(max(barWidth - 0.5f, 0.5f), barHeight)
            )
        }

        // Trim boundary lines
        if (trimStartFrac > 0f) {
            val x = trimStartFrac * size.width
            drawLine(T.accent, Offset(x, 0f), Offset(x, size.height), strokeWidth = 1f)
        }
        if (trimEndFrac > 0f) {
            val x = (1f - trimEndFrac) * size.width
            drawLine(T.accent, Offset(x, 0f), Offset(x, size.height), strokeWidth = 1f)
        }
    })
}

// ─────────────────────────────────────────────
// SHARE UTIL
// ─────────────────────────────────────────────

fun shareFile(context: Context, file: File) {
    try {
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "audio/*"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, "share audio"))
    } catch (e: Exception) {
        Toast.makeText(context, "could not share file", Toast.LENGTH_SHORT).show()
    }
}
