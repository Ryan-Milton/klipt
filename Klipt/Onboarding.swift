import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private unowned let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 716, height: 596),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Klipt Settings"
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.moveToActiveSpace]
            window.center()
            window.delegate = self
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private unowned let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 540),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Welcome to Klipt"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.center()
            window.delegate = self
            window.contentView = NSHostingView(rootView: OnboardingView(model: model))
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }
}

private struct OnboardingView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                Image(systemName: "clipboard.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 72, height: 72)
                    .background(.tint.opacity(0.14), in: .rect(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your clipboard, within reach")
                        .font(.largeTitle.bold())
                    Text("History and nine direct-paste snippets, built natively for macOS.")
                        .foregroundStyle(.secondary)
                }
            }

            onboardingCard(
                icon: "lock.shield",
                title: "Encrypted on this Mac",
                detail: "Klipt encrypts clipboard payloads with a per-install key held in your login Keychain. Nothing is uploaded."
            )

            onboardingCard(
                icon: "exclamationmark.triangle.fill",
                title: "Sensitive copies are included",
                detail: "As configured, Klipt stores all clipboard representations, including content password managers mark concealed or transient. Clear or pause history whenever needed.",
                color: .orange
            )

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Allow direct paste").font(.headline)
                    Text("Accessibility lets Return and snippet shortcuts paste into the previous app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.accessibilityTrusted ? "Allowed" : "Request Access") {
                    model.requestAccessibility()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.accessibilityTrusted)
            }

            Spacer()
            HStack {
                Text("History: \(model.historyShortcut.displayText)  ·  Snippets: ⌃⌥1–9")
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Start Klipt") { model.completeOnboarding() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(32)
        .frame(width: 620, height: 540)
        .background(.ultraThinMaterial)
    }

    private func onboardingCard(icon: String, title: String, detail: String, color: Color = .accentColor) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.background.opacity(0.55), in: .rect(cornerRadius: 12))
    }
}
