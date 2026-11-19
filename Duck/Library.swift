import AppKit
import Observation
import OSLog

struct PaperMeta: Codable, Equatable {
    var tags: [String] = []
    var added = Date()
    var lastPage = 0
    var opened: Date? // optional so library.json files written before this field still load
    var highlights: [Highlight]?
}

struct Highlight: Codable, Equatable {
    var page: Int
    var rect: CGRect
}

struct Paper: Identifiable {
    let id: String // filename inside the library folder
    let meta: PaperMeta
    var title: String { (id as NSString).deletingPathExtension }
    var added: Date { meta.added }
    var tagList: String { meta.tags.joined(separator: ", ") }
}

/// A folder of PDFs plus `library.json` holding tags and reading positions.
/// The folder lives in iCloud Drive when available so an iOS version can share it later.
@MainActor @Observable
final class Library {
    let folder: URL
    private(set) var files: [String] = []
    private(set) var meta: [String: PaperMeta] = [:]
    var lastError: String?

    @ObservationIgnored private var canSave = true
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    private var metaURL: URL { folder.appending(path: "library.json") }

    nonisolated static func defaultFolder() -> URL {
        // `-libraryPath /some/folder` on launch points the app at another library (handy for testing).
        if let path = UserDefaults.standard.string(forKey: "libraryPath") { return URL(fileURLWithPath: path) }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let iCloud = home.appending(path: "Library/Mobile Documents/com~apple~CloudDocs")
        let base = FileManager.default.fileExists(atPath: iCloud.path) ? iCloud : home.appending(path: "Documents")
        return base.appending(path: "Duck Library")
    }

