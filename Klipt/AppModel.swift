import AppKit
import Foundation
import Observation

enum SnippetAssignmentSurface: Sendable, Equatable {
    case history
    case settings
}

enum SettingsTab: Hashable {
    case general
    case shortcuts
    case snippets
    case storage
    case license
}

@MainActor
enum SnippetAssignmentSource: Sendable {
    case history(ClipboardRecord)
    case payload(ClipboardPayload)

    var preview: ClipboardRecord {
        switch self {
        case .history(let record): record
        case .payload(let payload): PasteboardCodec.makeRecord(from: payload)
        }
    }
}

@MainActor
struct SnippetAssignmentRequest: Identifiable, Sendable {
    let id = UUID()
    let source: SnippetAssignmentSource
    let targetSlot: Int
    let surface: SnippetAssignmentSurface
    let preview: ClipboardRecord
    let matchingSnippets: [SnippetRecord]
    let targetSnippet: SnippetRecord?

    init(
        source: SnippetAssignmentSource,
        targetSlot: Int,
        surface: SnippetAssignmentSurface,
        snippets: [SnippetRecord]
    ) {
        self.source = source
        self.targetSlot = targetSlot
        self.surface = surface
        let assignmentPreview = source.preview
        preview = assignmentPreview
        matchingSnippets = snippets
            .filter { $0.preview.contentHash == assignmentPreview.contentHash }
            .sorted { $0.slot < $1.slot }
        targetSnippet = snippets.first { $0.slot == targetSlot }
    }

    var isNoOp: Bool {
        matchingSnippets.count == 1 && matchingSnippets[0].slot == targetSlot
    }

    var requiresConfirmation: Bool {
        !isNoOp && (targetSnippet != nil || !matchingSnippets.isEmpty)
    }

    var confirmationFingerprint: Set<UUID> {
        Set(matchingSnippets.map(\.payloadID) + [targetSnippet?.payloadID].compactMap { $0 })
    }
}

struct SnippetAssignmentMessage: Sendable {
    let text: String
    let surface: SnippetAssignmentSurface
}

@MainActor
@Observable
final class AppModel {
    @ObservationIgnored private static let launchAtLoginPreferenceKey = "launchAtLoginRequested"

    var history: [ClipboardRecord] = []
    var snippets: [SnippetRecord] = []
    var searchQuery = ""
    var selectedHistoryID: UUID?
    var isCapturePaused = false
    var lastError: String?
    var accessibilityTrusted = AccessibilityService.isTrusted
    var launchAtLoginEnabled = LaunchAtLoginService.isEnabled
    var launchAtLoginError: String?
    var shortcutErrors: [HotKeyAction: String] = [:]
    var historyShortcut = KeyboardShortcutSetting.history
    var snippetShortcuts = Dictionary(uniqueKeysWithValues: (1...9).map { ($0, KeyboardShortcutSetting.snippet(slot: $0)) })
    var snippetTextDrafts: [Int: String] = [:]
    var pendingSnippetAssignment: SnippetAssignmentRequest?
    var snippetAssignmentMessage: SnippetAssignmentMessage?
    var settingsTab: SettingsTab = .general
    let license: LicenseController

    @ObservationIgnored private let monitor = ClipboardMonitor()
    @ObservationIgnored private let hotKeyManager = GlobalHotKeyManager()
    @ObservationIgnored private let updater: UpdaterController
    @ObservationIgnored private var store: EncryptedStore?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var servicesActive = false
    @ObservationIgnored private var mutationTask: Task<Void, Never>?
    @ObservationIgnored private var snippetAssignmentMessageTask: Task<Void, Never>?
    @ObservationIgnored private var licenseValidationTask: Task<Void, Never>?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var lastExternalApplication: NSRunningApplication?
    @ObservationIgnored var pasteTarget: NSRunningApplication?
    @ObservationIgnored lazy var panelController = HistoryPanelController(model: self)
    @ObservationIgnored lazy var onboardingController = OnboardingWindowController(model: self)
    @ObservationIgnored lazy var settingsController = SettingsWindowController(model: self)
    @ObservationIgnored lazy var licenseAlertController = LicenseAlertController(model: self)

