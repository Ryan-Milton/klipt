import Darwin
import Foundation
import Observation

enum LicenseFailureKind: String, Codable, Sendable {
    case network
    case server
    case response
    case storage
}

struct LicenseFailure: Error, Equatable, Sendable {
    let kind: LicenseFailureKind
    let message: String
}

enum LicenseState: Equatable, Sendable {
    case loading
    case notActivated
    case activating
    case active
    case offlineActive(LicenseFailure)
    case refunded
    case revoked
    case error(LicenseFailure)

    var isUsable: Bool {
        switch self {
        case .active, .offlineActive: true
        default: false
        }
    }

    var statusText: String {
        switch self {
        case .loading: "Loading"
        case .notActivated: "Not activated"
        case .activating: "Activating"
        case .active: "Active"
        case .offlineActive: "Active (offline)"
        case .refunded: "License refunded"
        case .revoked: "License revoked"
        case .error: "Activation required"
        }
    }

    var detailText: String? {
        switch self {
        case .offlineActive(let failure), .error(let failure): failure.message
        case .notActivated: "Enter the license key emailed after purchase."
        case .refunded: "This license was refunded and can no longer be used on this Mac."
        case .revoked: "This license has been revoked and can no longer be used on this Mac."
        default: nil
        }
    }
}

enum LicensedFeature: Sendable {
    case capture
    case paste
    case snippetAssignment
}

enum LicenseGate {
    static func allows(_ feature: LicensedFeature, state: LicenseState) -> Bool {
        state.isUsable
    }
}

enum ValidationPolicy {
    static let interval: TimeInterval = 24 * 60 * 60

    static func isDue(lastSuccessfulValidation: Date?, now: Date = Date()) -> Bool {
        guard let lastSuccessfulValidation else { return true }
        return now.timeIntervalSince(lastSuccessfulValidation) >= interval
    }
}

struct LicenseDevice: Equatable, Sendable {
    let nickname: String
    let model: String
    let appVersion: String
    let appBuild: String
}

struct LicenseAPIRequest: Encodable, Sendable {
    let licenseKey: String
    let installationID: UUID
    let device: LicenseDevice

    enum CodingKeys: String, CodingKey {
        case licenseKey = "license_key"
        case installationID = "installation_id"
        case deviceNickname = "device_nickname"
        case deviceModel = "device_model"
        case appVersion = "app_version"
        case appBuild = "app_build"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(licenseKey, forKey: .licenseKey)
        try container.encode(installationID.uuidString, forKey: .installationID)
        try container.encode(device.nickname, forKey: .deviceNickname)
        try container.encode(device.model, forKey: .deviceModel)
        try container.encode(device.appVersion, forKey: .appVersion)
        try container.encode(device.appBuild, forKey: .appBuild)
    }
}

enum LicenseServerStatus: Equatable, Sendable {
    case active
    case notActivated
    case refunded
    case revoked
}

struct LicenseServerResult: Equatable, Sendable {
    let status: LicenseServerStatus
    let activatedAt: Date?
    let message: String?
}

enum LicenseResponseMapper {
    static func map(data: Data, statusCode: Int) throws -> LicenseServerResult {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LicenseFailure(kind: .response, message: "The licensing server returned an unreadable response.")
        }
        let nested = (object["license"] as? [String: Any])
            ?? (object["data"] as? [String: Any])
            ?? [:]
        let rawStatus = string("status", in: object, nested: nested)
            ?? string("license_status", in: object, nested: nested)
            ?? ((object["valid"] as? Bool) == true ? "active" : nil)
        let message = string("message", in: object, nested: nested)
            ?? string("error", in: object, nested: nested)

        guard let rawStatus else {
            if !(200..<300).contains(statusCode) {
                throw LicenseFailure(kind: .server, message: message ?? "Licensing server error (HTTP \(statusCode)).")
            }
            throw LicenseFailure(kind: .response, message: "The licensing server response did not include a license status.")
        }

        let status: LicenseServerStatus
        switch rawStatus.lowercased().replacingOccurrences(of: "-", with: "_") {
        case "active", "activated", "valid": status = .active
        case "refunded": status = .refunded
        case "revoked": status = .revoked
        case "not_activated", "inactive", "invalid", "invalid_key", "not_found", "expired": status = .notActivated
        default:
            throw LicenseFailure(kind: .server, message: message ?? "The licensing server returned status “\(rawStatus)”.")
        }

        if !(200..<300).contains(statusCode), status == .active {
            throw LicenseFailure(kind: .server, message: message ?? "Licensing server error (HTTP \(statusCode)).")
        }

