import Carbon
import AppKit

let label = "local.screenshot-clipboard"
let args = CommandLine.arguments
if args.contains("--status") {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    p.arguments = ["print", "gui/\(getuid())/\(label)"]; try p.run(); p.waitUntilExit(); exit(p.terminationStatus)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let executable = URL(fileURLWithPath: args[0]).standardizedFileURL
let worker = executable.deletingLastPathComponent().appendingPathComponent("capture")
var active: Process?
var readyFile: URL?
var refs: [EventHotKeyRef] = []
func capture(_ id: UInt32) {
    if let old = active, old.isRunning {
        // Selection is already active; let Escape cancel it. A finished capture's
        // preview can be dismissed immediately to allow another screenshot.
        guard let readyFile, FileManager.default.fileExists(atPath: readyFile.path) else { return }
        old.terminate(); old.waitUntilExit()
    }
    if let readyFile { try? FileManager.default.removeItem(at: readyFile) }
    CFPreferencesAppSynchronize("com.apple.screencapture" as CFString)
    let configured = CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String
    let folder = configured.map { ($0 as NSString).expandingTildeInPath }
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path
    let marker = FileManager.default.temporaryDirectory.appendingPathComponent("screenshot-ready-\(UUID().uuidString)")
    let process = Process(); process.executableURL = worker
    process.arguments = ["--output-directory", folder, "--ready-file", marker.path] + (id == 1 ? ["--full-screen"] : [])
    process.terminationHandler = { finished in
        fputs("Capture exited: \(finished.terminationStatus) reason \(finished.terminationReason.rawValue)\n", stderr)
        try? FileManager.default.removeItem(at: marker)
    }
    do { try process.run(); active = process; readyFile = marker }
    catch { fputs("ScreenshotClipboard: \(error.localizedDescription)\n", stderr) }
}
let handler: EventHandlerUPP = { _, event, _ in
    var hotkey = EventHotKeyID()
    guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
        MemoryLayout<EventHotKeyID>.size, nil, &hotkey) == noErr else { return OSStatus(eventNotHandledErr) }
    fputs("Hotkey received\n", stderr)
    capture(hotkey.id)
    return noErr
}
var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
var eventHandler: EventHandlerRef?
guard InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, &eventHandler) == noErr else { exit(1) }
for (id, key) in [(UInt32(1), UInt32(kVK_ANSI_3)), (UInt32(2), UInt32(kVK_ANSI_4))] {
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(key, UInt32(cmdKey | shiftKey), EventHotKeyID(signature: 0x53434350, id: id),
        GetApplicationEventTarget(), 0, &ref)
    guard status == noErr, let ref else {
        fputs("ScreenshotClipboard: shortcut registration failed: \(status)\n", stderr); exit(1)
    }
    refs.append(ref)
}
if let index = args.firstIndex(of: "--ready-file"), index+1 < args.count {
    FileManager.default.createFile(atPath: args[index+1], contents: Data())
}
app.run()
