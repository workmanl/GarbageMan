import Foundation
import Observation

@MainActor
@Observable
final class DiskInspectorModel {

    enum Phase: Equatable { case idle, scanning, ready }

    private(set) var phase: Phase = .idle
    private(set) var path: [URL]
    private(set) var entries: [FolderSizer.Entry] = []
    private(set) var lastScannedAt: Date?

    /// Maximum rows displayed per directory level.
    var maxRows: Int = 50

    private var inMemoryCache: [String: InspectorCache.Snapshot]
    private let persistence: InspectorCache

    init(root: URL = FileManager.default.homeDirectoryForCurrentUser,
         persistence: InspectorCache = InspectorCache()) {
        self.path = [root]
        self.persistence = persistence
        self.inMemoryCache = persistence.load()
    }

    var currentRoot: URL { path.last ?? FileManager.default.homeDirectoryForCurrentUser }
    var breadcrumbs: [URL] { path }
    var canPop: Bool { path.count > 1 }
    var topEntries: [FolderSizer.Entry] { Array(entries.prefix(maxRows)) }

    func reset() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        path = [home]
        entries = []
        inMemoryCache.removeAll()
        try? persistence.save(inMemoryCache)
        phase = .idle
        lastScannedAt = nil
    }

    func pop() async {
        guard canPop else { return }
        path.removeLast()
        await loadCurrent(forceRescan: false)
    }

    func drill(into url: URL) async {
        guard url.hasDirectoryPath || (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return }
        path.append(url)
        await loadCurrent(forceRescan: false)
    }

    func scan(forceRescan: Bool = false) async {
        await loadCurrent(forceRescan: forceRescan)
    }

    private func loadCurrent(forceRescan: Bool) async {
        let root = currentRoot
        let key = root.path

        if !forceRescan,
           let cached = inMemoryCache[key],
           Date().timeIntervalSince(cached.scannedAt) < 24 * 3600 {
            entries = persistence.entries(from: cached)
            phase = .ready
            lastScannedAt = cached.scannedAt
            return
        }

        // Don't wipe `entries` before the new scan finishes — the previous
        // view stays visible (dimmed by the view layer) so drilling into a
        // folder doesn't flash empty.
        phase = .scanning

        let fresh = await FolderSizer.contents(of: root)
        let now = Date()
        let snapshot = persistence.snapshotAdapter(from: fresh, scannedAt: now)
        inMemoryCache[key] = snapshot
        try? persistence.save(inMemoryCache)

        entries = fresh
        lastScannedAt = now
        phase = .ready
    }
}
