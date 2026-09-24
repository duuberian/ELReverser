import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var vm = AudioReverserViewModel()
    @State private var isImporterPresented = false
    @State private var isDropTargeted = false

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
                            AudioRow(item: item, vm: vm, depth: vm.depth(of: item))
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                }
            }
        }
        .frame(minWidth: 620, idealWidth: 700, minHeight: 460, idealHeight: 580)
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
        .alert(
            "Audio Operation Failed",
            isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) { vm.clearError() }
        } message: {
            Text(vm.errorMessage ?? "An unexpected error occurred.")
        }
        .onAppear {
            installKeyboardHandler()
            AppDelegate.shared?.sharedViewModel = vm
        }
    }

    private func installKeyboardHandler() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Let text controls handle spaces normally.
            let responder = NSApp.keyWindow?.firstResponder
            if event.keyCode == 49 && !(responder is NSTextView) {
                if vm.isRecording {
                    vm.stopRecording()
                } else if vm.playingItemID != nil {
                    vm.stop()
                } else if let item = vm.selectedItem {
                    vm.play(item: item)
                }
                return nil
            }
            return event
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                vm.isRecording ? vm.stopRecording() : vm.startRecording()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: vm.isRecording ? "stop.circle.fill" : "record.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(vm.isRecording ? .red : Color.red.opacity(0.75))
                    Text(vm.isRecording ? "Stop Recording" : "Record Audio")
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(vm.isRecording ? Color.red.opacity(0.12) : Color(nsColor: .controlBackgroundColor)))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .keyboardShortcut("r", modifiers: [.command])
            .help("Record audio (⌘R)")

            Button {
                isImporterPresented = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 14))
                    Text("Import Audio").font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor)))
            }
            .buttonStyle(.plain)
            .focusable(false)

            Spacer()

            if !vm.items.isEmpty {
                Label(
                    "\(vm.items.count) item\(vm.items.count == 1 ? "" : "s")",
                    systemImage: "waveform.list"
                )
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
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
            Image(systemName: "waveform.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(.quaternary)

            VStack(spacing: 6) {
                Text("Add audio to begin")
                    .font(.system(size: 15, weight: .medium))
                Text("Drop a file here, import it, or press ⌘R to record.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Button {
                    isImporterPresented = true
                } label: {
                    Label("Import Audio", systemImage: "plus.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                }
                .buttonStyle(.plain)

                Button {
                    vm.startRecording()
                } label: {
                    Label("Record", systemImage: "record.circle")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Color.secondary.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)

            Text("WAV · M4A · MP3 · AIFF")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
                .padding(.top, 4)
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
    private var isSelected: Bool { vm.selectedItemID == item.id }
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
            if isExpanded && !isLoading { scramblePanel }
        }
        .background(
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(rowBg)
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
                .strokeBorder((isExpanded || showDecodeField || isSelected)
                              ? itemColor.opacity(0.18) : Color.clear, lineWidth: 1)
        )
        .padding(.leading, CGFloat(depth) * 20)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) { isHovered = hovering }
        }
        .onTapGesture { vm.selectedItemID = item.id }
        .onExitCommand {
            if isEditingName { isEditingName = false }
            else if showDecodeField { showDecodeField = false }
            else if isExpanded { vm.toggleExpanded(item: item) }
            else { vm.selectedItemID = nil }
        }
        .contextMenu {
            Button {
                vm.toggleExpanded(item: item)
            } label: {
                Label("Scramble…", systemImage: "wand.and.stars")
            }

            Button {
                showDecodeField = true
            } label: {
                Label("Decode…", systemImage: "key")
            }

            Button {
                editedName = item.name
                isEditingName = true
            } label: {
                Label("Rename…", systemImage: "pencil")
            }

            Button {
                vm.save(item: item)
            } label: {
                Label("Save…", systemImage: "square.and.arrow.down")
            }

            Divider()

            Button(role: .destructive) {
                vm.delete(item: item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .onChange(of: isExpanded) { expanded in
            if expanded {
                options.trimStart = 0
                options.trimEnd = 0
            }
        }
    }

    // MARK: - Main Row

    private var mainRow: some View {
        HStack(spacing: 0) {
            playButton

            let waveform = vm.waveformSamples(for: item)
            if !waveform.isEmpty {
                MiniWaveform(samples: waveform, color: itemColor)
                    .frame(width: 48, height: 24)
                    .padding(.leading, 8)
                    .opacity(0.7)
            }

            VStack(alignment: .leading, spacing: 2) {
                if isEditingName {
                    renameField
                } else {
                    Text(displayName)
                        .font(.system(size: 12, weight: isChild ? .regular : .medium))
                        .lineLimit(1)
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
                            .lineLimit(1)
                    }
                }
            }
            .padding(.leading, 8)

            Spacer(minLength: 8)

            if isPlaying && !isHovered {
                PlayingBars().frame(width: 18, height: 12).padding(.trailing, 4)
            }

            HStack(spacing: 1) {
                if !isLoading {
                    actionBtn(icon: "wand.and.stars",
                              tip: "Scramble with reverse or chunked reverse",
                              active: isHovered, tint: itemColor) {
                        vm.toggleExpanded(item: item)
                    }

                    actionBtn(icon: "key",
                              tip: "Decode using a code",
                              active: isHovered, tint: .green) {
                        withAnimation(.easeOut(duration: 0.15)) { showDecodeField.toggle() }
                    }

                    moreMenu
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private var playButton: some View {
        Button {
            vm.selectedItemID = item.id
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
    }

    private var renameField: some View {
        HStack(spacing: 4) {
            TextField("Name", text: $editedName, onCommit: commitRename)
                .font(.system(size: 12, weight: .medium))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 180)
                .onExitCommand { isEditingName = false }

            Button(action: commitRename) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Finish renaming")
        }
    }

    private var moreMenu: some View {
        Menu {
            Button {
                vm.toggleExpanded(item: item)
            } label: {
                Label("Scramble…", systemImage: "wand.and.stars")
            }

            if item.scrambleCode != nil {
                Button {
                    vm.copyCode(for: item)
                    codeCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { codeCopied = false }
                } label: {
                    Label(codeCopied ? "Code Copied" : "Copy Decode Code", systemImage: codeCopied ? "checkmark" : "key.horizontal")
                }
            }

            Button {
                editedName = item.name
                isEditingName = true
            } label: {
                Label("Rename…", systemImage: "pencil")
            }

            Button {
                vm.save(item: item)
            } label: {
                Label("Save…", systemImage: "square.and.arrow.down")
            }

            Divider()

            Button(role: .destructive) {
                vm.delete(item: item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isHovered ? Color.secondary.opacity(0.85) : Color.secondary.opacity(0.45))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovered ? Color.secondary.opacity(0.08) : Color.secondary.opacity(0.04))
                )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More actions")
    }

    private func commitRename() {
        let trimmed = editedName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { vm.rename(itemID: item.id, to: trimmed) }
        isEditingName = false
    }

    private var displayName: String {
        if isEditingName { return item.name }
        if isChild { return item.shortName }
        return item.name
    }

    // MARK: - Action Button

    private func actionBtn(icon: String,
                           tip: String,
                           active: Bool,
                           tint: Color? = nil,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(active ? (tint ?? Color.secondary.opacity(0.85)) : Color.secondary.opacity(0.45))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(active ? Color.secondary.opacity(0.08) : Color.secondary.opacity(0.04))
                )
        }
        .buttonStyle(.plain)
        .help(tip)
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

            VStack(alignment: .leading, spacing: 4) {
                Text("This audio can be unscrambled with a reversible recipe. Paste its decode code to undo the operations.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                if let ownCode = item.scrambleCode {
                    HStack(spacing: 6) {
                        Text(ownCode)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Button {
                            vm.copyCode(for: item)
                            codeCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { codeCopied = false }
                        } label: {
                            Label(codeCopied ? "Copied" : "Copy", systemImage: codeCopied ? "checkmark" : "doc.on.clipboard")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .help("Copy this audio's decode code")
                    }
                }
            }
            .padding(.horizontal, 10)

            HStack(spacing: 6) {
                Image(systemName: "lock.open")
                    .font(.system(size: 11))
                    .foregroundStyle(.green.opacity(0.6))

                TextField("SCR1:R-C0.5-R", text: $decodeCode, onCommit: { runDecode() })
                    .font(.system(size: 11, design: .monospaced))
                    .textFieldStyle(.roundedBorder)

                Button {
                    if decodeCode.trimmingCharacters(in: .whitespaces).isEmpty,
                       let clipboard = NSPasteboard.general.string(forType: .string) {
                        decodeCode = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    runDecode()
                } label: {
                    Text("Decode")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .foregroundColor(.white)
                        .background(Capsule().fill(Color.green))
                }
                .buttonStyle(.plain)

                Button {
                    if let clipboard = NSPasteboard.general.string(forType: .string) {
                        decodeCode = clipboard
                    }
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

    // MARK: - Scramble Panel

    private var scramblePanel: some View {
        let source = vm.reverseSource(for: item)
        let sourceDuration = source.duration
        let waveform = vm.waveformSamples(for: item)
        let kept = max(0, sourceDuration - options.trimStart - options.trimEnd)

        return VStack(spacing: 10) {
            Divider().padding(.horizontal, 8)

            if sourceDuration > 0 {
                VStack(alignment: .leading, spacing: 5) {
                    sectionHeader("Trim")

                    WaveformTrimSlider(
                        duration: sourceDuration,
                        trimStart: $options.trimStart,
                        trimEnd: $options.trimEnd,
                        waveform: waveform,
                        accentColor: itemColor
                    )

                    HStack {
                        Text(formatDuration(options.trimStart))
                            .font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                        Spacer()
                        Text("\(formatDuration(kept)) selected")
                            .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                        Spacer()
                        Text(formatDuration(sourceDuration - options.trimEnd))
                            .font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                    }

                    HStack {
                        Button {
                            if isPlaying { vm.stop() } else {
                                vm.playTrimPreview(
                                    url: source.url, trimStart: options.trimStart,
                                    duration: sourceDuration, trimEnd: options.trimEnd,
                                    itemID: item.id
                                )
                            }
                        } label: {
                            Label(isPlaying ? "Stop" : "Preview Selection", systemImage: isPlaying ? "stop.fill" : "play.fill")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .buttonStyle(.plain)

                        Spacer()
                        Text("Scramble uses only the selected region.")
                            .font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 12)
            }

            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("Operation")

                HStack(spacing: 8) {
                    operationButton("Simple Reverse", subtitle: "Reverses the whole selection", isSelected: !options.useChunks) {
                        options.useChunks = false
                    }

                    operationButton("Chunked Reverse", subtitle: "Reverses each chunk separately", isSelected: options.useChunks) {
                        options.useChunks = true
                    }

                    Spacer()
                }

                if options.useChunks {
                    HStack(spacing: 5) {
                        Text("Chunk size").font(.system(size: 10)).foregroundStyle(.secondary)
                        ForEach([0.25, 0.5, 1.0, 2.0], id: \.self) { value in
                            Button { options.chunkSize = value } label: {
                                Text(chunkLabel(value))
                                    .font(.system(size: 9, weight: .medium))
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(RoundedRectangle(cornerRadius: 4)
                                        .fill(abs(options.chunkSize - value) < 0.01
                                              ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.06)))
                            }
                            .buttonStyle(.plain)
                        }

                        TextField("", value: $options.chunkSize, format: .number.precision(.fractionLength(1...2)))
                            .frame(width: 44).textFieldStyle(.roundedBorder).font(.system(size: 10))
                        Text("s").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 12)

            if !item.steps.isEmpty || options.trimStart > 0 || options.trimEnd > 0 {
                VStack(alignment: .leading, spacing: 5) {
                    sectionHeader("Pipeline")
                    pipelineView
                }
                .padding(.horizontal, 12)
            }

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

                Button {
                    vm.reverseItem(item: item, options: options)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "wand.and.stars").font(.system(size: 10))
                        Text("Apply Scramble").font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .foregroundColor(.white)
                    .background(Capsule().fill(Color.purple))
                }
                .buttonStyle(.plain)
                .disabled(sourceDuration > 0 && kept < 0.05)
            }
            .padding(.horizontal, 12).padding(.bottom, 8)
        }
        .padding(.top, 2)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var pipelineView: some View {
        HStack(spacing: 4) {
            pipelineChip("Original", color: .secondary)
            if options.trimStart > 0 || options.trimEnd > 0 {
                Image(systemName: "arrow.right").font(.system(size: 8)).foregroundStyle(.tertiary)
                pipelineChip(trimSummary, color: .orange)
            }
            ForEach(Array(item.steps.enumerated()), id: \.offset) { _, step in
                Image(systemName: "arrow.right").font(.system(size: 8)).foregroundStyle(.tertiary)
                pipelineChip(step.displayName, color: .purple)
            }
            Image(systemName: "arrow.right").font(.system(size: 8)).foregroundStyle(.tertiary)
            pipelineChip(options.useChunks ? "Chunk \(String(format: "%.2g", options.chunkSize))s" : "Reverse", color: .orange)
        }
    }

    private var trimSummary: String {
        if options.trimStart > 0 && options.trimEnd > 0 {
            return "Trim \(formatDuration(options.trimStart))–\(formatDuration(options.trimEnd))"
        }
        if options.trimStart > 0 { return "Trim start \(formatDuration(options.trimStart))" }
        return "Trim end \(formatDuration(options.trimEnd))"
    }

    private func pipelineChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .medium))
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.1)))
            .foregroundStyle(color)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func operationButton(_ title: String, subtitle: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 11, weight: .medium))
                Text(subtitle).font(.system(size: 9)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: 170, alignment: .leading)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func chunkLabel(_ value: Double) -> String {
        value < 1 ? "\(String(format: "%.2g", value))s" : "\(Int(value))s"
    }

    // MARK: - Helpers

    private var rowBg: Color {
        if isExpanded || showDecodeField { return Color(nsColor: .controlBackgroundColor) }
        if isSelected { return Color(nsColor: .controlBackgroundColor).opacity(0.9) }
        if isHovered { return Color(nsColor: .controlBackgroundColor).opacity(0.8) }
        if isChild { return itemColor.opacity(0.02) }
        return Color.clear
    }

    private func formatDuration(_ time: Double) -> String {
        let seconds = max(0, time)
        if seconds < 60 { return String(format: "%.1fs", seconds) }
        let minutes = Int(seconds) / 60
        let remainder = seconds - Double(minutes * 60)
        return String(format: "%d:%04.1f", minutes, remainder)
    }
}

// MARK: - Mini Waveform

struct MiniWaveform: View {
    let samples: [Float]
    var color: Color = .accentColor

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let count = min(samples.count, 24)
            let step = max(1, samples.count / count)
            let barWidth = width / CGFloat(count) - 0.5

            HStack(spacing: 0.5) {
                ForEach(0..<count, id: \.self) { index in
                    let sampleIndex = min(index * step, samples.count - 1)
                    let amplitude = CGFloat(samples[sampleIndex]) * height * 0.9
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(color.opacity(0.5))
                        .frame(width: max(barWidth, 1), height: max(amplitude, 1))
                }
            }
            .frame(width: width, height: height, alignment: .center)
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
    private let handleWidth: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let leftFraction = duration > 0 ? CGFloat(trimStart / duration) : 0
            let rightFraction = duration > 0 ? CGFloat(trimEnd / duration) : 0
            let leftX = leftFraction * width
            let rightX = width - rightFraction * width

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.04))
                    .frame(width: width, height: barHeight)

                WaveformShape(samples: waveform)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: width, height: barHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                if leftX > 0 {
                    Color(nsColor: .windowBackgroundColor).opacity(0.8)
                        .frame(width: leftX, height: barHeight)
                        .position(x: leftX / 2, y: barHeight / 2)
                }

                let rightWidth = width - rightX
                if rightWidth > 0 {
                    Color(nsColor: .windowBackgroundColor).opacity(0.8)
                        .frame(width: rightWidth, height: barHeight)
                        .position(x: rightX + rightWidth / 2, y: barHeight / 2)
                }

                let selectedWidth = max(0, rightX - leftX)
                if selectedWidth > 0 {
                    WaveformShape(samples: waveform)
                        .fill(accentColor.opacity(0.35))
                        .frame(width: width, height: barHeight)
                        .mask(Rectangle().frame(width: selectedWidth, height: barHeight)
                            .position(x: leftX + selectedWidth / 2, y: barHeight / 2))

                    Rectangle().fill(accentColor.opacity(0.3))
                        .frame(width: selectedWidth, height: 1)
                        .position(x: leftX + selectedWidth / 2, y: 0.5)
                    Rectangle().fill(accentColor.opacity(0.3))
                        .frame(width: selectedWidth, height: 1)
                        .position(x: leftX + selectedWidth / 2, y: barHeight - 0.5)
                }

                handleView()
                    .position(x: leftX, y: barHeight / 2)
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .local)
                        .onChanged { value in
                            if dragStartLeft == nil { dragStartLeft = trimStart }
                            let delta = Double(value.translation.width / width) * duration
                            trimStart = max(0, min(duration - trimEnd - 0.05,
                                                   (dragStartLeft ?? 0) + delta))
                        }
                        .onEnded { _ in dragStartLeft = nil })

                handleView()
                    .position(x: rightX, y: barHeight / 2)
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .local)
                        .onChanged { value in
                            if dragStartRight == nil { dragStartRight = trimEnd }
                            let delta = Double(value.translation.width / width) * duration
                            trimEnd = max(0, min(duration - trimStart - 0.05,
                                                 (dragStartRight ?? 0) - delta))
                        }
                        .onEnded { _ in dragStartRight = nil })
            }
            .frame(width: width, height: barHeight).clipped()
        }
        .frame(height: barHeight)
    }

    private func handleView() -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(accentColor)
                .frame(width: handleWidth, height: barHeight)
            VStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 0.5).fill(Color.white.opacity(0.6)).frame(width: 2, height: 7)
                RoundedRectangle(cornerRadius: 0.5).fill(Color.white.opacity(0.6)).frame(width: 2, height: 7)
            }
        }
        .frame(width: handleWidth + 14, height: barHeight + 6)
        .contentShape(Rectangle())
    }
}

// MARK: - Waveform Shape

struct WaveformShape: Shape {
    let samples: [Float]
    func path(in rect: CGRect) -> Path {
        guard samples.count > 1 else { return Path() }
        var path = Path()
        let middleY = rect.midY
        let barWidth = rect.width / CGFloat(samples.count)
        for (index, sample) in samples.enumerated() {
            let x = CGFloat(index) * barWidth
            let amplitude = CGFloat(sample) * rect.height * 0.45
            path.addRoundedRect(
                in: CGRect(x: x, y: middleY - amplitude,
                           width: max(barWidth - 0.5, 0.5), height: amplitude * 2),
                cornerSize: CGSize(width: 0.5, height: 0.5)
            )
        }
        return path
    }
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
            ForEach(0..<3) { index in
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(Color.accentColor.opacity(0.5))
                    .frame(width: 2.5, height: animate ? CGFloat.random(in: 3...12) : 3)
                    .animation(.easeInOut(duration: 0.4).repeatForever().delay(Double(index) * 0.15), value: animate)
            }
        }
        .onAppear { animate = true }
    }
}
