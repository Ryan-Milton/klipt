import AppKit
import SwiftUI

struct MenuBarContent: View {
    @Bindable var model: AppModel
    @State private var confirmClear = false

    var body: some View {
        Button("Show Clipboard History") { model.showHistory() }
        Button(model.isCapturePaused ? "Resume Capture" : "Pause Capture") { model.toggleCapture() }

        Divider()
        Text("\(model.history.count) history items")
        Text(model.storageDescription)

        if let error = model.lastError {
            Divider()
            Text(error)
            Button("Dismiss Message") { model.lastError = nil }
        }

        Divider()
        Button("Settings…") { model.showSettings() }
            .keyboardShortcut(",", modifiers: .command)
        Button("Check for Updates…") { model.checkForUpdates() }
        Button("Clear History…") { confirmClear = true }
            .disabled(model.history.isEmpty)
        Button("Quit Klipt") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
        .confirmationDialog("Clear all clipboard history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { model.clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes all history. Snippets are not affected.")
        }
    }
}

struct HistoryPanelView: View {
    @Bindable var model: AppModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "clipboard.fill")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.accentColor.gradient, in: .rect(cornerRadius: 8))
                TextField("Search clipboard history", text: $model.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($searchFocused)
                Text(model.historyShortcut.displayText)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: .rect(cornerRadius: 6))
            }
            .padding(18)

            Divider()

            if !model.license.state.isUsable {
                HStack(spacing: 10) {
                    Label(model.license.state.statusText, systemImage: "key.fill")
                        .font(.callout.weight(.semibold))
                    Text("History remains available, but paste and snippet assignment require activation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Enter Key") { model.showSettings(tab: .license) }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                Divider()
            }

            if model.filteredHistory.isEmpty {
                ContentUnavailableView(
                    model.searchQuery.isEmpty ? "Clipboard history is empty" : "No matching copies",
                    systemImage: model.searchQuery.isEmpty ? "clipboard" : "magnifyingglass",
                    description: Text(model.searchQuery.isEmpty ? "Copy something in any app to get started." : "Try a different search.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(model.filteredHistory) { record in
                                let assignedSlots = model.assignedSnippetSlots(contentHash: record.contentHash)
                                HistoryRow(
                                    record: record,
                                    isSelected: model.selectedHistoryID == record.id,
                                    assignedSlots: assignedSlots
                                )
                                    .id(record.id)
                                    .contentShape(.rect)
                                    .onTapGesture(count: 2) {
                                        model.selectedHistoryID = record.id
                                        Task { await model.pasteHistory(record, target: model.pasteTarget) }
                                    }
                                    .onTapGesture {
                                        model.selectedHistoryID = record.id
                                    }
                                    .contextMenu {
                                        Menu("Assign to Snippet Slot") {
                                            ForEach(1...9, id: \.self) { slot in
                                                Button {
                                                    model.requestHistoryAssignment(record, to: slot)
                                                } label: {
                                                    if assignedSlots.contains(slot) {
                                                        Label(model.snippetDestinationLabel(slot: slot), systemImage: "checkmark")
                                                    } else {
                                                        Text(model.snippetDestinationLabel(slot: slot))
                                                    }
                                                }
                                            }
                                        }
                                        .onAppear { model.selectedHistoryID = record.id }
                                    }
                            }
                        }
                        .padding(10)
                    }
                    .onChange(of: model.selectedHistoryID) { _, id in
                        if let id { withAnimation(.snappy(duration: 0.16)) { proxy.scrollTo(id, anchor: .center) } }
                    }
                }
            }

            Divider()
            HStack {
                if let message = model.snippetAssignmentMessage, message.surface == .history {
                    Label(message.text, systemImage: "info.circle.fill")
                        .lineLimit(1)
                } else {
                    Label("Navigate", systemImage: "arrow.up.arrow.down")
                    Label("Paste", systemImage: "return")
                    Spacer()
                    Text("⌘⌥1–9 Assign  ·  ⌘⌫ Delete  ·  esc Close")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
        }
        .frame(
            width: HistoryPanelController.width,
            height: HistoryPanelController.contentHeight(for: model.filteredHistory.count)
        )
        .background(Color(nsColor: .windowBackgroundColor), in: .rect(cornerRadius: 16))
        .clipShape(.rect(cornerRadius: 16))
        .overlay(.separator.opacity(0.8), in: .rect(cornerRadius: 16).stroke(lineWidth: 1))
        .onAppear { searchFocused = true }
        .onChange(of: model.searchQuery) {
            model.selectedHistoryID = model.filteredHistory.first?.id
        }
        .onChange(of: model.filteredHistory.count) { _, itemCount in
            model.panelController.updateHeight(for: itemCount)
        }
        .snippetAssignmentSheet(model: model, surface: .history)
    }
}

