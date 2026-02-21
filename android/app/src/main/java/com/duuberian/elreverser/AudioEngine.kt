package com.duuberian.elreverser

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

// MARK: - Scrambler Step

sealed class ScramblerStep {
    data object Reverse : ScramblerStep()
    data class ChunkedReverse(val chunkSize: Double) : ScramblerStep()

    val displayName: String
        get() = when (this) {
            is Reverse -> "Reverse"
            is ChunkedReverse -> "Chunk ${"%.2g".format(chunkSize)}s"
        }

    val token: String
        get() = when (this) {
            is Reverse -> "R"
            is ChunkedReverse -> "C${"%.4g".format(chunkSize)}"
        }

    companion object {
        fun fromToken(token: String): ScramblerStep? {
            if (token == "R") return Reverse
            if (token.startsWith("C")) {
                val value = token.drop(1).toDoubleOrNull()
                if (value != null && value > 0) return ChunkedReverse(value)
            }
            return null
        }
    }
}

// MARK: - Scramble Code

object ScrambleCode {
    private const val PREFIX = "SCR1:"

    fun encode(steps: List<ScramblerStep>): String {
        val tokens = steps.joinToString("-") { it.token }
        return "$PREFIX$tokens"
    }

    fun decode(code: String): List<ScramblerStep>? {
        val trimmed = code.trim()
        if (!trimmed.startsWith(PREFIX)) return null
        val body = trimmed.drop(PREFIX.length)
        if (body.isEmpty()) return null
        val tokens = body.split("-")
        val steps = tokens.mapNotNull { ScramblerStep.fromToken(it) }
        return steps.ifEmpty { null }
    }

    fun inverseSteps(steps: List<ScramblerStep>): List<ScramblerStep> = steps.reversed()
}

// MARK: - Audio Engine

object AudioEngine {

    /**
     * Decode any audio file to raw PCM (16-bit, mono or stereo) WAV.
     * Returns: the output WAV file, sample rate, channel count, total sample count per channel.
     */
    fun decodeToWav(inputFile: File, outputFile: File): WavInfo {
        val extractor = MediaExtractor()
        extractor.setDataSource(inputFile.absolutePath)

        var audioTrack = -1
        var format: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val f = extractor.getTrackFormat(i)
            val mime = f.getString(MediaFormat.KEY_MIME) ?: ""
            if (mime.startsWith("audio/")) {
                audioTrack = i
                format = f
                break
            }
        }
        if (audioTrack < 0 || format == null) {
            extractor.release()
            throw IllegalArgumentException("No audio track found")
        }

        extractor.selectTrack(audioTrack)
        val sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        val channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        val mime = format.getString(MediaFormat.KEY_MIME)!!

        val codec = MediaCodec.createDecoderByType(mime)
        codec.configure(format, null, null, 0)
        codec.start()

        val allSamples = mutableListOf<Short>()
        val bufferInfo = MediaCodec.BufferInfo()
        var inputDone = false
        var outputDone = false

        while (!outputDone) {
            if (!inputDone) {
                val inputIndex = codec.dequeueInputBuffer(10000)
                if (inputIndex >= 0) {
                    val inputBuffer = codec.getInputBuffer(inputIndex)!!
                    val sampleSize = extractor.readSampleData(inputBuffer, 0)
                    if (sampleSize < 0) {
                        codec.queueInputBuffer(inputIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputDone = true
                    } else {
                        codec.queueInputBuffer(inputIndex, 0, sampleSize, extractor.sampleTime, 0)
                        extractor.advance()
                    }
                }
            }

            val outputIndex = codec.dequeueOutputBuffer(bufferInfo, 10000)
            if (outputIndex >= 0) {
                val outputBuffer = codec.getOutputBuffer(outputIndex)!!
                outputBuffer.order(ByteOrder.LITTLE_ENDIAN)
                val shortBuffer = outputBuffer.asShortBuffer()
                val samples = ShortArray(shortBuffer.remaining())
                shortBuffer.get(samples)
                allSamples.addAll(samples.toList())
                codec.releaseOutputBuffer(outputIndex, false)
                if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                    outputDone = true
                }
            }
        }

        codec.stop()
        codec.release()
        extractor.release()

        val pcmData = ShortArray(allSamples.size)
        for (i in allSamples.indices) pcmData[i] = allSamples[i]

