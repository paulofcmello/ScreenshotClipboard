import AppKit
import ImageIO
import Darwin

// Standalone experiment: no shortcut interception, polling, or preference changes.
let args = CommandLine.arguments
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}
func metrics(_ event: String, _ extra: [String: Any] = [:]) {
#if MEASURE
    var info = rusage_info_v4()
    let result = withUnsafeMutablePointer(to: &info) { p in
        p.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0) }
    }
    var record = extra
    record["event"] = event
    record["resourceReadOK"] = result == 0
    record["residentBytes"] = info.ri_resident_size
    record["footprintBytes"] = info.ri_phys_footprint
    record["peakFootprintBytes"] = info.ri_lifetime_max_phys_footprint
    record["userTicks"] = info.ri_user_time
    record["systemTicks"] = info.ri_system_time
    record["wakeups"] = info.ri_interrupt_wkups
    record["timeNs"] = DispatchTime.now().uptimeNanoseconds
    var timebase = mach_timebase_info_data_t()
    mach_timebase_info(&timebase)
    record["timebaseNumer"] = timebase.numer
    record["timebaseDenom"] = timebase.denom
    print(String(data: try! JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), encoding: .utf8)!)
    fflush(stdout)
#endif
}

if args.contains("--help") {
    print("""
    Thumbnail prototype (standalone; no installed settings changed)
      --full-screen                Capture main display; default is region/window selection
      --output-directory PATH      Save capture here; default is Pictures
      --fixture PNG                Use an existing PNG instead of capturing
      --pasteboard NAME            Use isolated test clipboard
      --benchmark                  Measure idle, preview and release phases
      --verify-clipboard           Read back clipboard bytes (adds measurement overhead)
      --no-preview                 Clipboard-only benchmark control
      --render-preview PATH         Save a rendering of the preview for visual inspection
    """)
    exit(0)
}

final class PreviewView: NSView, NSDraggingSource {
    var thumbnail: NSImage?
    var file: URL?
    var onOpen: (() -> Void)?
    var onDragEnd: (() -> Void)?
    var dragging = false
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
        thumbnail?.draw(in: bounds.insetBy(dx: 5, dy: 5))
    }
    override func mouseDown(with event: NSEvent) { if event.clickCount == 2 { onOpen?() } }
    override func mouseDragged(with event: NSEvent) {
        guard !dragging, let file, let thumbnail else { return }
        dragging = true
        let item = NSDraggingItem(pasteboardWriter: file as NSURL)
        item.setDraggingFrame(bounds.insetBy(dx: 5, dy: 5), contents: thumbnail)
        beginDraggingSession(with: [item], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragging = false
        onDragEnd?()
    }
}

final class Prototype: NSObject, NSApplicationDelegate {
    var panel: NSPanel?
    var dismissal: DispatchWorkItem?
    let benchmark = args.contains("--benchmark")
    func applicationDidFinishLaunching(_ notification: Notification) {
        metrics("preview-started")
        guard let path = option("--preview-file"), let rawStart = option("--publication-start"), let start = UInt64(rawStart) else {
            fail("Missing preview input"); return
        }
        show(URL(fileURLWithPath: path), start: start)
    }
    func applicationWillTerminate(_ notification: Notification) {
        if !args.contains("--keep-test-clipboard"), let name = option("--pasteboard") { NSPasteboard(name: .init(name)).releaseGlobally() }
    }
    func fail(_ message: String) {
        fputs("Thumbnail: \(message)\n", stderr); exit(1)
    }
    func show(_ file: URL, start: UInt64) {
        autoreleasepool {
            if args.contains("--no-preview") { return }
            guard let source = CGImageSourceCreateWithURL(file as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary),
                let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 440,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary) else { fail("Cannot make preview"); return }
            let scale = min(220 / CGFloat(cg.width), 160 / CGFloat(cg.height))
            let width = CGFloat(cg.width) * scale + 10
            let height = CGFloat(cg.height) * scale + 10
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 700)
            let rect = NSRect(x: screen.maxX - width - 26, y: screen.minY + 26, width: width, height: height)
            let window = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            let view = PreviewView(frame: NSRect(origin: .zero, size: rect.size))
            view.thumbnail = NSImage(cgImage: cg, size: NSSize(width: width - 10, height: height - 10))
            view.file = file
            view.toolTip = "Drag to copy the file. Double-click to open."
            view.onOpen = { [weak self] in NSWorkspace.shared.open(file); self?.dismiss() }
            view.onDragEnd = { [weak self] in self?.dismiss() }
            window.contentView = view
            panel = window
            window.orderFrontRegardless()
            if let path = option("--render-preview"), let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            metrics("shown", ["elapsedMs": Double(DispatchTime.now().uptimeNanoseconds - start)/1e6,
                "thumbnailPixelBytes": cg.bytesPerRow * cg.height])
        }
