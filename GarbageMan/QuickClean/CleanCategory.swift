import Foundation

/// Result of a category that cleans itself with a command instead of the
/// default recycle-to-Trash flow (for example `xcrun simctl delete unavailable`).
struct CustomCleanOutcome: Equatable {
    var succeeded: Int
    var failed: Int
    var errorMessage: String?
}

/// A category of reclaimable disk space. Each category resolves to one or more
/// concrete paths at runtime.
struct CleanCategory: Identifiable, Hashable {

    /// Where the category is listed in Quick Clean. Developer categories are
    /// only shown when at least one of them exists on this Mac.
    enum Section: String, CaseIterable {
        case general
        case developer

        var title: String {
            switch self {
            case .general: "General"
            case .developer: "Developer"
            }
        }
    }

    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let section: Section
    /// When `true` the resolved paths themselves are recycled (each one is a
    /// disposable folder, like a stale build dir in /private/tmp). When
    /// `false` (default) only the CHILDREN of each root are recycled so dirs
    /// like `~/Library/Caches` keep existing.
    let recyclesRootsDirectly: Bool
    /// Optional command-based cleaner. When set, Quick Clean calls this
    /// instead of recycling paths; the paths are still used for sizing.
    let customClean: (() async -> CustomCleanOutcome)?
    /// Paths produced lazily so we can reference $HOME and other dynamic
    /// locations without baking them into static initialisers.
    let pathProvider: () -> [URL]

    init(
        id: String,
        title: String,
        subtitle: String,
        symbol: String,
        section: Section = .general,
        recyclesRootsDirectly: Bool = false,
        customClean: (() async -> CustomCleanOutcome)? = nil,
        pathProvider: @escaping () -> [URL]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.section = section
        self.recyclesRootsDirectly = recyclesRootsDirectly
        self.customClean = customClean
        self.pathProvider = pathProvider
    }

