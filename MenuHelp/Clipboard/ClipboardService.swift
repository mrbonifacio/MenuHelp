//
//  ClipboardService.swift
//  MenuHelp
//
//  Created on 28/01/2026.
//

import AppKit
import Combine
import CryptoKit
import Foundation

enum ClipboardItemKind: String, Codable {
    case text
    case image
}

protocol ClipboardPasteboard: AnyObject {
    var changeCount: Int { get }
    var types: [NSPasteboard.PasteboardType]? { get }

    func data(forType dataType: NSPasteboard.PasteboardType) -> Data?
    func string(forType dataType: NSPasteboard.PasteboardType) -> String?
    func clearContents() -> Int
    func declareTypes(_ newTypes: [NSPasteboard.PasteboardType], owner newOwner: Any?) -> Int
    func setData(_ data: Data?, forType dataType: NSPasteboard.PasteboardType) -> Bool
    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool
}

extension NSPasteboard: ClipboardPasteboard { }

struct ClipboardItem: Identifiable, Codable {
    let id: UUID
    let kind: ClipboardItemKind
    let text: String?
    let imageFileName: String?
    let fingerprint: String?
    let timestamp: Date

    init(text: String) {
        self.id = UUID()
        self.kind = .text
        self.text = text
        self.imageFileName = nil
        self.fingerprint = nil
        self.timestamp = Date()
    }

    init(imageFileName: String, fingerprint: String) {
        self.id = UUID(uuidString: imageFileName.replacingOccurrences(of: ".png", with: "")) ?? UUID()
        self.kind = .image
        self.text = nil
        self.imageFileName = imageFileName
        self.fingerprint = fingerprint
        self.timestamp = Date()
    }

    var preview: String {
        guard let text else { return "Imagem" }

        let maxLength = 100
        if text.count > maxLength {
            return String(text.prefix(maxLength)) + "..."
        }
        return text
    }

    var searchableContent: String {
        switch kind {
        case .text:
            return text ?? ""
        case .image:
            return "imagem foto image"
        }
    }

    var timestampString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case text
        case imageFileName
        case fingerprint
        case timestamp
        case content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)

        if let decodedKind = try container.decodeIfPresent(ClipboardItemKind.self, forKey: .kind) {
            kind = decodedKind
            text = try container.decodeIfPresent(String.self, forKey: .text)
            imageFileName = try container.decodeIfPresent(String.self, forKey: .imageFileName)
            fingerprint = try container.decodeIfPresent(String.self, forKey: .fingerprint)
        } else {
            // Compatibilidade com o histórico antigo, que armazenava somente
            // os campos id, content e timestamp.
            kind = .text
            text = try container.decode(String.self, forKey: .content)
            imageFileName = nil
            fingerprint = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(imageFileName, forKey: .imageFileName)
        try container.encodeIfPresent(fingerprint, forKey: .fingerprint)
        try container.encode(timestamp, forKey: .timestamp)
    }
}

class ClipboardService: ObservableObject {
    static let shared = ClipboardService()

    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var isEnabled: Bool
    @Published private(set) var maxItemCount: Int
    @Published private(set) var retentionDays: Int
    @Published var searchText: String = ""

    private let pasteboard: ClipboardPasteboard
    private let storageFolderURL: URL
    private var lastChangeCount: Int = 0
    private var monitorTimer: Timer?
    private let imageCache = NSCache<NSString, NSImage>()
    private static let enabledDefaultsKey = "clipboardHistoryEnabled"
    private static let maxItemCountDefaultsKey = "clipboardMaxItemCount"
    private static let retentionDaysDefaultsKey = "clipboardRetentionDays"
    private static let maximumImageStorageBytes = 200 * 1_024 * 1_024
    private static let secureDirectoryPermissions = 0o700
    private static let secureFilePermissions = 0o600

    static let itemCountOptions = [50, 100, 250, 500]
    static let retentionDayOptions = [7, 30, 90, 0]

    private static let ignoredPasteboardTypes: Set<NSPasteboard.PasteboardType> = [
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
        NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType"),
    ]

