import XCTest

final class QuickCleanTotalsTests: XCTestCase {

    private typealias PathSize = QuickCleanModel.PathSize

    private func entry(_ path: String, _ bytes: UInt64) -> PathSize {
        PathSize(url: URL(fileURLWithPath: path), bytes: bytes)
    }

    func test_unrelated_paths_are_summed() {
        let total = QuickCleanModel.uniqueBytes(of: [
            entry("/Users/u/.npm", 100),
            entry("/Users/u/.gem", 50)
        ])
        XCTAssertEqual(total, 150)
    }

    func test_nested_path_is_counted_once() {
        let total = QuickCleanModel.uniqueBytes(of: [
            entry("/Users/u/Library/Caches/com.apple.Safari", 300),
            entry("/Users/u/Library/Caches", 1000)
        ])
        XCTAssertEqual(total, 1000)
    }

    func test_identical_paths_are_counted_once() {
        let total = QuickCleanModel.uniqueBytes(of: [
            entry("/Users/u/Library/Caches/pip", 40),
            entry("/Users/u/Library/Caches/pip/", 40)
        ])
        XCTAssertEqual(total, 40)
    }

    func test_sibling_with_shared_name_prefix_is_not_nested() {
        // "Caches-old" starts with the same characters as "Caches" but is a
        // different folder, so both count.
        let total = QuickCleanModel.uniqueBytes(of: [
            entry("/Users/u/Library/Caches", 10),
            entry("/Users/u/Library/Caches-old", 5)
        ])
        XCTAssertEqual(total, 15)
    }

    func test_empty_is_zero() {
        XCTAssertEqual(QuickCleanModel.uniqueBytes(of: []), 0)
    }

    // MARK: - Model integration

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "GarbageManTotals-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    @MainActor
    func test_selected_total_does_not_double_count_nested_category() async throws {
        let caches = tmp.appending(path: "Caches")
        let browser = caches.appending(path: "Browser")
        let outside = tmp.appending(path: "AppSupportCache")
        try FileManager.default.createDirectory(at: browser, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data(count: 64 * 1024).write(to: caches.appending(path: "top.bin"))
        try Data(count: 128 * 1024).write(to: browser.appending(path: "b.bin"))
        try Data(count: 32 * 1024).write(to: outside.appending(path: "o.bin"))

        let parent = CleanCategory(id: "parent", title: "Parent", subtitle: "", symbol: "folder") { [caches] }
        // Like Chrome: one path inside the parent, one outside it.
        let child = CleanCategory(id: "child", title: "Child", subtitle: "", symbol: "folder") { [browser, outside] }

        let model = QuickCleanModel(categories: [parent, child])
        await model.scan()

        let parentSize = try XCTUnwrap(model.rows[0].size)
        let childSize = try XCTUnwrap(model.rows[1].size)
        let outsideSize = try XCTUnwrap(model.rows[1].pathSizes.first { $0.url == outside }?.bytes)

        // Row sizes are unchanged: each row still shows everything it covers.
        XCTAssertEqual(model.rows[1].pathSizes.reduce(0) { $0 + $1.bytes }, childSize)
        // Totals count the nested Browser folder once.
        XCTAssertEqual(model.totalSelectedBytes, parentSize + outsideSize)
        XCTAssertEqual(model.totalBytes, parentSize + outsideSize)
        XCTAssertEqual(model.cleanableBytes, parentSize + outsideSize)
        XCTAssertLessThan(model.totalSelectedBytes, parentSize + childSize)

        // Deselecting the parent: the child counts in full again.
        model.setSelection(for: "parent", to: false)
        XCTAssertEqual(model.totalSelectedBytes, childSize)
    }
}
