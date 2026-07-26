import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import Klipt

@Suite(.serialized)
struct PasteboardCodecTests {
    @Test @MainActor
    func capturesAndReconstructsMultipleRepresentations() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("KliptTests.\(UUID().uuidString)"))
        let item = NSPasteboardItem()
        let text = "Klipt clipboard test"
        let customData = Data([0x01, 0x02, 0x03, 0xFF])
        item.setString(text, forType: .string)
        item.setData(customData, forType: NSPasteboard.PasteboardType("com.klipt.test-data"))
        pasteboard.writeObjects([item])

        let payload = try #require(PasteboardCodec.capture(from: pasteboard, sourceApplication: nil))
        #expect(payload.items.count == 1)
        #expect(payload.items[0].representations.contains { $0.data == customData })

        let output = NSPasteboard(name: NSPasteboard.Name("KliptTests.Output.\(UUID().uuidString)"))
        #expect(PasteboardCodec.write(payload, to: output))
        #expect(output.string(forType: .string) == text)
        #expect(output.data(forType: NSPasteboard.PasteboardType("com.klipt.test-data")) == customData)
    }

    @Test @MainActor
    func canonicalHashIgnoresRepresentationOrder() {
        let first = PasteboardRepresentation(typeIdentifier: "public.text", data: Data("one".utf8))
        let second = PasteboardRepresentation(typeIdentifier: "public.data", data: Data([4, 5, 6]))
        let forward = [ClipboardItemPayload(representations: [first, second])]
        let reverse = [ClipboardItemPayload(representations: [second, first])]

        #expect(PasteboardCodec.contentHash(for: forward) == PasteboardCodec.contentHash(for: reverse))
    }

    @Test @MainActor
    func textPreviewIsSearchable() throws {
        let payload = PasteboardCodec.textPayload("A reusable release checklist")
        let record = PasteboardCodec.makeRecord(from: payload)

        #expect(record.kind == .text)
        #expect(record.searchableText.contains("release checklist"))
        #expect(record.contentHash == payload.contentHash)
    }
}

struct EncryptedStoreTests {
    @Test
    func encryptedPayloadAndManifestRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = Data(repeating: 0xA7, count: 32)
        let store = try EncryptedStore(baseURL: directory, keyData: key)
        let payload = makePayload(text: "unencrypted marker")
        let record = makeRecord(for: payload)
        let manifest = StoreManifest(history: [record], snippets: [])

        try await store.saveHistoryPayload(payload)
        try await store.saveManifest(manifest)

        #expect(try await store.loadHistoryPayload(id: payload.id) == payload)
        #expect(try await store.loadManifest() == manifest)

        let encryptedData = try Data(contentsOf: directory
            .appendingPathComponent("History")
            .appendingPathComponent("\(payload.id.uuidString).klipt"))
        #expect(encryptedData.range(of: Data("unencrypted marker".utf8)) == nil)
    }

    @Test
    func wrongKeyCannotReadPayload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = try EncryptedStore(baseURL: directory, keyData: Data(repeating: 1, count: 32))
        let payload = makePayload(text: "secret")
        try await writer.saveHistoryPayload(payload)

        let reader = try EncryptedStore(baseURL: directory, keyData: Data(repeating: 2, count: 32))
        await #expect(throws: StoreError.self) {
            try await reader.loadHistoryPayload(id: payload.id)
        }
    }

    @Test
    func reconciliationRemovesOnlyOrphanedPayloads() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EncryptedStore(baseURL: directory, keyData: Data(repeating: 7, count: 32))
        let kept = makePayload(text: "kept")
        let orphan = makePayload(text: "orphan")
        try await store.saveHistoryPayload(kept)
        try await store.saveHistoryPayload(orphan)
        let manifest = StoreManifest(history: [makeRecord(for: kept)], snippets: [])

        try await store.reconcile(with: manifest)

        #expect(try await store.loadHistoryPayload(id: kept.id) == kept)
        await #expect(throws: (any Error).self) {
            try await store.loadHistoryPayload(id: orphan.id)
        }
    }

    @Test
    func snippetPayloadSurvivesHistoryRemovalAndReconciliation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EncryptedStore(baseURL: directory, keyData: Data(repeating: 9, count: 32))
        let source = makePayload(text: "protected snippet")
        let snippetPayload = source.copyWithFreshID()
        let snippet = makeSnippet(slot: 3, payload: snippetPayload)
        let manifest = StoreManifest(history: [], snippets: [snippet])

        try await store.saveSnippetPayload(snippetPayload)
        try await store.saveManifest(manifest)
        try await store.reconcile(with: manifest)

        #expect(try await store.loadSnippetPayload(id: snippetPayload.id) == snippetPayload)
        #expect(try await store.loadManifest() == manifest)
    }
}