        writeWav(outputFile, pcmData, sampleRate, channels)

        val framesPerChannel = pcmData.size / channels
        return WavInfo(sampleRate, channels, framesPerChannel)
    }

    data class WavInfo(val sampleRate: Int, val channels: Int, val framesPerChannel: Int) {
        val duration: Double get() = framesPerChannel.toDouble() / sampleRate
    }

    /**
     * Read a WAV file into a short array. Returns (samples, sampleRate, channels).
     */
    fun readWav(file: File): Triple<ShortArray, Int, Int> {
        val raf = RandomAccessFile(file, "r")
        // Skip RIFF header
        raf.skipBytes(4) // "RIFF"
        raf.skipBytes(4) // file size
        raf.skipBytes(4) // "WAVE"

        var sampleRate = 44100
        var channels = 1
        var bitsPerSample = 16
        var dataSize = 0
        var dataFound = false

        while (!dataFound && raf.filePointer < raf.length()) {
            val chunkId = ByteArray(4)
            raf.readFully(chunkId)
            val chunkSizeBytes = ByteArray(4)
            raf.readFully(chunkSizeBytes)
            val chunkSize = ByteBuffer.wrap(chunkSizeBytes).order(ByteOrder.LITTLE_ENDIAN).int

            val id = String(chunkId)
            when (id) {
                "fmt " -> {
                    val fmtData = ByteArray(chunkSize)
                    raf.readFully(fmtData)
                    val bb = ByteBuffer.wrap(fmtData).order(ByteOrder.LITTLE_ENDIAN)
                    bb.short // audio format
                    channels = bb.short.toInt()
                    sampleRate = bb.int
                    bb.int // byte rate
                    bb.short // block align
                    bitsPerSample = bb.short.toInt()
                }
                "data" -> {
                    dataSize = chunkSize
                    dataFound = true
                }
                else -> {
                    raf.skipBytes(chunkSize)
                }
            }
        }

        val numSamples = dataSize / (bitsPerSample / 8)
        val rawBytes = ByteArray(dataSize)
        raf.readFully(rawBytes)
        raf.close()

        val samples = ShortArray(numSamples)
        val bb = ByteBuffer.wrap(rawBytes).order(ByteOrder.LITTLE_ENDIAN)
        for (i in 0 until numSamples) {
            samples[i] = bb.short
        }

        return Triple(samples, sampleRate, channels)
    }

    fun writeWav(file: File, samples: ShortArray, sampleRate: Int, channels: Int) {
        val bitsPerSample = 16
        val dataSize = samples.size * 2
        val byteRate = sampleRate * channels * bitsPerSample / 8
        val blockAlign = channels * bitsPerSample / 8

        val raf = RandomAccessFile(file, "rw")
        raf.setLength(0)

        // RIFF header
        raf.writeBytes("RIFF")
        raf.write(intToLEBytes(36 + dataSize))
        raf.writeBytes("WAVE")

        // fmt chunk
        raf.writeBytes("fmt ")
        raf.write(intToLEBytes(16))
        raf.write(shortToLEBytes(1)) // PCM
        raf.write(shortToLEBytes(channels.toShort()))
        raf.write(intToLEBytes(sampleRate))
        raf.write(intToLEBytes(byteRate))
        raf.write(shortToLEBytes(blockAlign.toShort()))
        raf.write(shortToLEBytes(bitsPerSample.toShort()))

        // data chunk
        raf.writeBytes("data")
        raf.write(intToLEBytes(dataSize))

        val buffer = ByteBuffer.allocate(samples.size * 2).order(ByteOrder.LITTLE_ENDIAN)
        for (s in samples) buffer.putShort(s)
        raf.write(buffer.array())
        raf.close()
    }

    /**
     * Process audio: decode input, trim, apply a single step, write WAV output.
     */
    fun processAudio(
        inputFile: File,
        outputFile: File,
        trimStart: Double,
        trimEnd: Double,
        step: ScramblerStep
    ): Double {
        // Decode or read WAV
        val (samples, sampleRate, channels) = readOrDecode(inputFile)
        val totalFrames = samples.size / channels

        // Trim
        val trimStartFrames = min((trimStart * sampleRate).roundToInt(), totalFrames)
        val trimEndFrames = min((trimEnd * sampleRate).roundToInt(), totalFrames)
        val endFrame = max(trimStartFrames, totalFrames - trimEndFrames)
        val kept = endFrame - trimStartFrames
        if (kept < 2) throw IllegalArgumentException("Trim removed too much audio")

        val trimmedSamples = if (trimStartFrames > 0 || kept < totalFrames) {
            val result = ShortArray(kept * channels)
            for (ch in 0 until channels) {
                for (i in 0 until kept) {
                    result[i * channels + ch] = samples[(trimStartFrames + i) * channels + ch]
                }
            }
            result
        } else {
            samples
        }

        // Apply step
        val frameCount = trimmedSamples.size / channels
        applyStep(trimmedSamples, frameCount, channels, sampleRate, step)

        writeWav(outputFile, trimmedSamples, sampleRate, channels)
        return frameCount.toDouble() / sampleRate
    }

    /**
     * Apply multiple steps sequentially (for decode).
     */
    fun applySteps(inputFile: File, outputFile: File, steps: List<ScramblerStep>): Double {
        val (samples, sampleRate, channels) = readOrDecode(inputFile)
        val frameCount = samples.size / channels

        for (step in steps) {
            applyStep(samples, frameCount, channels, sampleRate, step)
        }

        writeWav(outputFile, samples, sampleRate, channels)
        return frameCount.toDouble() / sampleRate
    }

    private fun readOrDecode(file: File): Triple<ShortArray, Int, Int> {
        return if (file.extension.lowercase() == "wav") {
            readWav(file)
        } else {
            val tempWav = File.createTempFile("decode_input_", ".wav", file.parentFile ?: File(System.getProperty("java.io.tmpdir")!!)
)
            tempWav.deleteOnExit()
            val info = decodeToWav(file, tempWav)
            val result = readWav(tempWav)
            tempWav.delete()
            result
        }
    }

    private fun applyStep(
        samples: ShortArray,
        frameCount: Int,
        channels: Int,
        sampleRate: Int,
        step: ScramblerStep
    ) {
        val chunkFrames = when (step) {
            is ScramblerStep.Reverse -> frameCount
            is ScramblerStep.ChunkedReverse -> max(1, (step.chunkSize * sampleRate).roundToInt())
        }

        // Reverse in chunks, for each channel
        var s = 0
        while (s < frameCount) {
            val e = min(s + chunkFrames, frameCount)
            // Reverse frames s..e-1
            var l = s
            var r = e - 1
            while (l < r) {
                for (ch in 0 until channels) {
                    val li = l * channels + ch
                    val ri = r * channels + ch
                    val tmp = samples[li]
                    samples[li] = samples[ri]
                    samples[ri] = tmp
                }
                l++
                r--
            }
            s = e
        }
    }

    /**
     * Generate waveform data (peak amplitudes) for visualization.
     */
    fun generateWaveform(file: File, pointCount: Int = 200): FloatArray {
        return try {
            val (samples, _, channels) = readOrDecode(file)
            val totalFrames = samples.size / channels
            if (totalFrames == 0) return FloatArray(0)

            val samplesPerPoint = max(1, totalFrames / pointCount)
            val result = FloatArray(min(pointCount, totalFrames))

            for (i in result.indices) {
                val start = i * samplesPerPoint
                val end = min(start + samplesPerPoint, totalFrames)
                var peak = 0f
                for (j in start until end) {
                    // Use first channel
                    val v = abs(samples[j * channels].toFloat()) / 32768f
                    if (v > peak) peak = v
                }
                result[i] = peak
            }

            val mx = result.max()
            if (mx > 0f) {
                for (i in result.indices) result[i] /= mx
            }
            result
        } catch (e: Exception) {
            FloatArray(0)
        }
    }

    /**
     * Get audio duration in seconds.
     */
    fun getAudioDuration(file: File): Double {
        return try {
            val extractor = MediaExtractor()
            extractor.setDataSource(file.absolutePath)
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("audio/")) {
                    val duration = format.getLong(MediaFormat.KEY_DURATION)
                    extractor.release()
                    return duration / 1_000_000.0
                }
            }
            extractor.release()
            0.0
        } catch (e: Exception) {
            0.0
        }
    }

    private fun intToLEBytes(value: Int): ByteArray {
        return ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(value).array()
    }

    private fun shortToLEBytes(value: Short): ByteArray {
        return ByteBuffer.allocate(2).order(ByteOrder.LITTLE_ENDIAN).putShort(value).array()
    }
}
