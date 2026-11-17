import Foundation

/// A parsed reference to an installed macOS application bundle. Built from a
/// dropped .app URL; carries the identifiers we use to find leftovers.
struct AppBundle: Equatable {
    let url: URL
    let bundleIdentifier: String
    let displayName: String
    let executableName: String?
    let version: String?

    /// Parse the .app at `url`. Returns nil if the URL isn't a usable bundle.
    init?(url: URL) {
        guard url.pathExtension.lowercased() == "app" else { return nil }
        guard let bundle = Bundle(url: url),
              let bid = bundle.bundleIdentifier else { return nil }
        let info = bundle.infoDictionary ?? [:]
        let display = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        self.url = url
        self.bundleIdentifier = bid
        self.displayName = display
        self.executableName = info["CFBundleExecutable"] as? String
        self.version = (info["CFBundleShortVersionString"] as? String) ?? (info["CFBundleVersion"] as? String)
    }

    /// Test-only init so we can build instances without touching disk.
    init(url: URL, bundleIdentifier: String, displayName: String, executableName: String? = nil, version: String? = nil) {
        self.url = url
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.executableName = executableName
        self.version = version
    }
}
