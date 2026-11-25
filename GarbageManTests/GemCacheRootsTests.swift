import XCTest

final class GemCacheRootsTests: XCTestCase {

    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appending(path: "GemCacheRootsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func make(_ path: String, file: Bool = false) throws {
        let url = home.appending(path: path)
        if file {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
        } else {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func paths(_ urls: [URL]) -> [String] {
        // Listings can return /private/var/... for a /var/... home, so match
        // on the unique folder name rather than the full prefix.
        urls.map { $0.path.components(separatedBy: home.lastPathComponent).last ?? $0.path }
    }

    func test_only_spec_cache_and_gem_file_caches_are_roots() throws {
        try make(".gem/credentials", file: true)
        try make(".gem/specs/index.rubygems.org%443")
        try make(".gem/ruby/3.3.0/gems/rake-13.2.1")
        try make(".gem/ruby/3.3.0/specifications")
        try make(".gem/ruby/3.3.0/cache")
        try make(".gem/ruby/2.6.0/cache")

        let roots = CleanCategory.gemCacheRoots(home: home).filter {
            FileManager.default.fileExists(atPath: $0.path)
        }

        XCTAssertEqual(paths(roots), [
            "/.gem/specs",
            "/.gem/ruby/2.6.0/cache",
            "/.gem/ruby/3.3.0/cache"
        ])
    }

    func test_cleaning_the_roots_leaves_installed_gems_and_credentials() throws {
        try make(".gem/credentials", file: true)
        try make(".gem/ruby/3.3.0/gems/rake-13.2.1/lib/rake.rb", file: true)
        try make(".gem/ruby/3.3.0/cache/rake-13.2.1.gem", file: true)

        let children = Cleaner.enumerableChildren(of: CleanCategory.gemCacheRoots(home: home))

        XCTAssertEqual(paths(children), ["/.gem/ruby/3.3.0/cache/rake-13.2.1.gem"])
    }

    func test_xdg_layout_is_covered() throws {
        try make(".cache/gem/specs/index.rubygems.org%443")
        try make(".local/share/gem/ruby/3.4.0/gems/json-2.9.1")
        try make(".local/share/gem/ruby/3.4.0/cache")

        let roots = CleanCategory.gemCacheRoots(home: home).filter {
            FileManager.default.fileExists(atPath: $0.path)
        }

        XCTAssertEqual(paths(roots), [
            "/.cache/gem/specs",
            "/.local/share/gem/ruby/3.4.0/cache"
        ])
    }

    func test_no_ruby_folders_means_nothing_to_clean() {
        let existing = CleanCategory.gemCacheRoots(home: home).filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        XCTAssertTrue(existing.isEmpty)
    }
}
