import AppKit
import SwiftUI

/// Custom About panel hosted via `NSHostingView` so it can use SwiftUI
/// without becoming a top-level `Scene` in the app structure. A single
/// shared instance is reused so re-opening just brings the existing panel
/// forward.
@MainActor
final class AboutWindow {

    static let shared = AboutWindow()

    private var panel: NSPanel?

    func present() {
        if let panel {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let host = NSHostingView(rootView: AboutView())
        host.translatesAutoresizingMaskIntoConstraints = false

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 380),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "About GarbageMan"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.center()
        panel.contentView = host

        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}
