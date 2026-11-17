import Foundation

/// Finds and removes iOS/watchOS/tvOS/visionOS simulator devices whose
/// runtime is no longer installed, using Apple's own tool:
/// `xcrun simctl list devices unavailable -j` and
/// `xcrun simctl delete unavailable`.
///
/// Going through simctl (instead of trashing device folders) keeps
/// CoreSimulator's device set consistent. If Xcode / xcrun is not installed
/// the category simply resolves to no paths.
enum SimulatorCleaner {

    static var devicesRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Developer/CoreSimulator/Devices")
    }

    /// Device folders of unavailable simulators (used for sizing).
    static func unavailableDeviceDirectories() -> [URL] {
        guard let result = runXcrun(["simctl", "list", "devices", "unavailable", "-j"]),
              result.status == 0 else { return [] }
        return unavailableUDIDs(fromSimctlJSON: result.stdout).map { devicesRoot.appending(path: $0) }
    }

    /// Parse the JSON from `simctl list devices unavailable -j`. Every device
    /// listed there is unavailable; devices explicitly marked available are
    /// skipped as a guard.
    static func unavailableUDIDs(fromSimctlJSON data: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let byRuntime = root["devices"] as? [String: [[String: Any]]] else { return [] }
        var udids: [String] = []
        for (_, devices) in byRuntime {
            for device in devices {
                if (device["isAvailable"] as? Bool) == true { continue }
                if let udid = device["udid"] as? String, !udid.isEmpty {
                    udids.append(udid)
                }
            }
        }
        return udids.sorted()
    }

    /// Run `xcrun simctl delete unavailable`. Not recoverable from the Trash,
    /// but these devices cannot boot anyway because their runtime is gone.
    static func deleteUnavailable() async -> CustomCleanOutcome {
        await Task.detached(priority: .userInitiated) {
            let before = unavailableDeviceDirectories().count
            guard before > 0 else { return CustomCleanOutcome(succeeded: 0, failed: 0, errorMessage: nil) }
            guard let result = runXcrun(["simctl", "delete", "unavailable"], timeout: 120) else {
                return CustomCleanOutcome(succeeded: 0, failed: before, errorMessage: "xcrun simctl is not available.")
            }
            let after = unavailableDeviceDirectories().count
            let removed = max(0, before - after)
            let message = result.status == 0 ? nil : "simctl delete unavailable exited with status \(result.status)."
            return CustomCleanOutcome(succeeded: removed, failed: after, errorMessage: message)
        }.value
    }

    struct ProcessResult {
        let status: Int32
        let stdout: Data
    }

    /// Run /usr/bin/xcrun with a timeout. Returns nil when it cannot launch.
    static func runXcrun(_ arguments: [String], timeout: TimeInterval = 15) -> ProcessResult? {
        let xcrun = URL(fileURLWithPath: "/usr/bin/xcrun")
        guard FileManager.default.isExecutableFile(atPath: xcrun.path) else { return nil }
        let process = Process()
        process.executableURL = xcrun
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        // Read stdout before waiting so a large listing cannot fill the pipe.
        var data = Data()
        let reader = DispatchQueue(label: "SimulatorCleaner.read")
        let group = DispatchGroup()
        group.enter()
        reader.async {
            data = out.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        if group.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }
        process.waitUntilExit()
        return ProcessResult(status: process.terminationStatus, stdout: data)
    }
}
