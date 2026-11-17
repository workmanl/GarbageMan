import Foundation

/// Permanently deletes the contents of a Trash-style directory.
///
/// This is the ONE place in the app where `FileManager.removeItem` is used.
/// Every other delete path goes through `NSWorkspace.shared.recycle(at:)` so
/// the user can recover. The Trash is special: recycling a Trash item back to
/// Trash is a no-op, so emptying it requires permanent deletion — guarded by
/// an explicit two-tap confirmation in the UI.
enum TrashEmptier {

    struct Outcome: Equatable {
        let removed: Int
        let failed: Int
        let bytesReclaimed: UInt64
        let firstError: String?
    }

    /// Empty every direct child of `root`. The root directory itself is not
    /// deleted (Trash must remain). Symlinks are deleted by removing the link,
    /// not the target. Hidden files like `.DS_Store` are removed too.
    static func empty(root: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash")) -> Outcome {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            return Outcome(removed: 0, failed: 0, bytesReclaimed: 0, firstError: "Trash directory not found.")
        }
        guard let kids = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: []) else {
            return Outcome(removed: 0, failed: 0, bytesReclaimed: 0, firstError: "Cannot enumerate Trash.")
        }

        var removed = 0
        var failed = 0
        var bytes: UInt64 = 0
        var firstError: String?

        for child in kids {
            let size = sizeOf(child)
            do {
                try fm.removeItem(at: child)
                removed += 1
                bytes &+= size
            } catch {
                failed += 1
                if firstError == nil {
                    firstError = (error as NSError).localizedDescription
                }
            }
        }

        return Outcome(removed: removed, failed: failed, bytesReclaimed: bytes, firstError: firstError)
    }

    private static func sizeOf(_ url: URL) -> UInt64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isDirectory == true {
            // Recursive walk for directories.
            var total: UInt64 = 0
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey],
                options: [],
                errorHandler: { _, _ in true }
            ) else { return 0 }
            for case let item as URL in enumerator {
                guard let v = try? item.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]),
                      v.isRegularFile == true else { continue }
                total &+= UInt64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            }
            return total
        }
        return UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }
}