private struct HistoryRow: View {
    let record: ClipboardRecord
    let isSelected: Bool
    let assignedSlots: [Int]

    var body: some View {
        HStack(spacing: 12) {
            preview
                .frame(width: 52, height: 44)
                .background(.quaternary.opacity(0.55), in: .rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(record.title)
                    .lineLimit(2)
                    .font(.body.weight(.medium))
                HStack(spacing: 6) {
                    SourceApplicationIcon(bundleIdentifier: record.sourceBundleIdentifier)
                    Text(record.sourceApplicationName ?? "Unknown app")
                    Text("·")
                    Text(record.createdAt, style: .relative)
                    Text("·")
                    Text(ByteCountFormatter.string(fromByteCount: record.byteCount, countStyle: .file))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            ForEach(assignedSlots, id: \.self) { slot in
                Text("Snippet \(slot)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.tint.opacity(0.12), in: .capsule)
            }
            Image(systemName: "return")
                .foregroundStyle(.secondary)
                .opacity(isSelected ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear, in: .rect(cornerRadius: 10))
    }

    @ViewBuilder private var preview: some View {
        if let data = record.previewImageData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(.rect(cornerRadius: 8))
        } else {
            Image(systemName: previewIconName)
            .font(.title2)
            .foregroundStyle(.secondary)
        }
    }

    private var previewIconName: String {
        switch record.kind {
        case .text: "text.alignleft"
        case .image: "photo"
        case .files: "doc.on.doc"
        case .richContent: "textformat"
        case .data: "shippingbox"
        }
    }
}

private struct SourceApplicationIcon: View {
    let bundleIdentifier: String?

    var body: some View {
        if let bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 14, height: 14)
        } else {
            Image(systemName: "app")
                .frame(width: 14, height: 14)
        }
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView(selection: $model.settingsTab) {
            GeneralSettings(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            ShortcutSettings(model: model)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(SettingsTab.shortcuts)
            SnippetSettings(model: model)
                .tabItem { Label("Snippets", systemImage: "number.square") }
                .tag(SettingsTab.snippets)
            StorageSettings(model: model)
                .tabItem { Label("Storage", systemImage: "externaldrive") }
                .tag(SettingsTab.storage)
            LicenseSettingsView(model: model)
                .tabItem { Label("License", systemImage: "key") }
                .tag(SettingsTab.license)
        }
        .frame(width: 680, height: 560)
        .padding(18)
        .snippetAssignmentSheet(model: model, surface: .settings)
    }
}

private struct GeneralSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Clipboard capture") {
                Toggle("Pause clipboard capture", isOn: Binding(
                    get: { model.isCapturePaused },
                    set: { _ in model.toggleCapture() }
                ))
                LabeledContent("History capacity", value: "100 items")
                Text("Klipt captures all clipboard representations, including content marked concealed or transient by password managers.")
                    .foregroundStyle(.orange)
            }