struct StoragePolicyTests {
    @Test
    func evictsOldestForCountLimit() {
        let records = (0..<5).map { makeRecord(byteCount: 10, title: "\($0)") }
        let result = StoragePolicy.trimHistory(records, snippetBytes: 0, limit: 1_000, countLimit: 3)

        #expect(result.kept.map(\.title) == ["0", "1", "2"])
        #expect(result.evicted.map(\.title) == ["4", "3"])
    }

    @Test
    func reservesStorageForProtectedSnippets() {
        let records = (0..<3).map { makeRecord(byteCount: 40, title: "\($0)") }
        let result = StoragePolicy.trimHistory(records, snippetBytes: 70, limit: 150, countLimit: 100)

        #expect(result.kept.map(\.title) == ["0", "1"])
        #expect(result.evicted.map(\.title) == ["2"])
    }
}

struct SettingsControlTests {
    @Test @MainActor
    func shortcutRecorderRendersAfterShortcutChanges() throws {
        let view = ShortcutRecorderNSView(
            shortcut: .history,
            onChange: { _ in },
            onRecordingChanged: { _ in }
        )
        view.frame = NSRect(x: 0, y: 0, width: 110, height: 28)
        view.shortcut = KeyboardShortcutSetting(keyCode: 42, modifiers: 0)
        view.layoutSubtreeIfNeeded()

        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        #expect(bitmap.pixelsWide > 0)
    }
}

struct HistoryPanelLayoutTests {
    @Test @MainActor
    func sizesToVisibleItemsWithinLimits() {
        #expect(HistoryPanelController.contentHeight(for: 0) == 260)
        #expect(HistoryPanelController.contentHeight(for: 2) == 260)
        #expect(HistoryPanelController.contentHeight(for: 4) == 379)
        #expect(HistoryPanelController.contentHeight(for: 100) == 520)
    }

    @Test @MainActor
    func mapsTopRowAndKeypadAssignmentShortcuts() {
        let modifiers: NSEvent.ModifierFlags = [.command, .option]

        #expect(HistoryPanelController.assignmentSlot(keyCode: UInt16(kVK_ANSI_1), modifiers: modifiers) == 1)
        #expect(HistoryPanelController.assignmentSlot(keyCode: UInt16(kVK_ANSI_9), modifiers: modifiers) == 9)
        #expect(HistoryPanelController.assignmentSlot(keyCode: UInt16(kVK_ANSI_Keypad4), modifiers: modifiers) == 4)
        #expect(HistoryPanelController.assignmentSlot(keyCode: UInt16(kVK_ANSI_4), modifiers: [.command]) == nil)
        #expect(HistoryPanelController.assignmentSlot(keyCode: UInt16(kVK_ANSI_4), modifiers: [.command, .option, .shift]) == nil)
    }
}

struct SnippetAssignmentTests {
    @Test
    func copiedPayloadHasIndependentIdentity() {
        let source = makePayload(text: "independent")
        let copy = source.copyWithFreshID()

        #expect(copy.id != source.id)
        #expect(copy.contentHash == source.contentHash)
        #expect(copy.items == source.items)
        #expect(copy.byteCount == source.byteCount)
    }

