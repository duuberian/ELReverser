import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var vm = AudioReverserViewModel()
    @State private var isImporterPresented = false
    @State private var isDropTargeted = false
    @State private var draggedItemID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()

            if vm.isRecording {
                recordingBanner
                Divider()
            }

            if vm.items.isEmpty && !vm.isRecording {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(vm.items) { item in
                            let depth = vm.depth(of: item)
                            AudioRow(item: item, vm: vm, depth: depth)
                                .onDrag {
                                    NSItemProvider(object: item.id.uuidString as NSString)
                                }
                                .onDrop(of: [.text], delegate: RowDropDelegate(
                                    targetID: item.id, vm: vm, draggedID: $draggedItemID
                                ))
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                }
            }
        }
        .frame(minWidth: 580, idealWidth: 660, minHeight: 440, idealHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            vm.handleDrop(providers: providers)
        }
        .overlay(dropOverlay)
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            vm.handleFileImport(result)
        }
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 49 {
                    if vm.isRecording { vm.stopRecording() }
                    else if vm.playingItemID != nil { vm.stop() }
                    else { vm.startRecording() }
                    return nil
                }
                return event
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                vm.isRecording ? vm.stopRecording() : vm.startRecording()
            } label: {
                HStack(spacing: 6) {
                    if vm.isRecording {
                        RoundedRectangle(cornerRadius: 2).fill(Color.red).frame(width: 10, height: 10)
                    } else {
                        Circle().fill(Color.red.opacity(0.8)).frame(width: 10, height: 10)
                    }
                    Text(vm.isRecording ? "Stop" : "Record")
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(vm.isRecording ? Color.red.opacity(0.12) : Color(nsColor: .controlBackgroundColor)))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .keyboardShortcut("r", modifiers: [.command])

            Button {
                isImporterPresented = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                    Text("Add File").font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor)))
            }
            .buttonStyle(.plain)
            .focusable(false)

            Spacer()

            if !vm.items.isEmpty {
                Text("\(vm.items.count) item\(vm.items.count == 1 ? "" : "s")")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    // MARK: - Recording Banner

    private var recordingBanner: some View {
        HStack(spacing: 10) {
            PulsingDot()
            Text("Recording").font(.system(size: 12, weight: .medium)).foregroundStyle(.red)
            Text(vm.formattedRecordingTime)
                .font(.system(size: 18, weight: .light, design: .monospaced))
                .contentTransition(.numericText())
            Spacer()
            Text("Space or ⌘R to stop").font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color.red.opacity(0.03))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "waveform").font(.system(size: 28)).foregroundStyle(.quaternary)
            Text("Drop an audio file or press Space to record")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Text("WAV · M4A · MP3 · AIFF")
                .font(.system(size: 10)).foregroundStyle(.quaternary).padding(.top, 2)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var dropOverlay: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .background(Color.accentColor.opacity(0.04))
                .padding(4).allowsHitTesting(false)
        }
    }
}

// MARK: - Audio Row

struct AudioRow: View {
    let item: AudioItem
    @ObservedObject var vm: AudioReverserViewModel
    var depth: Int = 0
    @State private var isHovered = false
    @State private var options = ReverseOptions()
    @State private var isEditingName = false
    @State private var editedName = ""
    @State private var showDecodeField = false
    @State private var decodeCode = ""
    @State private var codeCopied = false

    private var isPlaying: Bool { vm.playingItemID == item.id }
    private var isLoading: Bool { item.isLoading }
    private var isExpanded: Bool { vm.expandedItemID == item.id }
    private var isChild: Bool { depth > 0 }

    private var itemColor: Color {
        if item.isDecoded { return .green }
        if item.isReversed { return .purple }
        return .accentColor
    }

