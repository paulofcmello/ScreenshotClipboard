import AppKit
import Darwin
import ImageIO

outputMetrics = false
let fm = FileManager.default
let root = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath()
    .appendingPathComponent("screenshot-clipboard-tests-\(UUID().uuidString)")
try fm.createDirectory(at: root, withIntermediateDirectories: true)
let board = NSPasteboard.withUniqueName()
defer { board.releaseGlobally() }
board.clearContents()
let realClipboard = board.setString("probe", forType: .string) && board.string(forType: .string) == "probe"
final class TestClipboard: ImageClipboard {
    var changeCount = 0
    var image: ReadyImage?
    var text: String?
    func publish(_ image: ReadyImage) -> Bool {
        self.image = image; text = nil; changeCount += 1; return true
    }
    func setText(_ text: String) { self.text = text; image = nil; changeCount += 1 }
}
let memoryClipboard = TestClipboard()
let sink: ImageClipboard = realClipboard ? NativeImageClipboard(board) : memoryClipboard
func setText(_ text: String) {
    if realClipboard { board.clearContents(); board.setString(text, forType: .string) }
    else { memoryClipboard.setText(text) }
}
func currentText() -> String? { realClipboard ? board.string(forType: .string) : memoryClipboard.text }
if !realClipboard { print("Clipboard service unavailable: using memory sink. These timings are NOT real clipboard latency.") }
var assertions = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    guard value() else { fputs("FAIL: \(message)\nFixtures: \(root.path)\n", stderr); exit(1) }
    assertions += 1
}
func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline { RunLoop.main.run(until: min(deadline, Date().addingTimeInterval(0.002))) }
}
func until(_ predicate: () -> Bool, timeout: Double = 3) {
    let deadline = Date().addingTimeInterval(timeout)
    while !predicate() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.001)) }
    check(predicate(), "Timed out waiting for filesystem notification / pasteboard update")
}
func png(_ width: Int, _ height: Int, noisy: Bool = false) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)!
    let p = rep.bitmapData!
    var seed: UInt32 = 0x12345678
    for y in 0..<height {
        for x in 0..<width {
            let i = (y * width + x) * 4
            if noisy {
                seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
                p[i] = UInt8(truncatingIfNeeded: seed)
                p[i+1] = UInt8(truncatingIfNeeded: seed >> 8)
                p[i+2] = UInt8(truncatingIfNeeded: seed >> 16)
            } else { p[i] = UInt8(x % 256); p[i+1] = UInt8(y % 256); p[i+2] = 123 }
            p[i+3] = 255
        }
    }
    rep.size = NSSize(width: Double(width) / 2, height: Double(height) / 2)
    return rep.representation(using: .png, properties: [:])!
}
func mark(_ url: URL) throws {
    let value = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
    let status = value.withUnsafeBytes { setxattr(url.path, screenshotAttribute, $0.baseAddress, value.count, 0, 0) }
    check(status == 0, "Set screenshot xattr")
}
@discardableResult func write(_ name: String, _ data: Data, tagged: Bool = true) throws -> URL {
    let url = root.appendingPathComponent(name)
    try data.write(to: url)
    if tagged { try mark(url) }
    return url
}
func append(_ url: URL, _ data: Data) throws {
    let file = try FileHandle(forWritingTo: url)
    try file.seekToEnd(); try file.write(contentsOf: data); try file.close()
}

check(screenshotPreferenceChanges([:], desktop: false, desktopPath: "/Desktop").isEmpty,
      "Native default preferences need no writes")
check(screenshotPreferenceChanges(["location": "/Custom", "type": "png", "target": "file"],
    desktop: false, desktopPath: "/Desktop").isEmpty, "Preserve compatible screenshot settings")
check(screenshotPreferenceChanges(["location": "/Custom", "type": "jpg", "target": "clipboard"],
    desktop: false, desktopPath: "/Desktop") == ["type": "png", "target": "file"],
    "Change only settings required for saved PNGs")
check(screenshotPreferenceChanges(["location": "/Custom"], desktop: true,
    desktopPath: "/Desktop") == ["location": "/Desktop"], "Desktop change requires explicit option")

