import AppKit
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: KeyboardShortcutSetting
    let onChange: (KeyboardShortcutSetting) -> Void
    let onRecordingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        ShortcutRecorderNSView(
            shortcut: shortcut,
            onChange: onChange,
            onRecordingChanged: onRecordingChanged
        )
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        nsView.shortcut = shortcut
        nsView.onChange = onChange
        nsView.onRecordingChanged = onRecordingChanged
        nsView.needsDisplay = true
    }
}

final class ShortcutRecorderNSView: NSView {
    var shortcut: KeyboardShortcutSetting
    var onChange: (KeyboardShortcutSetting) -> Void
    var onRecordingChanged: (Bool) -> Void
    private var isRecording = false
    private let label = NSTextField(labelWithString: "")

    init(
        shortcut: KeyboardShortcutSetting,
        onChange: @escaping (KeyboardShortcutSetting) -> Void,
        onRecordingChanged: @escaping (Bool) -> Void
    ) {
        self.shortcut = shortcut
        self.onChange = onChange
        self.onRecordingChanged = onRecordingChanged
        super.init(frame: NSRect(x: 0, y: 0, width: 110, height: 28))
        label.alignment = .center
        label.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        label.lineBreakMode = .byClipping
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 110, height: 28) }

    override func layout() {
        super.layout()
        label.frame = bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
        onRecordingChanged(true)
        needsDisplay = true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        onRecordingChanged(false)
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let modifiers = KeyboardShortcutSetting.carbonModifiers(from: flags)
        guard modifiers != 0 else {
            NSSound.beep()
            return
        }
        shortcut = KeyboardShortcutSetting(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        isRecording = false
        onRecordingChanged(false)
        onChange(shortcut)
        window?.makeFirstResponder(nil)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.18) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.stroke()

        label.stringValue = isRecording ? "Type shortcut" : shortcut.displayText
        label.textColor = isRecording ? .controlAccentColor : .labelColor
    }
}

struct SnippetDropTarget: NSViewRepresentable {
    let slot: Int
    let onDrop: (ClipboardPayload) -> Void

    func makeNSView(context: Context) -> SnippetDropNSView {
        SnippetDropNSView(slot: slot, onDrop: onDrop)
    }

    func updateNSView(_ nsView: SnippetDropNSView, context: Context) {
        nsView.slot = slot
        nsView.onDrop = onDrop
    }
}

final class SnippetDropNSView: NSView {
    var slot: Int
    var onDrop: (ClipboardPayload) -> Void
    private var isTargeted = false
    private let label = NSTextField(labelWithString: "Drop clipboard content")

    init(slot: Int, onDrop: @escaping (ClipboardPayload) -> Void) {
        self.slot = slot
        self.onDrop = onDrop
        super.init(frame: NSRect(x: 0, y: 0, width: 150, height: 30))
        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 12)
        addSubview(label)
        registerForDraggedTypes([
            .string, .fileURL, .png, .tiff, .rtf,
            NSPasteboard.PasteboardType("public.item"),
            NSPasteboard.PasteboardType("public.data")
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 30) }

    override func layout() {
        super.layout()
        label.frame = bounds
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isTargeted = true
        needsDisplay = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isTargeted = false
        needsDisplay = true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isTargeted = false
        needsDisplay = true
        guard let payload = PasteboardCodec.capture(from: sender.draggingPasteboard, sourceApplication: nil) else {
            return false
        }
        onDrop(payload)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
        let color = isTargeted ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor
        color.withAlphaComponent(isTargeted ? 0.15 : 0.06).setFill()
        path.fill()
        color.setStroke()
        path.setLineDash([4, 3], count: 2, phase: 0)
        path.stroke()
        label.textColor = color
    }
}
