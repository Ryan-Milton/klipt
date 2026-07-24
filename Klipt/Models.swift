import AppKit
import CryptoKit
import Foundation
import ImageIO

struct PasteboardRepresentation: Codable, Hashable, Sendable {
    let typeIdentifier: String
    let data: Data
}

struct ClipboardItemPayload: Codable, Hashable, Sendable {
    let representations: [PasteboardRepresentation]
}

struct ClipboardPayload: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let sourceBundleIdentifier: String?
    let sourceApplicationName: String?
    let items: [ClipboardItemPayload]
    let byteCount: Int64
    let contentHash: String

    func copyWithFreshID() -> ClipboardPayload {
        ClipboardPayload(
            id: UUID(),
            createdAt: createdAt,
            sourceBundleIdentifier: sourceBundleIdentifier,
            sourceApplicationName: sourceApplicationName,
            items: items,
            byteCount: byteCount,
            contentHash: contentHash
        )
    }
}

enum ClipboardPreviewKind: String, Codable, Sendable {
    case text
    case image
    case files
    case richContent
    case data
}

struct ClipboardRecord: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var createdAt: Date
    var sourceBundleIdentifier: String?
    var sourceApplicationName: String?
    let byteCount: Int64
    let contentHash: String
    let kind: ClipboardPreviewKind
    let title: String
    let detail: String
    let searchableText: String
    let previewImageData: Data?
}

struct SnippetRecord: Codable, Hashable, Identifiable, Sendable {
    var id: Int { slot }
    let slot: Int
    var name: String
    var payloadID: UUID
    var byteCount: Int64
    var preview: ClipboardRecord
}

struct StoreManifest: Codable, Equatable, Sendable {
    var history: [ClipboardRecord] = []
    var snippets: [SnippetRecord] = []
}

enum KliptLimits {
    static let historyCount = 100
    static let maximumEntryBytes: Int64 = 100 * 1_024 * 1_024
    static let maximumStorageBytes: Int64 = 1_024 * 1_024 * 1_024
}

enum StoragePolicy {
    static func trimHistory(
        _ history: [ClipboardRecord],
        snippetBytes: Int64,
        limit: Int64 = KliptLimits.maximumStorageBytes,
        countLimit: Int = KliptLimits.historyCount
    ) -> (kept: [ClipboardRecord], evicted: [ClipboardRecord]) {
        var kept = history
        var evicted: [ClipboardRecord] = []
        var total = kept.reduce(snippetBytes) { $0 + $1.byteCount }

        while kept.count > countLimit || total > limit {
            guard let removed = kept.popLast() else { break }
            total -= removed.byteCount
            evicted.append(removed)
        }
        return (kept, evicted)
    }
}

@MainActor
enum PasteboardCodec {
    static func capture(
        from pasteboard: NSPasteboard,
        sourceApplication: NSRunningApplication? = NSWorkspace.shared.frontmostApplication
    ) -> ClipboardPayload? {
        guard let pasteboardItems = pasteboard.pasteboardItems, !pasteboardItems.isEmpty else {
            return nil
        }

        var items: [ClipboardItemPayload] = []
        var byteCount: Int64 = 0

        for item in pasteboardItems {
            var representations: [PasteboardRepresentation] = []
            for type in item.types {
                let data = item.data(forType: type)
                    ?? item.string(forType: type)?.data(using: .utf8)
                guard let data else { continue }
                byteCount += Int64(data.count)
                guard byteCount <= KliptLimits.maximumEntryBytes else { return nil }
                representations.append(PasteboardRepresentation(typeIdentifier: type.rawValue, data: data))
            }
            if !representations.isEmpty {
                items.append(ClipboardItemPayload(representations: representations))
            }
        }

        guard !items.isEmpty else { return nil }
        let now = Date()
        return ClipboardPayload(
            id: UUID(),
            createdAt: now,
            sourceBundleIdentifier: sourceApplication?.bundleIdentifier,
            sourceApplicationName: sourceApplication?.localizedName,
            items: items,
            byteCount: byteCount,
            contentHash: contentHash(for: items)
        )
    }

    static func textPayload(_ text: String) -> ClipboardPayload {
        let data = Data(text.utf8)
        let items = [ClipboardItemPayload(representations: [
            PasteboardRepresentation(typeIdentifier: NSPasteboard.PasteboardType.string.rawValue, data: data)
        ])]
        return ClipboardPayload(
            id: UUID(),
            createdAt: Date(),
            sourceBundleIdentifier: Bundle.main.bundleIdentifier,
            sourceApplicationName: "Klipt",
            items: items,
            byteCount: Int64(data.count),
            contentHash: contentHash(for: items)
        )
    }

