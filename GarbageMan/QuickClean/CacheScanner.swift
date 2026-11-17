import Foundation

/// Computes the on-disk size of a directory tree. All work happens off the
/// main actor so callers can scan tens of GB without blocking the UI.
enum CacheScanner {

    /// Richer scan result that includes both the byte total and any subpaths
    /// the enumerator was unable to read (typically permission errors).
    struct ScanResult: Equatable {
        var bytes: UInt64
        /// URLs we attempted to enumerate but couldn't. Useful for surfacing a
        /// "needs privileges" hint to the user. Order is not significant.
        var unreadablePaths: [URL]

        static let empty = ScanResult(bytes: 0, unreadablePaths: [])
    }

    /// Convenience that drops the error list. Equivalent to `detailed(...).bytes`.
    static func size(of urls: [URL]) async -> UInt64 {
        await detailed(of: urls).bytes
    }

    static func size(of url: URL) async -> UInt64 {
        await detailed(of: url).bytes
    }

    static func detailed(of urls: [URL]) async -> ScanResult {
        await withTaskGroup(of: ScanResult.self) { group in
            for url in urls {
                group.addTask(priority: .utility) {
                    await detailed(of: url)
                }
            }
            var aggregate = ScanResult.empty
            for await partial in group {
                aggregate.bytes &+= partial.bytes
                aggregate.unreadablePaths.append(contentsOf: partial.unreadablePaths)
            }
            return aggregate
        }
    }

    static func detailed(of url: URL) async -> ScanResult {
        await Task.detached(priority: .utility) {
            scanDirectory(url)
        }.value
    }

    private static func scanDirectory(_ url: URL) -> ScanResult {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return .empty }
        if !isDir.boolValue {
            return ScanResult(bytes: fileAllocatedSize(url), unreadablePaths: [])
        }

        var errorPaths: [URL] = []
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { failed, _ in
                errorPaths.append(failed)
                return true
            }
        ) else { return ScanResult(bytes: 0, unreadablePaths: [url]) }

        var total: UInt64 = 0
        for case let child as URL in enumerator {
            guard let values = try? child.resourceValues(forKeys: Set(keys)) else {
                errorPaths.append(child)
                continue
            }
            if values.isSymbolicLink == true { continue }
            if values.isRegularFile != true { continue }
            let size = UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            total &+= size
        }
        return ScanResult(bytes: total, unreadablePaths: errorPaths)
    }

    private static func fileAllocatedSize(_ url: URL) -> UInt64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        return UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }
}
