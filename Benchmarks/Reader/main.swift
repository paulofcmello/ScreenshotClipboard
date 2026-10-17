import AppKit
import Darwin

outputMetrics = false
func resources() -> [String: Any] {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return ["maxRSSBytes": usage.ru_maxrss,
            "userSeconds": Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec)/1e6,
            "systemSeconds": Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec)/1e6,
            "voluntaryContextSwitches": usage.ru_nvcsw,
            "involuntaryContextSwitches": usage.ru_nivcsw]
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
var series: [String: Any] = [:]
for name in ["1920x1080", "3840x2160", "3840x2160-noise"] {
    let url = directory.appendingPathComponent("\(name)-0.png")
    var s = stat(); precondition(lstat(url.path, &s) == 0)
    var samples: [Double] = []
    for i in 0..<103 {
        let start = DispatchTime.now().uptimeNanoseconds
        autoreleasepool {
            guard let image = readReadyImage(url, identity: Identity(s)) else { fatalError("Invalid fixture") }
            precondition(!image.tiff.isEmpty)
        }
        if i >= 3 { samples.append(Double(DispatchTime.now().uptimeNanoseconds - start)/1e6) }
    }
    samples.sort()
    series[name] = ["count": samples.count, "meanMs": samples.reduce(0,+)/Double(samples.count),
        "p95Ms": samples[94], "p99Ms": samples[98], "samplesMs": samples]
}
let report: [String: Any] = ["method": "100 warm-cache readReadyImage calls per identical fixture, 3 warmups, monotonic time; includes full read, CRC, decode, TIFF, stat checks and autorelease drain; excludes watcher and pasteboard", "series": series, "resources": resources()]
print(String(data: try! JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted]), encoding: .utf8)!)