    init(folder: URL = Library.defaultFolder()) {
        self.folder = folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        load()
        scan()
        Log.library.notice("Opened library at \(folder.path, privacy: .public) with \(self.files.count) papers")
        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scan() }
        }
        center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.save() }
        }
    }

    var papers: [Paper] { files.map { Paper(id: $0, meta: meta[$0] ?? PaperMeta()) } }

    var allTags: [String] {
        let present = Set(files)
        return Set(meta.filter { present.contains($0.key) }.values.flatMap(\.tags))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func url(for id: String) -> URL { folder.appending(path: id) }

    // MARK: Files

    /// Re-reads the folder, so PDFs added or removed in Finder show up.
    func scan() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var found: [String] = []
        for name in names {
            let lower = name.lowercased()
            if lower.hasSuffix(".pdf"), !name.hasPrefix(".") {
                found.append(name)
            } else if name.hasPrefix("."), lower.hasSuffix(".pdf.icloud") {
                // iCloud evicted this file to save space; ask for it back so the library works offline.
                let real = String(name.dropFirst().dropLast(".icloud".count))
                try? FileManager.default.startDownloadingUbiquitousItem(at: url(for: real))
                found.append(real)
            }
        }
        var changed = false
        for name in found where meta[name] == nil {
            let created = try? url(for: name).resourceValues(forKeys: [.creationDateKey]).creationDate
            meta[name] = PaperMeta(added: created ?? Date())
            changed = true
        }
        if Set(found) != Set(files) { files = found }
        if changed { save() }
    }

    func add(_ urls: [URL]) {
        for source in urls where source.pathExtension.lowercased() == "pdf" {
            guard source.deletingLastPathComponent().standardizedFileURL != folder.standardizedFileURL else { continue }
            let accessing = source.startAccessingSecurityScopedResource()
            defer { if accessing { source.stopAccessingSecurityScopedResource() } }
            let name = uniqueName(for: source.lastPathComponent)
            do {
                try FileManager.default.copyItem(at: source, to: url(for: name))
                meta[name] = PaperMeta()
            } catch {
                fail("Couldn't add \(source.lastPathComponent): \(error.localizedDescription)")
            }
        }
        save()
        scan()
    }

    @discardableResult
    func rename(_ id: String, to title: String) throws -> String {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        guard !clean.isEmpty else { return id }
        let newID = clean + ".pdf"
        guard newID != id else { return id }
        // Case-only renames hit the same file on macOS's case-insensitive disk, so they're allowed.
        if newID.lowercased() != id.lowercased(), FileManager.default.fileExists(atPath: url(for: newID).path) {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSLocalizedDescriptionKey: "A paper named “\(clean)” already exists."])
        }
        try FileManager.default.moveItem(at: url(for: id), to: url(for: newID))
        meta[newID] = meta.removeValue(forKey: id)
        save()
        scan()
        return newID
    }

    func trash(_ ids: Set<String>) {
        for id in ids {
            do {
                try FileManager.default.trashItem(at: url(for: id), resultingItemURL: nil)
                meta[id] = nil
            } catch {
                fail("Couldn't move \(id) to the Trash: \(error.localizedDescription)")
            }
        }
        save()
        scan()
    }

    private func uniqueName(for name: String) -> String {
        let base = (name as NSString).deletingPathExtension
        var candidate = name
        var n = 2
        while files.contains(candidate) || FileManager.default.fileExists(atPath: url(for: candidate).path) {
            candidate = "\(base) \(n).pdf"
            n += 1
        }
        return candidate
    }

    // MARK: Metadata

    func updateTags(_ ids: Set<String>, adding: Set<String>, removing: Set<String>) {
        for id in ids {
            var m = meta[id] ?? PaperMeta()
            m.tags = Set(m.tags).subtracting(removing).union(adding)
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            meta[id] = m
        }
        save()
    }

    func removeTag(_ tag: String) {
        updateTags(Set(meta.filter { $0.value.tags.contains(tag) }.keys), adding: [], removing: [tag])
    }

    func markOpened(_ id: String) {
        guard meta[id] != nil else { return }
        meta[id]?.opened = Date()
        save()
    }

    /// Replaces the highlights on the given pages.
    func setHighlights(_ id: String, _ pages: [Int: [CGRect]]) {
        guard var m = meta[id] else { return }
        var highlights = (m.highlights ?? []).filter { pages[$0.page] == nil }
        for (page, rects) in pages { highlights += rects.map { Highlight(page: page, rect: $0) } }
        m.highlights = highlights.sorted { ($0.page, -$0.rect.maxY) < ($1.page, -$1.rect.maxY) }
        meta[id] = m
        save()
    }

    func setLastPage(_ id: String, _ page: Int) {
        guard meta[id] != nil, meta[id]?.lastPage != page else { return }
        meta[id]?.lastPage = page
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { self?.save() }
        }
    }

    func save() {
        saveTask?.cancel()
        guard canSave else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(meta).write(to: metaURL, options: .atomic)
        } catch {
            fail("Couldn't save the library: \(error.localizedDescription)")
        }
    }

    private func load() {
        let placeholder = folder.appending(path: ".library.json.icloud")
        let fm = FileManager.default
        guard fm.fileExists(atPath: metaURL.path) || fm.fileExists(atPath: placeholder.path) else { return }
        // A coordinated read waits for iCloud to download the file if it was evicted.
        var data: Data?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: metaURL, options: [], error: &coordinationError) {
            data = try? Data(contentsOf: $0)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            guard let data else { throw coordinationError ?? CocoaError(.fileReadUnknown) }
            meta = try decoder.decode([String: PaperMeta].self, from: data)
        } catch {
            // Never overwrite a library file we couldn't read: that would wipe every tag.
            canSave = false
            Log.library.fault("library.json unreadable: \(String(describing: error), privacy: .public)")
            fail("Couldn't read library.json, so changes to tags won't be saved until it's fixed.")
        }
    }

    /// Shows an error in the library window and records it in the system log.
    func fail(_ message: String) {
        Log.library.error("\(message, privacy: .public)")
        lastError = message
    }

    /// Waits for an iCloud file to finish downloading. Returns immediately for local files.
    nonisolated static func download(_ url: URL) async {
        await Task.detached {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            var error: NSError?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { _ in }
            if let error { Log.library.error("Couldn't download \(url.lastPathComponent, privacy: .public): \(error, privacy: .public)") }
        }.value
    }
}
