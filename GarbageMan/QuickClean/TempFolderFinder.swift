import Foundation

/// Finds disposable folders in /private/tmp: folders you own that nothing has
/// written to for a while (old build output, test browser profiles, render
/// scratch). Only direct children of the root are considered.
///
/// Safety rules:
/// - Only directories (never sockets, files or symlinks).
/// - Only folders owned by the current user.
/// - Never names on the protected list (live tool temp dirs, system dirs).
/// - "Untouched" means the folder AND its direct children are older than
///   `olderThan`. This check stays shallow so it is cheap enough to run on
///   every scan.
enum TempFolderFinder {

    static let defaultRoot = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
    static let defaultAge: TimeInterval = 2 * 24 * 60 * 60

    /// Prefixes of folders that belong to running tools or the system.
    static let protectedPrefixes = [
        ".", "claude-", "codex-", "com.apple", "com.openai", "launchd", "powerlog", "tmux-", "ssh-", "KSOutOfProcessFetcher", "boost_interprocess"
    ]

    static func staleFolders(
        root: URL = defaultRoot,
        olderThan age: TimeInterval = defaultAge,
        now: Date = .now,
        ownerUID: uid_t = getuid()
    ) -> [URL] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
        guard let children = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: keys,
            options: []
        ) else { return [] }

        let cutoff = now.addingTimeInterval(-age)
        return children.filter { url in
            let name = url.lastPathComponent
            if protectedPrefixes.contains(where: { name.hasPrefix($0) }) { return false }
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isDirectory == true,
                  values.isSymbolicLink != true else { return false }
            guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                  let owner = (attrs[.ownerAccountID] as? NSNumber)?.uint32Value,
                  owner == ownerUID else { return false }
            return newestModification(of: url) < cutoff
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Newest modification date of a folder and its direct children.
    static func newestModification(of url: URL) -> Date {
        let fm = FileManager.default
        var newest = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        if let kids = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: []
        ) {
            for kid in kids {
                if let date = (try? kid.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                   date > newest {
                    newest = date
                }
            }
        }
        return newest
    }
}
