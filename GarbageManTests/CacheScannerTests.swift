import XCTest

final class CacheScannerTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "GarbageManTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func test_size_of_empty_dir_is_zero() async throws {
        let bytes = await CacheScanner.size(of: [tmp])
        XCTAssertEqual(bytes, 0)
    }

    func test_size_of_missing_url_is_zero() async throws {
        let bogus = tmp.appending(path: "does-not-exist")
        let bytes = await CacheScanner.size(of: [bogus])
        XCTAssertEqual(bytes, 0)
    }

    func test_size_of_flat_dir_with_three_files() async throws {
        try writeFile(at: tmp.appending(path: "a.bin"), byteCount: 1024)
        try writeFile(at: tmp.appending(path: "b.bin"), byteCount: 2048)
        try writeFile(at: tmp.appending(path: "c.bin"), byteCount: 4096)
        let bytes = await CacheScanner.size(of: [tmp])
        // Allocated size may round up vs logical size; assert at least 7 KB and under 64 KB slack.
        XCTAssertGreaterThanOrEqual(bytes, 7 * 1024)
        XCTAssertLessThan(bytes, 64 * 1024)
    }

    func test_size_of_nested_dir_recurses() async throws {
        let nested = tmp.appending(path: "sub/sub2")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try writeFile(at: nested.appending(path: "deep.bin"), byteCount: 8192)
        let bytes = await CacheScanner.size(of: [tmp])
        XCTAssertGreaterThanOrEqual(bytes, 8 * 1024)
    }

    func test_size_skips_symlinks() async throws {
        let realFile = tmp.appending(path: "real.bin")
        try writeFile(at: realFile, byteCount: 16 * 1024)

        let outside = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "GarbageManTests-outside-\(UUID().uuidString).bin")
        try writeFile(at: outside, byteCount: 1024 * 1024)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(
            at: tmp.appending(path: "link-to-outside.bin"),
            withDestinationURL: outside
        )

        let bytes = await CacheScanner.size(of: [tmp])
        // Should pick up the 16 KB real file and SKIP the 1 MB symlink target.
        XCTAssertGreaterThanOrEqual(bytes, 16 * 1024)
        XCTAssertLessThan(bytes, 256 * 1024)
    }

    func test_size_sums_multiple_roots() async throws {
        let a = tmp.appending(path: "rootA")
        let b = tmp.appending(path: "rootB")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        try writeFile(at: a.appending(path: "x.bin"), byteCount: 4096)
        try writeFile(at: b.appending(path: "y.bin"), byteCount: 4096)
        let bytes = await CacheScanner.size(of: [a, b])
        XCTAssertGreaterThanOrEqual(bytes, 8 * 1024)
    }

    // MARK: - helpers

    private func writeFile(at url: URL, byteCount: Int) throws {
        let data = Data(count: byteCount)
        try data.write(to: url)
    }
}
