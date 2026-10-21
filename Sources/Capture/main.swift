import AppKit
import ImageIO
import Darwin

// On-demand capture worker. The separate hotkey listener launches this process.
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
    ScreenshotClipboard capture worker
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

// `defaults write local.screenshot-clipboard PreviewStyle native` approximates Apple's
// floating thumbnail; `defaults delete local.screenshot-clipboard PreviewStyle` restores the default.
let nativeStyle = UserDefaults.standard.string(forKey: "PreviewStyle") == "native"
let padding: CGFloat = nativeStyle ? 4 : 5
// Set in the settings window. Only the off state is stored, so a missing key means on.
let copyImage = UserDefaults.standard.object(forKey: "CopyToClipboard") as? Bool ?? true
// When saving is off, the capture lives in a temporary folder just long enough for the
// preview; the next capture clears it. Passed on to the preview so both phases agree.
let unsaved = args.contains("--unsaved") || UserDefaults.standard.object(forKey: "SaveFile") as? Bool == false
let unsavedFolder = FileManager.default.temporaryDirectory.appendingPathComponent("ScreenshotClipboard", isDirectory: true)

final class PreviewView: NSView, NSDraggingSource, NSMenuDelegate {
    var thumbnail: NSImage?
    var file: URL?
    var onOpen: (() -> Void)?
    var onDragEnd: (() -> Void)?
    var onHold: (() -> Void)?
    var onRelease: (() -> Void)?
    var onDismiss: (() -> Void)?
    var dragging = false
    var swipe: CGFloat = 0
    var restingX: CGFloat = 0
    var pressed: NSPoint?
    var sliding = false
    var scrolling = false
    override func draw(_ dirtyRect: NSRect) {
        if nativeStyle {
            // Measured from Apple's thumbnail: ~4pt black frame with 5pt corners,
            // image edged by a 1pt light line.
            NSColor.black.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
            let image = bounds.insetBy(dx: padding, dy: padding)
            thumbnail?.draw(in: image)
            NSColor(white: 0.85, alpha: 1).setStroke()
            let edge = NSBezierPath(rect: image.insetBy(dx: 0.5, dy: 0.5)); edge.lineWidth = 1; edge.stroke()
            return
        }
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
        thumbnail?.draw(in: bounds.insetBy(dx: 5, dy: 5))
    }
    override func mouseDown(with event: NSEvent) {
        pressed = NSEvent.mouseLocation; sliding = false
        if event.clickCount == 2 { onOpen?() }
    }
    // A mostly rightward drag slides the preview away like the native one;
    // any other direction drags the file out.
    override func mouseDragged(with event: NSEvent) {
        guard !dragging, let window, let start = pressed else { return }
        let now = NSEvent.mouseLocation, dx = now.x - start.x, dy = now.y - start.y
        if !sliding {
            guard hypot(dx, dy) > 4 else { return }
            if dx > abs(dy) {
                sliding = true; restingX = window.frame.minX; onHold?()
            } else { beginFileDrag(event); return }
        }
        swipe = max(0, dx)
        window.setFrameOrigin(NSPoint(x: restingX + swipe, y: window.frame.minY))
    }
    override func mouseUp(with event: NSEvent) {
        pressed = nil
        if sliding { sliding = false; settle() }
    }
    func beginFileDrag(_ event: NSEvent) {
        guard let file, let thumbnail else { return }
        dragging = true
        let item = NSDraggingItem(pasteboardWriter: file as NSURL)
        item.setDraggingFrame(bounds.insetBy(dx: padding, dy: padding), contents: thumbnail)
        beginDraggingSession(with: [item], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragging = false
        onDragEnd?()
    }

    // Built only when requested, so an unused preview pays nothing for it.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard file != nil else { return nil }
        let menu = NSMenu()
        menu.delegate = self
        let items = [("Open", #selector(openFile)), ("Show in Finder", #selector(reveal)), ("Move to Trash", #selector(trash))]
        // An unsaved capture has no file worth finding or trashing.
        for (title, action) in unsaved ? Array(items.prefix(1)) : items {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close", action: #selector(close), keyEquivalent: "").target = self
        return menu
    }
    func menuWillOpen(_ menu: NSMenu) { onHold?() }
    func menuDidClose(_ menu: NSMenu) {
        // Item actions run after menuDidClose; let them dismiss first.
        DispatchQueue.main.async { [weak self] in self?.onRelease?() }
    }
    @objc func openFile() { onOpen?() }
    @objc func reveal() {
        if let file { NSWorkspace.shared.activateFileViewerSelecting([file]) }
        onDismiss?()
    }
    @objc func trash() {
        if let file { NSWorkspace.shared.recycle([file]) }
        onDismiss?()
    }
    @objc func close() { onDismiss?() }

    // Two-finger swipe right slides the preview off screen, like the native one.
    override func scrollWheel(with event: NSEvent) {
        guard let window, event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return }
        if event.phase.contains(.began) { swipe = 0; restingX = window.frame.minX; scrolling = true; onHold?() }
        guard scrolling else { return }
        let dx = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        swipe = max(0, swipe + dx)
        window.setFrameOrigin(NSPoint(x: restingX + swipe, y: window.frame.minY))
        guard event.phase.contains(.ended) || event.phase.contains(.cancelled) else { return }
        scrolling = false; settle()
    }
    func settle() {
        guard let window else { return }
        let away = swipe > 40
        var target = window.frame
        target.origin.x = away ? (window.screen?.frame.maxX ?? target.maxX) + 10 : restingX
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.15
            window.animator().setFrame(target, display: true)
        }, completionHandler: { [weak self] in away ? self?.onDismiss?() : self?.onRelease?() })
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
            let fit = nativeStyle ? NSSize(width: 146, height: 95) : NSSize(width: 220, height: 160)
            let scale = min(fit.width / CGFloat(cg.width), fit.height / CGFloat(cg.height))
            let width = CGFloat(cg.width) * scale + padding * 2
            let height = CGFloat(cg.height) * scale + padding * 2
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 700)
            let margin = nativeStyle ? NSSize(width: 12, height: 13) : NSSize(width: 26, height: 26)
            let rect = NSRect(x: screen.maxX - width - margin.width, y: screen.minY + margin.height, width: width, height: height)
            let window = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.sharingType = .none
            let view = PreviewView(frame: NSRect(origin: .zero, size: rect.size))
            view.thumbnail = NSImage(cgImage: cg, size: NSSize(width: width - padding * 2, height: height - padding * 2))
            view.file = file
            view.toolTip = "Drag to copy the file. Double-click to open. Swipe right to dismiss."
            view.onOpen = { [weak self] in NSWorkspace.shared.open(file); self?.dismiss() }
            view.onDragEnd = { [weak self] in self?.dismiss() }
            view.onDismiss = { [weak self] in self?.dismiss() }
            view.onHold = { [weak self] in self?.dismissal?.cancel() }
            view.onRelease = { [weak self] in self?.scheduleDismissal() }
            window.contentView = view
            panel = window
            if nativeStyle, !args.contains("--render-preview") {
                // Slide in from the right edge, as Apple's thumbnail does.
                window.setFrameOrigin(NSPoint(x: screen.maxX + 10, y: rect.minY))
                window.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    window.animator().setFrame(rect, display: true)
                }
            } else { window.orderFrontRegardless() }
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
        scheduleDismissal()
    }
    func scheduleDismissal() {
        guard panel != nil else { return }
        dismissal?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard nativeStyle, let view = self?.panel?.contentView as? PreviewView, !view.dragging else {
                self?.dismiss(); return
            }
            view.swipe = .greatestFiniteMagnitude; view.settle()
        }
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
        var folder = option("--output-directory").map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
        if unsaved {
            try? FileManager.default.removeItem(at: unsavedFolder)
            try? FileManager.default.createDirectory(at: unsavedFolder, withIntermediateDirectories: true)
            folder = unsavedFolder
        }
        file = folder.appendingPathComponent("Screenshot-\(UUID().uuidString).png")
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        var captureArguments = ["-x", "-t", "png"]
        captureArguments.append(args.contains("--full-screen") ? "-m" : "-i")
        captureArguments.append(file.path)
        capture.arguments = captureArguments
        do { try capture.run(); capture.waitUntilExit() }
        catch { fputs("Capture failed: \(error)\n", stderr); exit(1) }
        guard capture.terminationStatus == 0, FileManager.default.fileExists(atPath: file.path) else { exit(1) }
    }
    let start = DispatchTime.now().uptimeNanoseconds
    let copied = !copyImage || autoreleasepool { () -> Bool in
        guard let data = try? Data(contentsOf: file, options: .alwaysMapped) else { return false }
        let board = option("--pasteboard").map { NSPasteboard(name: .init($0)) } ?? .general
        board.clearContents()
        // A temporary file goes away, so an unsaved capture is copied as an image only.
        let url = unsaved ? nil : file.absoluteString
        guard board.setData(data, forType: .png), url.map({ board.setString($0, forType: .fileURL) }) ?? true else { return false }
        let verify = args.contains("--verify-clipboard")
        if verify && (board.data(forType: .png) != data || board.string(forType: .fileURL) != url) { return false }
        metrics("copied", ["elapsedMs": Double(DispatchTime.now().uptimeNanoseconds - start)/1e6,
            "pngBytes": data.count, "clipboardVerified": verify ? true as Any : NSNull()])
        return true
    }
    guard copied else { fputs("Could not copy PNG to clipboard.\n", stderr); exit(1) }
    if let ready = option("--ready-file") { FileManager.default.createFile(atPath: ready, contents: Data()) }
    let executable = URL(fileURLWithPath: args[0]).standardizedFileURL.path
    let arguments = [executable] + Array(args.dropFirst()) + ["--preview-file", file.path, "--publication-start", String(start)]
        + (unsaved && !args.contains("--unsaved") ? ["--unsaved"] : [])
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
