import CryptoKit
import Foundation
import Security

enum StoreError: LocalizedError {
    case keychain(OSStatus)
    case invalidEncryptedData
    case entryTooLarge
    case storageFull

    var errorDescription: String? {
        switch self {
        case .keychain(let status): "Keychain error (\(status))."
        case .invalidEncryptedData: "Klipt could not decrypt its local clipboard data."
        case .entryTooLarge: "This clipboard item is larger than Klipt's 100 MB per-item limit."
        case .storageFull: "Klipt's 1 GB storage limit is full of protected snippets."
        }
    }
}

actor EncryptedStore {
    private let baseURL: URL
    private let historyURL: URL
    private let snippetsURL: URL
    private let manifestURL: URL
    private let key: SymmetricKey
    private let encoder: PropertyListEncoder
    private let decoder = PropertyListDecoder()

    init(baseURL: URL? = nil, keyData: Data? = nil) throws {
        let root = try baseURL ?? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Klipt", isDirectory: true)

        self.baseURL = root
        historyURL = root.appendingPathComponent("History", isDirectory: true)
        snippetsURL = root.appendingPathComponent("Snippets", isDirectory: true)
        manifestURL = root.appendingPathComponent("manifest.klipt")
        key = SymmetricKey(data: try keyData ?? KeychainKey.loadOrCreate())
        encoder = PropertyListEncoder()
        encoder.outputFormat = .binary

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: historyURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: snippetsURL, withIntermediateDirectories: true)
    }

    func loadManifest() throws -> StoreManifest {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return StoreManifest() }
        let encrypted = try Data(contentsOf: manifestURL)
        return try decoder.decode(StoreManifest.self, from: decrypt(encrypted))
    }

    func saveManifest(_ manifest: StoreManifest) throws {
        try encrypt(encoder.encode(manifest)).write(to: manifestURL, options: [.atomic, .completeFileProtection])
    }

    func saveHistoryPayload(_ payload: ClipboardPayload) throws {
        try save(payload, at: historyURL.appendingPathComponent("\(payload.id.uuidString).klipt"))
    }

    func loadHistoryPayload(id: UUID) throws -> ClipboardPayload {
        try load(from: historyURL.appendingPathComponent("\(id.uuidString).klipt"))
    }

    func deleteHistoryPayload(id: UUID) throws {
        try removeIfPresent(historyURL.appendingPathComponent("\(id.uuidString).klipt"))
    }

    func saveSnippetPayload(_ payload: ClipboardPayload) throws {
        try save(payload, at: snippetsURL.appendingPathComponent("\(payload.id.uuidString).klipt"))
    }

    func loadSnippetPayload(id: UUID) throws -> ClipboardPayload {
        try load(from: snippetsURL.appendingPathComponent("\(id.uuidString).klipt"))
    }

    func deleteSnippetPayload(id: UUID) throws {
        try removeIfPresent(snippetsURL.appendingPathComponent("\(id.uuidString).klipt"))
    }

    func clearHistory(ids: [UUID]) throws {
        for id in ids { try deleteHistoryPayload(id: id) }
    }

    func reconcile(with manifest: StoreManifest) throws {
        try removeOrphans(in: historyURL, keeping: Set(manifest.history.map { "\($0.id.uuidString).klipt" }))
        try removeOrphans(in: snippetsURL, keeping: Set(manifest.snippets.map { "\($0.payloadID.uuidString).klipt" }))
    }

    private func save(_ payload: ClipboardPayload, at url: URL) throws {
        try encrypt(encoder.encode(payload)).write(to: url, options: [.atomic, .completeFileProtection])
    }

    private func load(from url: URL) throws -> ClipboardPayload {
        try decoder.decode(ClipboardPayload.self, from: decrypt(Data(contentsOf: url)))
    }

    private func encrypt(_ data: Data) throws -> Data {
        guard let combined = try AES.GCM.seal(data, using: key).combined else {
            throw StoreError.invalidEncryptedData
        }
        return combined
    }

    private func decrypt(_ data: Data) throws -> Data {
        do {
            return try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key)
        } catch {
            throw StoreError.invalidEncryptedData
        }
    }

    private func removeIfPresent(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func removeOrphans(in directory: URL, keeping expectedNames: Set<String>) throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for file in files where !expectedNames.contains(file.lastPathComponent) {
            try FileManager.default.removeItem(at: file)
        }
    }
}

private enum KeychainKey {
    static let service = "com.ryanmilton.Klipt.local-storage"
    static let account = "encryption-key"

    static func loadOrCreate() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data { return data }
        guard status == errSecItemNotFound else { throw StoreError.keychain(status) }

        var bytes = [UInt8](repeating: 0, count: 32)
        let randomStatus = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard randomStatus == errSecSuccess else { throw StoreError.keychain(randomStatus) }
        let data = Data(bytes)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw StoreError.keychain(addStatus) }
        return data
    }
}
