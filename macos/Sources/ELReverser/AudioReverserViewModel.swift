import SwiftUI
import AVFoundation
import AppKit
import UniformTypeIdentifiers

// MARK: - Scrambler Step

enum ScramblerStep: Codable, Equatable {
    case reverse
    case chunkedReverse(chunkSize: Double)

    var displayName: String {
        switch self {
        case .reverse: return "Reverse"
        case .chunkedReverse(let s): return "Chunk \(String(format: "%.2g", s))s"
        }
    }

    /// Encode to compact string token
    var token: String {
        switch self {
        case .reverse: return "R"
        case .chunkedReverse(let s): return "C\(String(format: "%.4g", s))"
        }
    }

    /// Decode from compact string token
    static func from(token: String) -> ScramblerStep? {
        if token == "R" { return .reverse }
        if token.hasPrefix("C"), let val = Double(String(token.dropFirst())), val > 0 {
            return .chunkedReverse(chunkSize: val)
        }
        return nil
    }
}

// MARK: - Scramble Code

struct ScrambleCode {
    static let prefix = "SCR1:"

    static func encode(steps: [ScramblerStep]) -> String {
        let tokens = steps.map { $0.token }.joined(separator: "-")
        return prefix + tokens
    }

    static func decode(code: String) -> [ScramblerStep]? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else { return nil }
        let body = String(trimmed.dropFirst(prefix.count))
        guard !body.isEmpty else { return nil }
        let tokens = body.split(separator: "-").map(String.init)
        var steps: [ScramblerStep] = []
        for t in tokens {
            guard let step = ScramblerStep.from(token: t) else { return nil }
            steps.append(step)
        }
        return steps.isEmpty ? nil : steps
    }

    /// To unscramble: apply the same operations in reverse order
    /// (reverse is self-inverse, chunked reverse is self-inverse)
    static func inverseSteps(of steps: [ScramblerStep]) -> [ScramblerStep] {
        return steps.reversed()
    }
}

// MARK: - Audio Item

struct AudioItem: Identifiable {
    let id: UUID
    var name: String
    let url: URL
    let duration: Double
    let isReversed: Bool
    let isDecoded: Bool
    let isLoading: Bool
    let parentID: UUID?
    let sourceURL: URL?
    let sourceDuration: Double
    let prevTrimStart: Double
    let prevTrimEnd: Double
    /// All scramble steps from root to this item
    let steps: [ScramblerStep]
    let operationSummary: String?

    init(id: UUID = UUID(), name: String, url: URL, duration: Double,
         isReversed: Bool, isDecoded: Bool = false, isLoading: Bool = false, parentID: UUID? = nil,
         sourceURL: URL? = nil, sourceDuration: Double = 0,
         prevTrimStart: Double = 0, prevTrimEnd: Double = 0,
         steps: [ScramblerStep] = [],
         operationSummary: String? = nil) {
        self.id = id; self.name = name; self.url = url; self.duration = duration
        self.isReversed = isReversed; self.isDecoded = isDecoded; self.isLoading = isLoading
        self.parentID = parentID; self.sourceURL = sourceURL
        self.sourceDuration = sourceDuration
        self.prevTrimStart = prevTrimStart; self.prevTrimEnd = prevTrimEnd
        self.steps = steps; self.operationSummary = operationSummary
    }

    var scrambleCode: String? {
        guard !steps.isEmpty else { return nil }
        return ScrambleCode.encode(steps: steps)
    }

    /// Short display name (just the last operation, not the full chain)
    var shortName: String {
        if isDecoded { return "Decoded" }
        if let last = steps.last {
            return last.displayName
        }
        return name
    }
}

struct ReverseOptions {
    var trimStart: Double = 0
    var trimEnd: Double = 0
    var useChunks: Bool = false
    var chunkSize: Double = 0.5
}

// MARK: - ViewModel

