import Foundation
import Observation

@MainActor
@Observable
final class UninstallerModel {

    enum Phase: Equatable {
        case empty
        case scanning
        case ready
        case uninstalling
        case done
    }

    struct LeftoverRow: Identifiable, Equatable {
        let leftover: LeftoverFinder.Leftover
        var size: UInt64?
        var isSelected: Bool

        var id: String { leftover.id }
    }

    struct UninstallOutcome: Equatable {
        let recycled: Int
        let failed: Int
        let bytesReclaimedEstimate: UInt64
        let errorMessage: String?
        let appWasIncluded: Bool
        let appWasRecycled: Bool

        /// True when the user asked to remove the app but it is still installed.
        var appLeftInstalled: Bool { appWasIncluded && !appWasRecycled }

        /// Build the outcome from what was attempted and what actually moved.
        /// Bytes count only the items that moved, using each item's own size,
        /// so a failed large app doesn't inflate the reclaimed total.
        static func make(
            attempted: [URL],
            succeeded: [URL],
            sizes: [URL: UInt64],
            appURL: URL?,
            error: Error?
        ) -> UninstallOutcome {
            func key(_ url: URL) -> String { url.standardizedFileURL.path }
            let moved = Set(succeeded.map(key))
            let movedAttempts = attempted.filter { moved.contains(key($0)) }
            let sizeByKey = Dictionary(sizes.map { (key($0.key), $0.value) }, uniquingKeysWith: { a, _ in a })
            let bytes = movedAttempts.reduce(UInt64(0)) { $0 &+ (sizeByKey[key($1)] ?? 0) }
            return UninstallOutcome(
                recycled: movedAttempts.count,
                failed: attempted.count - movedAttempts.count,
                bytesReclaimedEstimate: bytes,
                errorMessage: error.map { ($0 as NSError).localizedDescription },
                appWasIncluded: appURL != nil,
                appWasRecycled: appURL.map { moved.contains(key($0)) } ?? false
            )
        }
    }

    private(set) var phase: Phase = .empty
    private(set) var bundle: AppBundle?
    private(set) var rows: [LeftoverRow] = []
    private(set) var lastOutcome: UninstallOutcome?
    var includeAppItself: Bool = true

    func clear() {
        bundle = nil
        rows = []
        phase = .empty
        lastOutcome = nil
        includeAppItself = true
    }

    func acceptDrop(urls: [URL]) async {
        guard let url = urls.first(where: { $0.pathExtension.lowercased() == "app" }) else { return }
        guard let app = AppBundle(url: url) else { return }
        bundle = app
        phase = .scanning
        rows = []
        lastOutcome = nil
        includeAppItself = true

        let raw = LeftoverFinder.find(for: app)
        var stage: [LeftoverRow] = raw.map { LeftoverRow(leftover: $0, size: nil, isSelected: true) }

        // Compute sizes concurrently.
        await withTaskGroup(of: (String, UInt64).self) { group in
            for row in stage {
                let id = row.id
                let url = row.leftover.url
                group.addTask { (id, await CacheScanner.size(of: [url])) }
            }
            for await (id, size) in group {
                if let idx = stage.firstIndex(where: { $0.id == id }) {
                    stage[idx].size = size
                }
            }
        }
        rows = stage
        phase = .ready
    }

    var groupedRows: [(group: String, rows: [LeftoverRow])] {
        let groups = Dictionary(grouping: rows, by: { $0.leftover.groupTitle })
        return groups
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value.sorted(by: { $0.leftover.displayName < $1.leftover.displayName })) }
    }

    var selectedRows: [LeftoverRow] { rows.filter { $0.isSelected } }

    var totalSelectedBytes: UInt64 {
        let leftovers: UInt64 = selectedRows.reduce(0) { acc, row in acc &+ (row.size ?? 0) }
        return includeAppItself ? leftovers &+ approxAppSize : leftovers
    }

    var approxAppSize: UInt64 {
        guard let url = bundle?.url else { return 0 }
        // Cached on first call would be nicer but the on-disk walk is fast
        // enough for a single .app. Done on the main actor here intentionally
        // — we accept the small wait because this is a UI accessor.
        return synchronouslySize(url)
    }

    private func synchronouslySize(_ url: URL) -> UInt64 {
        var total: UInt64 = 0
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }
        for case let item as URL in enumerator {
            guard let values = try? item.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            total &+= UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    func setSelection(for id: String, _ value: Bool) {
        guard let idx = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[idx].isSelected = value
    }

    func uninstall() async {
        guard phase == .ready, let bundle else { return }
        phase = .uninstalling

        var urls: [URL] = []
        var sizes: [URL: UInt64] = [:]
        if includeAppItself {
            urls.append(bundle.url)
            sizes[bundle.url] = approxAppSize
        }
        for row in selectedRows {
            urls.append(row.leftover.url)
            sizes[row.leftover.url] = row.size ?? 0
        }

        let (succeeded, firstError) = await Cleaner.recycle(urls)

        lastOutcome = UninstallOutcome.make(
            attempted: urls,
            succeeded: succeeded,
            sizes: sizes,
            appURL: includeAppItself ? bundle.url : nil,
            error: firstError
        )
        phase = .done
    }
}
