import AppKit
import Darwin
outputMetrics = false
final class Sink: ImageClipboard {
    var changeCount = 0
    func publish(_ image: ReadyImage) -> Bool { fatalError("Corrupt image published") }
}
let root = FileManager.default.temporaryDirectory.appendingPathComponent("screenshot-churn-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let watcher = ScreenshotWatcher(clipboard: Sink())
try watcher.watch([root])
let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
var data = try Data(contentsOf: fixture); data[40] ^= 1
let url = root.appendingPathComponent("corrupt.png")
try data.write(to: url)
let marker = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
precondition(marker.withUnsafeBytes { setxattr(url.path, screenshotAttribute, $0.baseAddress, marker.count, 0, 0) } == 0)
watcher.scan(root.path)
benchmarkReads = 0
let start = DispatchTime.now().uptimeNanoseconds
for _ in 0..<1000 { autoreleasepool { watcher.scan(root.path) } }
let result: [String: Any] = ["scans":1000, "readAttempts":benchmarkReads,
    "elapsedMs": Double(DispatchTime.now().uptimeNanoseconds-start)/1e6,
    "method":"1000 explicit directory scans with an unchanged corrupt tagged PNG; no event loop during measurement"]
print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys,.prettyPrinted]),encoding:.utf8)!)
watcher.stop()
try FileManager.default.removeItem(at: root)
