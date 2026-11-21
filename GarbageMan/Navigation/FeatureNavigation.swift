import Foundation

/// The sections of the main window.
enum Feature: String, CaseIterable, Identifiable, Hashable {
    case quickClean
    case uninstaller
    case diskInspector
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickClean: "Quick Clean"
        case .uninstaller: "Uninstaller"
        case .diskInspector: "Disk Inspector"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .quickClean: "trash.circle"
        case .uninstaller: "shippingbox"
        case .diskInspector: "externaldrive"
        case .settings: "gearshape"
        }
    }
}

extension Notification.Name {
    /// Asks the main window to switch to a section. `object` is the
    /// `Feature.rawValue` to show.
    static let showFeature = Notification.Name("GarbageMan.showFeature")
}

extension Feature {

    /// Sections the menu bar opens directly, in menu order, with their key
    /// equivalents.
    static let menuBarShortcuts: [(feature: Feature, key: String)] = [
        (.quickClean, "1"),
        (.uninstaller, "2"),
        (.diskInspector, "3")
    ]

    var menuTitle: String { "\(title)…" }

    /// Tell the main window to show this section.
    func requestShow(in center: NotificationCenter = .default) {
        center.post(name: .showFeature, object: rawValue)
    }

    /// The section a `.showFeature` notification asks for, or `nil` for any
    /// other notification.
    init?(showRequest notification: Notification) {
        guard notification.name == .showFeature,
              let raw = notification.object as? String,
              let feature = Feature(rawValue: raw) else { return nil }
        self = feature
    }
}
