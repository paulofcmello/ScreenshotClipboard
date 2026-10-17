import AppKit
import ImageIO
import Darwin
import zlib

let screenshotAttribute = "com.apple.metadata:kMDItemIsScreenCapture"

func screenshotMarked(_ fd: Int32) -> Bool {
    let size = fgetxattr(fd, screenshotAttribute, nil, 0, 0, 0)
    guard size > 0, size < 4096 else { return false }
    var data = Data(count: size)
    let count = data.withUnsafeMutableBytes {
        fgetxattr(fd, screenshotAttribute, $0.baseAddress, size, 0, 0)
    }
    guard count == size,
          let flag = try? PropertyListSerialization.propertyList(from: data, format: nil) as? NSNumber
    else { return false }
    return flag.boolValue
}

struct Identity: Hashable {
    let device: Int32
    let inode: UInt64
    let birthSeconds: Int
    let birthNanos: Int
    init(_ s: stat) {
        device = s.st_dev; inode = s.st_ino
        birthSeconds = s.st_birthtimespec.tv_sec; birthNanos = s.st_birthtimespec.tv_nsec
    }
}

func unchanged(_ a: stat, _ b: stat) -> Bool {
    Identity(a) == Identity(b) && a.st_size == b.st_size &&
    a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec &&
    a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec &&
    a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec &&
    a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
}

// PNG's IEND is a format-level completion marker. Verify every chunk's CRC
// and a decoded image before touching the pasteboard.
func completePNG(_ data: Data) -> Bool {
    data.withUnsafeBytes { raw in
        let b = raw.bindMemory(to: UInt8.self)
        guard b.count >= 57, Array(b.prefix(8)) == [137,80,78,71,13,10,26,10] else { return false }
        func uint32(_ i: Int) -> UInt32 {
            UInt32(b[i]) << 24 | UInt32(b[i+1]) << 16 | UInt32(b[i+2]) << 8 | UInt32(b[i+3])
        }
        var offset = 8, sawHeader = false, sawData = false
        while offset <= b.count - 12 {
            let length = Int(uint32(offset))
            guard length <= b.count - offset - 12 else { return false }
            let type = uint32(offset + 4)
            if !sawHeader {
                guard type == 0x49484452, length == 13 else { return false }
                sawHeader = true
            }
            let crc = crc32(0, b.baseAddress!.advanced(by: offset + 4), uInt(length + 4))
            guard UInt32(crc) == uint32(offset + 8 + length) else { return false }
            if type == 0x49444154 { sawData = true }
            offset += length + 12
            if type == 0x49454e44 { return length == 0 && sawData && offset == b.count }
        }
        return false
    }
}

struct ReadyImage {
    let png: Data
    let tiff: Data
    let width: Int
    let height: Int
    let modified: Double
}

