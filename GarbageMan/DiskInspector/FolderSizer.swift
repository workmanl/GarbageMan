import Foundation

/// Discovers the direct children of a directory and computes the on-disk
/// size of each in parallel. Reuses `CacheScanner.size` for the per-child
/// walk so the sizing semantics stay consistent across the app.
enum FolderSizer {

    struct Entry: Identifiable, Equatable {
        let url: URL
        let isDirectory: Bool
        let size: UInt64

        var id: String { url.path }
        var displayName: String { url.lastPathComponent }
    }

    /// Return every direct child of `root` with its size, sorted descending.
    /// Hidden direct children of `root` are not listed, but each listed
    /// child's size includes the hidden files inside it. Symlinks are not
    /// followed.
    static func contents(of root: URL) async -> [Entry] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else { return [] }
        guard let kids = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let entries = await withTaskGroup(of: Entry?.self) { group in
            for child in kids {
                group.addTask(priority: .utility) {
                    let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    if values?.isSymbolicLink == true { return nil }
                    let isDir = values?.isDirectory ?? false
                    let size = await CacheScanner.size(of: [child])
                    return Entry(url: child, isDirectory: isDir, size: size)
                }
            }
            var out: [Entry] = []
            for await result in group {
                if let entry = result { out.append(entry) }
            }
            return out
        }
        return entries.sorted { $0.size > $1.size }
    }
}
