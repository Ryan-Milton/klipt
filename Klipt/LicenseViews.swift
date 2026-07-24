import AppKit
import SwiftUI

struct LicenseSettingsView: View {
    @Bindable var model: AppModel
    @State private var licenseKey = ""
    @State private var nickname = ""

    var body: some View {
        Form {
            Section("License") {
                LabeledContent("Status") {
                    Label(model.license.state.statusText, systemImage: statusIcon)
                        .foregroundStyle(statusColor)
                }
                if let detail = model.license.state.detailText ?? model.license.lastFailure?.message {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(model.license.state.isUsable ? Color.secondary : Color.orange)
                }
                if let maskedKey = model.license.maskedKey {
                    LabeledContent("License key", value: maskedKey)
                }
                if !model.license.state.isUsable {
                    SecureField("Emailed license key", text: $licenseKey)
                    TextField("Device nickname", text: $nickname)
                    Button(model.license.state == .activating ? "Activating…" : "Activate") {
                        let submittedKey = licenseKey
                        licenseKey = ""
                        Task { await model.activateLicense(key: submittedKey, nickname: nickname) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || model.license.state == .activating)
                }
            }

            Section("This Mac") {
                LabeledContent("Device nickname", value: model.license.deviceNickname)
                LabeledContent("Model", value: model.license.deviceModel)
                if let activatedAt = model.license.activatedAt {
                    LabeledContent("Activated", value: activatedAt.formatted(date: .abbreviated, time: .shortened))
                }
                if let validatedAt = model.license.lastSuccessfulValidation {
                    LabeledContent("Last successful validation", value: validatedAt.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("Version", value: "\(model.license.appVersion) (\(model.license.appBuild))")
            }

            Section {
                HStack {
                    Button(model.license.isRefreshing ? "Refreshing…" : "Refresh") {
                        Task { await model.refreshLicense() }
                    }
                    .disabled(!model.license.hasStoredKey || model.license.isRefreshing)
                    Button("Buy") { NSWorkspace.shared.open(LicensingLinks.buy) }
                    Button("Support") { NSWorkspace.shared.open(LicensingLinks.support) }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if nickname.isEmpty { nickname = model.license.deviceNickname }
        }
    }

    private var statusIcon: String {
        switch model.license.state {
        case .active, .offlineActive: "checkmark.seal.fill"
        case .loading, .activating: "clock.fill"
        default: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch model.license.state {
        case .active: .green
        case .offlineActive: .orange
        default: .red
        }
    }
}

@MainActor
final class LicenseAlertController: NSWindowController {
    private unowned let model: AppModel

    init(model: AppModel) {
        self.model = model
        super.init(window: nil)
    }

    required init?(coder: NSCoder) { nil }

    func present(_ state: LicenseState) {
        guard state == .refunded || state == .revoked else {
            model.showSettings(tab: .license)
            return
        }
        let content = LicenseTerminalView(
            state: state,
            enterKey: { [weak self] in
                self?.close()
                self?.model.showSettings(tab: .license)
            },
            buy: { NSWorkspace.shared.open(LicensingLinks.buy) },
            support: { NSWorkspace.shared.open(LicensingLinks.support) }
        )
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 250),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.title = state == .refunded ? "License refunded" : "License revoked"
        window?.contentView = NSHostingView(rootView: content)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.orderFrontRegardless()
    }
}

private struct LicenseTerminalView: View {
    let state: LicenseState
    let enterKey: () -> Void
    let buy: () -> Void
    let support: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.title2.bold())
                .foregroundStyle(.orange)
            Text(bodyText)
                .foregroundStyle(.secondary)
            Spacer()
            HStack {
                Button("Support", action: support)
                Button("Buy", action: buy)
                Spacer()
                Button("Enter Key", action: enterKey)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 440, height: 220)
    }

    private var title: String { state == .refunded ? "License refunded" : "License revoked" }
    private var bodyText: String {
        state == .refunded
            ? "This license was refunded and can no longer be used on this Mac. Enter another key, buy a license, or contact support."
            : "This license was revoked and can no longer be used on this Mac. Enter another key, buy a license, or contact support."
    }
}
