package com.duuberian.elreverser

import android.content.Context
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.io.File
import java.util.UUID
import kotlin.math.max

// MARK: - Audio Item

data class AudioItem(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val file: File,
    val duration: Double,
    val isReversed: Boolean = false,
    val isDecoded: Boolean = false,
    val isLoading: Boolean = false,
    val parentID: String? = null,
    val steps: List<ScramblerStep> = emptyList(),
    val operationSummary: String? = null
) {
    val scrambleCode: String?
        get() = if (steps.isNotEmpty()) ScrambleCode.encode(steps) else null

    val shortName: String
        get() = when {
            isDecoded -> "Decoded"
            steps.isNotEmpty() -> steps.last().displayName
            else -> name
        }
}

data class ReverseOptions(
    val trimStart: Double = 0.0,
    val trimEnd: Double = 0.0,
    val useChunks: Boolean = false,
    val chunkSize: Double = 0.5
)

// MARK: - UI State

data class AudioReverserState(
    val items: List<AudioItem> = emptyList(),
    val isRecording: Boolean = false,
    val recordingTime: Double = 0.0,
    val playingItemID: String? = null,
    val expandedItemID: String? = null,
    val showDecodeForItemID: String? = null,
    val waveformCache: Map<String, FloatArray> = emptyMap()
)

// MARK: - ViewModel

class AudioReverserViewModel : ViewModel() {
    private val _state = MutableStateFlow(AudioReverserState())
    val state: StateFlow<AudioReverserState> = _state.asStateFlow()

    private var recorder: MediaRecorder? = null
    private var player: MediaPlayer? = null
    private var recordingFile: File? = null
    private val handler = Handler(Looper.getMainLooper())
    private var recordingStartTime = 0L

    private val recordingTimerRunnable = object : Runnable {
        override fun run() {
            if (_state.value.isRecording) {
                val elapsed = (System.currentTimeMillis() - recordingStartTime) / 1000.0
                _state.update { it.copy(recordingTime = elapsed) }
                handler.postDelayed(this, 100)
            }
        }
    }

    fun depth(item: AudioItem): Int {
        var d = 0
        var current = item
        while (current.parentID != null) {
            val parent = _state.value.items.find { it.id == current.parentID } ?: break
            d++
            current = parent
        }
        return d
    }

    // MARK: - Import

