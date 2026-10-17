import AppKit
import ImageIO
import Darwin

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let data = try Data(contentsOf: url)
let iterations = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2])! : 30
func measure(_ name: String, _ body: () -> Void) {
    var samples: [Double] = []
    for _ in 0..<iterations {
        let start = DispatchTime.now().uptimeNanoseconds
        autoreleasepool { body() }
        samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
    }
    samples.sort()
    let report: [String: Any] = ["stage": name, "count": iterations,
        "meanMs": samples.reduce(0,+)/Double(iterations),
        "p95Ms": samples[Int(ceil(Double(iterations)*0.95))-1],
        "p99Ms": samples[Int(ceil(Double(iterations)*0.99))-1]]
    print(String(data: try! JSONSerialization.data(withJSONObject: report, options: .sortedKeys), encoding: .utf8)!)
}
measure("read-copy") { precondition((try! Data(contentsOf: url)).count == data.count) }
measure("read-mapped-and-touch") {
    let mapped = try! Data(contentsOf: url, options: .alwaysMapped)
    precondition(completePNG(mapped))
}
measure("crc-framing") { precondition(completePNG(data)) }
measure("decode") {
    let source = CGImageSourceCreateWithData(data as CFData, nil)!
    precondition(CGImageSourceCreateImageAtIndex(source, 0,
        [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) != nil)
}
let source = CGImageSourceCreateWithData(data as CFData, nil)!
let image = CGImageSourceCreateImageAtIndex(source, 0,
    [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)!
measure("bitmap-tiff") {
    let bitmap = NSBitmapImageRep(cgImage: image)
    precondition(bitmap.representation(using: .tiff, properties: [.compressionFactor: 1.0]) != nil)
}
measure("imageio-tiff") {
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(output, "public.tiff" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination))
}
