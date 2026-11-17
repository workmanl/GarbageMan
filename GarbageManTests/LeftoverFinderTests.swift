import XCTest

final class LeftoverFinderTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "GarbageManUninstallerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - Pure matcher

    func test_matches_exact_bundle_id() {
        XCTAssertTrue(LeftoverFinder.matches(name: "com.example.app", mode: .standard, bundle: bundleFixture()))
    }

    func test_matches_bundle_id_prefix_with_dot() {
        XCTAssertTrue(LeftoverFinder.matches(name: "com.example.app.helper", mode: .standard, bundle: bundleFixture()))
    }

    func test_matches_team_prefix_group_container() {
        XCTAssertTrue(LeftoverFinder.matches(name: "ABCDE12345.com.example.app", mode: .standard, bundle: bundleFixture()))
    }

    func test_matches_display_name_in_standard_mode() {
        XCTAssertTrue(LeftoverFinder.matches(name: "Example", mode: .standard, bundle: bundleFixture()))
        XCTAssertTrue(LeftoverFinder.matches(name: "example", mode: .standard, bundle: bundleFixture()))
        XCTAssertTrue(LeftoverFinder.matches(name: "Example.plist", mode: .standard, bundle: bundleFixture()))
    }

    func test_does_not_match_unrelated_name() {
        XCTAssertFalse(LeftoverFinder.matches(name: "com.other.app", mode: .standard, bundle: bundleFixture()))
        XCTAssertFalse(LeftoverFinder.matches(name: "Examplary", mode: .standard, bundle: bundleFixture()))
    }

    func test_launch_plist_mode_requires_plist_suffix() {
        XCTAssertTrue(LeftoverFinder.matches(name: "com.example.app.plist", mode: .launchPlist, bundle: bundleFixture()))
        XCTAssertTrue(LeftoverFinder.matches(name: "com.example.app.helper.plist", mode: .launchPlist, bundle: bundleFixture()))
        XCTAssertFalse(LeftoverFinder.matches(name: "Example.plist", mode: .launchPlist, bundle: bundleFixture()))
    }

    // MARK: - Filesystem search

    func test_find_in_root_picks_up_only_matching_children() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: tmp.appending(path: "com.example.app"), withIntermediateDirectories: true)
        try fm.createDirectory(at: tmp.appending(path: "com.other.app"), withIntermediateDirectories: true)
        try Data().write(to: tmp.appending(path: "Example.plist"))
        try Data().write(to: tmp.appending(path: "random.txt"))

        let root = LeftoverFinder.SearchRoot(title: "Test", url: tmp, mode: .standard)
        let hits = LeftoverFinder.find(in: root, for: bundleFixture())

        let names = Set(hits.map(\.displayName))
        XCTAssertEqual(names, ["com.example.app", "Example.plist"])
    }

    func test_find_in_root_classifies_kind() throws {
        try FileManager.default.createDirectory(at: tmp.appending(path: "com.example.app"), withIntermediateDirectories: true)
        try Data().write(to: tmp.appending(path: "com.example.app.plist"))

        let root = LeftoverFinder.SearchRoot(title: "Test", url: tmp, mode: .standard)
        let hits = LeftoverFinder.find(in: root, for: bundleFixture())
        let dirs = hits.filter { $0.kind == .directory }.map(\.displayName)
        let files = hits.filter { $0.kind == .file }.map(\.displayName)
        XCTAssertEqual(Set(dirs), ["com.example.app"])
        XCTAssertEqual(Set(files), ["com.example.app.plist"])
    }

    func test_find_returns_empty_for_missing_root() {
        let root = LeftoverFinder.SearchRoot(title: "Missing", url: tmp.appending(path: "nope"), mode: .standard)
        let hits = LeftoverFinder.find(in: root, for: bundleFixture())
        XCTAssertTrue(hits.isEmpty)
    }

    // MARK: - helpers

    // MARK: - Tightened matching (security review 2026-11-17)

    func test_does_not_match_id_as_substring() {
        // `com.example.app` must not claim `com.example.appstore` or a name that merely contains it.
        XCTAssertFalse(LeftoverFinder.matches(name: "com.example.appstore", mode: .standard, bundle: bundleFixture()))
        XCTAssertFalse(LeftoverFinder.matches(name: "backup-com.example.app-old", mode: .standard, bundle: bundleFixture()))
    }

    func test_matches_group_container_forms() {
        XCTAssertTrue(LeftoverFinder.matches(name: "group.com.example.app", mode: .standard, bundle: bundleFixture()))
        XCTAssertTrue(LeftoverFinder.matches(name: "ABCDE12345.com.example.app.shared", mode: .standard, bundle: bundleFixture()))
        XCTAssertFalse(LeftoverFinder.matches(name: "AB.com.example.app", mode: .standard, bundle: bundleFixture()))
        // Team IDs are exactly 10 uppercase letters or digits.
        XCTAssertFalse(LeftoverFinder.matches(name: "ABCD12.com.example.app", mode: .standard, bundle: bundleFixture()))
        XCTAssertFalse(LeftoverFinder.matches(name: "abcde12345.com.example.app", mode: .standard, bundle: bundleFixture()))
    }

    func test_refuses_apple_and_generic_bundle_ids() {
        let safari = AppBundle(url: URL(fileURLWithPath: "/Applications/Safari.app"), bundleIdentifier: "com.apple.Safari", displayName: "Safari")
        XCTAssertFalse(LeftoverFinder.matches(name: "com.apple.Safari", mode: .standard, bundle: safari))
        XCTAssertFalse(LeftoverFinder.matches(name: "Safari", mode: .standard, bundle: safari))

        let generic = AppBundle(url: URL(fileURLWithPath: "/Applications/X.app"), bundleIdentifier: "app", displayName: "Example")
        XCTAssertFalse(LeftoverFinder.matches(name: "app", mode: .standard, bundle: generic))
        XCTAssertFalse(LeftoverFinder.isMatchableBundleID("a.b"))
        XCTAssertFalse(LeftoverFinder.isMatchableBundleID("com..example"))
        XCTAssertTrue(LeftoverFinder.isMatchableBundleID("com.example.app"))
        // A bare vendor prefix would sweep up every app from that vendor.
        XCTAssertFalse(LeftoverFinder.isMatchableBundleID("com.vendor"))
        XCTAssertFalse(LeftoverFinder.isMatchableBundleID("com.apple"))
        XCTAssertFalse(LeftoverFinder.isMatchableBundleID("group.com.example.app"))
        XCTAssertFalse(LeftoverFinder.isMatchableBundleID("ABCDE12345.com.example.app"))
        XCTAssertFalse(LeftoverFinder.isMatchableBundleID("net.evil.com.apple.Safari"))
    }

    func test_never_offers_apple_files() {
        XCTAssertFalse(LeftoverFinder.matches(name: "com.apple.example.app", mode: .standard, bundle: bundleFixture()))
    }

    func test_short_display_names_are_not_matched() {
        let tv = AppBundle(url: URL(fileURLWithPath: "/Applications/TV.app"), bundleIdentifier: "com.example.tvapp", displayName: "TV")
        XCTAssertFalse(LeftoverFinder.matches(name: "TV", mode: .standard, bundle: tv))
        XCTAssertTrue(LeftoverFinder.matches(name: "com.example.tvapp", mode: .standard, bundle: tv))
    }

    private func bundleFixture() -> AppBundle {
        AppBundle(
            url: URL(fileURLWithPath: "/Applications/Example.app"),
            bundleIdentifier: "com.example.app",
            displayName: "Example"
        )
    }
}