    var body: some View {
        VStack(spacing: 0) {
            mainRow
            if showDecodeField { decodePanel }
            if isExpanded && !isLoading { reverseSettingsPanel }
        }
        .background(
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(rowBg)
                // Left accent bar for children
                if isChild {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(itemColor.opacity(0.3))
                        .frame(width: 3)
                        .padding(.vertical, 4)
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isExpanded || showDecodeField ? itemColor.opacity(0.15) : Color.clear, lineWidth: 1)
        )
        .padding(.leading, CGFloat(depth) * 20)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.1)) { isHovered = h } }
        .onExitCommand {
            if isEditingName { isEditingName = false }
            else if showDecodeField { showDecodeField = false }
            else if isExpanded { vm.toggleExpanded(item: item) }
        }
        .onChange(of: isExpanded) { expanded in
            if expanded { options.trimStart = 0; options.trimEnd = 0 }
        }
    }

    // MARK: - Main Row

    private var mainRow: some View {
        HStack(spacing: 0) {
            // Play button
            Button {
                isPlaying ? vm.stop() : vm.play(item: item)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isPlaying ? Color.red.opacity(0.1) : itemColor.opacity(0.08))
                        .frame(width: 36, height: 36)

                    if isLoading {
                        ProgressView().scaleEffect(0.45)
                    } else if isHovered || isPlaying {
                        Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isPlaying ? .red : .primary.opacity(0.6))
                    } else {
                        Image(systemName: item.isDecoded ? "lock.open.fill" :
                                (item.isReversed ? "shuffle" : "waveform"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(itemColor)
                    }
                }
            }
            .buttonStyle(.plain).disabled(isLoading)

            // Mini waveform
            let waveform = vm.waveformSamples(for: item)
            if !waveform.isEmpty {
                MiniWaveform(samples: waveform, color: itemColor)
                    .frame(width: 48, height: 24)
                    .padding(.leading, 8)
                    .opacity(0.7)
            }

            // Name + metadata
            VStack(alignment: .leading, spacing: 2) {
                if isEditingName {
                    HStack(spacing: 4) {
                        TextField("Name", text: $editedName, onCommit: {
                            let trimmed = editedName.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty { vm.rename(itemID: item.id, to: trimmed) }
                            isEditingName = false
                        })
                        .font(.system(size: 12, weight: .medium))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 180)
                        .onExitCommand { isEditingName = false }

                        Button { isEditingName = false } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    // Use short name for children, full name for root
                    Text(isChild ? item.shortName : item.name)
                        .font(.system(size: 12, weight: isChild ? .regular : .medium))
                        .lineLimit(1)
                        .onTapGesture(count: 2) {
                            editedName = item.name
                            isEditingName = true
                        }
                }

                HStack(spacing: 5) {
                    if item.duration > 0 {
                        Text(formatDuration(item.duration))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }

                    if item.isDecoded {
                        Label("decoded", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.green.opacity(0.7))
                    } else if !item.steps.isEmpty {
                        Text("\(item.steps.count) step\(item.steps.count == 1 ? "" : "s")")
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.purple.opacity(0.1)))
                            .foregroundStyle(.purple.opacity(0.7))
                    }

                    if let summary = item.operationSummary {
                        Text(summary)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary.opacity(0.7))
                    }
                }
            }
            .padding(.leading, 8)

            Spacer(minLength: 8)

            // Action buttons
            HStack(spacing: 1) {
                if !isLoading {
                    actionBtn(icon: "shuffle", tip: "Reverse", dimmed: !isHovered) {
                        vm.toggleExpanded(item: item)
                    }

                    if !item.steps.isEmpty {
                        actionBtn(icon: codeCopied ? "checkmark" : "doc.on.doc",
                                  tip: codeCopied ? "Copied!" : "Copy code",
                                  tint: codeCopied ? .green : nil, dimmed: !isHovered) {
                            vm.copyCode(for: item)
                            codeCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { codeCopied = false }
                        }
                    }

                    actionBtn(icon: "lock.open", tip: "Decode", dimmed: !isHovered) {
                        withAnimation(.easeOut(duration: 0.15)) { showDecodeField.toggle() }
                    }

                    actionBtn(icon: "arrow.down.to.line", tip: "Save", dimmed: !isHovered) {
                        vm.save(item: item)
                    }

                    actionBtn(icon: "xmark", tip: "Remove", tint: .red.opacity(0.6), dimmed: !isHovered) {
                        vm.delete(item: item)
                    }
                }
            }

            if isPlaying && !isHovered {
                PlayingBars().frame(width: 18, height: 12).padding(.trailing, 4)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: - Action Button

    private func actionBtn(icon: String, tip: String, tint: Color? = nil, dimmed: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(dimmed ? Color.secondary.opacity(0.2) : (tint ?? Color.secondary.opacity(0.7)))
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(dimmed ? Color.clear : Color.secondary.opacity(0.06)))
        }
        .buttonStyle(.plain).help(tip)
    }

    // MARK: - Decode Panel

    private func runDecode(withCode: String? = nil) {
        let code = (withCode ?? decodeCode).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        vm.decode(item: item, code: code)
        showDecodeField = false
        decodeCode = ""
    }

    private var decodePanel: some View {
        VStack(spacing: 6) {
            Divider().padding(.horizontal, 8)

            HStack(spacing: 6) {
                Image(systemName: "lock.open")
                    .font(.system(size: 11))
                    .foregroundStyle(.green.opacity(0.6))

                TextField("SCR1:R-C0.5-R ...", text: $decodeCode, onCommit: { runDecode() })
                    .font(.system(size: 11, design: .monospaced))
                    .textFieldStyle(.roundedBorder)

                Button {
                    var code = decodeCode.trimmingCharacters(in: .whitespaces)
                    if code.isEmpty, let cb = NSPasteboard.general.string(forType: .string) {
                        code = cb.trimmingCharacters(in: .whitespacesAndNewlines)
                        decodeCode = code
                    }
                    runDecode(withCode: code)
                } label: {
                    Text("Decode")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .foregroundColor(.white)
                        .background(Capsule().fill(Color.green))
                }
                .buttonStyle(.plain)

                Button {
                    if let cb = NSPasteboard.general.string(forType: .string) { decodeCode = cb }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.06)))
                }
                .buttonStyle(.plain).help("Paste")

                Button {
                    showDecodeField = false; decodeCode = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.bottom, 6)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Reverse Settings Panel

    private var reverseSettingsPanel: some View {
        let src = vm.reverseSource(for: item)
        let srcDuration = src.duration
        let waveform = vm.waveformSamples(for: item)

        return VStack(spacing: 10) {
            Divider().padding(.horizontal, 8)

            // Trim
            if srcDuration > 0 {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Trim").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary).textCase(.uppercase)
                        Spacer()
                        Button {
                            if isPlaying { vm.stop() } else {
                                vm.playTrimPreview(
                                    url: src.url, trimStart: options.trimStart,
                                    duration: srcDuration, trimEnd: options.trimEnd,
                                    itemID: item.id
                                )
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: isPlaying ? "stop.fill" : "play.fill").font(.system(size: 8))
                                Text(isPlaying ? "Stop" : "Preview").font(.system(size: 10, weight: .medium))
                            }
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                    }

                    WaveformTrimSlider(
                        duration: srcDuration,
                        trimStart: $options.trimStart,
                        trimEnd: $options.trimEnd,
                        waveform: waveform,
                        accentColor: itemColor
                    )

                    HStack {
                        Text(formatDuration(options.trimStart))
                            .font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                        Spacer()
                        let kept = max(0, srcDuration - options.trimStart - options.trimEnd)
                        Text("\(formatDuration(kept)) selected")
                            .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                        Spacer()
                        Text(formatDuration(srcDuration - options.trimEnd))
                            .font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 12)
            }

            // Chunks
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Text("Chunks").font(.system(size: 11))
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { options.useChunks.toggle() }
                    } label: {
                        ZStack(alignment: options.useChunks ? .trailing : .leading) {
                            Capsule()
                                .fill(options.useChunks ? Color.accentColor : Color.secondary.opacity(0.2))
                                .frame(width: 32, height: 18)
                            Circle()
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                                .frame(width: 14, height: 14)
                                .padding(.horizontal, 2)
                        }
                    }
                    .buttonStyle(.plain)
                }

                if options.useChunks {
                    HStack(spacing: 3) {
                        ForEach([0.25, 0.5, 1.0, 2.0], id: \.self) { val in
                            Button { options.chunkSize = val } label: {
                                Text(val < 1 ? "\(String(format: "%.2g", val))s" : "\(Int(val))s")
                                    .font(.system(size: 9, weight: .medium))
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(RoundedRectangle(cornerRadius: 3)
                                        .fill(abs(options.chunkSize - val) < 0.01
                                              ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.06)))
                            }
                            .buttonStyle(.plain)
                        }
                        TextField("", value: $options.chunkSize, format: .number.precision(.fractionLength(1...2)))
                            .frame(width: 40).textFieldStyle(.roundedBorder).font(.system(size: 10))
                        Text("s").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12)

            // Steps chain (if already has steps)
            if !item.steps.isEmpty {
                HStack(spacing: 3) {
                    Text("Chain:")
                        .font(.system(size: 9)).foregroundStyle(.tertiary)
                    ForEach(Array(item.steps.enumerated()), id: \.offset) { _, step in
                        Text(step.displayName)
                            .font(.system(size: 8, weight: .medium))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 2).fill(Color.purple.opacity(0.1)))
                            .foregroundStyle(.purple)
                    }
                    Image(systemName: "arrow.right").font(.system(size: 8)).foregroundStyle(.tertiary)
                    Text(options.useChunks ? "Chunk \(String(format: "%.2g", options.chunkSize))s" : "Reverse")
                        .font(.system(size: 8, weight: .medium))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 2).fill(Color.orange.opacity(0.1)))
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 12)
            }

            // Action buttons
            HStack {
                Button {
                    vm.toggleExpanded(item: item)
                } label: {
                    Text("Cancel").font(.system(size: 11))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                if options.useChunks {
                    Text("Each \(String(format: "%.2g", options.chunkSize))s chunk reversed separately")
                        .font(.system(size: 9)).foregroundStyle(.tertiary)
                }

                Button {
                    vm.reverseItem(item: item, options: options)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "shuffle").font(.system(size: 10))
                        Text("Reverse").font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .foregroundColor(.white)
                    .background(Capsule().fill(Color.purple))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.bottom, 8)
        }
        .padding(.top, 2)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Helpers

    private var rowBg: Color {
        if isExpanded || showDecodeField { return Color(nsColor: .controlBackgroundColor) }
        if isHovered { return Color(nsColor: .controlBackgroundColor).opacity(0.8) }
        if isChild { return itemColor.opacity(0.02) }
        return Color.clear
    }

    private func formatDuration(_ t: Double) -> String {
        let s = max(0, t)
        if s < 60 { return String(format: "%.1fs", s) }
        let m = Int(s) / 60
        let sec = s - Double(m * 60)
        return String(format: "%d:%04.1f", m, sec)
    }
}

