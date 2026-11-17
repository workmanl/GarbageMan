import Foundation

/// JSON-backed persistence for Disk Inspector scans. Saves to
/// `~/Library/Application Support/GarbageMan/disk-inspector-cache.json` by
/// default; tests can point the URL elsewhere.
///
/// The on-disk schema is intentionally tiny so it can be hand-edited or
/// inspected. Future versions should bump `Payload.version` and migrate.
struct InspectorCache {

    static let currentVersion = 1

    struct Snapshot: Codable, Equatable {
        var scannedAt: Date
        var children: [Child]

        struct Child: Codable, Equatable {
            var path: String
            var size: UInt64
            var isDirectory: Bool
        }
    }

    struct Payload: Codable {
        var version: Int
        var snapshots: [String: Snapshot]
    }

    let fileURL: URL

    init(fileURL: URL = InspectorCache.defaultURL()) {
        self.fileURL = fileURL
    }

    /// Default location under Application Support. Creates the directory
    /// lazily; failures are non-fatal — the cache silently degrades to a no-op.
    static func defaultURL() -> URL {
        let fm = FileManager.default
        let base = (fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                    ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support"))
            .appending(path: "GarbageMan")
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appending(path: "disk-inspector-cache.json")
    }

    func load() -> [String: Snapshot] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(Payload.self, from: data) else { return [:] }
        // Only honour the version we know about. Future formats yield an empty
        // cache rather than misinterpreted data.
        guard payload.version == Self.currentVersion else { return [:] }
        return payload.snapshots
    }

    /// Persist the entire snapshot map. Atomic write so a crash mid-write
    /// doesn't corrupt the cache.
    func save(_ snapshots: [String: Snapshot]) throws {
        let payload = Payload(version: Self.currentVersion, snapshots: snapshots)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: fileURL, options: [.atomic])
    }

    func snapshotAdapter(from entries: [FolderSizer.Entry], scannedAt: Date) -> Snapshot {
        Snapshot(
            scannedAt: scannedAt,
            children: entries.map { Snapshot.Child(path: $0.url.path, size: $0.size, isDirectory: $0.isDirectory) }
        )
    }

    func entries(from snapshot: Snapshot) -> [FolderSizer.Entry] {
        snapshot.children.map {
            FolderSizer.Entry(url: URL(fileURLWithPath: $0.path), isDirectory: $0.isDirectory, size: $0.size)
        }
    }
}
