import AppKit

// Settings window: turn the app on/off, choose whether screenshots are saved
// and/or copied, choose the preview look, and update from GitHub.
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

// Saving and copying are on unless turned off; only the off state is stored.
func option(_ key: String) -> Bool {
    CFPreferencesAppSynchronize(domain)
    return CFPreferencesCopyAppValue(key as CFString, domain) as? Bool != false
}

func setOption(_ key: String, _ on: Bool) {
    CFPreferencesSetAppValue(key as CFString, on ? nil : kCFBooleanFalse, domain)
    CFPreferencesAppSynchronize(domain)
}

// Updates come from the latest GitHub release: its tag is the version, its DMG the app.
let releaseAPI = URL(string: "https://api.github.com/repos/paulofcmello/ScreenshotClipboard/releases/latest")!
let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
struct Release { let version: String; let dmg: URL }

func failure(_ text: String) -> NSError { NSError(domain: label, code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }

func isNewer(_ a: String, than b: String) -> Bool {
    let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
    for i in 0..<max(x.count, y.count) where (i < x.count ? x[i] : 0) != (i < y.count ? y[i] : 0) {
        return (i < x.count ? x[i] : 0) > (i < y.count ? y[i] : 0)
    }
    return false
}

func latestRelease() async throws -> Release {
    var request = URLRequest(url: releaseAPI)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let tag = json["tag_name"] as? String,
          let assets = json["assets"] as? [[String: Any]],
          let link = assets.first(where: { $0["name"] as? String == "ScreenshotClipboard.dmg" })?["browser_download_url"] as? String,
          let dmg = URL(string: link) else { throw failure("Couldn't read the latest release from GitHub.") }
    return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, dmg: dmg)
}

// Downloads the release, checks it, swaps it in for this copy of the app and restarts
// the screenshot service when it runs from this copy. Files fetched by this app carry
// no download flag, so the new copy opens without the Open Anyway step.
func install(_ release: Release) async throws {
    let work = FileManager.default.temporaryDirectory.appendingPathComponent("ScreenshotClipboard-update-\(UUID().uuidString)")
    let mount = work.appendingPathComponent("mount"), image = work.appendingPathComponent("update.dmg")
    try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
    defer {
        run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
        try? FileManager.default.removeItem(at: work)
    }
    let (download, response) = try await URLSession.shared.download(from: release.dmg)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw failure("The download failed.") }
    try FileManager.default.moveItem(at: download, to: image)
    guard run("/usr/bin/hdiutil", ["attach", image.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path]).status == 0
    else { throw failure("The download couldn't be opened.") }
    let new = mount.appendingPathComponent("Screenshot Clipboard.app")
    guard Bundle(url: new)?.bundleIdentifier == Bundle.main.bundleIdentifier,
          run("/usr/bin/codesign", ["--verify", "--deep", "--strict", new.path]).status == 0
    else { throw failure("The download isn't a valid copy of the app.") }
    // Stage next to this copy so the swap stays on one disk.
    let current = Bundle.main.bundleURL
    let staged = current.deletingLastPathComponent().appendingPathComponent(".Screenshot Clipboard update.app")
    try? FileManager.default.removeItem(at: staged)
    guard run("/usr/bin/ditto", [new.path, staged.path]).status == 0
    else { throw failure("Couldn't write to \(current.deletingLastPathComponent().path).") }
    let restart = isEnabled() && !agentIsStale()
    _ = try FileManager.default.replaceItemAt(current, withItemAt: staged)
    if restart { setEnabled(true) }
}

