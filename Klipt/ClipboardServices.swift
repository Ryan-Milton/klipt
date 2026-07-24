import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation
import ServiceManagement

@MainActor
final class ClipboardMonitor {
    var onPayload: ((ClipboardPayload) -> Void)?
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private(set) var isPaused = false

    func start() {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkPasteboard() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func synchronizeChangeCount() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    private func checkPasteboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard !isPaused, let payload = PasteboardCodec.capture(from: pasteboard) else { return }
        onPayload?(payload)
    }
}

struct KeyboardShortcutSetting: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let history = KeyboardShortcutSetting(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: UInt32(controlKey | optionKey)
    )

    static func snippet(slot: Int) -> KeyboardShortcutSetting {
        let keyCodes = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                        kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        return KeyboardShortcutSetting(
            keyCode: UInt32(keyCodes[slot - 1]),
            modifiers: UInt32(controlKey | optionKey)
        )
    }

    var displayText: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + Self.keyName(for: keyCode)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

    private static func keyName(for keyCode: UInt32) -> String {
        let known: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2", UInt32(kVK_ANSI_3): "3",
            UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5", UInt32(kVK_ANSI_6): "6",
            UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8", UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_Space): "Space"
        ]
        return known[keyCode] ?? "Key \(keyCode)"
    }
}

enum HotKeyAction: Hashable, Sendable {
    case history
    case snippet(Int)
}

@MainActor
final class GlobalHotKeyManager {
    var onAction: ((HotKeyAction) -> Void)?
    private var hotKeys: [HotKeyAction: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = 0x4B4C5054 // KLPT

    init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, hotKeyID.signature == manager.signature else { return status }
                Task { @MainActor in
                    if hotKeyID.id == 1 {
                        manager.onAction?(.history)
                    } else if (101...109).contains(hotKeyID.id) {
                        manager.onAction?(.snippet(Int(hotKeyID.id - 100)))
                    }
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    func register(_ shortcut: KeyboardShortcutSetting, for action: HotKeyAction) -> OSStatus {
        unregister(action)
        let id: UInt32 = switch action {
        case .history: 1
        case .snippet(let slot): UInt32(100 + slot)
        }
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            EventHotKeyID(signature: signature, id: id),
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if status == noErr, let reference { hotKeys[action] = reference }
        return status
    }

    func unregister(_ action: HotKeyAction) {
        guard let reference = hotKeys.removeValue(forKey: action) else { return }
        UnregisterEventHotKey(reference)
    }

    func unregisterAll() {
        for action in Array(hotKeys.keys) { unregister(action) }
    }
}

enum AccessibilityService {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    static func screen(containingFocusedWindowOf application: NSRunningApplication?) -> NSScreen? {
        guard isTrusted, let application else { return NSScreen.main }
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        var focusedWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success,
              let focusedWindow,
              CFGetTypeID(focusedWindow) == AXUIElementGetTypeID() else { return NSScreen.main }
        let windowElement = focusedWindow as! AXUIElement
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return NSScreen.main }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return NSScreen.main }

        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let cocoaRect = CGRect(
            x: position.x,
            y: primaryHeight - position.y - size.height,
            width: size.width,
            height: size.height
        )
        return NSScreen.screens.max { first, second in
            first.frame.intersection(cocoaRect).area < second.frame.intersection(cocoaRect).area
        }
    }
}

private extension CGRect {
    var area: CGFloat { max(0, width) * max(0, height) }
}

@MainActor
enum PasteCoordinator {
    enum Result {
        case pasted
        case copiedOnly
        case failedToWrite
    }

    static func paste(
        _ payload: ClipboardPayload,
        into target: NSRunningApplication?,
        monitor: ClipboardMonitor,
        isAllowed: @escaping @MainActor () -> Bool
    ) async -> Result {
        guard isAllowed() else { return .failedToWrite }
        guard AccessibilityService.isTrusted else {
            guard isAllowed() else { return .failedToWrite }
            guard PasteboardCodec.write(payload, to: .general) else { return .failedToWrite }
            monitor.synchronizeChangeCount()
            return .copiedOnly
        }

        guard let target,
              !target.isTerminated,
              target.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              target.activate(options: []) else {
            guard isAllowed() else { return .failedToWrite }
            guard PasteboardCodec.write(payload, to: .general) else { return .failedToWrite }
            monitor.synchronizeChangeCount()
            return .copiedOnly
        }

        for _ in 0..<10 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
            guard isAllowed() else { return .failedToWrite }
            guard PasteboardCodec.write(payload, to: .general) else { return .failedToWrite }
            monitor.synchronizeChangeCount()
            return .copiedOnly
        }
        guard isAllowed() else { return .failedToWrite }
        guard PasteboardCodec.write(payload, to: .general) else { return .failedToWrite }
        monitor.synchronizeChangeCount()
        let expectedChangeCount = NSPasteboard.general.changeCount
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            return .copiedOnly
        }
        guard NSPasteboard.general.changeCount == expectedChangeCount,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier,
              isAllowed() else {
            return .copiedOnly
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return .pasted
    }
}

enum LaunchAtLoginService {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled && SMAppService.mainApp.status != .requiresApproval {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
            try SMAppService.mainApp.unregister()
        }
    }
}
