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

    /// Bundle IDs we refuse to match at all: Apple's own apps (system files
    /// share their prefixes) and IDs too short or generic to be safe.
    static func isMatchableBundleID(_ id: String) -> Bool {
        let lower = id.lowercased()
        guard lower.count >= 8 else { return false }
        let parts = lower.split(separator: ".", omittingEmptySubsequences: false)
        // At least vendor + org + product, so a bare vendor prefix like
        // `com.vendor` can never sweep up that vendor's other apps.
        guard parts.count >= 3, !parts.contains(where: \.isEmpty) else { return false }
        if lower == "com.apple" || lower.hasPrefix("com.apple.") || lower.contains(".com.apple.") { return false }
        // IDs that start like a container prefix are not real bundle IDs.
        if parts[0] == "group" || parts[0] == "groups" { return false }
        if isTeamIDComponent(String(id.split(separator: ".").first ?? "")) { return false }
        return true
    }

    /// Apple team IDs are exactly 10 characters of A-Z and 0-9.
    static func isTeamIDComponent(_ s: String) -> Bool {
        s.count == 10 && s.unicodeScalars.allSatisfy { ("A"..."Z").contains($0) || ("0"..."9").contains($0) }
    }

    /// Pure-function name matcher — extracted for unit testing.
    /// Every rule is anchored (exact name, or the ID followed by "."), so an
    /// app such as `com.foo.mail` never matches `com.foo.mailbox`.
    static func matches(name: String, mode: SearchRoot.MatchMode, bundle: AppBundle) -> Bool {
        let id = bundle.bundleIdentifier
        guard isMatchableBundleID(id) else { return false }
        let lowerName = name.lowercased()
        let lowerID = id.lowercased()
        // Never offer Apple's own files, whatever app is being removed.
        if lowerName.hasPrefix("com.apple.") || lowerName.contains(".com.apple.") { return false }

        // Universal rules (apply in both modes):
        // 1. exact bundle ID match
        if lowerName == lowerID { return true }
        // 2. bundle ID prefix followed by '.', e.g. `com.example.app.helper`
        if lowerName.hasPrefix(lowerID + ".") { return true }
        // 3. Group Containers: `group.<id>` or a team-ID prefix `<TEAMID>.<id>`
        if lowerName == "group.\(lowerID)" || lowerName.hasPrefix("group.\(lowerID).") { return true }
        if let dot = name.firstIndex(of: ".") {
            // Team ID is checked on the original (case-sensitive) name.
            let prefix = String(name[..<dot])
            let rest = String(name[name.index(after: dot)...]).lowercased()
            if isTeamIDComponent(prefix) && (rest == lowerID || rest.hasPrefix(lowerID + ".")) { return true }
        }

        if mode == .launchPlist {
            // LaunchAgents/LaunchDaemons plists are usually `<bundleid>.plist`
            if lowerName == "\(lowerID).plist" { return true }
            if lowerName.hasPrefix(lowerID + ".") && lowerName.hasSuffix(".plist") { return true }
            return false
        }

        // .standard mode also accepts an exact app-name match (case-insensitive)
        // — used by things like `~/Library/Caches/Slack` that don't use the bundle ID.
        // Only for names long enough to be distinctive (no "app", "kit", "tv").
        let appBase = bundle.displayName.lowercased()
        if appBase.count >= 4 {
            if lowerName == appBase { return true }
            // Pref files such as `Slack.plist`
            if lowerName == "\(appBase).plist" { return true }
        }
        return false
    }
}
