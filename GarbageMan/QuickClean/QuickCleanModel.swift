import Foundation
import Observation

@MainActor
@Observable
final class QuickCleanModel {

    enum ScanState: Equatable {
        case idle
        case scanning
        case ready
        case cleaning
    }

    struct CleanOutcome: Equatable {
        let recycled: Int
        let failed: Int
        let bytesReclaimedEstimate: UInt64
        let errorMessage: String?
    }

    struct CategoryRow: Identifiable, Equatable {
        let category: CleanCategory
        var size: UInt64?
        var isSelected: Bool
        var isScanning: Bool
        /// `true` when at least one of the category's URLs exists on this
        /// machine. Captured at scan time so the UI can distinguish "no
        /// paths existed" from "paths existed but were empty".
        var hasResolvedPaths: Bool
        /// First resolved path (used for Reveal-in-Finder).
        var primaryPath: URL?
        /// Subpaths the scanner was unable to read on the last scan, usually
        /// permission denials. UI surfaces a warning glyph when non-empty.
        var unreadablePaths: [URL] = []
        /// Estimated bytes recovered by the most recent clean operation.
        /// Set during `cleanSequentially()` and auto-cleared a few seconds
        /// after the clean finishes so the inline confirmation fades out.
        var lastReclaimed: UInt64?

        var id: String { category.id }
    }

    private(set) var rows: [CategoryRow]
    private(set) var state: ScanState = .idle
    private(set) var lastScanCompletedAt: Date?
    private(set) var lastCleanOutcome: CleanOutcome?
    private(set) var currentCleaningCategoryID: String?
    /// Number of categories the active clean has finished. Pairs with
    /// `cleanTotalCategoryCount` so the UI can show "Cleaning N of M…".
    private(set) var cleanCompletedCount: Int = 0
    private(set) var cleanTotalCategoryCount: Int = 0
    private var cleaningTask: Task<Void, Never>?

    /// Categories the cleaner intentionally skips (e.g. `~/.Trash`, which
    /// would need a permanent delete and is reserved for a future iteration
    /// with its own explicit confirmation flow).
    static let cleanExcludedCategoryIDs: Set<String> = ["trash"]

    init(categories: [CleanCategory] = CleanCategory.all) {
        rows = categories.map {
            let resolved = $0.resolvedPaths()
            return CategoryRow(
                category: $0,
                size: nil,
                isSelected: true,
                isScanning: false,
                hasResolvedPaths: !resolved.isEmpty,
                primaryPath: resolved.first
            )
        }
    }

    var totalSelectedBytes: UInt64 {
        rows.reduce(0) { acc, row in
            guard row.isSelected, let size = row.size else { return acc }
            return acc &+ size
        }
    }

    var cleanableRows: [CategoryRow] {
        rows.filter { $0.isSelected
            && !Self.cleanExcludedCategoryIDs.contains($0.id)
            && $0.hasResolvedPaths }
    }

    var cleanableBytes: UInt64 {
        cleanableRows.reduce(0) { acc, row in acc &+ (row.size ?? 0) }
    }

    var hasCleanableSelection: Bool {
        cleanableRows.contains { ($0.size ?? 0) > 0 }
    }

    var totalBytes: UInt64 {
        rows.reduce(0) { acc, row in acc &+ (row.size ?? 0) }
    }

    var selectedCount: Int { rows.filter(\.isSelected).count }

    func setSelection(for id: String, to isSelected: Bool) {
        guard let idx = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[idx].isSelected = isSelected
    }

    func toggleAll(_ on: Bool) {
        for idx in rows.indices { rows[idx].isSelected = on }
    }

    func scan() async {
        guard state != .scanning else { return }
        state = .scanning
        for idx in rows.indices {
            rows[idx].size = nil
            rows[idx].isScanning = true
            rows[idx].unreadablePaths = []
            // Preserve lastReclaimed across re-scans so the inline
            // confirmation survives until its fade timer fires.
        }

        // Refresh path resolution so freshly installed apps show up between scans.
        for idx in rows.indices {
            let resolved = rows[idx].category.resolvedPaths()
            rows[idx].hasResolvedPaths = !resolved.isEmpty
            rows[idx].primaryPath = resolved.first
        }

        await withTaskGroup(of: (String, CacheScanner.ScanResult).self) { group in
            for row in rows {
                let urls = row.category.resolvedPaths()
                if urls.isEmpty {
                    self.applyResult(for: row.id, result: .empty)
                    continue
                }
                group.addTask {
                    let result = await CacheScanner.detailed(of: urls)
                    return (row.id, result)
                }
            }
            for await (id, result) in group {
                applyResult(for: id, result: result)
            }
        }

        state = .ready
        lastScanCompletedAt = .now
    }

    private func applySize(for id: String, size: UInt64) {
        guard let idx = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[idx].size = size
        rows[idx].isScanning = false
    }

    private func applyResult(for id: String, result: CacheScanner.ScanResult) {
        guard let idx = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[idx].size = result.bytes
        rows[idx].unreadablePaths = result.unreadablePaths
        rows[idx].isScanning = false
    }

