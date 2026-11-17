import Foundation

/// Locates leftover files associated with an `AppBundle` across the standard
/// macOS support directories. We only ever READ here — recycling is delegated
/// to `Cleaner.recycle` after the user confirms.
enum LeftoverFinder {

    /// A discovered leftover, grouped by its parent location.
    struct Leftover: Hashable, Identifiable {
        let url: URL
        let kind: Kind
        let groupTitle: String

        var id: String { url.path }
        var displayName: String { url.lastPathComponent }

        enum Kind: String { case directory, file }
    }

    struct SearchRoot {
        let title: String
        let url: URL
        /// LaunchAgents/LaunchDaemons folders match files whose names start
        /// with the bundle identifier; for everything else we use the broader
        /// rule.
        let mode: MatchMode

        enum MatchMode {
            case standard
            case launchPlist
        }
    }

    /// Standard set of roots to search, in display order.
    static func defaultRoots() -> [SearchRoot] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            SearchRoot(title: "User · Application Support", url: home.appending(path: "Library/Application Support"), mode: .standard),
            SearchRoot(title: "User · Caches", url: home.appending(path: "Library/Caches"), mode: .standard),
            SearchRoot(title: "User · Preferences", url: home.appending(path: "Library/Preferences"), mode: .standard),
            SearchRoot(title: "User · Logs", url: home.appending(path: "Library/Logs"), mode: .standard),
            SearchRoot(title: "User · Containers", url: home.appending(path: "Library/Containers"), mode: .standard),
            SearchRoot(title: "User · Group Containers", url: home.appending(path: "Library/Group Containers"), mode: .standard),
            SearchRoot(title: "User · Saved Application State", url: home.appending(path: "Library/Saved Application State"), mode: .standard),
            SearchRoot(title: "User · WebKit", url: home.appending(path: "Library/WebKit"), mode: .standard),
            SearchRoot(title: "User · HTTPStorages", url: home.appending(path: "Library/HTTPStorages"), mode: .standard),
            SearchRoot(title: "User · Cookies", url: home.appending(path: "Library/Cookies"), mode: .standard),
            SearchRoot(title: "User · LaunchAgents", url: home.appending(path: "Library/LaunchAgents"), mode: .launchPlist),
            SearchRoot(title: "System · Application Support", url: URL(fileURLWithPath: "/Library/Application Support"), mode: .standard),
            SearchRoot(title: "System · Caches", url: URL(fileURLWithPath: "/Library/Caches"), mode: .standard),
            SearchRoot(title: "System · Logs", url: URL(fileURLWithPath: "/Library/Logs"), mode: .standard),
            SearchRoot(title: "System · Preferences", url: URL(fileURLWithPath: "/Library/Preferences"), mode: .standard),
            SearchRoot(title: "System · LaunchAgents", url: URL(fileURLWithPath: "/Library/LaunchAgents"), mode: .launchPlist),
            SearchRoot(title: "System · LaunchDaemons", url: URL(fileURLWithPath: "/Library/LaunchDaemons"), mode: .launchPlist)
        ]
    }

    /// Walk every search root and collect matching leftovers for `bundle`.
    static func find(for bundle: AppBundle, roots: [SearchRoot] = defaultRoots()) -> [Leftover] {
        var out: [Leftover] = []
        for root in roots {
            out.append(contentsOf: find(in: root, for: bundle))
        }
        return out
    }

    static func find(in root: SearchRoot, for bundle: AppBundle) -> [Leftover] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.url.path, isDirectory: &isDir), isDir.boolValue else { return [] }
        guard let kids = try? fm.contentsOfDirectory(at: root.url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        return kids.compactMap { child in
            let name = child.lastPathComponent
            guard matches(name: name, mode: root.mode, bundle: bundle) else { return nil }
            let kind: Leftover.Kind
            var sub: ObjCBool = false
            if fm.fileExists(atPath: child.path, isDirectory: &sub), sub.boolValue {
                kind = .directory
            } else {
                kind = .file
            }
            return Leftover(url: child, kind: kind, groupTitle: root.title)
        }
    }

    /// Pure-function name matcher — extracted for unit testing.
    static func matches(name: String, mode: SearchRoot.MatchMode, bundle: AppBundle) -> Bool {
        let id = bundle.bundleIdentifier
        let lowerName = name.lowercased()
        let lowerID = id.lowercased()

        // Universal rules (apply in both modes):
        // 1. exact bundle ID match
        if lowerName == lowerID { return true }
        // 2. bundle ID prefix followed by '.', e.g. `com.apple.Safari.helper`
        if lowerName.hasPrefix(lowerID + ".") { return true }
        // 3. Containers / Group Containers use bundle ID as-is or with team-ID prefix
        if lowerName.contains(lowerID) { return true }

        if mode == .launchPlist {
            // LaunchAgents/LaunchDaemons plists are usually `<bundleid>.plist`
            if lowerName == "\(lowerID).plist" { return true }
            if lowerName.hasPrefix(lowerID + ".") && lowerName.hasSuffix(".plist") { return true }
            return false
        }

        // .standard mode also accepts an exact app-name match (case-insensitive)
        // — used by things like `~/Library/Caches/Slack` that don't use the bundle ID.
        let appBase = bundle.displayName.lowercased()
        if !appBase.isEmpty {
            if lowerName == appBase { return true }
            // Pref files such as `Slack.plist`
            if lowerName == "\(appBase).plist" { return true }
        }
        return false
    }
}