    fun importFile(context: Context, uri: Uri) {
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val cacheDir = context.cacheDir
                val fileName = uri.lastPathSegment?.substringAfterLast('/') ?: "imported_audio"
                val cleanName = fileName.replace(Regex("[^a-zA-Z0-9._-]"), "_")
                val destFile = File(cacheDir, "import_${UUID.randomUUID()}_$cleanName")

                context.contentResolver.openInputStream(uri)?.use { input ->
                    destFile.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }

                val duration = AudioEngine.getAudioDuration(destFile)
                val item = AudioItem(
                    name = fileName,
                    file = destFile,
                    duration = duration
                )

                _state.update { state ->
                    state.copy(items = listOf(item) + state.items)
                }

                loadWaveform(item)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    // MARK: - Recording

    @Suppress("DEPRECATION")
    fun startRecording(context: Context) {
        try {
            val file = File(context.cacheDir, "recording_${UUID.randomUUID()}.m4a")
            recordingFile = file

            recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(context)
            } else {
                MediaRecorder()
            }.apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setAudioSamplingRate(44100)
                setAudioChannels(1)
                setAudioEncodingBitRate(128000)
                setOutputFile(file.absolutePath)
                prepare()
                start()
            }

            recordingStartTime = System.currentTimeMillis()
            _state.update { it.copy(isRecording = true, recordingTime = 0.0) }
            handler.post(recordingTimerRunnable)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun stopRecording() {
        try {
            recorder?.stop()
            recorder?.release()
        } catch (_: Exception) {}
        recorder = null
        handler.removeCallbacks(recordingTimerRunnable)

        val file = recordingFile ?: return
        recordingFile = null

        val elapsed = _state.value.recordingTime
        val secs = elapsed.toInt()

        viewModelScope.launch(Dispatchers.IO) {
            val duration = AudioEngine.getAudioDuration(file)
            val item = AudioItem(
                name = "Recording (${secs}s)",
                file = file,
                duration = duration
            )

            _state.update { state ->
                state.copy(
                    isRecording = false,
                    items = listOf(item) + state.items
                )
            }

            loadWaveform(item)
        }
    }

    // MARK: - Playback

    fun play(item: AudioItem) {
        stop()
        try {
            player = MediaPlayer().apply {
                setDataSource(item.file.absolutePath)
                prepare()
                setOnCompletionListener {
                    _state.update { it.copy(playingItemID = null) }
                }
                start()
            }
            _state.update { it.copy(playingItemID = item.id) }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun stop() {
        try {
            player?.stop()
            player?.release()
        } catch (_: Exception) {}
        player = null
        _state.update { it.copy(playingItemID = null) }
    }

    // MARK: - Expand / Collapse

    fun toggleExpanded(item: AudioItem) {
        _state.update { state ->
            val newId = if (state.expandedItemID == item.id) null else item.id
            state.copy(expandedItemID = newId, showDecodeForItemID = null)
        }
        if (_state.value.expandedItemID == item.id) {
            loadWaveform(item)
        }
    }

    fun toggleDecode(item: AudioItem) {
        _state.update { state ->
            val newId = if (state.showDecodeForItemID == item.id) null else item.id
            state.copy(showDecodeForItemID = newId, expandedItemID = null)
        }
    }

    // MARK: - Waveform

    private fun loadWaveform(item: AudioItem) {
        val key = item.file.absolutePath
        if (_state.value.waveformCache.containsKey(key)) return

        viewModelScope.launch(Dispatchers.IO) {
            val samples = AudioEngine.generateWaveform(item.file)
            _state.update { state ->
                state.copy(waveformCache = state.waveformCache + (key to samples))
            }
        }
    }

    fun waveformSamples(item: AudioItem): FloatArray {
        return _state.value.waveformCache[item.file.absolutePath] ?: FloatArray(0)
    }

    // MARK: - Reverse

    fun reverseItem(context: Context, item: AudioItem, options: ReverseOptions) {
        _state.update { it.copy(expandedItemID = null) }

        val newStep = if (options.useChunks && options.chunkSize > 0) {
            ScramblerStep.ChunkedReverse(options.chunkSize)
        } else {
            ScramblerStep.Reverse
        }

        val allSteps = item.steps + newStep
        val placeholderID = UUID.randomUUID().toString()
        val placeholder = AudioItem(
            id = placeholderID,
            name = "Reversed",
            file = item.file,
            duration = 0.0,
            isReversed = true,
            isLoading = true,
            parentID = item.id,
            steps = allSteps,
            operationSummary = "Generating…"
        )

        // Insert after parent and its existing children
        _state.update { state ->
            val items = state.items.toMutableList()
            val idx = items.indexOfFirst { it.id == item.id }
            if (idx >= 0) {
                var insertIdx = idx + 1
                while (insertIdx < items.size && items[insertIdx].parentID == item.id) insertIdx++
                items.add(insertIdx, placeholder)
            }
            state.copy(items = items)
        }

        viewModelScope.launch(Dispatchers.IO) {
            try {
                val outputFile = File(context.cacheDir, "reversed_${UUID.randomUUID()}.wav")
                val dur = AudioEngine.processAudio(
                    inputFile = item.file,
                    outputFile = outputFile,
                    trimStart = options.trimStart,
                    trimEnd = options.trimEnd,
                    step = newStep
                )

                val summary = buildString {
                    append(newStep.displayName)
                    if (options.trimStart > 0 || options.trimEnd > 0) {
                        append(" · Trimmed ${"%.1f".format(options.trimStart)}s–${"%.1f".format(options.trimEnd)}s")
                    }
                }

                _state.update { state ->
                    val items = state.items.toMutableList()
                    val idx = items.indexOfFirst { it.id == placeholderID }
                    if (idx >= 0) {
                        items[idx] = AudioItem(
                            id = placeholderID,
                            name = "Reversed",
                            file = outputFile,
                            duration = dur,
                            isReversed = true,
                            parentID = item.id,
                            steps = allSteps,
                            operationSummary = summary
                        )
                    }
                    state.copy(items = items)
                }

                // Load waveform for the new item
                val waveform = AudioEngine.generateWaveform(outputFile)
                _state.update { state ->
                    state.copy(waveformCache = state.waveformCache + (outputFile.absolutePath to waveform))
                }
            } catch (e: Exception) {
                e.printStackTrace()
                _state.update { state ->
                    state.copy(items = state.items.filter { it.id != placeholderID })
                }
            }
        }
    }

    // MARK: - Decode

    fun decode(context: Context, item: AudioItem, code: String) {
        val steps = ScrambleCode.decode(code) ?: return
        val inverseSteps = ScrambleCode.inverseSteps(steps)

        _state.update { it.copy(showDecodeForItemID = null) }

        val placeholderID = UUID.randomUUID().toString()
        val placeholder = AudioItem(
            id = placeholderID,
            name = "Decoded",
            file = item.file,
            duration = 0.0,
            isDecoded = true,
            isLoading = true,
            parentID = item.id,
            operationSummary = "Decoding…"
        )

        _state.update { state ->
            val items = state.items.toMutableList()
            val idx = items.indexOfFirst { it.id == item.id }
            if (idx >= 0) {
                var insertIdx = idx + 1
                while (insertIdx < items.size && items[insertIdx].parentID == item.id) insertIdx++
                items.add(insertIdx, placeholder)
            }
            state.copy(items = items)
        }

        viewModelScope.launch(Dispatchers.IO) {
            try {
                val outputFile = File(context.cacheDir, "decoded_${UUID.randomUUID()}.wav")
                val dur = AudioEngine.applySteps(item.file, outputFile, inverseSteps)

                _state.update { state ->
                    val items = state.items.toMutableList()
                    val idx = items.indexOfFirst { it.id == placeholderID }
                    if (idx >= 0) {
                        items[idx] = AudioItem(
                            id = placeholderID,
                            name = "Decoded",
                            file = outputFile,
                            duration = dur,
                            isDecoded = true,
                            parentID = item.id,
                            operationSummary = "Decoded (${inverseSteps.size} steps undone)"
                        )
                    }
                    state.copy(items = items)
                }
            } catch (e: Exception) {
                e.printStackTrace()
                _state.update { state ->
                    state.copy(items = state.items.filter { it.id != placeholderID })
                }
            }
        }
    }

    // MARK: - Copy Code

    fun getScrambleCode(item: AudioItem): String? = item.scrambleCode

    // MARK: - Save (share)

    fun getSaveFile(item: AudioItem): File = item.file

    // MARK: - Delete

    fun delete(item: AudioItem) {
        stop()
        _state.update { state ->
            state.copy(items = state.items.filter { it.id != item.id && it.parentID != item.id })
        }
    }

    fun formatDuration(t: Double): String {
        val s = max(0.0, t)
        return if (s < 60) "%.1fs".format(s)
        else {
            val m = s.toInt() / 60
            val sec = s - m * 60
            "%d:%04.1f".format(m, sec)
        }
    }

    val formattedRecordingTime: String
        get() {
            val t = _state.value.recordingTime
            val m = t.toInt() / 60
            val s = t.toInt() % 60
            val tenths = ((t * 10) % 10).toInt()
            return "%d:%02d.%d".format(m, s, tenths)
        }

    override fun onCleared() {
        stop()
        try { recorder?.release() } catch (_: Exception) {}
        handler.removeCallbacksAndMessages(null)
    }
}
