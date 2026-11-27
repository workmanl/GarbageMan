import AppKit
import Foundation

/// Moves the contents of a directory into the system Trash.
///
/// Two important invariants:
/// 1. We recycle the CHILDREN of each category root, not the root itself.
///    Apps and the OS expect dirs like `~/Library/Caches` to keep existing.
/// 2. We never use `unlink()` / `FileManager.removeItem`. Everything goes
///    through `NSWorkspace.shared.recycle` so the user can recover.
enum Cleaner {

    struct Result {
        var recycledCount: Int = 0
        var failedCount: Int = 0
        var bytesReclaimedEstimate: UInt64 = 0
        var firstError: Error?
    }

    /// Compute the list of child URLs that would be recycled for a set of
    /// category roots. Each root is expanded to its direct children; missing
    /// or unreadable roots are skipped.
    static func enumerableChildren(of roots: [URL]) -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        for root in roots {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else { continue }
            guard let kids = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            out.append(contentsOf: kids)
        }
        return out
    }

    /// Recycle a flat list of URLs in one shot. NSWorkspace handles batching
    /// internally and returns a map of original URL -> Trash URL for the
    /// successes plus a single combined error for the failures.
    ///
    /// `succeeded` holds the ORIGINAL URLs that moved (the map's keys), so
    /// callers can match them against what they asked to recycle.
    static func recycle(_ urls: [URL]) async -> (succeeded: [URL], firstError: Error?) {
        guard !urls.isEmpty else { return ([], nil) }
        return await withCheckedContinuation { cont in
            NSWorkspace.shared.recycle(urls) { mapping, error in
                cont.resume(returning: (Array(mapping.keys), error))
            }
        }
    }
}