        let activatedAt = string("activated_at", in: object, nested: nested).flatMap(parseDate)
        return LicenseServerResult(status: status, activatedAt: activatedAt, message: message)
    }

    private static func string(_ key: String, in object: [String: Any], nested: [String: Any]) -> String? {
        (object[key] as? String) ?? (nested[key] as? String)
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

protocol LicenseAPIClient: Sendable {
    func activate(_ request: LicenseAPIRequest) async throws -> LicenseServerResult
    func validate(_ request: LicenseAPIRequest) async throws -> LicenseServerResult
}

enum LicenseAPIConfiguration {
    static let infoKey = "KliptLicenseAPIBaseURL"

    static func validatedBaseURL(_ value: String?) -> URL? {
        guard
            let value,
            let components = URLComponents(string: value),
            components.scheme == "https",
            components.host != nil,
            components.user == nil,
            components.password == nil,
            components.query == nil,
            components.fragment == nil,
            components.path == "/api/licenses/",
            let url = components.url
        else { return nil }
        return url
    }

    static func bundleBaseURL(bundle: Bundle = .main) -> URL {
        let value = bundle.object(forInfoDictionaryKey: infoKey) as? String
        guard let url = validatedBaseURL(value) else {
            preconditionFailure("KliptLicenseAPIBaseURL must be a valid HTTPS /api/licenses/ URL")
        }
        return url
    }
}

final class FirstPartyLicenseAPI: LicenseAPIClient, @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession

    init(session: URLSession? = nil, baseURL: URL? = nil) {
        self.baseURL = baseURL ?? LicenseAPIConfiguration.bundleBaseURL()
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10
            configuration.timeoutIntervalForResource = 15
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
    }

    func activate(_ request: LicenseAPIRequest) async throws -> LicenseServerResult {
        try await send(request, endpoint: "activate")
    }

    func validate(_ request: LicenseAPIRequest) async throws -> LicenseServerResult {
        try await send(request, endpoint: "validate")
    }

    private func send(_ payload: LicenseAPIRequest, endpoint: String) async throws -> LicenseServerResult {
        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(payload)
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw LicenseFailure(kind: .response, message: "The licensing server returned an invalid response.")
            }
            return try LicenseResponseMapper.map(data: data, statusCode: response.statusCode)
        } catch let failure as LicenseFailure {
            throw failure
        } catch {
            throw LicenseFailure(kind: .network, message: "Klipt could not reach the licensing server. Check your connection and try again.")
        }
    }
}

private enum CachedLicenseStatus: String, Codable {
    case active
    case refunded
    case revoked
}

private struct CachedLicense: Codable {
    let status: CachedLicenseStatus
    let maskedKey: String
    let deviceNickname: String
    let deviceModel: String
    let activatedAt: Date?
    let lastSuccessfulValidation: Date?
}

@MainActor
@Observable
final class LicenseController {
    var state: LicenseState = .loading
    var isRefreshing = false
    var maskedKey: String?
    var deviceNickname: String
    let deviceModel: String
    let appVersion: String
    let appBuild: String
    var activatedAt: Date?
    var lastSuccessfulValidation: Date?
    var lastFailure: LicenseFailure?

    @ObservationIgnored var onStateChange: ((LicenseState, LicenseState, Bool) -> Void)?
    @ObservationIgnored private let credentials: any LicenseCredentialStoring
    @ObservationIgnored private let api: any LicenseAPIClient
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var operationID: UUID?
    @ObservationIgnored private static let cacheKey = "license.cached-state.v1"

    init(
        credentials: any LicenseCredentialStoring,
        api: any LicenseAPIClient = FirstPartyLicenseAPI(),
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.credentials = credentials
        self.api = api
        self.defaults = defaults
        self.now = now
        let info = DeviceInformation.current
        deviceNickname = info.nickname
        deviceModel = info.model
        appVersion = info.appVersion
        appBuild = info.appBuild
    }

    var hasStoredKey: Bool { maskedKey != nil }

    @discardableResult
    func restore() -> Bool {
        do {
            _ = try credentials.installationID()
            guard let key = try credentials.licenseKey(), !key.isEmpty else {
                setState(.notActivated, presentTerminal: false)
                return false
            }
            maskedKey = Self.mask(key)
            guard let data = defaults.data(forKey: Self.cacheKey),
                  let cached = try? JSONDecoder().decode(CachedLicense.self, from: data) else {
                setState(.loading, presentTerminal: false)
                return true
            }
            maskedKey = cached.maskedKey
            deviceNickname = cached.deviceNickname
            activatedAt = cached.activatedAt
            lastSuccessfulValidation = cached.lastSuccessfulValidation
            let restoredState: LicenseState = switch cached.status {
            case .active: .active
            case .refunded: .refunded
            case .revoked: .revoked
            }
            setState(restoredState, presentTerminal: false)
            return ValidationPolicy.isDue(lastSuccessfulValidation: cached.lastSuccessfulValidation, now: now())
        } catch {
            setState(.error(storageFailure(error)), presentTerminal: false)
            return false
        }
    }

