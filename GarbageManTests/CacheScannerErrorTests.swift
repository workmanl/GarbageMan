import XCTest

final class CacheScannerErrorTests: XCTestCase {

    private var tmp: URL!
    private var unreadable: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "GarbageManScannerErrorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        // Readable file we expect to be sized.
        try Data(count: 8 * 1024).write(to: tmp.appending(path: "readable.bin"))

        // Unreadable subdirectory: create it, drop a file inside, then
        // chmod 000 the subdir so the scanner can't enumerate it.
        unreadable = tmp.appending(path: "locked")
        try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: true)
        try Data(count: 4 * 1024).write(to: unreadable.appending(path: "secret.bin"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.path)
    }

    override func tearDownWithError() throws {
        // Restore permissions so cleanup can run.
        if let u = unreadable, FileManager.default.fileExists(atPath: u.path) {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: u.path)
        }
        try? FileManager.default.removeItem(at: tmp)
    }

    func test_detailed_reports_unreadable_subpath_but_still_counts_readable_bytes() async throws {
        try XCTSkipIf(getuid() == 0, "Skipped under root — chmod 000 doesn't block root reads.")

        let result = await CacheScanner.detailed(of: [tmp])

        XCTAssertGreaterThanOrEqual(result.bytes, 8 * 1024, "Readable file should still be counted.")
        XCTAssertFalse(result.unreadablePaths.isEmpty, "Locked subdir should surface as unreadable.")
        let paths = result.unreadablePaths.map(\.path)
        XCTAssertTrue(
            paths.contains(where: { $0.contains("/locked") }),
            "Expected /locked in error list, got: \(paths)"
        )
    }

    func test_size_convenience_drops_error_list() async {
        let bytes = await CacheScanner.size(of: [tmp])
        XCTAssertGreaterThanOrEqual(bytes, 8 * 1024)
    }
}
