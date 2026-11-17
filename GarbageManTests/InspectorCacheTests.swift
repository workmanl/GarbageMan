import XCTest

final class InspectorCacheTests: XCTestCase {

    private var tmp: URL!
    private var cacheURL: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "GarbageManInspectorCacheTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        cacheURL = tmp.appending(path: "cache.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func test_load_returns_empty_when_file_absent() {
        let cache = InspectorCache(fileURL: cacheURL)
        XCTAssertTrue(cache.load().isEmpty)
    }

    func test_save_then_load_round_trip() throws {
        let cache = InspectorCache(fileURL: cacheURL)
        let now = Date()
        let snapshots: [String: InspectorCache.Snapshot] = [
            "/Users/test": .init(
                scannedAt: now,
                children: [
                    .init(path: "/Users/test/Downloads", size: 1024, isDirectory: true),
                    .init(path: "/Users/test/file.bin", size: 2048, isDirectory: false)
                ]
            )
        ]
        try cache.save(snapshots)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path))

        let loaded = cache.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded["/Users/test"]?.children.count, 2)
        XCTAssertEqual(loaded["/Users/test"]?.children.first?.path, "/Users/test/Downloads")
        XCTAssertEqual(loaded["/Users/test"]?.children.first?.isDirectory, true)

        // Date round-trip is ISO8601, so equal to the nearest second.
        let stored = loaded["/Users/test"]!.scannedAt
        XCTAssertLessThan(abs(stored.timeIntervalSince(now)), 1.0)
    }

    func test_load_ignores_unknown_version() throws {
        let payload = """
        { "version": 99, "snapshots": {} }
        """.data(using: .utf8)!
        try payload.write(to: cacheURL)
        let cache = InspectorCache(fileURL: cacheURL)
        XCTAssertTrue(cache.load().isEmpty)
    }

    func test_load_recovers_from_corrupt_file() throws {
        try "not even valid JSON".data(using: .utf8)!.write(to: cacheURL)
        let cache = InspectorCache(fileURL: cacheURL)
        XCTAssertTrue(cache.load().isEmpty)
    }

    func test_snapshot_round_trips_through_folder_sizer_adapter() {
        let cache = InspectorCache(fileURL: cacheURL)
        let entries: [FolderSizer.Entry] = [
            .init(url: URL(fileURLWithPath: "/a"), isDirectory: true, size: 100),
            .init(url: URL(fileURLWithPath: "/b.bin"), isDirectory: false, size: 200)
        ]
        let snapshot = cache.snapshotAdapter(from: entries, scannedAt: Date())
        let recovered = cache.entries(from: snapshot)
        XCTAssertEqual(recovered, entries)
    }
}
