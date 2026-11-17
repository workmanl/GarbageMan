import XCTest

final class TempFolderFinderTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "TempFolderFinderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeFolder(_ name: String, age: TimeInterval, childAge: TimeInterval? = nil) throws -> URL {
        let fm = FileManager.default
        let dir = root.appending(path: name)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if let childAge {
            let file = dir.appending(path: "child.txt")
            try Data("x".utf8).write(to: file)
            try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -childAge)], ofItemAtPath: file.path)
        }
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -age)], ofItemAtPath: dir.path)
        return dir
    }

    func testFindsOnlyOldUnprotectedFolders() throws {
        let threeDays: TimeInterval = 3 * 24 * 3600
        _ = try makeFolder("old-build", age: threeDays, childAge: threeDays)
        _ = try makeFolder("fresh-build", age: 60, childAge: 60)
        _ = try makeFolder("claude-501", age: threeDays)
        _ = try makeFolder("com.apple.launchd.x", age: threeDays)
        // Folder itself old, but a child was written recently: still active.
        _ = try makeFolder("old-folder-new-child", age: threeDays, childAge: 60)
        // A plain old file is never a candidate.
        let file = root.appending(path: "old-file.txt")
        try Data("x".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -threeDays)], ofItemAtPath: file.path)

        let found = TempFolderFinder.staleFolders(root: root).map(\.lastPathComponent)
        XCTAssertEqual(found, ["old-build"])
    }

    func testSkipsFoldersOwnedBySomeoneElse() throws {
        _ = try makeFolder("old-build", age: 3 * 24 * 3600)
        let found = TempFolderFinder.staleFolders(root: root, ownerUID: getuid() &+ 1)
        XCTAssertTrue(found.isEmpty)
    }

    func testMissingRootReturnsEmpty() {
        let missing = root.appending(path: "does-not-exist")
        XCTAssertTrue(TempFolderFinder.staleFolders(root: missing).isEmpty)
    }
}
