import AppKit
import Foundation

/// Owns the menu-bar `NSStatusItem` and the small live readout shown in the
/// dropdown. The system monitor is sampled at two cadences:
///
/// - 5 s while the user has the menu open (responsive).
/// - 30 s when closed (cheap idle).
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let monitor = SystemMonitor()

    // Live menu items so we can mutate their titles each tick.
    private let cpuItem = NSMenuItem(title: "CPU…", action: nil, keyEquivalent: "")
    private let ramItem = NSMenuItem(title: "Memory…", action: nil, keyEquivalent: "")
    private let diskItem = NSMenuItem(title: "Disk…", action: nil, keyEquivalent: "")
    private let batteryItem = NSMenuItem(title: "Battery…", action: nil, keyEquivalent: "")

    private var refreshTimer: Timer?
    private var isMenuOpen = false

    private let idleInterval: TimeInterval = 30
    private let activeInterval: TimeInterval = 5

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
        configureMenu()
        scheduleTimer(interval: idleInterval)
        Task { @MainActor in
            // Initial sample so the first menu open isn't full of placeholders.
            self.monitor.refresh()
            self.applySnapshotToMenuItems()
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "trash.circle", accessibilityDescription: "GarbageMan")
            button.image?.isTemplate = true
            button.toolTip = "GarbageMan — Quick Clean"
        }
    }

    private func configureMenu() {
        menu.delegate = self

        cpuItem.isEnabled = false
        ramItem.isEnabled = false
        diskItem.isEnabled = false
        batteryItem.isEnabled = false

        menu.addItem(makeItem(title: "Quick Clean…", action: #selector(openMain), key: "1"))
        menu.addItem(makeItem(title: "Uninstaller…", action: #selector(openMain), key: "2"))
        menu.addItem(makeItem(title: "Disk Inspector…", action: #selector(openMain), key: "3"))
        menu.addItem(.separator())
        menu.addItem(headerItem("System"))
        menu.addItem(cpuItem)
        menu.addItem(ramItem)
        menu.addItem(diskItem)
        menu.addItem(batteryItem)
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "About GarbageMan", action: #selector(showAbout), key: ""))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "Quit", action: #selector(NSApp.terminate(_:)), key: "q", target: NSApp))

        statusItem.menu = menu
    }

    private func makeItem(title: String, action: Selector?, key: String, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        return item
    }

    private func headerItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        return item
    }

    @objc private func openMain() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    @objc private func showAbout() {
        AboutWindow.shared.present()
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        Task { @MainActor in
            self.monitor.refresh()
            self.applySnapshotToMenuItems()
        }
        scheduleTimer(interval: activeInterval)
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        scheduleTimer(interval: idleInterval)
    }

    // MARK: - Refresh loop

    private func scheduleTimer(interval: TimeInterval) {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.monitor.refresh()
                self.applySnapshotToMenuItems()
            }
        }
        // Allow timer to fire while the menu is tracking events.
        if let t = refreshTimer { RunLoop.main.add(t, forMode: .common) }
    }

    @MainActor
    private func applySnapshotToMenuItems() {
        let s = monitor.snapshot

        cpuItem.attributedTitle = formattedLine(label: "CPU", value: String(format: "%.0f%%", s.cpuPercent))
        let usedPct = s.memoryTotalBytes > 0 ? (Double(s.memoryUsedBytes) / Double(s.memoryTotalBytes)) * 100.0 : 0
        let ramLine = "\(s.memoryUsedBytes.compactByteString) / \(s.memoryTotalBytes.compactByteString) (\(Int(usedPct))%)"
        ramItem.attributedTitle = formattedLine(label: "Memory", value: ramLine)
        let diskLine = "\(s.freeDiskBytes.compactByteString) free of \(s.totalDiskBytes.compactByteString)"
        diskItem.attributedTitle = formattedLine(label: "Disk", value: diskLine)

        if let pct = s.batteryPercent {
            let charging = s.isCharging ? " (charging)" : ""
            batteryItem.attributedTitle = formattedLine(label: "Battery", value: "\(pct)%\(charging)")
            batteryItem.isHidden = false
        } else {
            batteryItem.isHidden = true
        }
    }

    private func formattedLine(label: String, value: String) -> NSAttributedString {
        let line = NSMutableAttributedString()
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ]
        line.append(NSAttributedString(string: "\(label)    ", attributes: labelAttrs))
        line.append(NSAttributedString(string: value, attributes: valueAttrs))
        return line
    }
}
