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
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
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
        recyclesRootsDirectly: Bool = false,
        customClean: (() async -> CustomCleanOutcome)? = nil,
        pathProvider: @escaping () -> [URL]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
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
        symbol: "hammer"
    ) { [home.appending(path: "Library/Developer/Xcode/DerivedData")] }

    static let xcodeArchives = CleanCategory(
        id: "xcode-archives",
        title: "Xcode Archives",
        subtitle: "~/Library/Developer/Xcode/Archives",
        symbol: "archivebox"
    ) { [home.appending(path: "Library/Developer/Xcode/Archives")] }

    static let xcodeDeviceSupport = CleanCategory(
        id: "xcode-device-support",
        title: "Xcode Device Support",
        subtitle: "~/Library/Developer/Xcode/iOS DeviceSupport",
        symbol: "iphone"
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
        customClean: { await SimulatorCleaner.deleteUnavailable() }
    ) { SimulatorCleaner.unavailableDeviceDirectories() }

    /// Your own folders in /private/tmp that nothing has touched for 2+ days
    /// (old build and test output). Whole folders go to the Trash.
    static let staleTempFolders = CleanCategory(
        id: "stale-temp-folders",
        title: "Old Temp Build Folders",
        subtitle: "/private/tmp folders untouched for 2+ days",
        symbol: "folder.badge.minus",
        recyclesRootsDirectly: true
    ) { TempFolderFinder.staleFolders() }

    static let npmCache = CleanCategory(
        id: "npm-cache",
        title: "npm Cache",
        subtitle: "~/.npm",
        symbol: "shippingbox"
    ) { [home.appending(path: ".npm")] }

    static let yarnCache = CleanCategory(
        id: "yarn-cache",
        title: "Yarn Cache",
        subtitle: "~/Library/Caches/Yarn",
        symbol: "shippingbox.fill"
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
        symbol: "cube.box"
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
        symbol: "ladybug"
    ) { [home.appending(path: "Library/Caches/pip")] }

    static let gemCache = CleanCategory(
        id: "gem-cache",
        title: "Gem Cache",
        subtitle: "~/.gem",
        symbol: "diamond"
    ) { [home.appending(path: ".gem")] }
}
