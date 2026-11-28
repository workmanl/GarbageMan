import XCTest

final class FolderSizerTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "GarbageManFolderSizerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func test_contents_returns_empty_for_missing_root() async {
        let missing = tmp.appending(path: "no-such-dir")
        let entries = await FolderSizer.contents(of: missing)
        XCTAssertTrue(entries.isEmpty)
    }

    func test_contents_sorts_descending_by_size() async throws {
        let small = tmp.appending(path: "small")
        let medium = tmp.appending(path: "medium")
        let big = tmp.appending(path: "big")
        try FileManager.default.createDirectory(at: small, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: medium, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: big, withIntermediateDirectories: true)
        try Data(count: 1 * 1024).write(to: small.appending(path: "f.bin"))
        try Data(count: 64 * 1024).write(to: medium.appending(path: "f.bin"))
        try Data(count: 512 * 1024).write(to: big.appending(path: "f.bin"))

        let entries = await FolderSizer.contents(of: tmp)
        XCTAssertEqual(entries.map(\.displayName), ["big", "medium", "small"])
        XCTAssertGreaterThan(entries[0].size, entries[1].size)
        XCTAssertGreaterThan(entries[1].size, entries[2].size)
    }

    func test_contents_distinguishes_files_and_directories() async throws {
        let folder = tmp.appending(path: "subdir")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(count: 4096).write(to: folder.appending(path: "inside.bin"))
        try Data(count: 4096).write(to: tmp.appending(path: "lone.bin"))

        let entries = await FolderSizer.contents(of: tmp)
        let folderEntry = entries.first { $0.displayName == "subdir" }
        let fileEntry = entries.first { $0.displayName == "lone.bin" }
        XCTAssertEqual(folderEntry?.isDirectory, true)
        XCTAssertEqual(fileEntry?.isDirectory, false)
    }

    func test_contents_skips_symlinks() async throws {
        let real = tmp.appending(path: "real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try Data(count: 4096).write(to: real.appending(path: "inside.bin"))

        let outside = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "FolderSizerLinkTarget-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: tmp.appending(path: "link"), withDestinationURL: outside)

        let entries = await FolderSizer.contents(of: tmp)
        let names = entries.map(\.displayName)
        XCTAssertTrue(names.contains("real"))
        XCTAssertFalse(names.contains("link"))
    }

    func test_child_size_includes_hidden_folders_inside_it() async throws {
        // A project folder whose bulk is in a hidden `.git` folder.
        let project = tmp.appending(path: "project")
        let gitObjects = project.appending(path: ".git/objects")
        try FileManager.default.createDirectory(at: gitObjects, withIntermediateDirectories: true)
        try Data(count: 4096).write(to: project.appending(path: "main.swift"))
        try Data(count: 768 * 1024).write(to: gitObjects.appending(path: "pack.bin"))
        // Hidden direct children of the inspected folder are still not listed.
        try Data(count: 1024).write(to: tmp.appending(path: ".DS_Store"))

        let entries = await FolderSizer.contents(of: tmp)
        XCTAssertEqual(entries.map(\.displayName), ["project"])
        XCTAssertGreaterThanOrEqual(entries[0].size, 768 * 1024 + 4096)
    }
}
