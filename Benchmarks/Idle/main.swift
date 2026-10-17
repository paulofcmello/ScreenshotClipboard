import AppKit
import Darwin
outputMetrics = false
final class Sink: ImageClipboard {
    var changeCount = 0
    func publish(_ image: ReadyImage) -> Bool { changeCount += 1; return true }
}
func snapshot() -> [String: UInt64] {
    var info = rusage_info_v2()
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(getpid(), RUSAGE_INFO_V2, $0)
        }
    }
    precondition(result == 0, "Resource counters unavailable")
    return ["residentBytes": info.ri_resident_size, "physicalFootprintBytes": info.ri_phys_footprint,
        "interruptWakeups": info.ri_interrupt_wkups, "packageIdleWakeups": info.ri_pkg_idle_wkups,
        "userTicks": info.ri_user_time, "systemTicks": info.ri_system_time]
}
let root = FileManager.default.temporaryDirectory.appendingPathComponent("screenshot-idle-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let watcher = ScreenshotWatcher(clipboard: Sink())
try watcher.watch([root])
RunLoop.main.run(until: Date().addingTimeInterval(2))
let before = snapshot()
let start = DispatchTime.now().uptimeNanoseconds
RunLoop.main.run(until: Date().addingTimeInterval(30))
let seconds = Double(DispatchTime.now().uptimeNanoseconds - start)/1e9
let after = snapshot()
var timebase = mach_timebase_info_data_t()
precondition(mach_timebase_info(&timebase) == KERN_SUCCESS)
let cpu = Double(after["userTicks"]! - before["userTicks"]! + after["systemTicks"]! - before["systemTicks"]!) * Double(timebase.numer) / Double(timebase.denom) / 1e9
let result: [String: Any] = ["seconds": seconds, "cpuPercent": cpu/seconds*100,
    "machTimebase": ["numer": timebase.numer, "denom": timebase.denom],
    "before": before, "after": after,
    "interruptWakeupsDelta": after["interruptWakeups"]! - before["interruptWakeups"]!,
    "packageIdleWakeupsDelta": after["packageIdleWakeups"]! - before["packageIdleWakeups"]!,
    "method": "30 seconds idle watcher, empty directory and memory clipboard; excludes preferences monitoring and pasteboard service"]
print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted,.sortedKeys]), encoding: .utf8)!)
watcher.stop()
try FileManager.default.removeItem(at: root)
