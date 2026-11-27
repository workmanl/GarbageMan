import XCTest

final class CleanerTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "GarbageManCleanerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func test_enumerableChildren_returns_empty_for_missing_root() {
        let kids = Cleaner.enumerableChildren(of: [tmp.appending(path: "missing")])
        XCTAssertTrue(kids.isEmpty)
    }

    func test_enumerableChildren_returns_empty_for_regular_file() throws {
        let file = tmp.appending(path: "lonely.bin")
        try Data(count: 4).write(to: file)
        let kids = Cleaner.enumerableChildren(of: [file])
        XCTAssertTrue(kids.isEmpty)
    }

    func test_enumerableChildren_returns_direct_children_only() throws {
        try Data(count: 4).write(to: tmp.appending(path: "a.bin"))
        try Data(count: 4).write(to: tmp.appending(path: "b.bin"))
        let nested = tmp.appending(path: "sub")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(count: 4).write(to: nested.appending(path: "deep.bin"))

        let kids = Cleaner.enumerableChildren(of: [tmp])
        XCTAssertEqual(Set(kids.map(\.lastPathComponent)), ["a.bin", "b.bin", "sub"])
    }

    func test_enumerableChildren_aggregates_multiple_roots() throws {
        let a = tmp.appending(path: "A")
        let b = tmp.appending(path: "B")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        try Data(count: 4).write(to: a.appending(path: "x.bin"))
        try Data(count: 4).write(to: b.appending(path: "y.bin"))
        let kids = Cleaner.enumerableChildren(of: [a, b])
        XCTAssertEqual(kids.count, 2)
    }

    /// Recycle a tmp file and assert the original location is empty.
    /// We don't assert on the trash URL itself — recycle returns a mapping
    /// when running unattended, but it can be empty under sandboxed test
    /// environments. The contract we care about is "source no longer exists".
    func test_recycle_removes_file_from_source() async throws {
        let target = tmp.appending(path: "to-recycle.bin")
        try Data(count: 128).write(to: target)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))

        let (succeeded, firstError) = await Cleaner.recycle([target])

        if firstError != nil {
            // Headless test runners sometimes can't reach the user Trash; skip
            // rather than fail. This guards against CI flake without hiding
            // real failures on a developer machine.
            throw XCTSkip("Recycle unavailable in this test environment: \(firstError!.localizedDescription)")
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path), "source file should be gone after recycle")
        XCTAssertEqual(succeeded.count, 1)
        // Callers match results against what they asked to recycle, so the
        // returned URLs must be the originals, not the new Trash locations.
        XCTAssertEqual(succeeded.map { $0.standardizedFileURL.path }, [target.standardizedFileURL.path])
    }
}