    /// Permanently empty `~/.Trash`. Guarded by the UI's two-tap confirmation.
    /// Returns the outcome so the view can surface it.
    func emptyTrash() async -> TrashEmptier.Outcome {
        let outcome = await Task.detached(priority: .userInitiated) {
            TrashEmptier.empty()
        }.value
        await scan()
        return outcome
    }

    /// Kick off a cancellable clean. The view holds onto nothing — calling
    /// `cancelClean()` interrupts the task between categories.
    func startClean() {
        guard state != .cleaning, state != .scanning else { return }
        cleaningTask?.cancel()
        cleaningTask = Task { await cleanSequentially() }
    }

    func cancelClean() {
        cleaningTask?.cancel()
    }

    /// Await the currently running clean (if any) without owning it. Returns
    /// immediately if no clean is in flight.
    func waitForCleanToFinish() async {
        await cleaningTask?.value
    }

    private func cleanSequentially() async {
        state = .cleaning
        lastCleanOutcome = nil

        // Reset stale reclaim badges from any previous clean.
        for idx in rows.indices { rows[idx].lastReclaimed = nil }

        let targets = cleanableRows
        cleanTotalCategoryCount = targets.count
        cleanCompletedCount = 0

        guard !targets.isEmpty else {
            lastCleanOutcome = CleanOutcome(recycled: 0, failed: 0, bytesReclaimedEstimate: 0, errorMessage: "Nothing to clean.")
            state = .ready
            return
        }

        var totalRecycled = 0
        var totalFailed = 0
        var totalBytes: UInt64 = 0
        var firstError: String?
        var cancelled = false

        for row in targets {
            if Task.isCancelled { cancelled = true; break }
            currentCleaningCategoryID = row.id

            if let customClean = row.category.customClean {
                let preBytes = row.size ?? 0
                let outcome = await customClean()
                totalRecycled += outcome.succeeded
                totalFailed += outcome.failed
                let attempted = outcome.succeeded + outcome.failed
                let ratio = attempted == 0 ? 0 : Double(outcome.succeeded) / Double(attempted)
                let approxRowReclaimed = UInt64(Double(preBytes) * ratio)
                totalBytes &+= approxRowReclaimed
                if approxRowReclaimed > 0,
                   let idx = rows.firstIndex(where: { $0.id == row.id }) {
                    rows[idx].lastReclaimed = approxRowReclaimed
                }
                if firstError == nil, let message = outcome.errorMessage {
                    firstError = message
                }
                cleanCompletedCount += 1
                continue
            }

            let resolved = row.category.resolvedPaths()
            let children = row.category.recyclesRootsDirectly
                ? resolved
                : Cleaner.enumerableChildren(of: resolved)
            if children.isEmpty {
                cleanCompletedCount += 1
                continue
            }

            let preBytes = row.size ?? 0
            let (succeeded, err) = await Cleaner.recycle(children)
            totalRecycled += succeeded.count
            totalFailed += max(0, children.count - succeeded.count)

            let ratio = children.isEmpty ? 0 : (Double(succeeded.count) / Double(children.count))
            let approxRowReclaimed = UInt64(Double(preBytes) * ratio)
            totalBytes &+= approxRowReclaimed

            if approxRowReclaimed > 0,
               let idx = rows.firstIndex(where: { $0.id == row.id }) {
                rows[idx].lastReclaimed = approxRowReclaimed
            }

            if firstError == nil, let err {
                firstError = (err as NSError).localizedDescription
            }
            cleanCompletedCount += 1
        }
        currentCleaningCategoryID = nil

        let message: String?
        if cancelled {
            if let err = firstError {
                message = "Cancelled after partial progress. First error: \(err)"
            } else {
                message = "Cancelled by user. Partial progress was kept in Trash."
            }
        } else {
            message = firstError
        }

        lastCleanOutcome = CleanOutcome(
            recycled: totalRecycled,
            failed: totalFailed,
            bytesReclaimedEstimate: totalBytes,
            errorMessage: message
        )

        // Re-scan so the totals reflect the new state.
        await scan()

        // Fade out the per-row reclaimed badges after a beat so they read as
        // a confirmation pulse, not a sticky annotation.
        let badgesToClear = rows.compactMap { $0.lastReclaimed == nil ? nil : $0.id }
        if !badgesToClear.isEmpty {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                await self?.clearReclaimedBadges(for: badgesToClear)
            }
        }
    }

    private func clearReclaimedBadges(for ids: [String]) {
        for id in ids {
            if let idx = rows.firstIndex(where: { $0.id == id }) {
                rows[idx].lastReclaimed = nil
            }
        }
    }

    /// Back-compat shim for callers that want a synchronous-style `await`
    /// instead of the cancellable `startClean()` API. New code should prefer
    /// `startClean()` so cancellation is wired automatically.
    func clean() async {
        startClean()
        await cleaningTask?.value
    }
}

extension UInt64 {
    var formattedByteCount: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        let clamped = Swift.min(self, UInt64(Int64.max))
        return formatter.string(fromByteCount: Int64(clamped))
    }
}
