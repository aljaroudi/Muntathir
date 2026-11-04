import Foundation

/// The atomic index is shared with widgets. Downloaded databases are never backed up to iCloud.
struct QuranTranslationFiles: Sendable {
    struct Index: Codable, Sendable {
        var installed: [String: String] = [:]
        var pending: [String]?
        var hasInstalled = false
        var needsPackCleanup = false
    }

    let root: URL
    static var sharedRoot: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: QuranTranslationPreferences.groupID)?
            .appending(path: "Library/Application Support/QuranTranslations", directoryHint: .isDirectory)
    }

    func read() throws -> Index {
        let url = root.appending(path: "index.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return Index() }
        return try JSONDecoder().decode(Index.self, from: Data(contentsOf: url))
    }

    func write(_ index: Index) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var directory = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        try JSONEncoder().encode(index).write(to: root.appending(path: "index.json"), options: .atomic)
    }

    func installedURLs() throws -> [String: URL] {
        try read().installed.compactMapValues { relative in
            let url = root.appending(path: relative)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }

    func prepare(requested: String?) throws {
        var index = try read()
        let ids = QuranTranslation.downloadable.map(\.id)
        if let requested, !ids.contains(requested) {
            throw QuranDatabaseError.unavailable
        }
        index.pending = index.hasInstalled ? (requested.map { [$0] } ?? ids) : ids
        index.needsPackCleanup = false
        try write(index)
    }

    /// Publish only after every requested file has copied and passed validation.
    @concurrent func install(from directory: URL,
                             copy: @Sendable (URL, URL) throws -> Void = { try FileManager.default.copyItem(at: $0, to: $1) }) async throws
    {
        var index = try read()
        guard let pending = index.pending else { return }
        let generation = UUID().uuidString
        let staging = root.appending(path: generation, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            for id in pending {
                try Task.checkCancellation()
                guard QuranTranslation.downloadable.contains(where: { $0.id == id }) else { throw QuranDatabaseError.unavailable }
                let target = staging.appending(path: "\(id).db")
                try copy(directory.appending(path: "\(id).db"), target)
                try QuranDatabase.validateTranslation(at: target)
                index.installed[id] = "\(generation)/\(id).db"
            }
            index.pending = nil
            index.hasInstalled = true
            index.needsPackCleanup = true
            try write(index)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    func remove(_ ids: [String]) throws {
        var index = try read()
        guard index.pending == nil else { throw QuranDatabaseError.unavailable }
        for id in ids {
            guard let relative = index.installed[id] else { continue }
            let url = root.appending(path: relative)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            index.installed.removeValue(forKey: id)
            try write(index)
        }
    }

    /// Reclaim replaced files and interrupted staging directories without touching installed languages.
    func cleanOrphans() throws {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        let retained = try Set(read().installed.values)
        for directory in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) {
            guard try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { continue }
            for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                let relative = "\(directory.lastPathComponent)/\(file.lastPathComponent)"
                if !retained.contains(relative) {
                    try FileManager.default.removeItem(at: file)
                }
            }
            if try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty {
                try FileManager.default.removeItem(at: directory)
            }
        }
    }
}