    @Test @MainActor
    func emptySlotAssignmentNeedsNoConfirmation() {
        let payload = makePayload(text: "new")
        let request = SnippetAssignmentRequest(
            source: .payload(payload),
            targetSlot: 4,
            surface: .settings,
            snippets: []
        )

        #expect(!request.isNoOp)
        #expect(!request.requiresConfirmation)
        #expect(request.matchingSnippets.isEmpty)
    }

    @Test @MainActor
    func assigningToCurrentSlotIsNoOp() {
        let payload = makePayload(text: "current")
        let request = SnippetAssignmentRequest(
            source: .history(makeRecord(for: payload)),
            targetSlot: 3,
            surface: .history,
            snippets: [makeSnippet(slot: 3, payload: payload)]
        )

        #expect(request.isNoOp)
        #expect(!request.requiresConfirmation)
    }

    @Test @MainActor
    func moveIntoOccupiedSlotRequiresCombinedConfirmation() {
        let moving = makePayload(text: "moving")
        let replaced = makePayload(text: "replaced")
        let request = SnippetAssignmentRequest(
            source: .history(makeRecord(for: moving)),
            targetSlot: 5,
            surface: .history,
            snippets: [
                makeSnippet(slot: 2, payload: moving),
                makeSnippet(slot: 5, payload: replaced, name: "Deployment token")
            ]
        )

        #expect(request.requiresConfirmation)
        #expect(request.matchingSnippets.map(\.slot) == [2])
        #expect(request.targetSnippet?.slot == 5)
        #expect(request.targetSnippet?.name == "Deployment token")
    }

    @Test @MainActor
    func legacyDuplicatesAreAllIncludedForConsolidation() {
        let payload = makePayload(text: "duplicate")
        let request = SnippetAssignmentRequest(
            source: .payload(payload),
            targetSlot: 4,
            surface: .settings,
            snippets: [
                makeSnippet(slot: 7, payload: payload.copyWithFreshID()),
                makeSnippet(slot: 2, payload: payload.copyWithFreshID())
            ]
        )

        #expect(request.requiresConfirmation)
        #expect(request.matchingSnippets.map(\.slot) == [2, 7])
        #expect(request.confirmationFingerprint.count == 2)
    }
}

struct ValidationPolicyTests {
    @Test
    func validationBecomesDueAtTwentyFourHours() {
        let checkedAt = Date(timeIntervalSince1970: 1_000)

        #expect(!ValidationPolicy.isDue(
            lastSuccessfulValidation: checkedAt,
            now: checkedAt.addingTimeInterval(ValidationPolicy.interval - 1)
        ))
        #expect(ValidationPolicy.isDue(
            lastSuccessfulValidation: checkedAt,
            now: checkedAt.addingTimeInterval(ValidationPolicy.interval)
        ))
        #expect(ValidationPolicy.isDue(lastSuccessfulValidation: nil, now: checkedAt))
    }
}

