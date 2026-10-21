import AppKit

// Settings window: turn the app on/off and choose the preview look.
// Runs only while open; the screenshot service is unaffected when it quits.
// It also installs that service: the background app ships inside this bundle,
// so a download needs no compiler, Python or Terminal.
let label = "local.screenshot-clipboard"
let domain = label as CFString
let service = "gui/\(getuid())/\(label)"
let agent = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/LaunchAgents/\(label).plist")

@discardableResult
func run(_ path: String, _ args: [String]) -> (status: Int32, output: Data) {
    let process = Process(); process.executableURL = URL(fileURLWithPath: path); process.arguments = args
    let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return (-1, Data()) }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, data)
}

func isEnabled() -> Bool { run("/bin/launchctl", ["print", service]).status == 0 }

// ⌘⇧3 and ⌘⇧4 are symbolic hotkeys 28 and 30; the service owns them while enabled.
func setNativeShortcuts(_ on: Bool) {
    let data = run("/usr/bin/defaults", ["export", "com.apple.symbolichotkeys", "-"]).output
    guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let keys = plist["AppleSymbolicHotKeys"] as? [String: Any] else { return }
    for id in ["28", "30"] {
        guard var entry = keys[id] as? [String: Any] else { continue }
        entry["enabled"] = on
        guard let xml = try? PropertyListSerialization.data(fromPropertyList: entry, format: .xml, options: 0),
              let text = String(data: xml, encoding: .utf8) else { continue }
        run("/usr/bin/defaults", ["write", "com.apple.symbolichotkeys", "AppleSymbolicHotKeys", "-dict-add", id, text])
    }
    run("/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings", ["-u"])
}

let helper = Bundle.main.bundleURL
    .appendingPathComponent("Contents/Helpers/ScreenshotClipboard.app/Contents/MacOS/screenshot-clipboard")
// macOS runs downloaded apps from a temporary copy until they are moved with Finder.
let translocated = Bundle.main.bundlePath.contains("/AppTranslocation/")

func agentPlist() -> Data? {
    let log = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/ScreenshotClipboard.log")
    return try? PropertyListSerialization.data(fromPropertyList: [
        "Label": label, "ProgramArguments": [helper.path],
        "RunAtLoad": true, "KeepAlive": true, "ThrottleInterval": 10,
        "StandardOutPath": "/dev/null", "StandardErrorPath": log.path,
    ] as [String: Any], format: .xml, options: 0)
}

// True when the service runs a different copy of the app (moved or updated).
func agentIsStale() -> Bool { (try? Data(contentsOf: agent)) != agentPlist() }