// MARK: - Mini Waveform

struct MiniWaveform: View {
    let samples: [Float]
    var color: Color = .accentColor

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let count = min(samples.count, 24)
            let step = max(1, samples.count / count)
            let barW = w / CGFloat(count) - 0.5

            HStack(spacing: 0.5) {
                ForEach(0..<count, id: \.self) { i in
                    let idx = min(i * step, samples.count - 1)
                    let amp = CGFloat(samples[idx]) * h * 0.9
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(color.opacity(0.5))
                        .frame(width: max(barW, 1), height: max(amp, 1))
                }
            }
            .frame(width: w, height: h, alignment: .center)
        }
    }
}

// MARK: - Waveform Trim Slider

struct WaveformTrimSlider: View {
    let duration: Double
    @Binding var trimStart: Double
    @Binding var trimEnd: Double
    let waveform: [Float]
    var accentColor: Color = .accentColor

    @State private var dragStartLeft: Double?
    @State private var dragStartRight: Double?

    private let barHeight: CGFloat = 44
    private let handleW: CGFloat = 10
    private let snapThreshold: Double = 0.15

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let leftFrac = duration > 0 ? CGFloat(trimStart / duration) : 0
            let rightFrac = duration > 0 ? CGFloat(trimEnd / duration) : 0
            let leftX = leftFrac * w
            let rightX = w - rightFrac * w