final class Settings: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let enabled = NSButton(checkboxWithTitle: "Enable Screenshot Clipboard", target: nil, action: nil)
    let save = NSButton(checkboxWithTitle: "Save as a file", target: nil, action: nil)
    let copy = NSButton(checkboxWithTitle: "Copy to clipboard", target: nil, action: nil)
    let apple = NSButton(radioButtonWithTitle: "Apple", target: nil, action: nil)
    let classic = NSButton(radioButtonWithTitle: "Classic", target: nil, action: nil)
    let update = NSButton(title: "Check for Updates", target: nil, action: nil)
    var updateNote: NSTextField!
    var available: Release?

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

        for button in [enabled, save, copy, apple, classic] { button.target = self }
        enabled.action = #selector(toggleEnabled)
        save.action = #selector(toggleOption); copy.action = #selector(toggleOption)
        update.target = self; update.action = #selector(updateClicked)
        updateNote = note("Version \(currentVersion)")
        apple.action = #selector(chooseStyle); classic.action = #selector(chooseStyle)

        let separator = NSBox(); separator.boxType = .separator
        let separator2 = NSBox(); separator2.boxType = .separator
        let separator3 = NSBox(); separator3.boxType = .separator
        let grid = NSGridView(views: [
            [title("Status:"), enabled],
            [NSGridCell.emptyContentView, note("On: ⌘⇧3 and ⌘⇧4 use the options below.\nOff: your Mac's normal screenshots come back and this app does nothing.")],
            [separator],
            [title("Screenshots:"), save],
            [NSGridCell.emptyContentView, copy],
            [NSGridCell.emptyContentView, note("Files go to your screenshot folder. At least one stays on.")],
            [separator2],
            [title("Preview:"), apple],
            [NSGridCell.emptyContentView, note("Black frame that slides in from the edge, like macOS.")],
            [NSGridCell.emptyContentView, classic],
            [NSGridCell.emptyContentView, note("Rounded frame in your window color.")],
            [separator3],
            [title("Updates:"), update],
            [NSGridCell.emptyContentView, updateNote],
        ])
        grid.column(at: 0).xPlacement = .trailing
        // Wrapped notes measure their height at this width; a matching column keeps
        // every line visible.
        grid.column(at: 1).width = 260
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        for row in [2, 6, 11] {
            grid.row(at: row).mergeCells(in: NSRange(location: 0, length: 2))
            grid.row(at: row).topPadding = 6; grid.row(at: row).bottomPadding = 6
        }
        for row in [1, 5, 8, 10, 13] { grid.row(at: row).topPadding = -4 }
        grid.row(at: 9).topPadding = 4
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
            enabled.isEnabled = false; update.isEnabled = false
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
        if !translocated { checkForUpdate() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    // Settings can also change from Terminal; show the current state whenever focused.
    func applicationDidBecomeActive(_ notification: Notification) { if window != nil { refresh() } }

    func refresh() {
        enabled.state = isEnabled() ? .on : .off
        let isApple = appleStyle()
        apple.state = isApple ? .on : .off
        classic.state = isApple ? .off : .on
        save.state = option("SaveFile") ? .on : .off
        copy.state = option("CopyToClipboard") ? .on : .off
        // These only apply while enabled; the last one on can't be turned off.
        let on = enabled.state == .on
        apple.isEnabled = on; classic.isEnabled = on
        save.isEnabled = on && copy.state == .on
        copy.isEnabled = on && save.state == .on
    }
    @objc func toggleEnabled() { setEnabled(enabled.state == .on); refresh() }
    // One quiet request each time the window opens; nothing runs in the background.
    func checkForUpdate() {
        update.isEnabled = false
        updateNote.stringValue = "Version \(currentVersion) · Checking…"
        Task { @MainActor in
            do {
                let release = try await latestRelease()
                if isNewer(release.version, than: currentVersion) {
                    available = release
                    update.title = "Update Now"
                    updateNote.stringValue = "Version \(release.version) is available. You have \(currentVersion)."
                } else {
                    updateNote.stringValue = "Version \(currentVersion) · Up to date"
                }
            } catch {
                updateNote.stringValue = "Version \(currentVersion) · Couldn't check for updates."
            }
            update.isEnabled = true
        }
    }
    @objc func updateClicked() {
        guard let release = available else { checkForUpdate(); return }
        update.isEnabled = false
        updateNote.stringValue = "Updating to \(release.version)…"
        Task { @MainActor in
            do {
                try await install(release)
                // Reopen the new copy once this one has quit.
                let reopen = Process(); reopen.executableURL = URL(fileURLWithPath: "/bin/sh")
                reopen.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
                try? reopen.run()
                NSApp.terminate(nil)
            } catch {
                updateNote.stringValue = "\(error.localizedDescription) You can still download it from GitHub."
                update.isEnabled = true
            }
        }
    }
    @objc func toggleOption(_ sender: NSButton) {
        setOption(sender === save ? "SaveFile" : "CopyToClipboard", sender.state == .on); refresh()
    }
    @objc func chooseStyle(_ sender: NSButton) { setAppleStyle(sender === apple); refresh() }
}

// Command-line use, e.g. from install.sh: --on, --off, --style apple|classic,
// --save on|off, --copy on|off, --check-update, --update, --status.
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
    case "--save", "--copy":
        if args.count > 1 {
            guard ["on", "off"].contains(args[1]) else { fputs("Usage: \(command) on|off\n", stderr); exit(64) }
            let key = command == "--save" ? "SaveFile" : "CopyToClipboard"
            let other = command == "--save" ? "CopyToClipboard" : "SaveFile"
            guard args[1] == "on" || option(other) else { fputs("Saving and copying can't both be off.\n", stderr); exit(64) }
            setOption(key, args[1] == "on")
        }
    case "--check-update", "--update":
        Task {
            do {
                let release = try await latestRelease()
                guard isNewer(release.version, than: currentVersion) else { print("Up to date (\(currentVersion)).") ; exit(0) }
                print("Version \(release.version) is available. You have \(currentVersion).")
                if command == "--update" { try await install(release); print("Updated to \(release.version).") }
                exit(0)
            } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
        }
        dispatchMain()
    case "--status": break
    default:
        fputs("Usage: --on | --off | --style [apple|classic] | --save [on|off] | --copy [on|off] | --check-update | --update | --status\n", stderr)
        exit(64)
    }
    print("Enabled: \(isEnabled() ? "yes" : "no")\nSave file: \(option("SaveFile") ? "on" : "off")")
    print("Copy to clipboard: \(option("CopyToClipboard") ? "on" : "off")\nPreview style: \(appleStyle() ? "apple" : "classic")")
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = Settings()
app.delegate = delegate
app.run()