func setEnabled(_ on: Bool) {
    if on {
        guard !translocated, FileManager.default.isExecutableFile(atPath: helper.path), let plist = agentPlist() else { return }
        // The user already approved this app on first open; clear the download flag on
        // its own files so launchd can start the background part without another prompt.
        run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", Bundle.main.bundlePath])
        setNativeShortcuts(false)
        try? FileManager.default.createDirectory(at: agent.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? plist.write(to: agent)
        run("/bin/launchctl", ["enable", service])
        run("/bin/launchctl", ["bootout", service])
        run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", agent.path])
    } else {
        run("/bin/launchctl", ["disable", service])
        run("/bin/launchctl", ["bootout", service])
        setNativeShortcuts(true)
    }
}

func appleStyle() -> Bool {
    CFPreferencesAppSynchronize(domain)
    return CFPreferencesCopyAppValue("PreviewStyle" as CFString, domain) as? String == "native"
}

func setAppleStyle(_ on: Bool) {
    CFPreferencesSetAppValue("PreviewStyle" as CFString, on ? "native" as CFString : nil, domain)
    CFPreferencesAppSynchronize(domain)
}

final class Settings: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let enabled = NSButton(checkboxWithTitle: "Enable Screenshot Clipboard", target: nil, action: nil)
    let apple = NSButton(radioButtonWithTitle: "Apple", target: nil, action: nil)
    let classic = NSButton(radioButtonWithTitle: "Classic", target: nil, action: nil)

    func note(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.textColor = .secondaryLabelColor
        field.preferredMaxLayoutWidth = 260
        return field
    }
    func title(_ text: String) -> NSTextField { NSTextField(labelWithString: text) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Screenshot Clipboard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let bar = NSMenu()
        for menu in [appMenu, fileMenu] {
            let item = NSMenuItem(); item.submenu = menu; bar.addItem(item)
        }
        NSApp.mainMenu = bar

        for button in [enabled, apple, classic] { button.target = self }
        enabled.action = #selector(toggleEnabled)
        apple.action = #selector(chooseStyle); classic.action = #selector(chooseStyle)

        let separator = NSBox(); separator.boxType = .separator
        let grid = NSGridView(views: [
            [title("Status:"), enabled],
            [NSGridCell.emptyContentView, note("On: ⌘⇧3 and ⌘⇧4 copy each screenshot to your clipboard.\nOff: your Mac's own screenshots are back, exactly as before. Nothing from this app runs.")],
            [separator],
            [title("Preview:"), apple],
            [NSGridCell.emptyContentView, note("Black frame that slides in from the edge, like macOS.")],
            [NSGridCell.emptyContentView, classic],
            [NSGridCell.emptyContentView, note("Rounded frame in your window color.")],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.row(at: 2).mergeCells(in: NSRange(location: 0, length: 2))
        grid.row(at: 2).topPadding = 6; grid.row(at: 2).bottomPadding = 6
        for row in [1, 4, 6] { grid.row(at: row).topPadding = -4 }
        grid.row(at: 5).topPadding = 4
        grid.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 40),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -40),
        ])
        window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Screenshot Clipboard"
        // Darker, seamless dark-mode background like classic preference windows.
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 42/255, green: 43/255, blue: 43/255, alpha: 1) : .windowBackgroundColor
        }
        window.contentView = content
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        if translocated {
            enabled.isEnabled = false
            grid.cell(atColumnIndex: 1, rowIndex: 1).contentView = note(
                "Drag Screenshot Clipboard into your Applications folder, then open it from there.")
        } else if !FileManager.default.fileExists(atPath: agent.path) || (isEnabled() && agentIsStale()) {
            // First launch turns it on; after a move or update, point the service at this copy.
            setEnabled(true)
        }
        refresh()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    // Settings can also change from Terminal; show the current state whenever focused.
    func applicationDidBecomeActive(_ notification: Notification) { if window != nil { refresh() } }

    func refresh() {
        enabled.state = isEnabled() ? .on : .off
        let isApple = appleStyle()
        apple.state = isApple ? .on : .off
        classic.state = isApple ? .off : .on
        // The preview only exists while enabled.
        apple.isEnabled = enabled.state == .on; classic.isEnabled = apple.isEnabled
    }
    @objc func toggleEnabled() { setEnabled(enabled.state == .on); refresh() }
    @objc func chooseStyle(_ sender: NSButton) { setAppleStyle(sender === apple); refresh() }
}

// Command-line use, e.g. from install.sh: --on, --off, --style apple|classic, --status.
let args = Array(CommandLine.arguments.dropFirst()).filter { !$0.hasPrefix("-psn") }
if let command = args.first {
    switch command {
    case "--on": setEnabled(true)
    case "--off": setEnabled(false)
    case "--style":
        if args.count > 1 {
            guard ["apple", "classic"].contains(args[1]) else { fputs("Usage: --style apple|classic\n", stderr); exit(64) }
            setAppleStyle(args[1] == "apple")
        }
    case "--status": break
    default: fputs("Usage: --on | --off | --style [apple|classic] | --status\n", stderr); exit(64)
    }
    print("Enabled: \(isEnabled() ? "yes" : "no")\nPreview style: \(appleStyle() ? "apple" : "classic")")
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = Settings()
app.delegate = delegate
app.run()