            ZStack(alignment: .topLeading) {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.04))
                    .frame(width: w, height: barHeight)

                // Full waveform (dim)
                WaveformShape(samples: waveform)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: w, height: barHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                // Dimmed left
                if leftX > 0 {
                    Color(nsColor: .windowBackgroundColor).opacity(0.8)
                        .frame(width: leftX, height: barHeight)
                        .position(x: leftX / 2, y: barHeight / 2)
                }

                // Dimmed right
                let rightW = w - rightX
                if rightW > 0 {
                    Color(nsColor: .windowBackgroundColor).opacity(0.8)
                        .frame(width: rightW, height: barHeight)
                        .position(x: rightX + rightW / 2, y: barHeight / 2)
                }

                // Selected waveform
                let selW = max(0, rightX - leftX)
                if selW > 0 {
                    WaveformShape(samples: waveform)
                        .fill(accentColor.opacity(0.35))
                        .frame(width: w, height: barHeight)
                        .mask(Rectangle().frame(width: selW, height: barHeight)
                            .position(x: leftX + selW / 2, y: barHeight / 2))

                    // Top/bottom selection border
                    Rectangle().fill(accentColor.opacity(0.3))
                        .frame(width: selW, height: 1)
                        .position(x: leftX + selW / 2, y: 0.5)
                    Rectangle().fill(accentColor.opacity(0.3))
                        .frame(width: selW, height: 1)
                        .position(x: leftX + selW / 2, y: barHeight - 0.5)
                }

                // Left handle
                handleView()
                    .position(x: leftX, y: barHeight / 2)
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .local)
                        .onChanged { v in
                            if dragStartLeft == nil { dragStartLeft = trimStart }
                            let delta = Double(v.translation.width / w) * duration
                            trimStart = max(0, min(duration - trimEnd - 0.05, (dragStartLeft ?? 0) + delta))
                        }
                        .onEnded { _ in dragStartLeft = nil })

                // Right handle
                handleView()
                    .position(x: rightX, y: barHeight / 2)
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .local)
                        .onChanged { v in
                            if dragStartRight == nil { dragStartRight = trimEnd }
                            let delta = Double(v.translation.width / w) * duration
                            trimEnd = max(0, min(duration - trimStart - 0.05, (dragStartRight ?? 0) - delta))
                        }
                        .onEnded { _ in dragStartRight = nil })
            }
            .frame(width: w, height: barHeight).clipped()
        }
        .frame(height: barHeight)
    }

    private func handleView() -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(accentColor)
                .frame(width: handleW, height: barHeight)
            VStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 0.5).fill(Color.white.opacity(0.6)).frame(width: 2, height: 7)
                RoundedRectangle(cornerRadius: 0.5).fill(Color.white.opacity(0.6)).frame(width: 2, height: 7)
            }
        }
        .frame(width: handleW + 14, height: barHeight + 6)
        .contentShape(Rectangle())
    }
}