func pixels(_ data: Data) -> Data {
    let source = CGImageSourceCreateWithData(data as CFData, nil)!
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    var bytes = Data(count: image.width * image.height * 4)
    bytes.withUnsafeMutableBytes { raw in
        let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return bytes
}
let small = png(320, 240)
check(completePNG(small), "Valid PNG accepted")
check(!completePNG(small.dropLast()), "Truncated IEND rejected")
var corrupt = small; corrupt[40] ^= 1
check(!completePNG(corrupt), "Bad CRC rejected")
let fidelity = try write("fidelity.png", small)
var fidelityStat = stat(); check(lstat(fidelity.path, &fidelityStat) == 0, "Fidelity fixture exists")
let prepared = readReadyImage(fidelity, identity: Identity(fidelityStat))!
check(pixels(prepared.png) == pixels(prepared.tiff), "TIFF preserves decoded pixels and color")
let tiffSource = CGImageSourceCreateWithData(prepared.tiff as CFData, nil)!
let tiffProps = CGImageSourceCopyPropertiesAtIndex(tiffSource, 0, nil)! as NSDictionary
check(abs((tiffProps[kCGImagePropertyDPIWidth] as! Double) - 144) < 0.1, "TIFF preserves Retina DPI")
check((tiffProps[kCGImagePropertyPixelWidth] as! Int) == 320 &&
      (tiffProps[kCGImagePropertyPixelHeight] as! Int) == 240, "TIFF preserves dimensions")
var trailing = small; trailing.append(0)
check(!completePNG(trailing), "Trailing bytes after IEND rejected")
try write("preexisting.png", small)
setText("untouched")
var reads = 0
var changeClipboardDuringRead = false
let watcher = ScreenshotWatcher(clipboard: sink, readImage: { url, identity in
    reads += 1
    let image = readReadyImage(url, identity: identity)
    if changeClipboardDuringRead { setText("copy during decoding") }
    return image
})
var copies = 0
var lastURL: URL?
var latencies: [String: [Double]] = [:]
var completed: [String: Double] = [:]
var activeSeries: String?
watcher.onCopy = { url, image, finish in
    copies += 1; lastURL = url
    if realClipboard {
        check(board.data(forType: .png) == image.png, "Exact PNG bytes on isolated pasteboard")
        check(board.data(forType: .tiff) != nil, "TIFF image fallback available")
        check(NSImage(pasteboard: board) != nil, "AppKit can read actual clipboard image")
    } else {
        check(memoryClipboard.image?.png == image.png, "Exact PNG bytes prepared")
        check(memoryClipboard.image?.tiff.isEmpty == false, "TIFF fallback prepared")
        check(NSImage(data: image.png) != nil, "AppKit can read prepared image")
    }
    if let series = activeSeries, let ready = completed[url.lastPathComponent] {
        latencies[series, default: []].append((finish - ready) * 1000)
    }
}
try watcher.watch([root])
spin(0.03)
check(copies == 0 && currentText() == "untouched", "Startup does not copy old screenshots")
try write("Screenshot decoy.png", small, tagged: false)
spin(0.03)
check(copies == 0, "Unrelated PNG and screenshot-like filename ignored")

let partial = try write("Captura de Tela parcial.png", Data(small.prefix(small.count / 2)))
spin(0.03)
check(copies == 0, "Partial screenshot never copied")
try append(partial, Data(small.suffix(small.count - small.count / 2)))
until { copies == 1 }
check(lastURL?.resolvingSymlinksInPath().path == partial.resolvingSymlinksInPath().path, "Localized names supported")
let savedPartial = try Data(contentsOf: partial)
check(savedPartial == small, "Screenshot stays saved and unchanged")

let late = try write("metadata-late.png", small, tagged: false)
spin(0.03); check(copies == 1, "Metadata required")
try mark(late); until { copies == 2 }
try write("corrupt.png", corrupt); spin(0.03)
check(copies == 2, "Corrupt screenshot never reaches pasteboard")

let temp = try write(".capture-temporary", small)
spin(0.02)
let renamed = root.appendingPathComponent("window capture.png")
try fm.moveItem(at: temp, to: renamed)
until { copies == 3 }
check(lastURL?.resolvingSymlinksInPath().path == renamed.resolvingSymlinksInPath().path, "Atomic temporary-file rename supported")

let conflict = try write("clipboard-conflict.png", Data(small.prefix(40)))
spin(0.02)
setText("newer user copy")
try append(conflict, Data(small.dropFirst(40))); spin(0.03)
check(copies == 3 && currentText() == "newer user copy", "Newer clipboard preserved during file write")

let slow = try write("older-slow.png", Data(small.prefix(40)))
spin(0.02)
let newer = try write("newer-fast.png", small)
until { copies == 4 }
try append(slow, Data(small.dropFirst(40))); spin(0.03)
check(copies == 4 && lastURL?.resolvingSymlinksInPath().path == newer.resolvingSymlinksInPath().path, "Older capture finishing late cannot replace newer screenshot")

for n in 0..<12 { try write("burst-\(String(format: "%02d", n)).png", small) }
until { lastURL?.lastPathComponent == "burst-11.png" }
let burstCopies = copies
try FileHandle(forWritingTo: newer).close()
try mark(newer); spin(0.02)
check(copies == burstCopies, "Metadata updates do not copy a screenshot twice")
let symlink = root.appendingPathComponent("symlink.png")
try fm.createSymbolicLink(at: symlink, withDestinationURL: newer); spin(0.02)
check(copies == burstCopies, "Symlinks ignored")

// Directory churn must not repeatedly decode an unchanged corrupt candidate.
let readsBeforeScan = reads
watcher.scan(root.path); watcher.scan(root.path)
check(reads == readsBeforeScan, "Unrelated directory scans do not retry unchanged candidates")
let beforeRace = copies
let readsBeforeRace = reads
changeClipboardDuringRead = true
try write("decode-conflict.png", small)
try write("decode-conflict-second.png", small); spin(0.03)
changeClipboardDuringRead = false
check(copies == beforeRace && currentText() == "copy during decoding", "Clipboard change during decode preserved")
check(reads == readsBeforeRace + 1, "All captures discovered before a user copy retain their original generation")
// More completed captures than the incomplete-candidate descriptor limit,
// with filenames in reverse birth order.
let beforeLargeBurst = copies
for n in 0..<160 { try write("reverse-\(String(format: "%03d", 159-n)).png", small) }
until { lastURL?.lastPathComponent == "reverse-000.png" }
check(copies == beforeLargeBurst + 160, "Every completed capture in a large burst is published")
check(watcher.candidates.count < 128, "Completed burst does not exhaust candidate limit")
let beforeRestart = copies
watcher.stop()
let restarted = ScreenshotWatcher(clipboard: sink)
var restartCopies = 0
restarted.onCopy = { _, _, _ in restartCopies += 1 }
try restarted.watch([root]); spin(0.02)
check(restartCopies == 0 && copies == beforeRestart, "Restart does not replay screenshots")
restarted.stop()
try watcher.watch([root])

func benchmark(_ name: String, _ data: Data, count: Int) throws {
    activeSeries = name
    for i in 0..<count {
        let filename = "\(name)-\(i).png"
        let before = copies
        let url = try write(filename, data)
        // Same-process synchronous writer: marker and all PNG bytes have been
        // written and the writer is closed before this timestamp is recorded.
        completed[filename] = Date().timeIntervalSince1970
        until({ copies > before }, timeout: 10)
        check(fm.fileExists(atPath: url.path), "Benchmark file remains on disk")
    }
    activeSeries = nil
}
try benchmark("1920x1080", png(1920, 1080), count: 30)
try benchmark("3840x2160", png(3840, 2160), count: 20)
try benchmark("3840x2160-noise", png(3840, 2160, noisy: true), count: 10)

// Native capture benchmark is optional and never requests a new permission.
// Tests use a private pasteboard, never the user's general clipboard.
let screenPermission = CGPreflightScreenCaptureAccess()
if screenPermission {
    activeSeries = "native-main-display"
    for i in 0..<5 {
        let name = "native-\(i).png", url = root.appendingPathComponent("native-\(i).png")
        let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-x", "-m", "-t", "png", url.path]
        let before = copies
        try task.run(); task.waitUntilExit()
        check(task.terminationStatus == 0, "Native screencapture succeeded")
        completed[name] = Date().timeIntervalSince1970
        until({ copies > before }, timeout: 10)
    }
    activeSeries = nil
}

var report: [String: Any] = ["assertions": assertions, "screenCapturePermissionAlreadyGranted": screenPermission,
    "realClipboardAvailable": realClipboard,
    "testClipboard": realClipboard ? "isolated named NSPasteboard; general clipboard never accessed" : "in-memory test sink: real clipboard service blocked",
    "method": "in-process actual filesystem notifications, tagged PNG write/close + metadata completion to image publication in chosen sink; native series (when permitted) starts at screencapture process exit, a lower-bound proxy",
    "date": ISO8601DateFormatter().string(from: Date()), "fixtureDirectory": root.path]
var series: [String: Any] = [:]
for name in latencies.keys.sorted() {
    let values = latencies[name]!.sorted(), n = values.count
    let mean = values.reduce(0, +) / Double(n), p95 = values[min(n-1, Int(ceil(Double(n) * 0.95)) - 1)]
    series[name] = ["count": n, "meanMs": mean, "medianMs": values[n/2], "p95Ms": p95,
        "p99Ms": values[min(n-1, Int(ceil(Double(n) * 0.99)) - 1)], "maxMs": values.last!, "under200Ms": values.allSatisfy { $0 < 200 }, "samplesMs": values]
    print(String(format: "%@: n=%d mean=%.2f ms p95=%.2f ms max=%.2f ms", name, n, mean, p95, values.last!))
}
report["series"] = series
let output = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("build/benchmark.json")
try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output)
watcher.stop()
print("PASS: \(assertions) assertions. Native capture permission already granted: \(screenPermission).")
print("Report: \(output.path)")
print("Generated fixtures retained for inspection: \(root.path)")