    @discardableResult
    static func write(_ payload: ClipboardPayload, to pasteboard: NSPasteboard) -> Bool {
        let items = payload.items.compactMap { payloadItem -> NSPasteboardItem? in
            let item = NSPasteboardItem()
            var wroteRepresentation = false
            for representation in payloadItem.representations {
                let type = NSPasteboard.PasteboardType(representation.typeIdentifier)
                wroteRepresentation = item.setData(representation.data, forType: type) || wroteRepresentation
            }
            return wroteRepresentation ? item : nil
        }
        guard !items.isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.writeObjects(items)
    }

    static func makeRecord(from payload: ClipboardPayload) -> ClipboardRecord {
        let representations = payload.items.flatMap(\.representations)
        let text = preferredText(in: representations)
        let fileNames = fileNames(in: representations)
        let imageData = preferredImageData(in: representations)
        let typeNames = Array(Set(representations.map(\.typeIdentifier))).sorted()

        let kind: ClipboardPreviewKind
        let title: String
        let detail: String

        if !fileNames.isEmpty {
            kind = .files
            title = fileNames.count == 1 ? fileNames[0] : "\(fileNames.count) files"
            detail = fileNames.joined(separator: " ")
        } else if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            kind = typeNames.contains(NSPasteboard.PasteboardType.rtf.rawValue) ? .richContent : .text
            let cleaned = text.replacingOccurrences(of: "\n", with: " ")
            title = String(cleaned.prefix(180))
            detail = typeNames.joined(separator: ", ")
        } else if imageData != nil {
            kind = .image
            title = "Image"
            detail = ByteCountFormatter.string(fromByteCount: payload.byteCount, countStyle: .file)
        } else {
            kind = .data
            title = typeNames.first?.split(separator: ".").last.map(String.init) ?? "Clipboard data"
            detail = typeNames.joined(separator: ", ")
        }

        var searchParts = [fileNames.joined(separator: " "), typeNames.joined(separator: " ")]
        if let text { searchParts.insert(String(text.prefix(10_000)), at: 0) }

        return ClipboardRecord(
            id: payload.id,
            createdAt: payload.createdAt,
            sourceBundleIdentifier: payload.sourceBundleIdentifier,
            sourceApplicationName: payload.sourceApplicationName,
            byteCount: payload.byteCount,
            contentHash: payload.contentHash,
            kind: kind,
            title: title,
            detail: detail,
            searchableText: searchParts.joined(separator: " "),
            previewImageData: imageData.flatMap(thumbnailData)
        )
    }

    static func contentHash(for items: [ClipboardItemPayload]) -> String {
        var hasher = SHA256()
        for (itemIndex, item) in items.enumerated() {
            hasher.update(data: Data("item:\(itemIndex);".utf8))
            for representation in item.representations.sorted(by: { $0.typeIdentifier < $1.typeIdentifier }) {
                hasher.update(data: Data("type:\(representation.typeIdentifier.utf8.count):".utf8))
                hasher.update(data: Data(representation.typeIdentifier.utf8))
                hasher.update(data: Data("data:\(representation.data.count):".utf8))
                hasher.update(data: representation.data)
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func preferredText(in representations: [PasteboardRepresentation]) -> String? {
        let preferredTypes = [
            NSPasteboard.PasteboardType.string.rawValue,
            "public.utf8-plain-text",
            "public.utf16-plain-text"
        ]
        for type in preferredTypes {
            guard let representation = representations.first(where: { $0.typeIdentifier == type }) else { continue }
            if let text = String(data: representation.data, encoding: .utf8)
                ?? String(data: representation.data, encoding: .utf16) {
                return text
            }
        }
        return nil
    }

    private static func fileNames(in representations: [PasteboardRepresentation]) -> [String] {
        representations.compactMap { representation in
            guard representation.typeIdentifier == NSPasteboard.PasteboardType.fileURL.rawValue,
                  let value = String(data: representation.data, encoding: .utf8),
                  let url = URL(string: value) else { return nil }
            return url.lastPathComponent
        }
    }

    private static func preferredImageData(in representations: [PasteboardRepresentation]) -> Data? {
        let imageTypes = [NSPasteboard.PasteboardType.png.rawValue, NSPasteboard.PasteboardType.tiff.rawValue]
        return imageTypes.lazy.compactMap { type in
            representations.first(where: { $0.typeIdentifier == type })?.data
        }.first
    }

    private static func thumbnailData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 180,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: image)
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.72])
    }
}