struct LicenseResponseMappingTests {
    @Test
    func mapsNestedActiveResponseAndActivationDate() throws {
        let data = Data(#"{"license":{"status":"active","activated_at":"2026-07-24T12:00:00Z"}}"#.utf8)
        let result = try LicenseResponseMapper.map(data: data, statusCode: 200)

        #expect(result.status == .active)
        #expect(result.activatedAt != nil)
    }

    @Test(arguments: [
        (#"{"status":"refunded"}"#, LicenseServerStatus.refunded),
        (#"{"data":{"status":"revoked"}}"#, LicenseServerStatus.revoked),
        (#"{"status":"invalid_key","message":"Unknown key"}"#, LicenseServerStatus.notActivated)
    ])
    func mapsTerminalAndInvalidStatuses(json: String, expected: LicenseServerStatus) throws {
        #expect(try LicenseResponseMapper.map(data: Data(json.utf8), statusCode: 200).status == expected)
    }

    @Test
    func distinguishesServerErrorsFromTransportFailures() {
        let data = Data(#"{"message":"Maintenance"}"#.utf8)

        #expect(throws: LicenseFailure.self) {
            _ = try LicenseResponseMapper.map(data: data, statusCode: 503)
        }
        #expect(throws: LicenseFailure.self) {
            _ = try LicenseResponseMapper.map(
                data: Data(#"{"status":"active"}"#.utf8),
                statusCode: 503
            )
        }
    }
}

struct LicenseAPIConfigurationTests {
    @Test
    func acceptsOnlyHTTPSLicenseEndpoints() {
        #expect(
            LicenseAPIConfiguration.validatedBaseURL("https://www.klipt.dev/api/licenses/")?.absoluteString
                == "https://www.klipt.dev/api/licenses/"
        )
        #expect(
            LicenseAPIConfiguration.validatedBaseURL("https://sandbox.klipt.dev/api/licenses/")?.absoluteString
                == "https://sandbox.klipt.dev/api/licenses/"
        )
        #expect(LicenseAPIConfiguration.validatedBaseURL("http://sandbox.klipt.dev/api/licenses/") == nil)
        #expect(LicenseAPIConfiguration.validatedBaseURL("https://sandbox.klipt.dev/api/admin/") == nil)
        #expect(LicenseAPIConfiguration.validatedBaseURL("https://user@sandbox.klipt.dev/api/licenses/") == nil)
    }
}

struct InstallIDStoreTests {
    @Test
    func generatesOnceAndRefreshesStorageAttributes() throws {
        let storage = MemoryStringStore()
        let expected = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let store = InstallIDStore(storage: storage, makeUUID: { expected })

        #expect(try store.loadOrCreate() == expected)
        #expect(try store.loadOrCreate() == expected)
        #expect(storage.savedValues == [expected.uuidString, expected.uuidString])
    }

    @Test
    func licensingItemsDoNotReuseEncryptionKeyItem() {
        #expect(KeychainLicenseCredentialStore.installService != "com.ryanmilton.Klipt.local-storage")
        #expect(KeychainLicenseCredentialStore.licenseService != "com.ryanmilton.Klipt.local-storage")
        #expect(KeychainLicenseCredentialStore.installService != KeychainLicenseCredentialStore.licenseService)
        #expect(KeychainLicenseCredentialStore.installAccount != KeychainLicenseCredentialStore.licenseAccount)
    }
}

struct LicenseGateTests {
    @Test
    func permitsOnlyActiveAndOfflineActiveStates() {
        let networkFailure = LicenseFailure(kind: .network, message: "Offline")
        for feature in [LicensedFeature.capture, .paste, .snippetAssignment] {
            #expect(LicenseGate.allows(feature, state: .active))
            #expect(LicenseGate.allows(feature, state: .offlineActive(networkFailure)))
            #expect(!LicenseGate.allows(feature, state: .notActivated))
            #expect(!LicenseGate.allows(feature, state: .refunded))
            #expect(!LicenseGate.allows(feature, state: .revoked))
            #expect(!LicenseGate.allows(feature, state: .error(networkFailure)))
        }
    }
}

@Suite(.serialized)
struct LicenseControllerTests {
    @Test @MainActor
    func networkFailureKeepsPreviouslyActiveLicenseUsable() async throws {
        let (defaults, suiteName) = temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentials = EphemeralLicenseCredentialStore()
        let api = StubLicenseAPI(
            activation: .success(LicenseServerResult(status: .active, activatedAt: nil, message: nil)),
            validation: .failure(LicenseFailure(kind: .network, message: "Offline"))
        )
        let controller = LicenseController(credentials: credentials, api: api, defaults: defaults)

        await controller.activate(key: "KLIPT-TEST-1234", nickname: "Desk Mac")
        await controller.refresh()

        #expect(controller.state.isUsable)
        #expect(controller.state == .offlineActive(LicenseFailure(kind: .network, message: "Offline")))
    }

    @Test @MainActor
    func refundedStatusIsCachedAndRestoredBlocked() async {
        let (defaults, suiteName) = temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentials = EphemeralLicenseCredentialStore()
        let api = StubLicenseAPI(
            activation: .success(LicenseServerResult(status: .active, activatedAt: nil, message: nil)),
            validation: .success(LicenseServerResult(status: .refunded, activatedAt: nil, message: nil))
        )
        let first = LicenseController(credentials: credentials, api: api, defaults: defaults)
        await first.activate(key: "KLIPT-TEST-5678", nickname: "Desk Mac")
        await first.refresh()

        let offlineAPI = StubLicenseAPI(
            activation: .failure(LicenseFailure(kind: .network, message: "Offline")),
            validation: .failure(LicenseFailure(kind: .network, message: "Offline"))
        )
        let restored = LicenseController(credentials: credentials, api: offlineAPI, defaults: defaults)
        _ = restored.restore()
        await restored.refresh()

        #expect(first.state == .refunded)
        #expect(restored.state == .refunded)
        #expect(!restored.state.isUsable)
    }

    @Test @MainActor
    func authoritativeInvalidStatusRemovesUsableCache() async {
        let (defaults, suiteName) = temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentials = EphemeralLicenseCredentialStore()
        let api = StubLicenseAPI(
            activation: .success(LicenseServerResult(status: .active, activatedAt: nil, message: nil)),
            validation: .success(LicenseServerResult(status: .notActivated, activatedAt: nil, message: nil))
        )
        let first = LicenseController(credentials: credentials, api: api, defaults: defaults)
        await first.activate(key: "KLIPT-TEST-9012", nickname: "Desk Mac")
        await first.refresh()

        let restored = LicenseController(credentials: credentials, api: api, defaults: defaults)
        #expect(restored.restore())
        #expect(!restored.state.isUsable)
        #expect(restored.state == .loading)
    }
}

private func makePayload(text: String) -> ClipboardPayload {
    let data = Data(text.utf8)
    let items = [ClipboardItemPayload(representations: [
        PasteboardRepresentation(typeIdentifier: NSPasteboard.PasteboardType.string.rawValue, data: data)
    ])]
    return ClipboardPayload(
        id: UUID(),
        createdAt: Date(timeIntervalSince1970: 123),
        sourceBundleIdentifier: "com.klipt.tests",
        sourceApplicationName: "Tests",
        items: items,
        byteCount: Int64(data.count),
        contentHash: "test-hash-\(text)"
    )
}

private final class MemoryStringStore: StringValueStoring {
    var value: String?
    var savedValues: [String] = []

    func load() -> String? { value }
    func save(_ value: String) {
        self.value = value
        savedValues.append(value)
    }
}

private struct StubLicenseAPI: LicenseAPIClient {
    let activation: Result<LicenseServerResult, LicenseFailure>
    let validation: Result<LicenseServerResult, LicenseFailure>

    func activate(_ request: LicenseAPIRequest) async throws -> LicenseServerResult {
        try activation.get()
    }

    func validate(_ request: LicenseAPIRequest) async throws -> LicenseServerResult {
        try validation.get()
    }
}

private func temporaryDefaults() -> (UserDefaults, String) {
    let name = "KliptTests.Licensing.\(UUID().uuidString)"
    return (UserDefaults(suiteName: name)!, name)
}

private func makeRecord(for payload: ClipboardPayload) -> ClipboardRecord {
    ClipboardRecord(
        id: payload.id,
        createdAt: payload.createdAt,
        sourceBundleIdentifier: payload.sourceBundleIdentifier,
        sourceApplicationName: payload.sourceApplicationName,
        byteCount: payload.byteCount,
        contentHash: payload.contentHash,
        kind: .text,
        title: "Test",
        detail: "public.text",
        searchableText: "Test",
        previewImageData: nil
    )
}

private func makeRecord(byteCount: Int64, title: String) -> ClipboardRecord {
    ClipboardRecord(
        id: UUID(),
        createdAt: Date(),
        sourceBundleIdentifier: nil,
        sourceApplicationName: nil,
        byteCount: byteCount,
        contentHash: title,
        kind: .data,
        title: title,
        detail: "",
        searchableText: title,
        previewImageData: nil
    )
}

private func makeSnippet(slot: Int, payload: ClipboardPayload, name: String? = nil) -> SnippetRecord {
    SnippetRecord(
        slot: slot,
        name: name ?? "Snippet \(slot)",
        payloadID: payload.id,
        byteCount: payload.byteCount,
        preview: makeRecord(for: payload)
    )
}
