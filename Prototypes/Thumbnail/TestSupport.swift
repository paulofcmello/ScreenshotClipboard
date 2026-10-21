import AppKit
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i+1]
}
// Fixture generation runs in its own process, outside the measured UI process.
if let path = option("--make-fixture") {
    let w = 3840, h = 2160
    let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
    var rng: UInt32 = 12345
    for y in 0..<h { for x in 0..<w {
        // Deterministic textured fixture, less compressible than a flat desktop.
        rng = rng &* 1664525 &+ 1013904223
        let i = (y * w + x) * 4
        pixels[i] = UInt8((x / 16 + Int(rng >> 28)) % 256)
        pixels[i+1] = UInt8((y / 8 + Int(rng >> 28)) % 256)
        pixels[i+2] = UInt8((x / 32 + y / 16) % 256)
        pixels[i+3] = 255
    } }
    let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination))
    exit(0)
}


if let name = option("--verify-pasteboard"), let path = option("--file") {
    let board = NSPasteboard(name: .init(name))
    let file = URL(fileURLWithPath: path).standardizedFileURL
    guard let expected = try? Data(contentsOf: file), board.data(forType: .png) == expected,
          board.string(forType: .fileURL) == file.absoluteString,
          NSImage(pasteboard: board) != nil else {
        fputs("Clipboard round-trip failed\n", stderr); exit(1)
    }
    print("PASS: exact PNG, file URL and AppKit image readback after producer exit")
    board.releaseGlobally()
    exit(0)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1920, height: 1080), styleMask: [.borderless], backing: .buffered, defer: false)
let view = NSImageView(frame: NSRect(x: 0, y: 0, width: 1920, height: 1080))
view.image = NSImage(contentsOfFile: CommandLine.arguments[1])
view.imageScaling = .scaleAxesIndependently
window.contentView = view
window.orderFrontRegardless()
print(window.windowNumber)
fflush(stdout)
DispatchQueue.main.asyncAfter(deadline: .now() + 30) { NSApp.terminate(nil) }
app.run()
