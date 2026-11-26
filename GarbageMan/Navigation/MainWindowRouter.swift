import Foundation

/// Gets the main window on screen showing a given section. When the user has
/// closed the main window, SwiftUI destroys it, so the router opens a new one
/// and remembers the section until that window appears.
@MainActor
final class MainWindowRouter {
    static let shared = MainWindowRouter()

    /// Scene id of the main `WindowGroup`.
    static let windowID = "main"

    /// Opens a new main window. SwiftUI's `openWindow` is only reachable from
    /// a view, so the main window's view sets this when it appears.
    var openWindow: (() -> Void)?

    /// The section a window being opened by `show` should start on.
    private(set) var pendingFeature: Feature?

    private let center: NotificationCenter

    init(center: NotificationCenter = .default) {
        self.center = center
    }

    /// Show `feature` in the main window. `bringExistingWindowToFront` brings
    /// the open main window forward and returns `false` when there is none, in
    /// which case a new window is opened.
    func show(_ feature: Feature, bringExistingWindowToFront: () -> Bool) {
        if !bringExistingWindowToFront() {
            // The new window may appear before or after the notification below,
            // so it also checks `takePendingFeature()` when it appears.
            pendingFeature = feature
            openWindow?()
        }
        feature.requestShow(in: center)
    }

    /// The section a newly appeared window should switch to, if any. Each
    /// request is handed out once, so a later Dock reopen starts on the default
    /// section.
    func takePendingFeature() -> Feature? {
        defer { pendingFeature = nil }
        return pendingFeature
    }
}
