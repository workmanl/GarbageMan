import XCTest

@MainActor
final class MainWindowRouterTests: XCTestCase {

    private var center: NotificationCenter!
    private var router: MainWindowRouter!
    private var opened = 0
    private var shown: [Feature] = []
    private var token: NSObjectProtocol?

    override func setUp() async throws {
        center = NotificationCenter()
        router = MainWindowRouter(center: center)
        router.openWindow = { [unowned self] in self.opened += 1 }
        token = center.addObserver(forName: .showFeature, object: nil, queue: nil) { [unowned self] note in
            if let feature = Feature(showRequest: note) { self.shown.append(feature) }
        }
    }

    override func tearDown() async throws {
        if let token { center.removeObserver(token) }
    }

    func test_open_window_is_brought_forward_not_duplicated() {
        var broughtForward = 0
        router.show(.diskInspector) { broughtForward += 1; return true }

        XCTAssertEqual(broughtForward, 1)
        XCTAssertEqual(opened, 0)
        XCTAssertEqual(shown, [.diskInspector])
        XCTAssertNil(router.takePendingFeature(), "an open window gets the notification; nothing to hold")
    }

    func test_closed_window_is_reopened() {
        router.show(.uninstaller) { false }

        XCTAssertEqual(opened, 1)
        XCTAssertEqual(shown, [.uninstaller])
    }

    func test_new_window_picks_up_the_requested_section() {
        // A window created by `show` may appear after the notification went out.
        router.show(.uninstaller) { false }

        XCTAssertEqual(router.takePendingFeature(), .uninstaller)
    }

    func test_request_is_handed_out_once() {
        router.show(.diskInspector) { false }
        _ = router.takePendingFeature()

        XCTAssertNil(router.takePendingFeature(), "a later Dock reopen must not jump to an old section")
    }

    func test_latest_request_wins() {
        router.show(.uninstaller) { false }
        router.show(.diskInspector) { false }

        XCTAssertEqual(router.takePendingFeature(), .diskInspector)
    }

    func test_no_opener_yet_does_not_crash() {
        router.openWindow = nil
        router.show(.quickClean) { false }

        XCTAssertEqual(shown, [.quickClean])
        XCTAssertEqual(router.takePendingFeature(), .quickClean)
    }
}
