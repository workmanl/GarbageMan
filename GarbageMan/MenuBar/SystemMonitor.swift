import Foundation
import Darwin
import IOKit.ps

/// Cheap, periodic snapshot of system load. Designed to be called from the
/// main actor every few seconds; all reads are kernel calls that return in
/// microseconds.
@MainActor
final class SystemMonitor {

    struct Snapshot: Equatable {
        var cpuPercent: Double = 0           // 0...100
        var memoryUsedBytes: UInt64 = 0
        var memoryTotalBytes: UInt64 = 0
        var freeDiskBytes: UInt64 = 0
        var totalDiskBytes: UInt64 = 0
        var batteryPercent: Int?             // nil on desktops / no battery
        var isCharging: Bool = false
        var timestamp: Date = .distantPast
    }

    private(set) var snapshot = Snapshot()

    private var lastCPUTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?

    /// Take a new sample and update `snapshot`. Safe to call frequently.
    func refresh() {
        snapshot.cpuPercent = readCPUPercent()
        let mem = readMemory()
        snapshot.memoryUsedBytes = mem.used
        snapshot.memoryTotalBytes = mem.total
        let disk = readDiskRoot()
        snapshot.freeDiskBytes = disk.free
        snapshot.totalDiskBytes = disk.total
        if let battery = readBattery() {
            snapshot.batteryPercent = battery.percent
            snapshot.isCharging = battery.isCharging
        } else {
            snapshot.batteryPercent = nil
            snapshot.isCharging = false
        }
        snapshot.timestamp = .now
    }

    // MARK: - CPU

    private func readCPUPercent() -> Double {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return snapshot.cpuPercent }

        let user = info.cpu_ticks.0
        let system = info.cpu_ticks.1
        let idle = info.cpu_ticks.2
        let nice = info.cpu_ticks.3

        defer { lastCPUTicks = (user, system, idle, nice) }
        guard let prev = lastCPUTicks else { return 0 }

        let dUser = Double(user &- prev.user)
        let dSystem = Double(system &- prev.system)
        let dIdle = Double(idle &- prev.idle)
        let dNice = Double(nice &- prev.nice)
        let dTotal = dUser + dSystem + dIdle + dNice
        guard dTotal > 0 else { return 0 }
        let busy = dUser + dSystem + dNice
        return min(100.0, max(0.0, (busy / dTotal) * 100.0))
    }

    // MARK: - RAM

    private func readMemory() -> (used: UInt64, total: UInt64) {
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return (0, ProcessInfo.processInfo.physicalMemory) }

        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(info.active_count) * pageSize
        let inactive = UInt64(info.inactive_count) * pageSize
        let wired = UInt64(info.wire_count) * pageSize
        let compressed = UInt64(info.compressor_page_count) * pageSize

        // Apple's "memory used" matches Activity Monitor's app/wired/compressed.
        let used = active + wired + compressed + inactive / 2
        let total = ProcessInfo.processInfo.physicalMemory
        return (used: min(used, total), total: total)
    }

    // MARK: - Disk

    private func readDiskRoot() -> (free: UInt64, total: UInt64) {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeTotalCapacityKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return (0, 0) }
        let free = UInt64(values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0))
        let total = UInt64(values.volumeTotalCapacity ?? 0)
        return (free, total)
    }

    // MARK: - Battery

    private func readBattery() -> (percent: Int, isCharging: Bool)? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return nil }
        guard let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for src in sources {
            guard let desc = IOPSGetPowerSourceDescription(blob, src)?.takeUnretainedValue() as? [String: Any] else { continue }
            guard let type = desc[kIOPSTypeKey] as? String, type == kIOPSInternalBatteryType else { continue }
            guard let current = desc[kIOPSCurrentCapacityKey] as? Int,
                  let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let pct = Int((Double(current) / Double(max)) * 100.0)
            let state = desc[kIOPSPowerSourceStateKey] as? String
            let charging = (state == kIOPSACPowerValue) && (desc[kIOPSIsChargingKey] as? Bool ?? false)
            return (pct, charging)
        }
        return nil
    }
}

extension UInt64 {
    /// Compact byte string for menu titles: "8.1 GB" rather than ByteCountFormatter's "8,123,456,789 bytes" fallback.
    var compactByteString: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        return formatter.string(fromByteCount: Int64(Swift.min(self, UInt64(Int64.max))))
    }
}