    init(
        pasteboard: ClipboardPasteboard = NSPasteboard.general,
        storageFolderURL: URL? = nil,
        automaticallyStartsMonitoring: Bool = true
    ) {
        let defaults = UserDefaults.standard
        self.pasteboard = pasteboard
        self.storageFolderURL = storageFolderURL ?? Self.prepareDefaultStorageFolderURL()
        self.isEnabled = defaults.object(forKey: Self.enabledDefaultsKey) == nil
            ? true
            : defaults.bool(forKey: Self.enabledDefaultsKey)

        let savedMaxItemCount = defaults.integer(forKey: Self.maxItemCountDefaultsKey)
        self.maxItemCount = Self.itemCountOptions.contains(savedMaxItemCount)
            ? savedMaxItemCount
            : 100

        let hasSavedRetention = defaults.object(forKey: Self.retentionDaysDefaultsKey) != nil
        let savedRetentionDays = defaults.integer(forKey: Self.retentionDaysDefaultsKey)
        self.retentionDays = hasSavedRetention && Self.retentionDayOptions.contains(savedRetentionDays)
            ? savedRetentionDays
            : 30

        try? FileManager.default.createDirectory(
            at: self.storageFolderURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: Self.secureDirectoryPermissions]
        )
        try? FileManager.default.createDirectory(
            at: imageFolderURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: Self.secureDirectoryPermissions]
        )
        secureStoragePermissions()

        loadHistory()

        if automaticallyStartsMonitoring, isEnabled {
            startMonitoring()
        }
    }

    var filteredItems: [ClipboardItem] {
        if searchText.isEmpty {
            return items
        }
        return items.filter { item in
            item.searchableContent.localizedCaseInsensitiveContains(searchText)
        }
    }

    func startMonitoring() {
        guard isEnabled else { return }
        monitorTimer?.invalidate()
        lastChangeCount = pasteboard.changeCount

        monitorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.checkClipboard()
            }
        }

        if let monitorTimer {
            RunLoop.current.add(monitorTimer, forMode: .common)
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }

        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledDefaultsKey)

        if enabled {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }

    func setMaxItemCount(_ count: Int) {
        guard Self.itemCountOptions.contains(count), count != maxItemCount else { return }
        maxItemCount = count
        UserDefaults.standard.set(count, forKey: Self.maxItemCountDefaultsKey)
        performMaintenance()
        saveHistory()
    }

    func setRetentionDays(_ days: Int) {
        guard Self.retentionDayOptions.contains(days), days != retentionDays else { return }
        retentionDays = days
        UserDefaults.standard.set(days, forKey: Self.retentionDaysDefaultsKey)
        performMaintenance()
        saveHistory()
    }

    func clearHistory() {
        items.forEach(removeStoredImage)
        items.removeAll()
        imageCache.removeAllObjects()
        removeOrphanedImageFiles()
        saveHistory()
    }

    func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    func checkClipboard() {
        guard isEnabled else { return }
        let currentChangeCount = pasteboard.changeCount

        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        guard !containsIgnoredPasteboardType else { return }

        // Imagem tem prioridade, pois alguns aplicativos publicam uma imagem
        // e também uma representação textual no mesmo pasteboard.
        if let imageData = imageDataFromPasteboard() {
            addImage(data: imageData)
        } else if let content = pasteboard.string(forType: .string), !content.isEmpty {
            addText(content)
        }
    }

    func image(for item: ClipboardItem) -> NSImage? {
        guard item.kind == .image,
              let imageFileName = item.imageFileName,
              let imageURL = safeImageURL(for: imageFileName) else {
            return nil
        }

        let cacheKey = item.id.uuidString as NSString
        if let cachedImage = imageCache.object(forKey: cacheKey) {
            return cachedImage
        }

        guard let image = NSImage(contentsOf: imageURL) else {
            return nil
        }

        imageCache.setObject(image, forKey: cacheKey)
        return image
    }

    @discardableResult
    func copyToClipboard(_ item: ClipboardItem) -> Bool {
        let copied: Bool

        switch item.kind {
        case .text:
            guard let text = item.text else { return false }
            _ = pasteboard.clearContents()
            copied = pasteboard.setString(text, forType: .string)

        case .image:
            guard let imageData = storedImageData(for: item),
                  let image = NSImage(data: imageData) else {
                return false
            }

            _ = pasteboard.clearContents()
            _ = pasteboard.declareTypes([.png, .tiff], owner: nil)
            let wrotePNG = pasteboard.setData(imageData, forType: .png)
            let wroteTIFF = image.tiffRepresentation.map {
                pasteboard.setData($0, forType: .tiff)
            } ?? false
            copied = wrotePNG || wroteTIFF
        }

        guard copied else { return false }
        lastChangeCount = pasteboard.changeCount
        DispatchQueue.main.async { [weak self] in
            self?.moveToTop(item)
        }
        return true
    }

    func deleteItem(_ item: ClipboardItem) {
        removeStoredImage(for: item)
        items.removeAll { $0.id == item.id }
        saveHistory()
    }

    func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL),
              let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) else {
            return
        }

        items = decoded.filter { item in
            switch item.kind {
            case .text:
                return item.text != nil
            case .image:
                guard let imageFileName = item.imageFileName,
                      let imageURL = safeImageURL(for: imageFileName) else { return false }
                return FileManager.default.fileExists(atPath: imageURL.path)
            }
        }
        performMaintenance()
        saveHistory()
    }

    private func addText(_ content: String) {
        if let firstItem = items.first,
           firstItem.kind == .text,
           firstItem.text == content {
            return
        }

        items.insert(ClipboardItem(text: content), at: 0)
        performMaintenance()
        saveHistory()
    }

    private func addImage(data: Data) {
        let fingerprint = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()

        if let firstItem = items.first,
           firstItem.kind == .image,
           firstItem.fingerprint == fingerprint {
            return
        }

        let id = UUID()
        let imageFileName = id.uuidString + ".png"
        guard let imageURL = safeImageURL(for: imageFileName) else { return }

        do {
            try data.write(to: imageURL, options: .atomic)
            secureFile(at: imageURL)
        } catch {
            return
        }

        let item = ClipboardItem(
            imageFileName: imageFileName,
            fingerprint: fingerprint
        )
        items.insert(item, at: 0)

        if let image = NSImage(data: data) {
            imageCache.setObject(image, forKey: item.id.uuidString as NSString)
        }

        performMaintenance()
        saveHistory()
    }

    private func imageDataFromPasteboard() -> Data? {
        if let pngData = pasteboard.data(forType: .png), NSImage(data: pngData) != nil {
            return pngData
        }

        if let tiffData = pasteboard.data(forType: .tiff),
           let image = NSImage(data: tiffData) {
            return pngData(for: image)
        }

        if let nativePasteboard = pasteboard as? NSPasteboard,
           let image = NSImage(pasteboard: nativePasteboard) {
            return pngData(for: image)
        }

        return nil
    }

    private func storedImageData(for item: ClipboardItem) -> Data? {
        guard item.kind == .image,
              let imageFileName = item.imageFileName,
              let imageURL = safeImageURL(for: imageFileName) else {
            return nil
        }

        return try? Data(contentsOf: imageURL)
    }

    private func pngData(for image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }

    private func moveToTop(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items.remove(at: index)
        items.insert(item, at: 0)
        saveHistory()
    }

    private func trimHistoryIfNeeded() {
        guard items.count > maxItemCount else { return }

        let removedItems = Array(items.dropFirst(maxItemCount))
        items = Array(items.prefix(maxItemCount))
        removedItems.forEach(removeStoredImage)
    }

    private func removeStoredImage(for item: ClipboardItem) {
        guard item.kind == .image,
              let imageFileName = item.imageFileName,
              let imageURL = safeImageURL(for: imageFileName) else { return }
        imageCache.removeObject(forKey: item.id.uuidString as NSString)
        try? FileManager.default.removeItem(at: imageURL)
    }

    private func saveHistory() {
        guard let encoded = try? JSONEncoder().encode(items) else { return }
        do {
            try encoded.write(to: historyURL, options: .atomic)
            secureFile(at: historyURL)
        } catch { }
    }

    private var historyURL: URL {
        storageFolderURL.appendingPathComponent("clipboard_history.json")
    }

    private var imageFolderURL: URL {
        storageFolderURL.appendingPathComponent("ClipboardImages", isDirectory: true)
    }

    private var containsIgnoredPasteboardType: Bool {
        guard let types = pasteboard.types else { return false }
        return !Self.ignoredPasteboardTypes.isDisjoint(with: types)
    }

    private func performMaintenance() {
        removeExpiredItems()
        trimHistoryIfNeeded()
        trimImageStorageIfNeeded()
        removeOrphanedImageFiles()
    }

    private func removeExpiredItems() {
        guard retentionDays > 0,
              let cutoff = Calendar.current.date(
                byAdding: .day,
                value: -retentionDays,
                to: Date()
              ) else { return }

        let expiredItems = items.filter { $0.timestamp < cutoff }
        guard !expiredItems.isEmpty else { return }

        expiredItems.forEach(removeStoredImage)
        let expiredIDs = Set(expiredItems.map(\.id))
        items.removeAll { expiredIDs.contains($0.id) }
    }

    private func trimImageStorageIfNeeded() {
        var imagesWithSizes: [(item: ClipboardItem, size: Int)] = []
        var totalBytes = 0

        for item in items where item.kind == .image {
            guard let imageFileName = item.imageFileName,
                  let imageURL = safeImageURL(for: imageFileName),
                  let values = try? imageURL.resourceValues(forKeys: [.fileSizeKey]),
                  let size = values.fileSize else { continue }

            totalBytes += size
            imagesWithSizes.append((item, size))
        }

        guard totalBytes > Self.maximumImageStorageBytes else { return }

        var removedIDs = Set<UUID>()
        for image in imagesWithSizes.reversed() where totalBytes > Self.maximumImageStorageBytes {
            removeStoredImage(for: image.item)
            totalBytes -= image.size
            removedIDs.insert(image.item.id)
        }

        if !removedIDs.isEmpty {
            items.removeAll { removedIDs.contains($0.id) }
        }
    }

    private func removeOrphanedImageFiles() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: imageFolderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        let referencedFileNames = Set(items.compactMap(\.imageFileName))
        for fileURL in files {
            let fileName = fileURL.lastPathComponent
            guard safeImageURL(for: fileName) != nil,
                  !referencedFileNames.contains(fileName) else { continue }
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func safeImageURL(for fileName: String) -> URL? {
        guard fileName == (fileName as NSString).lastPathComponent,
              fileName.hasSuffix(".png"),
              UUID(uuidString: String(fileName.dropLast(4))) != nil else {
            return nil
        }

        return imageFolderURL.appendingPathComponent(fileName, isDirectory: false)
    }

    private func secureStoragePermissions() {
        secureDirectory(at: storageFolderURL)
        secureDirectory(at: imageFolderURL)
        if FileManager.default.fileExists(atPath: historyURL.path) {
            secureFile(at: historyURL)
        }

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: imageFolderURL,
            includingPropertiesForKeys: nil
        ) else { return }
        files.forEach(secureFile)
    }

    private func secureDirectory(at url: URL) {
        try? FileManager.default.setAttributes(
            [.posixPermissions: Self.secureDirectoryPermissions],
            ofItemAtPath: url.path
        )
    }

    private func secureFile(at url: URL) {
        try? FileManager.default.setAttributes(
            [.posixPermissions: Self.secureFilePermissions],
            ofItemAtPath: url.path
        )
    }

    private static func prepareDefaultStorageFolderURL() -> URL {
        let applicationSupportURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let newURL = applicationSupportURL.appendingPathComponent("MenuHelp", isDirectory: true)
        let legacyURL = applicationSupportURL.appendingPathComponent("MenuGen", isDirectory: true)

        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: newURL.path),
           fileManager.fileExists(atPath: legacyURL.path) {
            try? fileManager.moveItem(at: legacyURL, to: newURL)
        }

        return newURL
    }
}
