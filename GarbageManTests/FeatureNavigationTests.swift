import XCTest

final class FeatureNavigationTests: XCTestCase {

    func test_menu_bar_opens_each_built_section_with_its_own_key() {
        let shortcuts = Feature.menuBarShortcuts
        XCTAssertEqual(shortcuts.map(\.feature), [.quickClean, .uninstaller, .diskInspector])
        XCTAssertEqual(shortcuts.map(\.key), ["1", "2", "3"])
    }

    func test_menu_titles_match_section_titles() {
        XCTAssertEqual(Feature.quickClean.menuTitle, "Quick Clean…")
        XCTAssertEqual(Feature.uninstaller.menuTitle, "Uninstaller…")
        XCTAssertEqual(Feature.diskInspector.menuTitle, "Disk Inspector…")
    }

    func test_show_request_round_trips_every_section() {
        let center = NotificationCenter()
        var received: [Feature] = []
        let token = center.addObserver(forName: .showFeature, object: nil, queue: nil) { note in
            if let feature = Feature(showRequest: note) { received.append(feature) }
        }
        defer { center.removeObserver(token) }

        for feature in Feature.allCases { feature.requestShow(in: center) }

        XCTAssertEqual(received, Feature.allCases)
    }

    func test_unknown_section_is_ignored() {
        let note = Notification(name: .showFeature, object: "trashCompactor")
        XCTAssertNil(Feature(showRequest: note))
    }

    func test_other_notifications_are_ignored() {
        let note = Notification(name: Notification.Name("SomethingElse"), object: Feature.uninstaller.rawValue)
        XCTAssertNil(Feature(showRequest: note))
    }
}