@MainActor
final class AudioReverserViewModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var items: [AudioItem] = []
    @Published var isRecording = false
    @Published var recordingTime: TimeInterval = 0
    @Published var playingItemID: UUID?
    @Published var expandedItemID: UUID?
    @Published var sourceWaveformCache: [String: [Float]] = [:]

    /// Compute the nesting depth of an item (0 for root, 1 for child, 2 for grandchild, etc.)
    func depth(of item: AudioItem) -> Int {
        var d = 0
        var current = item
        while let pid = current.parentID, let parent = items.first(where: { $0.id == pid }) {
            d += 1
            current = parent
        }
        return d
    }

    /// Get the root ancestor name for an item
    func rootName(of item: AudioItem) -> String {
        var current = item
        while let pid = current.parentID, let parent = items.first(where: { $0.id == pid }) {
            current = parent
        }
        return current.name
    }
    @Published var showDecodeSheet = false
    @Published var decodeTargetItemID: UUID?

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var recordingTimer: Timer?
    private var currentPlayingID: UUID?

    // MARK: - Drop

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
            guard let self else { return }
            let url: URL?
            if let data = item as? Data {
                url = NSURL(absoluteURLWithDataRepresentation: data, relativeTo: nil) as URL?
            } else if let str = item as? String {
                url = URL(string: str)
            } else if let u = item as? URL {
                url = u
            } else { url = nil }
            if let url { Task { @MainActor in self.addFile(url: url) } }
        }
        return true
    }

    func handleFileImport(_ result: Result<[URL], Error>) {
        if case .success(let urls) = result, let url = urls.first { addFile(url: url) }
    }

    private func addFile(url: URL) {
        let dur = Self.audioDuration(url: url)
        let item = AudioItem(
            name: url.lastPathComponent, url: url, duration: dur,
            isReversed: false, sourceURL: url, sourceDuration: dur
        )
        withAnimation(.easeOut(duration: 0.2)) { items.insert(item, at: 0) }
    }

    nonisolated private static func audioDuration(url: URL) -> Double {
        (try? AVAudioFile(forReading: url)).map { Double($0.length) / $0.processingFormat.sampleRate } ?? 0
    }

    // MARK: - Rename

    func rename(itemID: UUID, to newName: String) {
        guard let idx = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[idx].name = newName
    }

    // MARK: - Recording

    func startRecording() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor in
                guard granted else { return }
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("recording-\(UUID().uuidString).m4a")
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 44_100,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                ]
                do {
                    self.recorder = try AVAudioRecorder(url: tempURL, settings: settings)
                    self.recorder?.record()
                    self.recordingTime = 0
                    self.isRecording = true
                    self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                        Task { @MainActor in
                            guard let self, self.isRecording else { return }
                            self.recordingTime += 0.1
                        }
                    }
                } catch {}
            }
        }
    }

    func stopRecording() {
        recorder?.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        if let url = recorder?.url {
            let secs = Int(recordingTime)
            let dur = Self.audioDuration(url: url)
            let item = AudioItem(
                name: "Recording (\(secs)s)", url: url, duration: dur,
                isReversed: false, sourceURL: url, sourceDuration: dur
            )
            withAnimation(.easeOut(duration: 0.2)) { items.insert(item, at: 0) }
        }
        recorder = nil
    }

    // MARK: - Play

    func play(item: AudioItem) {
        player?.stop()
        do {
            player = try AVAudioPlayer(contentsOf: item.url)
            player?.delegate = self
            player?.prepareToPlay()
            player?.play()
            playingItemID = item.id
            currentPlayingID = item.id
        } catch { playingItemID = nil }
    }

    func playTrimPreview(url: URL, trimStart: Double, duration: Double, trimEnd: Double, itemID: UUID) {
        player?.stop()
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.currentTime = trimStart
            player?.prepareToPlay()
            player?.play()
            playingItemID = itemID
            currentPlayingID = itemID
            let playDuration = max(0, duration - trimStart - trimEnd)
            if playDuration > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + playDuration) { [weak self] in
                    guard let self, self.currentPlayingID == itemID else { return }
                    self.stop()
                }
            }
        } catch { playingItemID = nil }
    }

    func stop() {
        player?.stop()
        playingItemID = nil
        currentPlayingID = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.playingItemID = nil
            self.currentPlayingID = nil
        }
    }

    // MARK: - Waveform

    func loadWaveform(for item: AudioItem) {
        let key = item.url.absoluteString
        guard sourceWaveformCache[key] == nil else { return }
        DispatchQueue.global(qos: .utility).async {
            let samples = Self.generateWaveform(url: item.url, pointCount: 200)
            DispatchQueue.main.async { self.sourceWaveformCache[key] = samples }
        }
    }

    func waveformSamples(for item: AudioItem) -> [Float] {
        return sourceWaveformCache[item.url.absoluteString] ?? []
    }

    nonisolated private static func generateWaveform(url: URL, pointCount: Int) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url) else { return [] }
        let totalFrames = AVAudioFrameCount(file.length)
        guard totalFrames > 0 else { return [] }
        guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: totalFrames) else { return [] }
        do { try file.read(into: buf) } catch { return [] }
        let frames = Int(buf.frameLength)
        guard frames > 0, let floatData = buf.floatChannelData?[0] else { return [] }
        let spp = max(1, frames / pointCount)
        var result: [Float] = []
        result.reserveCapacity(pointCount)
        for i in 0..<pointCount {
            let start = i * spp; let end = min(start + spp, frames)
            var peak: Float = 0
            for j in start..<end { let v = abs(floatData[j]); if v > peak { peak = v } }
            result.append(peak)
        }
        let mx = result.max() ?? 1
        if mx > 0 { for i in 0..<result.count { result[i] /= mx } }
        return result
    }

    // MARK: - Expand / Collapse

    func toggleExpanded(item: AudioItem) {
        withAnimation(.easeOut(duration: 0.2)) {
            if expandedItemID == item.id {
                expandedItemID = nil
            } else {
                expandedItemID = item.id
                loadWaveform(for: item)
            }
        }
    }

    // MARK: - Source info

    func reverseSource(for item: AudioItem) -> (url: URL, duration: Double) {
        return (item.url, item.duration)
    }

    // MARK: - Reverse

    func reverseItem(item: AudioItem, options: ReverseOptions) {
        expandedItemID = nil

        let source = reverseSource(for: item)

        // Build the new step
        let newStep: ScramblerStep
        if options.useChunks && options.chunkSize > 0 {
            newStep = .chunkedReverse(chunkSize: options.chunkSize)
        } else {
            newStep = .reverse
        }

        // Accumulate steps from parent
        var allSteps = item.steps
        allSteps.append(newStep)

        let placeholderID = UUID()
        let placeholder = AudioItem(
            id: placeholderID,
            name: "Reversed",
            url: item.url, duration: 0,
            isReversed: true, isLoading: true,
            parentID: item.id,
            steps: allSteps,
            operationSummary: "Generating…"
        )

        // Insert after parent and all its existing children
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            var insertIdx = idx + 1
            while insertIdx < items.count && items[insertIdx].parentID == item.id {
                insertIdx += 1
            }
            withAnimation(.easeOut(duration: 0.2)) {
                items.insert(placeholder, at: insertIdx)
            }
        }

        let tempOutput = FileManager.default.temporaryDirectory
            .appendingPathComponent("reversed-\(UUID().uuidString).wav")

        let trimOpts = options
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try AudioEngine.processAudio(
                    inputURL: source.url, outputURL: tempOutput,
                    trimStart: trimOpts.trimStart, trimEnd: trimOpts.trimEnd,
                    step: newStep
                )
                let dur = Self.audioDuration(url: tempOutput)
                let summary = Self.stepSummary(step: newStep, trimStart: trimOpts.trimStart, trimEnd: trimOpts.trimEnd)
                DispatchQueue.main.async {
                    if let idx = self.items.firstIndex(where: { $0.id == placeholderID }) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            self.items[idx] = AudioItem(
                                id: placeholderID,
                                name: "Reversed",
                                url: tempOutput, duration: dur,
                                isReversed: true, isLoading: false,
                                parentID: item.id,
                                steps: allSteps,
                                operationSummary: summary
                            )
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    withAnimation { self.items.removeAll { $0.id == placeholderID } }
                }
            }
        }
    }

    // MARK: - Decode (unscramble)

    func decode(item: AudioItem, code: String) {
        print("[Decode] code='\(code)'")
        guard let steps = ScrambleCode.decode(code: code) else {
            print("[Decode] Failed to parse code")
            return
        }
        let inverseSteps = ScrambleCode.inverseSteps(of: steps)
        print("[Decode] steps=\(steps.map { $0.token }), inverse=\(inverseSteps.map { $0.token })")

        let placeholderID = UUID()
        let placeholder = AudioItem(
            id: placeholderID,
            name: "Decoded",
            url: item.url, duration: 0,
            isReversed: false, isDecoded: true, isLoading: true,
            parentID: item.id,
            steps: [],
            operationSummary: "Decoding…"
        )

        // Insert after parent and all its existing children
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            var insertIdx = idx + 1
            while insertIdx < items.count && items[insertIdx].parentID == item.id {
                insertIdx += 1
            }
            withAnimation(.easeOut(duration: 0.2)) {
                items.insert(placeholder, at: insertIdx)
            }
        }

        let inputURL = item.url
        // First convert to WAV so we can process it
        let tempInput = FileManager.default.temporaryDirectory
            .appendingPathComponent("decode-input-\(UUID().uuidString).wav")
        let tempOutput = FileManager.default.temporaryDirectory
            .appendingPathComponent("decoded-\(UUID().uuidString).wav")

        print("[Decode] inputURL=\(inputURL.path), outputURL=\(tempOutput.path)")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Convert input to WAV first if needed (handles m4a, mp3, etc.)
                let processURL: URL
                if inputURL.pathExtension.lowercased() == "wav" {
                    processURL = inputURL
                } else {
                    try Self.convertToWAV(input: inputURL, output: tempInput)
                    processURL = tempInput
                }
                try AudioEngine.applySteps(inputURL: processURL, outputURL: tempOutput, steps: inverseSteps)
                let dur = Self.audioDuration(url: tempOutput)
                print("[Decode] Success! duration=\(dur)")
                DispatchQueue.main.async {
                    if let idx = self.items.firstIndex(where: { $0.id == placeholderID }) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            self.items[idx] = AudioItem(
                                id: placeholderID,
                                name: "Decoded",
                                url: tempOutput, duration: dur,
                                isReversed: false, isDecoded: true, isLoading: false,
                                parentID: item.id,
                                steps: [],
                                operationSummary: "Decoded (\(inverseSteps.count) steps undone)"
                            )
                        }
                    }
                }
            } catch {
                print("[Decode] ERROR: \(error)")
                DispatchQueue.main.async {
                    withAnimation { self.items.removeAll { $0.id == placeholderID } }
                }
            }
        }
    }

    nonisolated private static func stepSummary(step: ScramblerStep, trimStart: Double, trimEnd: Double) -> String {
        var parts = [step.displayName]
        if trimStart > 0 || trimEnd > 0 {
            parts.append("Trimmed \(String(format: "%.1f", trimStart))s–\(String(format: "%.1f", trimEnd))s")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Copy code

    func copyCode(for item: AudioItem) {
        guard let code = item.scrambleCode else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
    }

    // MARK: - Reorder

    func moveItem(fromID: UUID, toID: UUID) {
        guard fromID != toID else { return }
        guard let fromIdx = items.firstIndex(where: { $0.id == fromID }),
              let toIdx = items.firstIndex(where: { $0.id == toID }) else { return }

        // Don't allow moving a child away from parent context
        // (but allow reordering top-level items and their groups)
        withAnimation(.easeOut(duration: 0.2)) {
            let item = items.remove(at: fromIdx)
            let newToIdx = items.firstIndex(where: { $0.id == toID }) ?? toIdx
            items.insert(item, at: newToIdx)
        }
    }

    // MARK: - Save

    func save(item: AudioItem) {
        let ext = item.url.pathExtension
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = ext == "wav" ? [.wav] : [.audio]
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = item.name.hasSuffix(".\(ext)") ? item.name : "\(item.name).\(ext)"
        guard savePanel.runModal() == .OK, let outputURL = savePanel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: outputURL.path) { try FileManager.default.removeItem(at: outputURL) }
            try FileManager.default.copyItem(at: item.url, to: outputURL)
        } catch {}
    }

    // MARK: - Convert to WAV

    nonisolated private static func convertToWAV(input: URL, output: URL) throws {
        let inputFile = try AVAudioFile(forReading: input)
        let fmt = inputFile.processingFormat
        let totalFrames = AVAudioFrameCount(inputFile.length)
        guard totalFrames > 0 else { throw NSError(domain: "ELReverser", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty audio"]) }
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: totalFrames) else {
            throw NSError(domain: "ELReverser", code: -1, userInfo: [NSLocalizedDescriptionKey: "Buffer alloc failed"])
        }
        try inputFile.read(into: buf)
        let outFmt = AVAudioFormat(commonFormat: fmt.commonFormat, sampleRate: fmt.sampleRate,
                                    channels: fmt.channelCount, interleaved: fmt.isInterleaved)!
        let outFile = try AVAudioFile(forWriting: output, settings: outFmt.settings,
                                       commonFormat: outFmt.commonFormat, interleaved: outFmt.isInterleaved)
        try outFile.write(from: buf)
    }

    // MARK: - Delete

    func delete(item: AudioItem) {
        withAnimation(.easeOut(duration: 0.2)) {
            items.removeAll { $0.id == item.id || $0.parentID == item.id }
        }
    }

    var formattedRecordingTime: String {
        let m = Int(recordingTime) / 60
        let s = Int(recordingTime) % 60
        let t = Int((recordingTime * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "%d:%02d.%d", m, s, t)
    }
}

// MARK: - Audio Engine

enum AudioEngine {
    /// Process audio with a single step (trim + reverse)
    static func processAudio(inputURL: URL, outputURL: URL,
                             trimStart: Double, trimEnd: Double,
                             step: ScramblerStep) throws {
        let inputFile = try AVAudioFile(forReading: inputURL)
        let fmt = inputFile.processingFormat
        let totalFrames = AVAudioFrameCount(inputFile.length)
        guard totalFrames > 0 else { throw err("Audio file is empty.") }

        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: totalFrames) else {
            throw err("Could not allocate buffer.")
        }
        try inputFile.read(into: buf)

        var frameCount = Int(buf.frameLength)
        let ch = Int(fmt.channelCount)

        // Trim
        let tsf = min(Int((trimStart * fmt.sampleRate).rounded()), frameCount)
        let tef = min(Int((trimEnd * fmt.sampleRate).rounded()), frameCount)
        let endFrame = max(tsf, frameCount - tef)
        let kept = endFrame - tsf
        guard kept > 1 else { throw err("Trim removed too much audio.") }

        if tsf > 0 || kept < frameCount {
            try trimInPlace(buf: buf, fmt: fmt, start: tsf, kept: kept, ch: ch)
            frameCount = kept
            buf.frameLength = AVAudioFrameCount(frameCount)
        }

        // Apply step
        try applyStep(buf: buf, fmt: fmt, frames: frameCount, ch: ch, step: step)

        // Write
        try writeBuffer(buf, fmt: fmt, to: outputURL)
    }

    /// Apply multiple steps sequentially (for decode)
    static func applySteps(inputURL: URL, outputURL: URL, steps: [ScramblerStep]) throws {
        let inputFile = try AVAudioFile(forReading: inputURL)
        let fmt = inputFile.processingFormat
        let totalFrames = AVAudioFrameCount(inputFile.length)
        guard totalFrames > 0 else { throw err("Audio file is empty.") }

        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: totalFrames) else {
            throw err("Could not allocate buffer.")
        }
        try inputFile.read(into: buf)

        let frameCount = Int(buf.frameLength)
        let ch = Int(fmt.channelCount)

        for step in steps {
            try applyStep(buf: buf, fmt: fmt, frames: frameCount, ch: ch, step: step)
        }

        try writeBuffer(buf, fmt: fmt, to: outputURL)
    }

    private static func applyStep(buf: AVAudioPCMBuffer, fmt: AVAudioFormat, frames: Int, ch: Int, step: ScramblerStep) throws {
        let chunkFrames: Int
        switch step {
        case .reverse:
            chunkFrames = frames
        case .chunkedReverse(let size):
            chunkFrames = max(1, Int((size * fmt.sampleRate).rounded()))
        }

        switch fmt.commonFormat {
        case .pcmFormatFloat32:
            guard let cd = buf.floatChannelData else { throw err("Unsupported.") }
            for c in 0..<ch { revChunked(cd[c], frames: frames, chunk: chunkFrames) }
        case .pcmFormatInt16:
            guard let cd = buf.int16ChannelData else { throw err("Unsupported.") }
            for c in 0..<ch { revChunked(cd[c], frames: frames, chunk: chunkFrames) }
        case .pcmFormatInt32:
            guard let cd = buf.int32ChannelData else { throw err("Unsupported.") }
            for c in 0..<ch { revChunked(cd[c], frames: frames, chunk: chunkFrames) }
        default: throw err("Unsupported audio format.")
        }
    }

    private static func trimInPlace(buf: AVAudioPCMBuffer, fmt: AVAudioFormat, start: Int, kept: Int, ch: Int) throws {
        switch fmt.commonFormat {
        case .pcmFormatFloat32:
            guard let cd = buf.floatChannelData else { throw err("Unsupported.") }
            for c in 0..<ch { memmove(cd[c], cd[c].advanced(by: start), kept * MemoryLayout<Float>.size) }
        case .pcmFormatInt16:
            guard let cd = buf.int16ChannelData else { throw err("Unsupported.") }
            for c in 0..<ch { memmove(cd[c], cd[c].advanced(by: start), kept * MemoryLayout<Int16>.size) }
        case .pcmFormatInt32:
            guard let cd = buf.int32ChannelData else { throw err("Unsupported.") }
            for c in 0..<ch { memmove(cd[c], cd[c].advanced(by: start), kept * MemoryLayout<Int32>.size) }
        default: throw err("Unsupported.")
        }
    }

    private static func writeBuffer(_ buf: AVAudioPCMBuffer, fmt: AVAudioFormat, to url: URL) throws {
        guard let outFmt = AVAudioFormat(
            commonFormat: fmt.commonFormat, sampleRate: fmt.sampleRate,
            channels: fmt.channelCount, interleaved: fmt.isInterleaved
        ) else { throw err("Could not create output format.") }
        let outFile = try AVAudioFile(
            forWriting: url, settings: outFmt.settings,
            commonFormat: outFmt.commonFormat, interleaved: outFmt.isInterleaved
        )
        try outFile.write(from: buf)
    }

    private static func revChunked<T>(_ p: UnsafeMutablePointer<T>, frames: Int, chunk: Int) {
        var s = 0
        while s < frames {
            let e = min(s + chunk, frames)
            var l = s, r = e - 1
            while l < r { let t = p[l]; p[l] = p[r]; p[r] = t; l += 1; r -= 1 }
            s = e
        }
    }

    private static func err(_ msg: String) -> NSError {
        NSError(domain: "ELReverser", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
    }
}
