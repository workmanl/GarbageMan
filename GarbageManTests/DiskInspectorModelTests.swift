import XCTest

/// Stands in for `FolderSizer`: each request waits until the test releases it,
/// so a test can decide which scan finishes first.
@MainActor
private final class GatedSizer {
    private var waiting: [String: CheckedContinuation<[FolderSizer.Entry], Never>] = [:]
    private(set) var requests: [String] = []

    func size(_ url: URL) async -> [FolderSizer.Entry] {
        requests.append(url.path)
        return await withCheckedContinuation { waiting[url.path] = $0 }
    }

    func isWaiting(on url: URL) -> Bool { waiting[url.path] != nil }

    func release(_ url: URL, with entries: [FolderSizer.Entry]) {
        waiting.removeValue(forKey: url.path)?.resume(returning: entries)
    }
}

@MainActor
final class DiskInspectorModelTests: XCTestCase {

    private var tmp: URL!
    private var root: URL!
    private var child: URL!
    private var cache: InspectorCache!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "GarbageManInspectorModel-\(UUID().uuidString)")
        root = tmp.appending(path: "root", directoryHint: .isDirectory)
        child = root.appending(path: "big", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        cache = InspectorCache(fileURL: tmp.appending(path: "cache.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func entry(_ url: URL, _ size: UInt64) -> FolderSizer.Entry {
        FolderSizer.Entry(url: url, isDirectory: true, size: size)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 where !condition() { await Task.yield() }
        XCTAssertTrue(condition(), "timed out waiting")
    }

    func test_scan_shows_result_for_the_folder_still_on_screen() async {
        let sizer = GatedSizer()
        let model = DiskInspectorModel(root: root, persistence: cache, sizer: { await sizer.size($0) })

        let scan = Task { await model.scan() }
        await waitUntil { sizer.isWaiting(on: self.root) }
        XCTAssertEqual(model.phase, .scanning)

        sizer.release(root, with: [entry(child, 500)])
        await scan.value

        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.entries.map(\.url.path), [child.path])
    }

    func test_slow_scan_finishing_after_going_up_does_not_replace_the_parent_list() async throws {
        // The parent folder is already cached, so going Up is instant.
        let parentRows = [entry(child, 500), entry(root.appending(path: "small"), 10)]
        try cache.save([root.path: cache.snapshotAdapter(from: parentRows, scannedAt: Date())])

        let sizer = GatedSizer()
        let model = DiskInspectorModel(root: root, persistence: cache, sizer: { await sizer.size($0) })
        await model.scan()
        XCTAssertEqual(model.entries.map(\.url.path), parentRows.map(\.url.path))

        // Drill into a folder that takes a while to size, then go Up before it finishes.
        let drill = Task { await model.drill(into: child) }
        await waitUntil { sizer.isWaiting(on: self.child) }
        await model.pop()
        XCTAssertEqual(model.currentRoot, root)

        let grandchild = child.appending(path: "inner")
        sizer.release(child, with: [entry(grandchild, 400)])
        await drill.value

        XCTAssertEqual(model.currentRoot, root)
        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.entries.map(\.url.path), parentRows.map(\.url.path),
                       "the late result must not show under the parent's breadcrumb")

        // The finished scan was still cached, so going back in is instant.
        await model.drill(into: child)
        XCTAssertEqual(model.entries.map(\.url.path), [grandchild.path])
        XCTAssertEqual(sizer.requests, [child.path])
    }
}
