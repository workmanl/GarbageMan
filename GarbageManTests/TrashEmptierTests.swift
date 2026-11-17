import XCTest

final class TrashEmptierTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "GarbageManTrashEmptierTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func test_empty_removes_every_child_but_keeps_root() throws {
        try Data(count: 2048).write(to: tmp.appending(path: "a.bin"))
        try Data(count: 4096).write(to: tmp.appending(path: "b.bin"))
        let nested = tmp.appending(path: "sub")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(count: 8192).write(to: nested.appending(path: "deep.bin"))

        let outcome = TrashEmptier.empty(root: tmp)

        XCTAssertEqual(outcome.removed, 3)
        XCTAssertEqual(outcome.failed, 0)
        XCTAssertNil(outcome.firstError)
        XCTAssertGreaterThanOrEqual(outcome.bytesReclaimed, 14 * 1024)

        // Root still exists, children gone.
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.path))
        let kids = try FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)
        XCTAssertTrue(kids.isEmpty)
    }

    func test_empty_handles_missing_root() {
        let bogus = tmp.appending(path: "no-such-dir")
        let outcome = TrashEmptier.empty(root: bogus)
        XCTAssertEqual(outcome.removed, 0)
        XCTAssertEqual(outcome.failed, 0)
        XCTAssertNotNil(outcome.firstError)
    }

    func test_empty_when_root_is_empty() {
        let outcome = TrashEmptier.empty(root: tmp)
        XCTAssertEqual(outcome.removed, 0)
        XCTAssertEqual(outcome.failed, 0)
        XCTAssertEqual(outcome.bytesReclaimed, 0)
        XCTAssertNil(outcome.firstError)
    }

    func test_empty_does_not_follow_symlinks_when_removing() throws {
        let realTarget = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "TrashEmptier-symlink-target-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: realTarget, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: realTarget) }
        let payload = realTarget.appending(path: "important.bin")
        try Data(count: 4096).write(to: payload)

        try FileManager.default.createSymbolicLink(at: tmp.appending(path: "link"), withDestinationURL: realTarget)

        _ = TrashEmptier.empty(root: tmp)

        // The symlink should be gone but the original target should still exist.
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.appending(path: "link").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: payload.path))
    }
}