func readReadyImage(_ url: URL, identity: Identity) -> ReadyImage? {
    let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
    guard fd >= 0 else { return nil }
    defer { close(fd) }
    var before = stat(), after = stat()
    guard fstat(fd, &before) == 0, Identity(before) == identity,
          before.st_mode & S_IFMT == S_IFREG, screenshotMarked(fd),
          before.st_size >= 57, before.st_size <= 512 * 1024 * 1024 else { return nil }
    // Avoid reading/rechecking megabytes on each notification during a long write.
    var tail = [UInt8](repeating: 0, count: 12)
    let tailCount = tail.withUnsafeMutableBytes {
        pread(fd, $0.baseAddress, 12, before.st_size - 12)
    }
    guard tailCount == 12, tail == [0,0,0,0,73,69,78,68,174,66,96,130] else { return nil }
    var data = Data(count: Int(before.st_size))
    let readOK = data.withUnsafeMutableBytes { buffer -> Bool in
        var offset = 0
        while offset < buffer.count {
            let n = pread(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset, off_t(offset))
            if n < 0 && errno == EINTR { continue }
            guard n > 0 else { return false }
            offset += n
        }
        return true
    }
    guard readOK, completePNG(data),
          let source = CGImageSourceCreateWithData(data as CFData, nil),
          CGImageSourceGetCount(source) == 1,
          CGImageSourceGetStatus(source) == .statusComplete,
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = props[kCGImagePropertyPixelWidth] as? Int,
          let height = props[kCGImagePropertyPixelHeight] as? Int,
          width > 0, height > 0, width <= 40000, height <= 40000,
          width * height <= 160_000_000,
          let image = CGImageSourceCreateImageAtIndex(source, 0,
              [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
          CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else { return nil }
    let bitmap = NSBitmapImageRep(cgImage: image)
    // PNG bytes remain exactly as saved, including Retina/DPI/profile information.
    if let dx = props[kCGImagePropertyDPIWidth] as? Double,
       let dy = props[kCGImagePropertyDPIHeight] as? Double, dx > 0, dy > 0 {
        bitmap.size = NSSize(width: Double(width) * 72 / dx, height: Double(height) * 72 / dy)
    }
    guard let tiff = bitmap.representation(using: .tiff, properties: [.compressionFactor: 1.0]),
          fstat(fd, &after) == 0, unchanged(before, after) else { return nil }
    var current = stat()
    guard lstat(url.path, &current) == 0, unchanged(after, current) else { return nil }
    return ReadyImage(png: data, tiff: tiff, width: width, height: height,
        modified: Double(after.st_mtimespec.tv_sec) + Double(after.st_mtimespec.tv_nsec) / 1e9)
}

var outputMetrics = true
func emit(_ event: String, _ fields: [String: Any] = [:]) {
    guard outputMetrics else { return }
    var record = fields
    record["event"] = event; record["time"] = Date().timeIntervalSince1970
    if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) {
        FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
    }
}

final class Candidate {
    var url: URL
    let identity: Identity
    var source: DispatchSourceFileSystemObject?
    let clipboardGeneration: UInt64
    let detected = Date().timeIntervalSince1970
    init(_ url: URL, _ id: Identity, _ generation: UInt64) {
        self.url = url; identity = id; clipboardGeneration = generation
    }
}

protocol ImageClipboard: AnyObject {
    var changeCount: Int { get }
    func publish(_ image: ReadyImage) -> Bool
}

final class NativeImageClipboard: ImageClipboard {
    let pasteboard: NSPasteboard
    init(_ pasteboard: NSPasteboard) { self.pasteboard = pasteboard }
    var changeCount: Int { pasteboard.changeCount }
    func publish(_ image: ReadyImage) -> Bool {
        let item = NSPasteboardItem()
        guard item.setData(image.png, forType: .png), item.setData(image.tiff, forType: .tiff) else { return false }
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }
}

final class ScreenshotWatcher {
    let clipboard: ImageClipboard
    let readImage: (URL, Identity) -> ReadyImage?
    let started = Date().timeIntervalSince1970
    var directories: [String: DispatchSourceFileSystemObject] = [:]
    var seen: Set<Identity> = []
    var candidates: [Identity: Candidate] = [:]
    var ownChangeCount: Int
    var generation: UInt64 = 0
    var cleanupScheduled = false
    var latestCopiedBirth: (Int, Int)?
    var onCopy: ((URL, ReadyImage, Double) -> Void)?
    convenience init(pasteboard: NSPasteboard = .general) {
        self.init(clipboard: NativeImageClipboard(pasteboard))
    }
    init(clipboard: ImageClipboard, readImage: @escaping (URL, Identity) -> ReadyImage? = readReadyImage) {
        self.clipboard = clipboard; self.readImage = readImage
        ownChangeCount = clipboard.changeCount
    }

    func observeClipboard() {
        let count = clipboard.changeCount
        if count != ownChangeCount { generation &+= 1; ownChangeCount = count }
    }

    func watch(_ urls: [URL]) throws {
        let paths = Set(urls.map { $0.standardizedFileURL.resolvingSymlinksInPath().path })
        for path in Array(directories.keys) where !paths.contains(path) {
            if let source = directories.removeValue(forKey: path) {
                source.setEventHandler(handler: nil); source.cancel()
            }
        }
        for path in paths.sorted() where directories[path] == nil {
            let fd = open(path, O_EVTONLY | O_NOFOLLOW)
            guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "Cannot watch \(path): \(String(cString: strerror(errno)))"]) }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
                eventMask: [.write, .rename, .delete, .revoke], queue: .main)
            source.setEventHandler { [weak self] in
                guard let self else { return }
                if !source.data.intersection([.rename, .delete, .revoke]).isEmpty {
                    emit("directory-unavailable", ["path": path]); exit(75)
                }
                autoreleasepool { self.scan(path) }
            }
            source.setCancelHandler { close(fd) }
            directories[path] = source
            // Arm first, then establish the initial baseline without replaying old captures.
            source.resume()
            for url in try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: path),
                includingPropertiesForKeys: nil) {
                var s = stat()
                if lstat(url.path, &s) == 0 { seen.insert(Identity(s)) }
            }
            emit("watching", ["path": path])
        }
    }

    func scan(_ path: String) {
        observeClipboard()
        let scanGeneration = generation
        guard let urls = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: nil) else { emit("scan-failed", ["path": path]); return }
        var found: [(URL, stat)] = []
        var pending: [Candidate] = []
        for url in urls {
            var s = stat()
            guard lstat(url.path, &s) == 0, s.st_mode & S_IFMT == S_IFREG else { continue }
            let id = Identity(s)
            if let candidate = candidates[id] {
                if candidate.url != url { candidate.url = url; pending.append(candidate) }
                continue
            }
            guard !seen.contains(id) else { continue }
            // Old screenshots moved/copied to this directory must not steal the clipboard.
            let birth = Double(s.st_birthtimespec.tv_sec) + Double(s.st_birthtimespec.tv_nsec) / 1e9
            guard birth >= started else { seen.insert(id); continue }
            found.append((url, s))
        }
        found.sort {
            let a = $0.1.st_birthtimespec, b = $1.1.st_birthtimespec
            return a.tv_sec == b.tv_sec ? a.tv_nsec < b.tv_nsec : a.tv_sec < b.tv_sec
        }
        for (url, s) in found {
            guard candidates.count < 128 else { emit("candidate-limit"); break }
            let id = Identity(s), fd = open(url.path, O_EVTONLY | O_NOFOLLOW)
            guard fd >= 0 else { continue }
            var opened = stat()
            guard fstat(fd, &opened) == 0, Identity(opened) == id,
                  opened.st_mode & S_IFMT == S_IFREG else { close(fd); continue }
            let candidate = Candidate(url, id, scanGeneration)
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
                eventMask: [.write, .extend, .attrib, .rename, .delete, .revoke], queue: .main)
            candidate.source = source
            source.setEventHandler { [weak self, weak candidate] in
                guard let self, let candidate else { return }
                if !source.data.intersection([.delete, .revoke]).isEmpty { self.remove(id); return }
                if source.data.contains(.rename) { autoreleasepool { self.scan(path) } }
                autoreleasepool { self.attempt(candidate) }
            }
            source.setCancelHandler { close(fd) }
            candidates[id] = candidate; seen.insert(id); source.resume()
            // Completed captures immediately release their candidate slot; a burst
            // of ready files must not exhaust the incomplete-file descriptor cap.
            autoreleasepool { attempt(candidate) }
        }
        for candidate in pending.sorted(by: {
            ($0.identity.birthSeconds, $0.identity.birthNanos) <
            ($1.identity.birthSeconds, $1.identity.birthNanos)
        }) { autoreleasepool { attempt(candidate) } }
        scheduleCleanup()
    }

    func attempt(_ candidate: Candidate) {
        guard candidates[candidate.identity] != nil,
              candidate.url.pathExtension.lowercased() == "png" else { return }
        let birth = (candidate.identity.birthSeconds, candidate.identity.birthNanos)
        if let latest = latestCopiedBirth, birth < latest { remove(candidate.identity); return }
        observeClipboard()
        guard candidate.clipboardGeneration == generation else {
            emit("skipped-newer-clipboard"); remove(candidate.identity); return
        }
        let eventTime = Date().timeIntervalSince1970
        guard let image = autoreleasepool(invoking: { readImage(candidate.url, candidate.identity) })
        else { return }
        observeClipboard()
        guard candidate.clipboardGeneration == generation else {
            emit("skipped-newer-clipboard"); remove(candidate.identity); return
        }
        // AppKit has no compare-and-swap pasteboard transaction; check immediately
        // before the standard clear+write operation. No screenshot data is promised lazily.
        guard clipboard.changeCount == ownChangeCount else {
            observeClipboard(); remove(candidate.identity); emit("skipped-newer-clipboard"); return
        }
        let success = clipboard.publish(image)
        ownChangeCount = clipboard.changeCount
        if success { latestCopiedBirth = birth }
        let finish = Date().timeIntervalSince1970
        emit(success ? "copied" : "clipboard-write-failed", [
            "width": image.width, "height": image.height, "pngBytes": image.png.count,
            "mtimeToClipboardMs": (finish - image.modified) * 1000,
            "processingMs": (finish - eventTime) * 1000])
        if !success {
            fputs("ScreenshotClipboard: image validated but pasteboard write failed; check clipboard access.\n", stderr)
        }
        remove(candidate.identity)
        if success { onCopy?(candidate.url, image, finish) }
    }

    func remove(_ id: Identity) {
        if let source = candidates.removeValue(forKey: id)?.source {
            source.setEventHandler(handler: nil); source.cancel()
        }
    }
    func scheduleCleanup() {
        guard !cleanupScheduled, !candidates.isEmpty || seen.count > 8192 else { return }
        cleanupScheduled = true
        // One-shot resource cleanup, never a readiness delay or polling loop.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self else { return }
            self.cleanupScheduled = false
            let cutoff = Date().timeIntervalSince1970 - 30
            for (id, candidate) in self.candidates where candidate.detected <= cutoff { self.remove(id) }
            // Keep identities still present, bounding memory across long sessions.
            if self.seen.count > 8192 {
                var present: Set<Identity> = []
                for path in self.directories.keys {
                    for url in (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: path),
                        includingPropertiesForKeys: nil)) ?? [] {
                        var s = stat(); if lstat(url.path, &s) == 0 { present.insert(Identity(s)) }
                    }
                }
                self.seen = present
            }
            if !self.candidates.isEmpty { self.scheduleCleanup() }
        }
    }
    func stop() {
        for source in directories.values { source.setEventHandler(handler: nil); source.cancel() }
        directories.removeAll()
        for id in Array(candidates.keys) { remove(id) }
    }
}