    func resolvedPaths() -> [URL] {
        pathProvider().filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func == (lhs: CleanCategory, rhs: CleanCategory) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension CleanCategory {

    static let all: [CleanCategory] = [
        userCaches,
        userLogs,
        trash,
        safariCaches,
        chromeCaches,
        firefoxCaches,
        arcCaches,
        braveCaches,
        xcodeDerivedData,
        xcodeArchives,
        xcodeDeviceSupport,
        unavailableSimulators,
        staleTempFolders,
        npmCache,
        yarnCache,
        pnpmStore,
        pipCache,
        gemCache
    ]

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    static let userCaches = CleanCategory(
        id: "user-caches",
        title: "User Caches",
        subtitle: "~/Library/Caches",
        symbol: "doc.zipper"
    ) { [home.appending(path: "Library/Caches")] }

    static let userLogs = CleanCategory(
        id: "user-logs",
        title: "User Logs",
        subtitle: "~/Library/Logs",
        symbol: "doc.text.magnifyingglass"
    ) { [home.appending(path: "Library/Logs")] }

    static let trash = CleanCategory(
        id: "trash",
        title: "Trash",
        subtitle: "~/.Trash",
        symbol: "trash"
    ) { [home.appending(path: ".Trash")] }

    static let safariCaches = CleanCategory(
        id: "safari-caches",
        title: "Safari Caches",
        subtitle: "~/Library/Caches/com.apple.Safari",
        symbol: "safari"
    ) {
        [
            home.appending(path: "Library/Caches/com.apple.Safari"),
            home.appending(path: "Library/Caches/com.apple.WebKit.WebContent")
        ]
    }

    static let chromeCaches = CleanCategory(
        id: "chrome-caches",
        title: "Chrome Caches",
        subtitle: "~/Library/Caches/Google/Chrome",
        symbol: "globe"
    ) {
        [
            home.appending(path: "Library/Caches/Google/Chrome"),
            home.appending(path: "Library/Application Support/Google/Chrome/Default/Cache")
        ]
    }

    static let firefoxCaches = CleanCategory(
        id: "firefox-caches",
        title: "Firefox Caches",
        subtitle: "~/Library/Caches/Firefox",
        symbol: "globe.americas"
    ) { [home.appending(path: "Library/Caches/Firefox")] }

    static let arcCaches = CleanCategory(
        id: "arc-caches",
        title: "Arc Caches",
        subtitle: "~/Library/Caches/Arc",
        symbol: "arrow.up.right.circle"
    ) {
        [
            home.appending(path: "Library/Caches/Arc"),
            home.appending(path: "Library/Caches/company.thebrowser.Browser")
        ]
    }

    static let braveCaches = CleanCategory(
        id: "brave-caches",
        title: "Brave Caches",
        subtitle: "~/Library/Caches/BraveSoftware",
        symbol: "shield"
    ) { [home.appending(path: "Library/Caches/BraveSoftware")] }

    static let xcodeDerivedData = CleanCategory(
        id: "xcode-derived",
        title: "Xcode DerivedData",
        subtitle: "~/Library/Developer/Xcode/DerivedData",
        symbol: "hammer",
        section: .developer
    ) { [home.appending(path: "Library/Developer/Xcode/DerivedData")] }

    static let xcodeArchives = CleanCategory(
        id: "xcode-archives",
        title: "Xcode Archives",
        subtitle: "~/Library/Developer/Xcode/Archives",
        symbol: "archivebox",
        section: .developer
    ) { [home.appending(path: "Library/Developer/Xcode/Archives")] }

    static let xcodeDeviceSupport = CleanCategory(
        id: "xcode-device-support",
        title: "Xcode Device Support",
        subtitle: "~/Library/Developer/Xcode/iOS DeviceSupport",
        symbol: "iphone",
        section: .developer
    ) {
        [
            home.appending(path: "Library/Developer/Xcode/iOS DeviceSupport"),
            home.appending(path: "Library/Developer/Xcode/watchOS DeviceSupport"),
            home.appending(path: "Library/Developer/Xcode/tvOS DeviceSupport"),
            home.appending(path: "Library/Developer/Xcode/visionOS DeviceSupport"),
            home.appending(path: "Library/Developer/Xcode/macOS DeviceSupport")
        ]
    }

    /// Simulator devices whose runtime is no longer installed. Sized from
    /// their device folders; cleaned with `xcrun simctl delete unavailable`
    /// so CoreSimulator's own device set stays consistent.
    static let unavailableSimulators = CleanCategory(
        id: "unavailable-simulators",
        title: "Unavailable Simulators",
        subtitle: "xcrun simctl delete unavailable",
        symbol: "iphone.slash",
        section: .developer,
        customClean: { await SimulatorCleaner.deleteUnavailable() }
    ) { SimulatorCleaner.unavailableDeviceDirectories() }

    /// Your own folders in /private/tmp that nothing has touched for 2+ days
    /// (old build and test output). Whole folders go to the Trash.
    static let staleTempFolders = CleanCategory(
        id: "stale-temp-folders",
        title: "Old Temp Build Folders",
        subtitle: "/private/tmp folders untouched for 2+ days",
        symbol: "folder.badge.minus",
        section: .developer,
        recyclesRootsDirectly: true
    ) { TempFolderFinder.staleFolders() }

    static let npmCache = CleanCategory(
        id: "npm-cache",
        title: "npm Cache",
        subtitle: "~/.npm",
        symbol: "shippingbox",
        section: .developer
    ) { [home.appending(path: ".npm")] }

    static let yarnCache = CleanCategory(
        id: "yarn-cache",
        title: "Yarn Cache",
        subtitle: "~/Library/Caches/Yarn",
        symbol: "shippingbox.fill",
        section: .developer
    ) {
        [
            home.appending(path: "Library/Caches/Yarn"),
            home.appending(path: ".yarn/cache")
        ]
    }

    static let pnpmStore = CleanCategory(
        id: "pnpm-store",
        title: "pnpm Store",
        subtitle: "~/Library/pnpm/store",
        symbol: "cube.box",
        section: .developer
    ) {
        [
            home.appending(path: "Library/pnpm/store"),
            home.appending(path: ".pnpm-store")
        ]
    }

    static let pipCache = CleanCategory(
        id: "pip-cache",
        title: "pip Cache",
        subtitle: "~/Library/Caches/pip",
        symbol: "ladybug",
        section: .developer
    ) { [home.appending(path: "Library/Caches/pip")] }

    /// Only RubyGems' caches, never `~/.gem` itself: that folder also holds
    /// gems installed with `--user-install` and the RubyGems API key
    /// (`~/.gem/credentials`).
    static let gemCache = CleanCategory(
        id: "gem-cache",
        title: "Gem Cache",
        subtitle: "~/.gem/specs, ~/.gem/ruby/*/cache",
        symbol: "diamond",
        section: .developer
    ) { gemCacheRoots(home: home) }

    /// RubyGems' spec cache plus the downloaded `.gem` files in each user gem
    /// directory, for both the classic `~/.gem` layout and the XDG one
    /// (`~/.cache/gem`, `~/.local/share/gem`).
    static func gemCacheRoots(home: URL) -> [URL] {
        var roots = [
            home.appending(path: ".gem/specs"),
            home.appending(path: ".cache/gem/specs")
        ]
        for gemHome in [".gem/ruby", ".local/share/gem/ruby"] {
            let versions = (try? FileManager.default.contentsOfDirectory(
                at: home.appending(path: gemHome),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            roots += versions
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .map { $0.appending(path: "cache") }
        }
        return roots
    }
}
