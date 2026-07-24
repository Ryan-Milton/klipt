import Foundation
import Security

enum CredentialStoreError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status): "Keychain error (\(status))."
        }
    }
}

protocol StringValueStoring {
    func load() throws -> String?
    func save(_ value: String) throws
}

final class KeychainStringStore: StringValueStoring {
    let service: String
    let account: String

    init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CredentialStoreError.keychain(status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw CredentialStoreError.keychain(errSecDecode)
        }
        return value
    }

    func save(_ value: String) throws {
        let data = Data(value.utf8)
        let status = SecItemUpdate(
            baseQuery as CFDictionary,
            [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ] as CFDictionary
        )
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw CredentialStoreError.keychain(status) }

        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw CredentialStoreError.keychain(addStatus) }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

struct InstallIDStore {
    let storage: any StringValueStoring
    var makeUUID: () -> UUID = UUID.init

    func loadOrCreate() throws -> UUID {
        if let value = try storage.load(), let identifier = UUID(uuidString: value) {
            try storage.save(identifier.uuidString)
            return identifier
        }
        let identifier = makeUUID()
        try storage.save(identifier.uuidString)
        return identifier
    }
}

protocol LicenseCredentialStoring {
    func installationID() throws -> UUID
    func licenseKey() throws -> String?
    func saveLicenseKey(_ key: String) throws
}

struct KeychainLicenseCredentialStore: LicenseCredentialStoring {
    static let installService = "com.ryanmilton.Klipt.installation"
    static let installAccount = "installation-id"
    static let licenseService = "com.ryanmilton.Klipt.license"
    static let licenseAccount = "license-key"

    private let installIDStore: InstallIDStore
    private let keyStore: any StringValueStoring

    init() {
        installIDStore = InstallIDStore(storage: KeychainStringStore(
            service: Self.installService,
            account: Self.installAccount
        ))
        keyStore = KeychainStringStore(service: Self.licenseService, account: Self.licenseAccount)
    }

    func installationID() throws -> UUID {
        try installIDStore.loadOrCreate()
    }

    func licenseKey() throws -> String? {
        try keyStore.load()
    }

    func saveLicenseKey(_ key: String) throws {
        try keyStore.save(key)
    }
}

final class EphemeralLicenseCredentialStore: LicenseCredentialStoring {
    private let identifier = UUID()
    private var key: String?

    func installationID() -> UUID { identifier }
    func licenseKey() -> String? { key }
    func saveLicenseKey(_ key: String) { self.key = key }
}