            Section("Direct paste") {
                LabeledContent("Accessibility") {
                    Label(model.accessibilityTrusted ? "Allowed" : "Not allowed",
                          systemImage: model.accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(model.accessibilityTrusted ? .green : .orange)
                }
                Button("Open Accessibility Prompt") { model.requestAccessibility() }
                Button("Refresh Status") { model.refreshAccessibilityStatus() }
                if !model.accessibilityTrusted {
                    Text("If Klipt is already enabled in System Settings, toggle it off and back on once. This can be required after replacing a development build.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Startup") {
                Toggle("Launch Klipt at login", isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.setLaunchAtLogin($0) }
                ))
                if let error = model.launchAtLoginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            while !Task.isCancelled {
                model.refreshAccessibilityStatus()
                model.refreshLaunchAtLoginStatus()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

private struct ShortcutSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Clipboard history") {
                shortcutRow(label: "Show history", shortcut: model.historyShortcut, action: .history) {
                    model.updateHistoryShortcut($0)
                }
            }
            Section("Direct snippets") {
                ForEach(1...9, id: \.self) { slot in
                    shortcutRow(
                        label: "Snippet \(slot)",
                        shortcut: model.snippetShortcuts[slot] ?? .snippet(slot: slot),
                        action: .snippet(slot)
                    ) { model.updateSnippetShortcut(slot: slot, shortcut: $0) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func shortcutRow(
        label: String,
        shortcut: KeyboardShortcutSetting,
        action: HotKeyAction,
        update: @escaping (KeyboardShortcutSetting) -> Void
    ) -> some View {
        LabeledContent(label) {
            VStack(alignment: .trailing, spacing: 3) {
                ShortcutRecorder(
                    shortcut: shortcut,
                    onChange: update,
                    onRecordingChanged: model.setShortcutRecording
                )
                if let error = model.shortcutErrors[action] {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        }
    }
}

private struct SnippetSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Assign a history item by right-clicking it or pressing ⌘⌥1–9 in clipboard history.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let message = model.snippetAssignmentMessage, message.surface == .settings {
                Label(message.text, systemImage: "info.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(1...9, id: \.self) { slot in
                        SnippetSlotView(model: model, slot: slot)
                    }
                }
                .padding(4)
            }
        }
    }
}

private struct SnippetSlotView: View {
    @Bindable var model: AppModel
    let slot: Int

    private var snippet: SnippetRecord? { model.snippets.first { $0.slot == slot } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(slot)")
                    .font(.headline.monospacedDigit())
                    .frame(width: 28, height: 28)
                    .background(.tint.opacity(0.16), in: .rect(cornerRadius: 7))
                if let snippet {
                    TextField("Snippet name", text: Binding(
                        get: {
                            model.snippets.first(where: { $0.slot == slot })?.name ?? snippet.name
                        },
                        set: {
                            model.renameSnippet(
                                slot: slot,
                                name: $0,
                                expectedPayloadID: snippet.payloadID
                            )
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                } else {
                    Text("Snippet \(slot)").foregroundStyle(.secondary)
                    Spacer()
                }
                Text(model.snippetShortcuts[slot]?.displayText ?? "")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            if let snippet {
                Text(snippet.preview.title)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
                HStack {
                    Text(ByteCountFormatter.string(fromByteCount: snippet.byteCount, countStyle: .file))
                    Spacer()
                    Button("Replace from Clipboard") { model.captureCurrentClipboard(for: slot) }
                    Button("Remove", role: .destructive) {
                        model.deleteSnippet(slot: slot, expectedPayloadID: snippet.payloadID)
                    }
                }
                .font(.caption)
            } else {
                TextEditor(text: Binding(
                    get: { model.snippetTextDrafts[slot, default: ""] },
                    set: { model.snippetTextDrafts[slot] = $0 }
                ))
                .font(.body.monospaced())
                .frame(height: 62)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))

                HStack {
                    SnippetDropTarget(slot: slot) { model.assignDroppedPayload($0, to: slot) }
                    Spacer()
                    Button("Capture Clipboard") { model.captureCurrentClipboard(for: slot) }
                    Button("Save Text") { model.saveTextSnippet(slot: slot) }
                }
            }
        }
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
    }
}

private struct SnippetAssignmentSheet: View {
    @Bindable var model: AppModel
    let request: SnippetAssignmentRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.title2.weight(.semibold))

            if !request.matchingSnippets.isEmpty {
                Label(
                    "Currently assigned to \(request.matchingSnippets.map { "Snippet \($0.slot)" }.joined(separator: ", "))",
                    systemImage: "arrow.right.square"
                )
                .foregroundStyle(.secondary)
            }

            AssignmentSummary(label: "New content", record: request.preview)

            if let target = request.targetSnippet,
               target.preview.contentHash != request.preview.contentHash {
                AssignmentSummary(label: "Replaces \(target.name)", record: target.preview)
            }

            HStack {
                Spacer()
                Button("Cancel") { model.cancelSnippetAssignment(id: request.id) }
                    .keyboardShortcut(.cancelAction)
                Button("Assign to Snippet \(request.targetSlot)") {
                    model.confirmSnippetAssignment(id: request.id)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 480)
    }

    private var title: String {
        if request.matchingSnippets.count > 1 {
            return "Consolidate into Snippet \(request.targetSlot)?"
        }
        if !request.matchingSnippets.isEmpty {
            return "Move to Snippet \(request.targetSlot)?"
        }
        return "Replace Snippet \(request.targetSlot)?"
    }
}

private struct AssignmentSummary: View {
    let label: String
    let record: ClipboardRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 42, height: 42)
                .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(record.title)
                    .lineLimit(2)
                Text(ByteCountFormatter.string(fromByteCount: record.byteCount, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
    }

    private var iconName: String {
        switch record.kind {
        case .text: "text.alignleft"
        case .image: "photo"
        case .files: "doc.on.doc"
        case .richContent: "textformat"
        case .data: "shippingbox"
        }
    }
}

private struct SnippetAssignmentSheetModifier: ViewModifier {
    @Bindable var model: AppModel
    let surface: SnippetAssignmentSurface

    func body(content: Content) -> some View {
        content.sheet(item: assignment) { request in
            SnippetAssignmentSheet(model: model, request: request)
        }
    }

    private var assignment: Binding<SnippetAssignmentRequest?> {
        Binding(
            get: {
                guard model.pendingSnippetAssignment?.surface == surface else { return nil }
                return model.pendingSnippetAssignment
            },
            set: { value in
                if value == nil, model.pendingSnippetAssignment?.surface == surface {
                    model.cancelSnippetAssignment()
                }
            }
        )
    }
}

private extension View {
    func snippetAssignmentSheet(model: AppModel, surface: SnippetAssignmentSurface) -> some View {
        modifier(SnippetAssignmentSheetModifier(model: model, surface: surface))
    }
}

private struct StorageSettings: View {
    @Bindable var model: AppModel
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section("Encrypted local storage") {
                LabeledContent("Used", value: model.storageDescription)
                ProgressView(value: Double(model.storageUsed), total: Double(KliptLimits.maximumStorageBytes))
                LabeledContent("Per-item limit", value: "100 MB")
                Text("Payloads and searchable metadata are encrypted with AES-GCM. The per-install key is kept in your login Keychain.")
                    .foregroundStyle(.secondary)
            }
            Section("History") {
                LabeledContent("Stored items", value: "\(model.history.count) of 100")
                Button("Clear Clipboard History", role: .destructive) { confirmClear = true }
                    .disabled(model.history.isEmpty)
                Text("Snippets are protected from automatic eviction. Old history is removed first when Klipt reaches its 1 GB limit.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Clear all clipboard history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { model.clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes all history. Snippets are not affected.")
        }
    }
}