// MARK: - Waveform Shape

struct WaveformShape: Shape {
    let samples: [Float]
    func path(in rect: CGRect) -> Path {
        guard samples.count > 1 else { return Path() }
        var path = Path()
        let midY = rect.midY
        let barWidth = rect.width / CGFloat(samples.count)
        for (i, sample) in samples.enumerated() {
            let x = CGFloat(i) * barWidth
            let amp = CGFloat(sample) * rect.height * 0.45
            path.addRoundedRect(in: CGRect(x: x, y: midY - amp, width: max(barWidth - 0.5, 0.5), height: amp * 2),
                                cornerSize: CGSize(width: 0.5, height: 0.5))
        }
        return path
    }
}

// MARK: - Row Drop Delegate

struct RowDropDelegate: DropDelegate {
    let targetID: UUID
    @ObservedObject var vm: AudioReverserViewModel
    @Binding var draggedID: UUID?

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedID, dragged != targetID else {
            if let provider = info.itemProviders(for: [.text]).first {
                provider.loadObject(ofClass: NSString.self) { str, _ in
                    if let idStr = str as? String, let uuid = UUID(uuidString: idStr) {
                        DispatchQueue.main.async {
                            self.draggedID = uuid
                            self.vm.moveItem(fromID: uuid, toID: self.targetID)
                        }
                    }
                }
            }
            return
        }
        vm.moveItem(fromID: dragged, toID: targetID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool { true }
}

// MARK: - Pulsing Dot

struct PulsingDot: View {
    @State private var pulse = false
    var body: some View {
        ZStack {
            Circle().fill(Color.red.opacity(0.2)).frame(width: 16, height: 16)
                .scaleEffect(pulse ? 1.4 : 1.0).opacity(pulse ? 0 : 0.8)
            Circle().fill(Color.red).frame(width: 7, height: 7)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

// MARK: - Playing Bars

struct PlayingBars: View {
    @State private var animate = false
    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<3) { i in
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(Color.accentColor.opacity(0.5))
                    .frame(width: 2.5, height: animate ? CGFloat.random(in: 3...12) : 3)
                    .animation(.easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.15), value: animate)
            }
        }
        .onAppear { animate = true }
    }
}
