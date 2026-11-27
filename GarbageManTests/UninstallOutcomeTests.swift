import XCTest

final class UninstallOutcomeTests: XCTestCase {

    private let app = URL(fileURLWithPath: "/Applications/Sample.app/", isDirectory: true)
    private let prefs = URL(fileURLWithPath: "/Users/test/Library/Preferences/com.example.sample.plist")
    private let caches = URL(fileURLWithPath: "/Users/test/Library/Caches/com.example.sample", isDirectory: true)

    private var sizes: [URL: UInt64] {
        [app: 500_000_000, prefs: 4_000, caches: 20_000_000]
    }

    func test_everything_moved_counts_all_bytes_and_app() {
        let o = UninstallerModel.UninstallOutcome.make(
            attempted: [app, prefs, caches], succeeded: [caches, app, prefs],
            sizes: sizes, appURL: app, error: nil
        )
        XCTAssertEqual(o.recycled, 3)
        XCTAssertEqual(o.failed, 0)
        XCTAssertEqual(o.bytesReclaimedEstimate, 520_004_000)
        XCTAssertTrue(o.appWasRecycled)
        XCTAssertFalse(o.appLeftInstalled)
    }

    /// The case that used to be wrong: the big app failed (for example a
    /// root-owned app), the small leftovers moved. Bytes must not include
    /// the app, and the outcome must say the app is still installed.
    func test_app_failed_leftovers_moved() {
        let o = UninstallerModel.UninstallOutcome.make(
            attempted: [app, prefs, caches], succeeded: [prefs, caches],
            sizes: sizes, appURL: app, error: NSError(domain: "test", code: 1)
        )
        XCTAssertEqual(o.recycled, 2)
        XCTAssertEqual(o.failed, 1)
        XCTAssertEqual(o.bytesReclaimedEstimate, 20_004_000)
        XCTAssertFalse(o.appWasRecycled)
        XCTAssertTrue(o.appLeftInstalled)
        XCTAssertNotNil(o.errorMessage)
    }

    func test_app_not_included_is_never_reported_as_left_installed() {
        let o = UninstallerModel.UninstallOutcome.make(
            attempted: [prefs], succeeded: [prefs],
            sizes: sizes, appURL: nil, error: nil
        )
        XCTAssertFalse(o.appWasIncluded)
        XCTAssertFalse(o.appWasRecycled)
        XCTAssertFalse(o.appLeftInstalled)
        XCTAssertEqual(o.bytesReclaimedEstimate, 4_000)
    }

    /// NSWorkspace can hand back a URL spelled without the trailing slash.
    func test_matching_ignores_trailing_slash_differences() {
        let appNoSlash = URL(fileURLWithPath: "/Applications/Sample.app", isDirectory: false)
        let o = UninstallerModel.UninstallOutcome.make(
            attempted: [app], succeeded: [appNoSlash],
            sizes: sizes, appURL: app, error: nil
        )
        XCTAssertTrue(o.appWasRecycled)
        XCTAssertEqual(o.bytesReclaimedEstimate, 500_000_000)
    }

    func test_nothing_attempted() {
        let o = UninstallerModel.UninstallOutcome.make(
            attempted: [], succeeded: [], sizes: [:], appURL: nil, error: nil
        )
        XCTAssertEqual(o.recycled, 0)
        XCTAssertEqual(o.failed, 0)
        XCTAssertEqual(o.bytesReclaimedEstimate, 0)
    }
}
