import XCTest

@MainActor
final class QuickCleanSectionsTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "GarbageManSections-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func category(_ id: String, _ section: CleanCategory.Section, exists: Bool) throws -> CleanCategory {
        let url = tmp.appending(path: id)
        if exists {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return CleanCategory(id: id, title: id, subtitle: "", symbol: "folder", section: section) { [url] }
    }

    func test_developer_section_is_hidden_when_no_developer_tool_exists() throws {
        let model = QuickCleanModel(categories: [
            try category("caches", .general, exists: true),
            try category("npm", .developer, exists: false),
            try category("xcode", .developer, exists: false)
        ])

        XCTAssertEqual(model.sections.map(\.section), [.general])
        XCTAssertEqual(model.visibleRows.map(\.id), ["caches"])
        XCTAssertEqual(model.selectedCount, 1)
    }

    func test_developer_section_shows_all_its_rows_when_one_tool_exists() throws {
        let model = QuickCleanModel(categories: [
            try category("caches", .general, exists: true),
            try category("npm", .developer, exists: true),
            try category("xcode", .developer, exists: false)
        ])

        XCTAssertEqual(model.sections.map(\.section), [.general, .developer])
        XCTAssertEqual(model.sections.last?.rows.map(\.id), ["npm", "xcode"])
        XCTAssertEqual(model.visibleRows.count, 3)
    }

    func test_general_section_shows_even_when_nothing_is_installed() throws {
        let model = QuickCleanModel(categories: [
            try category("firefox", .general, exists: false)
        ])

        XCTAssertEqual(model.sections.map(\.section), [.general])
    }

    func test_developer_section_appears_after_rescan_once_a_tool_is_installed() async throws {
        let late = try category("pip", .developer, exists: false)
        let model = QuickCleanModel(categories: [
            try category("caches", .general, exists: true),
            late
        ])
        XCTAssertEqual(model.sections.map(\.section), [.general])

        try FileManager.default.createDirectory(at: tmp.appending(path: "pip"), withIntermediateDirectories: true)
        await model.scan()

        XCTAssertEqual(model.sections.map(\.section), [.general, .developer])
    }

    func test_built_in_developer_categories() {
        let developer = CleanCategory.all.filter { $0.section == .developer }.map(\.id)
        XCTAssertEqual(developer, [
            "xcode-derived", "xcode-archives", "xcode-device-support",
            "unavailable-simulators", "stale-temp-folders",
            "npm-cache", "yarn-cache", "pnpm-store", "pip-cache", "gem-cache"
        ])
        XCTAssertTrue(CleanCategory.userCaches.section == .general)
        XCTAssertTrue(CleanCategory.trash.section == .general)
    }
}