    var filteredHistory: [ClipboardRecord] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return history }
        return history.filter {
            $0.searchableText.localizedCaseInsensitiveContains(query)
                || $0.title.localizedCaseInsensitiveContains(query)
                || ($0.sourceApplicationName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var storageUsed: Int64 {
        history.reduce(0) { $0 + $1.byteCount } + snippets.reduce(0) { $0 + $1.byteCount }
    }

    var storageDescription: String {
        "\(ByteCountFormatter.string(fromByteCount: storageUsed, countStyle: .file)) of 1 GB"
    }

    init(licenseController: LicenseController? = nil, updater: UpdaterController? = nil) {
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        self.license = licenseController ?? LicenseController(
            credentials: isTesting ? EphemeralLicenseCredentialStore() : KeychainLicenseCredentialStore()
        )
        self.updater = updater ?? UpdaterController()
        self.license.onStateChange = { [weak self] oldState, newState, presentTerminal in
            self?.licenseStateChanged(from: oldState, to: newState, presentTerminal: presentTerminal)
        }
        guard !isTesting else {
            loadShortcutPreferences()
            return
        }
        do {
            store = try EncryptedStore()
        } catch {
            lastError = error.localizedDescription
        }
        loadShortcutPreferences()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        observeApplicationActivation()
        hotKeyManager.onAction = { [weak self] action in self?.handleHotKey(action) }
        monitor.onPayload = { [weak self] payload in
            self?.enqueueMutation { await self?.capture(payload) }
        }

        enqueueMutation { [weak self] in
            guard let self else { return }
            await self.loadPersistedState()
            self.registerHotKeys()
            let validationDue = self.license.restore()
            self.reconcileLicenseState(atStartup: true)
            self.startLicenseValidationSchedule()
            if validationDue {
                Task { @MainActor [weak self] in
                    await self?.license.refresh(force: false)
                }
            }
        }
    }

    func showHistory() {
        pasteTarget = frontmostExternalApplication()
        searchQuery = ""
        selectedHistoryID = history.first?.id
        snippetAssignmentMessage = nil
        panelController.show(targetApplication: pasteTarget)
        if license.state == .refunded || license.state == .revoked {
            presentLicenseUIForBlockedAttempt()
        }
    }

    func hideHistory() {
        panelController.hide()
    }

    func showSettings(tab: SettingsTab? = nil) {
        if let tab { settingsTab = tab }
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.refreshAccessibilityStatus()
            self?.refreshLaunchAtLoginStatus()
            self?.settingsController.show()
        }
    }

    func toggleCapture() {
        guard requireLicense(.capture) else { return }
        isCapturePaused.toggle()
        monitor.setPaused(isCapturePaused)
    }

    func selectNext(offset: Int) {
        let records = filteredHistory
        guard !records.isEmpty else { selectedHistoryID = nil; return }
        guard let selectedHistoryID,
              let index = records.firstIndex(where: { $0.id == selectedHistoryID }) else {
            self.selectedHistoryID = records.first?.id
            return
        }
        self.selectedHistoryID = records[min(max(index + offset, 0), records.count - 1)].id
    }

    func pasteSelectedHistory() {
        guard let selectedHistoryID,
              let record = history.first(where: { $0.id == selectedHistoryID }) else { return }
        Task { await pasteHistory(record, target: pasteTarget) }
    }

    func pasteHistory(_ record: ClipboardRecord, target: NSRunningApplication? = nil) async {
        guard requireLicense(.paste), let store else { return }
        do {
            let payload = try await store.loadHistoryPayload(id: record.id)
            guard requireLicense(.paste) else { return }
            hideHistory()
            let result = await PasteCoordinator.paste(
                payload,
                into: target ?? frontmostExternalApplication(),
                monitor: monitor,
                isAllowed: { [weak self] in self?.license.state.isUsable == true }
            )
            handlePasteResult(result)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func pasteSnippet(slot: Int) {
        guard requireLicense(.paste),
              let snippet = snippets.first(where: { $0.slot == slot }), let store else { return }
        let target = frontmostExternalApplication()
        Task {
            do {
                let payload = try await store.loadSnippetPayload(id: snippet.payloadID)
                guard requireLicense(.paste) else { return }
                let result = await PasteCoordinator.paste(
                    payload,
                    into: target,
                    monitor: monitor,
                    isAllowed: { [weak self] in self?.license.state.isUsable == true }
                )
                handlePasteResult(result, copiedMessage: "Copied snippet \(slot), but the target app could not be verified for direct paste.")
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func deleteSelectedHistory() {
        guard let selectedHistoryID,
              let record = history.first(where: { $0.id == selectedHistoryID }) else { return }
        deleteHistory(record)
    }

    func deleteHistory(_ record: ClipboardRecord) {
        enqueueMutation { [weak self] in
            guard let self, let store = self.store else { return }
            let updatedHistory = self.history.filter { $0.id != record.id }
            do {
                try await store.saveManifest(StoreManifest(history: updatedHistory, snippets: self.snippets))
                self.history = updatedHistory
                self.selectedHistoryID = self.filteredHistory.first?.id
                try await store.deleteHistoryPayload(id: record.id)
            } catch { self.lastError = error.localizedDescription }
        }
    }

    func clearHistory() {
        enqueueMutation { [weak self] in
            guard let self, let store = self.store else { return }
            let ids = self.history.map(\.id)
            do {
                try await store.saveManifest(StoreManifest(history: [], snippets: self.snippets))
                self.history = []
                self.selectedHistoryID = nil
                try await store.clearHistory(ids: ids)
            } catch { self.lastError = error.localizedDescription }
        }
    }

    func captureCurrentClipboard(for slot: Int) {
        guard requireLicense(.snippetAssignment) else { return }
        guard let payload = PasteboardCodec.capture(from: .general) else {
            lastError = "The clipboard does not contain data Klipt can store."
            return
        }
        requestSnippetAssignment(.payload(payload), to: slot, surface: .settings)
    }

    func assignDroppedPayload(_ payload: ClipboardPayload, to slot: Int) {
        guard requireLicense(.snippetAssignment) else { return }
        requestSnippetAssignment(.payload(payload), to: slot, surface: .settings)
    }

    func saveTextSnippet(slot: Int) {
        guard requireLicense(.snippetAssignment) else { return }
        let text = snippetTextDrafts[slot, default: ""]
        guard !text.isEmpty else {
            lastError = "Enter snippet text before saving."
            return
        }
        let payload = PasteboardCodec.textPayload(text)
        requestSnippetAssignment(.payload(payload), to: slot, surface: .settings)
    }

    func assignSelectedHistory(to slot: Int) {
        guard requireLicense(.snippetAssignment) else { return }
        guard let selectedHistoryID,
              let record = history.first(where: { $0.id == selectedHistoryID }) else { return }
        requestHistoryAssignment(record, to: slot)
    }

    func requestHistoryAssignment(_ record: ClipboardRecord, to slot: Int) {
        guard requireLicense(.snippetAssignment) else { return }
        selectedHistoryID = record.id
        requestSnippetAssignment(.history(record), to: slot, surface: .history)
    }

    func confirmSnippetAssignment(id: UUID) {
        guard requireLicense(.snippetAssignment) else { return }
        guard let request = pendingSnippetAssignment, request.id == id else { return }
        pendingSnippetAssignment = nil
        enqueueMutation { [weak self] in
            await self?.performSnippetAssignment(request, confirmed: true)
        }
    }

    func cancelSnippetAssignment(id: UUID? = nil) {
        guard id == nil || pendingSnippetAssignment?.id == id else { return }
        pendingSnippetAssignment = nil
    }

    func assignedSnippetSlots(contentHash: String) -> [Int] {
        snippets
            .filter { $0.preview.contentHash == contentHash }
            .map(\.slot)
            .sorted()
    }

    func snippetDestinationLabel(slot: Int) -> String {
        let shortcut = snippetShortcuts[slot]?.displayText ?? KeyboardShortcutSetting.snippet(slot: slot).displayText
        guard let snippet = snippets.first(where: { $0.slot == slot }) else {
            return "Snippet \(slot) · \(shortcut) · Empty"
        }
        let title = snippet.preview.title.count > 36
            ? String(snippet.preview.title.prefix(35)) + "…"
            : snippet.preview.title
        return "\(snippet.name) · \(shortcut) · \(title)"
    }

    func renameSnippet(slot: Int, name: String, expectedPayloadID: UUID) {
        enqueueMutation { [weak self] in
            guard let self, let store = self.store,
                  let index = self.snippets.firstIndex(where: {
                      $0.slot == slot && $0.payloadID == expectedPayloadID
                  }) else { return }
            var updatedSnippets = self.snippets
            updatedSnippets[index].name = name.isEmpty ? "Snippet \(slot)" : name
            do {
                try await store.saveManifest(StoreManifest(history: self.history, snippets: updatedSnippets))
                self.snippets = updatedSnippets
            } catch { self.lastError = error.localizedDescription }
        }
    }

    func deleteSnippet(slot: Int, expectedPayloadID: UUID) {
        enqueueMutation { [weak self] in
            guard let self, let store = self.store,
                  let snippet = self.snippets.first(where: {
                      $0.slot == slot && $0.payloadID == expectedPayloadID
                  }) else { return }
            let updatedSnippets = self.snippets.filter { $0.slot != slot }
            do {
                try await store.saveManifest(StoreManifest(history: self.history, snippets: updatedSnippets))
                self.snippets = updatedSnippets
                self.snippetTextDrafts[slot] = nil
                self.hotKeyManager.unregister(.snippet(slot))
                try await store.deleteSnippetPayload(id: snippet.payloadID)
            } catch { self.lastError = error.localizedDescription }
        }
    }

    func requestAccessibility() {
        guard requireLicense(.paste) else { return }
        AccessibilityService.requestAccess()
        Task {
            for _ in 0..<40 {
                try? await Task.sleep(for: .milliseconds(500))
                accessibilityTrusted = AccessibilityService.isTrusted
                if accessibilityTrusted { break }
            }
        }
    }

    func refreshAccessibilityStatus() {
        accessibilityTrusted = AccessibilityService.isTrusted
    }

    func setShortcutRecording(_ recording: Bool) {
        if recording {
            hotKeyManager.unregisterAll()
        } else if hasStarted {
            registerHotKeys()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.launchAtLoginPreferenceKey)
        do {
            try LaunchAtLoginService.setEnabled(enabled)
            launchAtLoginEnabled = LaunchAtLoginService.isEnabled
            launchAtLoginError = nil
        } catch {
            launchAtLoginEnabled = LaunchAtLoginService.isEnabled
            launchAtLoginError = "Launch at Login could not be updated: \(error.localizedDescription)"
        }
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginEnabled = LaunchAtLoginService.isEnabled
    }

    func completeOnboarding() {
        guard requireLicense(.capture) else { return }
        UserDefaults.standard.set(true, forKey: "completedOnboarding")
        setLaunchAtLogin(true)
        onboardingController.close()
        activateServices()
    }

    func prepareForTermination() async {
        servicesActive = false
        licenseValidationTask?.cancel()
        monitor.stop()
        hotKeyManager.unregisterAll()
        await mutationTask?.value
    }

    func updateHistoryShortcut(_ shortcut: KeyboardShortcutSetting) {
        let previous = historyShortcut
        let status = hotKeyManager.register(shortcut, for: .history)
        guard status == noErr else {
            _ = hotKeyManager.register(previous, for: .history)
            shortcutErrors[.history] = "\(shortcut.displayText) is unavailable (error \(status))."
            return
        }
        historyShortcut = shortcut
        shortcutErrors[.history] = nil
        saveShortcutPreferences()
    }

    func updateSnippetShortcut(slot: Int, shortcut: KeyboardShortcutSetting) {
        let action = HotKeyAction.snippet(slot)
        let previous = snippetShortcuts[slot] ?? .snippet(slot: slot)
        if hasStarted, snippets.contains(where: { $0.slot == slot }) {
            let status = hotKeyManager.register(shortcut, for: action)
            guard status == noErr else {
                _ = hotKeyManager.register(previous, for: action)
                shortcutErrors[action] = "\(shortcut.displayText) is unavailable (error \(status))."
                return
            }
        }
        snippetShortcuts[slot] = shortcut
        shortcutErrors[action] = nil
        saveShortcutPreferences()
    }

    func activateLicense(key: String, nickname: String) async {
        await license.activate(key: key, nickname: nickname)
    }

    func refreshLicense() async {
        await license.refresh()
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }

    private func capture(_ payload: ClipboardPayload) async {
        guard requireLicense(.capture, presentUI: false),
              payload.byteCount <= KliptLimits.maximumEntryBytes, let store else {
            if payload.byteCount > KliptLimits.maximumEntryBytes { lastError = StoreError.entryTooLarge.localizedDescription }
            return
        }
        let record = PasteboardCodec.makeRecord(from: payload)
        let duplicate = history.first { $0.contentHash == record.contentHash }
        var candidates = history.filter { $0.contentHash != record.contentHash }
        candidates.insert(record, at: 0)
        let trimmed = StoragePolicy.trimHistory(candidates, snippetBytes: snippets.reduce(0) { $0 + $1.byteCount })

        do {
            let previousHistory = history
            try await store.saveHistoryPayload(payload)
            guard requireLicense(.capture, presentUI: false) else {
                try? await store.deleteHistoryPayload(id: payload.id)
                return
            }
            try await store.saveManifest(StoreManifest(history: trimmed.kept, snippets: snippets))
            guard requireLicense(.capture, presentUI: false) else {
                try? await store.saveManifest(StoreManifest(history: previousHistory, snippets: snippets))
                try? await store.deleteHistoryPayload(id: payload.id)
                return
            }
            history = trimmed.kept
            if let duplicate { try await store.deleteHistoryPayload(id: duplicate.id) }
            for evicted in trimmed.evicted where evicted.id != record.id {
                try await store.deleteHistoryPayload(id: evicted.id)
            }
        } catch {
            if !history.contains(where: { $0.id == payload.id }) {
                try? await store.deleteHistoryPayload(id: payload.id)
            }
            lastError = error.localizedDescription
        }
    }

    private func requestSnippetAssignment(
        _ source: SnippetAssignmentSource,
        to slot: Int,
        surface: SnippetAssignmentSurface
    ) {
        guard requireLicense(.snippetAssignment) else { return }
        guard (1...9).contains(slot) else { return }
        let request = SnippetAssignmentRequest(
            source: source,
            targetSlot: slot,
            surface: surface,
            snippets: snippets
        )
        if request.isNoOp {
            showSnippetAssignmentMessage("Already assigned to Snippet \(slot).", on: surface)
        } else if request.requiresConfirmation {
            pendingSnippetAssignment = request
        } else {
            enqueueMutation { [weak self] in
                await self?.performSnippetAssignment(request, confirmed: false)
            }
        }
    }

    private func performSnippetAssignment(_ requested: SnippetAssignmentRequest, confirmed: Bool) async {
        guard requireLicense(.snippetAssignment), let store else {
            reportSnippetAssignmentError("Encrypted storage is unavailable.", on: requested.surface)
            return
        }
        let request = SnippetAssignmentRequest(
            source: requested.source,
            targetSlot: requested.targetSlot,
            surface: requested.surface,
            snippets: snippets
        )
        if request.isNoOp {
            showSnippetAssignmentMessage("Already assigned to Snippet \(request.targetSlot).", on: request.surface)
            return
        }
        if request.requiresConfirmation,
           !confirmed || request.confirmationFingerprint != requested.confirmationFingerprint {
            pendingSnippetAssignment = request
            return
        }

        do {
            let payload: ClipboardPayload
            let createdPayload: Bool
            if let reusable = request.matchingSnippets.first {
                payload = try await store.loadSnippetPayload(id: reusable.payloadID)
                guard requireLicense(.snippetAssignment) else { return }
                createdPayload = false
            } else {
                let sourcePayload: ClipboardPayload
                switch request.source {
                case .history(let record):
                    let currentRecord = history.first {
                        $0.contentHash == request.preview.contentHash
                    } ?? record
                    sourcePayload = try await store.loadHistoryPayload(id: currentRecord.id)
                    guard requireLicense(.snippetAssignment) else { return }
                case .payload(let captured):
                    sourcePayload = captured
                }
                payload = sourcePayload.copyWithFreshID()
                createdPayload = true
            }

            guard payload.byteCount <= KliptLimits.maximumEntryBytes else {
                reportSnippetAssignmentError(StoreError.entryTooLarge.localizedDescription, on: request.surface)
                return
            }

            let removedSnippets = snippets.filter {
                $0.slot == request.targetSlot || $0.preview.contentHash == request.preview.contentHash
            }
            let remainingSnippets = snippets.filter {
                $0.slot != request.targetSlot && $0.preview.contentHash != request.preview.contentHash
            }
            let snippetBytes = remainingSnippets.reduce(payload.byteCount) { $0 + $1.byteCount }
            guard snippetBytes <= KliptLimits.maximumStorageBytes else {
                reportSnippetAssignmentError(StoreError.storageFull.localizedDescription, on: request.surface)
                return
            }

            let preview = PasteboardCodec.makeRecord(from: payload)
            let snippet = SnippetRecord(
                slot: request.targetSlot,
                name: request.targetSnippet?.name ?? "Snippet \(request.targetSlot)",
                payloadID: payload.id,
                byteCount: payload.byteCount,
                preview: preview
            )
            var updatedSnippets = remainingSnippets
            updatedSnippets.append(snippet)
            updatedSnippets.sort { $0.slot < $1.slot }
            let trimmed = StoragePolicy.trimHistory(history, snippetBytes: snippetBytes)

            guard requireLicense(.snippetAssignment) else { return }
            let previousHistory = history
            let previousSnippets = snippets
            if createdPayload {
                try await store.saveSnippetPayload(payload)
                guard requireLicense(.snippetAssignment) else {
                    try? await store.deleteSnippetPayload(id: payload.id)
                    return
                }
            }
            do {
                try await store.saveManifest(StoreManifest(history: trimmed.kept, snippets: updatedSnippets))
                guard requireLicense(.snippetAssignment) else {
                    try? await store.saveManifest(StoreManifest(
                        history: previousHistory,
                        snippets: previousSnippets
                    ))
                    if createdPayload { try? await store.deleteSnippetPayload(id: payload.id) }
                    return
                }
            } catch {
                if createdPayload { try? await store.deleteSnippetPayload(id: payload.id) }
                throw error
            }

            let previousSlots = Set(snippets.map(\.slot))
            history = trimmed.kept
            snippets = updatedSnippets
            for slot in previousSlots.subtracting(Set(updatedSnippets.map(\.slot))) {
                snippetTextDrafts[slot] = nil
                hotKeyManager.unregister(.snippet(slot))
            }
            snippetTextDrafts[request.targetSlot] = preview.kind == .text ? preview.title : ""
            let hotKeyRegistered = !hasStarted || registerHotKey(
                snippetShortcuts[request.targetSlot] ?? .snippet(slot: request.targetSlot),
                action: .snippet(request.targetSlot)
            )

            for removed in removedSnippets where removed.payloadID != payload.id {
                try await store.deleteSnippetPayload(id: removed.payloadID)
            }
            for evicted in trimmed.evicted { try await store.deleteHistoryPayload(id: evicted.id) }

            if !hotKeyRegistered {
                showSnippetAssignmentMessage(
                    "Assigned to Snippet \(request.targetSlot), but its hotkey is unavailable.",
                    on: request.surface
                )
            }
        } catch {
            reportSnippetAssignmentError(error.localizedDescription, on: request.surface)
        }
    }

    private func reportSnippetAssignmentError(_ text: String, on surface: SnippetAssignmentSurface) {
        lastError = text
        showSnippetAssignmentMessage(text, on: surface)
    }

    private func showSnippetAssignmentMessage(_ text: String, on surface: SnippetAssignmentSurface) {
        snippetAssignmentMessageTask?.cancel()
        snippetAssignmentMessage = SnippetAssignmentMessage(text: text, surface: surface)
        snippetAssignmentMessageTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.snippetAssignmentMessage = nil
        }
    }

    private func loadPersistedState() async {
        guard let store else { return }
        do {
            let manifest = try await store.loadManifest()
            history = manifest.history
            snippets = manifest.snippets.sorted { $0.slot < $1.slot }
            for snippet in snippets where snippet.preview.kind == .text {
                snippetTextDrafts[snippet.slot] = snippet.preview.title
            }
            try await store.reconcile(with: manifest)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func activateServices() {
        guard license.state.isUsable, !servicesActive else { return }
        servicesActive = true
        monitor.start()
    }

    private func reconcileLicenseState(atStartup: Bool = false) {
        if license.state.isUsable {
            proceedAfterActivation()
            return
        }
        servicesActive = false
        monitor.stop()
        if atStartup && (license.state == .notActivated || license.state == .loading) {
            showSettings(tab: .license)
        }
    }

    private func proceedAfterActivation() {
        if UserDefaults.standard.bool(forKey: "completedOnboarding") {
            if UserDefaults.standard.object(forKey: Self.launchAtLoginPreferenceKey) == nil {
                UserDefaults.standard.set(true, forKey: Self.launchAtLoginPreferenceKey)
            }
            if UserDefaults.standard.bool(forKey: Self.launchAtLoginPreferenceKey) {
                setLaunchAtLogin(true)
            }
            activateServices()
        } else {
            onboardingController.show()
        }
    }

    private func licenseStateChanged(
        from oldState: LicenseState,
        to newState: LicenseState,
        presentTerminal: Bool
    ) {
        guard hasStarted else { return }
        reconcileLicenseState()
        if presentTerminal,
           oldState != newState,
           newState == .refunded || newState == .revoked {
            licenseAlertController.present(newState)
        }
    }

    private func requireLicense(_ feature: LicensedFeature, presentUI: Bool = true) -> Bool {
        guard LicenseGate.allows(feature, state: license.state) else {
            if presentUI { presentLicenseUIForBlockedAttempt() }
            return false
        }
        return true
    }

    private func presentLicenseUIForBlockedAttempt() {
        if license.state == .refunded || license.state == .revoked {
            licenseAlertController.present(license.state)
        } else {
            showSettings(tab: .license)
        }
    }

    private func validateLicenseIfDue() {
        Task { @MainActor [weak self] in
            await self?.license.refresh(force: false)
        }
    }

    private func startLicenseValidationSchedule() {
        guard licenseValidationTask == nil else { return }
        licenseValidationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15 * 60))
                guard !Task.isCancelled else { return }
                await self?.license.refresh(force: false)
            }
        }
    }

    private func enqueueMutation(_ operation: @escaping @MainActor () async -> Void) {
        let previous = mutationTask
        mutationTask = Task { @MainActor in
            await previous?.value
            await operation()
        }
    }

    private func handlePasteResult(
        _ result: PasteCoordinator.Result,
        copiedMessage: String = "Copied to the clipboard, but the target app could not be verified for direct paste."
    ) {
        accessibilityTrusted = AccessibilityService.isTrusted
        switch result {
        case .pasted:
            break
        case .copiedOnly:
            lastError = accessibilityTrusted
                ? copiedMessage
                : "Copied to the clipboard. Allow Klipt in Privacy & Security > Accessibility for direct paste."
        case .failedToWrite:
            lastError = "Klipt could not place this item on the clipboard."
        }
    }

    private func handleHotKey(_ action: HotKeyAction) {
        switch action {
        case .history: showHistory()
        case .snippet(let slot): pasteSnippet(slot: slot)
        }
    }

    private func registerHotKeys() {
        hotKeyManager.unregisterAll()
        shortcutErrors = [:]
        registerHotKey(historyShortcut, action: .history)
        for snippet in snippets {
            registerHotKey(snippetShortcuts[snippet.slot] ?? .snippet(slot: snippet.slot), action: .snippet(snippet.slot))
        }
    }

    @discardableResult
    private func registerHotKey(_ shortcut: KeyboardShortcutSetting, action: HotKeyAction) -> Bool {
        let status = hotKeyManager.register(shortcut, for: action)
        if status == noErr {
            shortcutErrors[action] = nil
        } else {
            shortcutErrors[action] = "\(shortcut.displayText) is unavailable (error \(status))."
        }
        return status == noErr
    }

    private func frontmostExternalApplication() -> NSRunningApplication? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ownPID {
            lastExternalApplication = frontmost
            return frontmost
        }
        return lastExternalApplication
    }

    private func observeApplicationActivation() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ownPID {
            lastExternalApplication = frontmost
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task { @MainActor in
                self?.refreshAccessibilityStatus()
                if application.processIdentifier == ownPID {
                    self?.validateLicenseIfDue()
                }
                if application.processIdentifier != ownPID {
                    self?.lastExternalApplication = application
                }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.validateLicenseIfDue() }
        }
    }

    private func loadShortcutPreferences() {
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: "historyShortcut"),
           let shortcut = try? decoder.decode(KeyboardShortcutSetting.self, from: data) {
            historyShortcut = shortcut
        }
        for slot in 1...9 {
            if let data = UserDefaults.standard.data(forKey: "snippetShortcut.\(slot)"),
               let shortcut = try? decoder.decode(KeyboardShortcutSetting.self, from: data) {
                snippetShortcuts[slot] = shortcut
            }
        }
    }

    private func saveShortcutPreferences() {
        let encoder = JSONEncoder()
        UserDefaults.standard.set(try? encoder.encode(historyShortcut), forKey: "historyShortcut")
        for (slot, shortcut) in snippetShortcuts {
            UserDefaults.standard.set(try? encoder.encode(shortcut), forKey: "snippetShortcut.\(slot)")
        }
    }
}