#if MEASURE
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { metrics("settled") }
#endif
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }
    func dismiss() {
        // A drag session owns its image until the drop completes.
        if (panel?.contentView as? PreviewView)?.dragging == true { return }
        dismissal?.cancel(); dismissal = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel?.close(); panel = nil
        metrics("dismissed")
        if benchmark {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { metrics("released-before") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                metrics("released-after"); NSApp.terminate(nil)
            }
        } else { NSApp.terminate(nil) }
    }
}
// Publish without starting AppKit's application/window machinery. Then replace this
// process image (same PID) so transfer buffers cannot overlap the preview's lifetime.
// PNG bytes are eagerly stored in the pasteboard server and survive exec/exit.
if option("--preview-file") == nil {
    metrics("headless-started")
    if args.contains("--benchmark") {
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        metrics("idle-before")
        RunLoop.current.run(until: Date().addingTimeInterval(10))
        metrics("idle-after")
    }
    let file: URL
    if let path = option("--fixture") {
        file = URL(fileURLWithPath: path).standardizedFileURL
    } else {
        let folder = option("--output-directory").map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
        file = folder.appendingPathComponent("Screenshot-\(UUID().uuidString).png")
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-t", "png"] + (args.contains("--full-screen") ? ["-m"] : ["-i"]) + [file.path]
        do { try capture.run(); capture.waitUntilExit() }
        catch { fputs("Capture failed: \(error)\n", stderr); exit(1) }
        guard capture.terminationStatus == 0, FileManager.default.fileExists(atPath: file.path) else { exit(1) }
    }
    let start = DispatchTime.now().uptimeNanoseconds
    let copied = autoreleasepool { () -> Bool in
        guard let data = try? Data(contentsOf: file, options: .alwaysMapped) else { return false }
        let board = option("--pasteboard").map { NSPasteboard(name: .init($0)) } ?? .general
        board.clearContents()
        guard board.setData(data, forType: .png), board.setString(file.absoluteString, forType: .fileURL) else { return false }
        let verify = args.contains("--verify-clipboard")
        if verify && (board.data(forType: .png) != data || board.string(forType: .fileURL) != file.absoluteString) { return false }
        metrics("copied", ["elapsedMs": Double(DispatchTime.now().uptimeNanoseconds - start)/1e6,
            "pngBytes": data.count, "clipboardVerified": verify ? true as Any : NSNull()])
        return true
    }
    guard copied else { fputs("Could not copy PNG to clipboard.\n", stderr); exit(1) }
    let executable = URL(fileURLWithPath: args[0]).standardizedFileURL.path
    let arguments = [executable] + Array(args.dropFirst()) + ["--preview-file", file.path, "--publication-start", String(start)]
    let pointers = arguments.map { strdup($0) } + [nil]
    pointers.withUnsafeBufferPointer { _ = execv(executable, $0.baseAddress!) }
    fputs("Could not start preview: \(String(cString: strerror(errno)))\n", stderr)
    exit(1)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = Prototype()
app.delegate = delegate
app.run()
