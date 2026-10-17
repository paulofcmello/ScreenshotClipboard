import AppKit
import Darwin

func snapshot(_ pid: pid_t) -> [String: UInt64] {
    var info = rusage_info_v2()
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
        }
    }
    precondition(result == 0, "Process resource counters unavailable")
    return ["residentBytes": info.ri_resident_size, "physicalFootprintBytes": info.ri_phys_footprint,
        "interruptWakeups": info.ri_interrupt_wkups, "packageIdleWakeups": info.ri_pkg_idle_wkups,
        "userTicks": info.ri_user_time, "systemTicks": info.ri_system_time]
}
let process = Process()
process.executableURL = URL(fileURLWithPath: CommandLine.arguments[1])
// Exercise the normal directory and preference monitors, but never the user's clipboard.
let boardName = "ScreenshotClipboard.audit.\(UUID().uuidString)"
process.arguments = ["--pasteboard", boardName]
try process.run()
defer {
    if process.isRunning { process.terminate(); process.waitUntilExit() }
    NSPasteboard(name: .init(boardName)).releaseGlobally()
}
Thread.sleep(forTimeInterval: 2)
precondition(process.isRunning, "Daemon exited: check directory permissions")
let before = snapshot(process.processIdentifier)
let start = DispatchTime.now().uptimeNanoseconds
Thread.sleep(forTimeInterval: 30)
let seconds = Double(DispatchTime.now().uptimeNanoseconds - start)/1e9
let after = snapshot(process.processIdentifier)
var timebase = mach_timebase_info_data_t()
precondition(mach_timebase_info(&timebase) == KERN_SUCCESS)
let cpu = Double(after["userTicks"]! - before["userTicks"]! + after["systemTicks"]! - before["systemTicks"]!) * Double(timebase.numer) / Double(timebase.denom) / 1e9
let result: [String: Any] = ["seconds": seconds, "cpuPercent": cpu/seconds*100,
    "machTimebase": ["numer": timebase.numer, "denom": timebase.denom],
    "before": before, "after": after,
    "interruptWakeupsDelta": after["interruptWakeups"]! - before["interruptWakeups"]!,
    "packageIdleWakeupsDelta": after["packageIdleWakeups"]! - before["packageIdleWakeups"]!,
    "method": "30 seconds of full daemon after 2-second warmup; normal screenshot directories and preference monitoring; unique named pasteboard; proc_pid_rusage"]
print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted,.sortedKeys]), encoding: .utf8)!)
