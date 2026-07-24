import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class HistoryPanelController: NSObject, NSWindowDelegate {
    static let width: CGFloat = 640
    static let minimumContentHeight: CGFloat = 260
    static let maximumContentHeight: CGFloat = 520

    private unowned let model: AppModel
    private let panel: KliptPanel
    private var keyMonitor: Any?

    init(model: AppModel) {
        self.model = model
        panel = KliptPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.minimumContentHeight),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.delegate = self
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: HistoryPanelView(model: model))
    }

    func show(targetApplication: NSRunningApplication?) {
        updateHeight(for: model.filteredHistory.count)
        let screen = AccessibilityService.screen(containingFocusedWindowOf: targetApplication) ?? NSScreen.main
        if let visibleFrame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(
                x: visibleFrame.midX - panel.frame.width / 2,
                y: visibleFrame.midY - panel.frame.height / 2
            ))
        }
        installKeyMonitor()
        panel.orderFrontRegardless()
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKey()
    }

    func updateHeight(for itemCount: Int) {
        let contentHeight = Self.contentHeight(for: itemCount)
        let currentContentHeight = panel.contentRect(forFrameRect: panel.frame).height
        guard abs(currentContentHeight - contentHeight) > 0.5 else { return }

        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let frameSize = panel.frameRect(forContentRect: NSRect(
            x: 0,
            y: 0,
            width: Self.width,
            height: contentHeight
        )).size
        panel.setFrame(NSRect(
            x: center.x - frameSize.width / 2,
            y: center.y - frameSize.height / 2,
            width: frameSize.width,
            height: frameSize.height
        ), display: true, animate: panel.isVisible)
    }

    static func contentHeight(for itemCount: Int) -> CGFloat {
        min(maximumContentHeight, max(minimumContentHeight, 115 + CGFloat(itemCount) * 66))
    }

    func hide() {
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        if model.pendingSnippetAssignment?.surface == .history { return }
        if !model.license.state.isUsable { return }
        hide()
    }

    static func assignmentSlot(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Int? {
        let relevantModifiers = modifiers.intersection([.command, .option, .control, .shift])
        guard relevantModifiers == [.command, .option] else { return nil }
        let keyCodes = [
            kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
            kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
            kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3, kVK_ANSI_Keypad4, kVK_ANSI_Keypad5,
            kVK_ANSI_Keypad6, kVK_ANSI_Keypad7, kVK_ANSI_Keypad8, kVK_ANSI_Keypad9
        ]
        guard let index = keyCodes.firstIndex(of: Int(keyCode)) else { return nil }
        return index % 9 + 1
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            guard self.model.pendingSnippetAssignment?.surface != .history else { return event }
            if let slot = Self.assignmentSlot(keyCode: event.keyCode, modifiers: event.modifierFlags) {
                self.model.assignSelectedHistory(to: slot)
                return nil
            }
            switch Int(event.keyCode) {
            case kVK_UpArrow:
                self.model.selectNext(offset: -1)
            case kVK_DownArrow:
                self.model.selectNext(offset: 1)
            case kVK_Return, kVK_ANSI_KeypadEnter:
                self.model.pasteSelectedHistory()
            case kVK_Escape:
                self.hide()
            case kVK_Delete, kVK_ForwardDelete:
                if event.modifierFlags.contains(.command) || event.keyCode == UInt16(kVK_ForwardDelete) {
                    self.model.deleteSelectedHistory()
                } else {
                    return event
                }
            default:
                return event
            }
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

private final class KliptPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