    func activate(key submittedKey: String, nickname: String) async {
        let key = submittedKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !nickname.isEmpty else {
            setState(.error(LicenseFailure(kind: .response, message: "Enter both your emailed license key and a device nickname.")))
            return
        }
        setState(.activating)
        let operationID = UUID()
        self.operationID = operationID
        lastFailure = nil
        do {
            let request = try makeRequest(key: key, nickname: nickname)
            let result = try await api.activate(request)
            guard self.operationID == operationID else { return }
            if result.status != .notActivated {
                try credentials.saveLicenseKey(key)
                maskedKey = Self.mask(key)
            }
            deviceNickname = nickname
            apply(result, presentTerminal: true)
        } catch {
            guard self.operationID == operationID else { return }
            applyFailure(error)
        }
    }

    func refresh(force: Bool = true) async {
        guard !isRefreshing, state != .activating else { return }
        if !force && !ValidationPolicy.isDue(lastSuccessfulValidation: lastSuccessfulValidation, now: now()) {
            return
        }
        isRefreshing = true
        let operationID = UUID()
        self.operationID = operationID
        defer { isRefreshing = false }
        do {
            guard let key = try credentials.licenseKey(), !key.isEmpty else {
                setState(.notActivated)
                return
            }
            let result = try await api.validate(makeRequest(key: key, nickname: deviceNickname))
            guard self.operationID == operationID else { return }
            apply(result, presentTerminal: true)
        } catch {
            guard self.operationID == operationID else { return }
            applyFailure(error)
        }
    }

    private func makeRequest(key: String, nickname: String) throws -> LicenseAPIRequest {
        LicenseAPIRequest(
            licenseKey: key,
            installationID: try credentials.installationID(),
            device: LicenseDevice(
                nickname: nickname,
                model: deviceModel,
                appVersion: appVersion,
                appBuild: appBuild
            )
        )
    }

    private func apply(_ result: LicenseServerResult, presentTerminal: Bool) {
        let checkedAt = now()
        lastSuccessfulValidation = checkedAt
        lastFailure = nil
        if let activatedAt = result.activatedAt { self.activatedAt = activatedAt }
        switch result.status {
        case .active:
            setState(.active)
            persist(.active)
        case .refunded:
            setState(.refunded, presentTerminal: presentTerminal)
            persist(.refunded)
        case .revoked:
            setState(.revoked, presentTerminal: presentTerminal)
            persist(.revoked)
        case .notActivated:
            lastFailure = LicenseFailure(kind: .server, message: result.message ?? "The licensing server did not recognize this key.")
            lastSuccessfulValidation = nil
            defaults.removeObject(forKey: Self.cacheKey)
            setState(.notActivated)
        }
    }

    private func applyFailure(_ error: Error) {
        let failure = (error as? LicenseFailure) ?? storageFailure(error)
        lastFailure = failure
        switch state {
        case .active, .offlineActive:
            setState(.offlineActive(failure))
            persist(.active)
        case .refunded, .revoked:
            break
        default:
            setState(.error(failure))
        }
    }

    private func persist(_ status: CachedLicenseStatus) {
        guard let maskedKey else { return }
        let cached = CachedLicense(
            status: status,
            maskedKey: maskedKey,
            deviceNickname: deviceNickname,
            deviceModel: deviceModel,
            activatedAt: activatedAt,
            lastSuccessfulValidation: lastSuccessfulValidation
        )
        defaults.set(try? JSONEncoder().encode(cached), forKey: Self.cacheKey)
    }

    private func setState(_ newState: LicenseState, presentTerminal: Bool = false) {
        let oldState = state
        state = newState
        onStateChange?(oldState, newState, presentTerminal)
    }

    private func storageFailure(_ error: Error) -> LicenseFailure {
        LicenseFailure(kind: .storage, message: "Klipt could not access its licensing credentials: \(error.localizedDescription)")
    }

    private static func mask(_ key: String) -> String {
        let suffix = key.suffix(4)
        return "••••-••••-\(suffix)"
    }
}

enum DeviceInformation {
    static var current: LicenseDevice {
        let bundle = Bundle.main
        return LicenseDevice(
            nickname: Host.current().localizedName ?? "My Mac",
            model: hardwareModel,
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0",
            appBuild: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        )
    }

    private static var hardwareModel: String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "Mac" }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &value, &size, nil, 0) == 0 else { return "Mac" }
        let bytes = value.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}

enum LicensingLinks {
    static let buy = URL(string: "https://www.klipt.dev/buy")!
    static let support = URL(string: "https://www.klipt.dev/support")!
}
