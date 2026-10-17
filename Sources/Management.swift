import AppKit

let serviceLabel = "local.screenshot-clipboard"
let preferenceDomain = "com.apple.screencapture"
let supportDirectory = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/ScreenshotClipboard", isDirectory: true)
let installedApp = supportDirectory.appendingPathComponent("ScreenshotClipboard.app", isDirectory: true)
let installedBinary = installedApp.appendingPathComponent("Contents/MacOS/screenshot-clipboard")
let launchAgent = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/LaunchAgents/\(serviceLabel).plist")
let preferencesBackup = supportDirectory.appendingPathComponent("screenshot-preferences.plist")

func preference(_ key: String) -> Any? {
    CFPreferencesCopyAppValue(key as CFString, preferenceDomain as CFString)
}

func configuredDirectories() -> [URL] {
    CFPreferencesAppSynchronize(preferenceDomain as CFString)
    let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    guard let path = preference("location") as? String, !path.isEmpty else { return [desktop] }
    return [desktop, URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)]
}

@discardableResult
func run(_ executable: String, _ arguments: [String], allowFailure: Bool = false) throws -> Int32 {
    let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
    try process.run(); process.waitUntilExit()
    if !allowFailure && process.terminationStatus != 0 {
        throw NSError(domain: serviceLabel, code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: "\(executable) failed (\(process.terminationStatus))"])
    }
    return process.terminationStatus
}

func writePlist(_ value: Any, _ url: URL) throws {
    let data = try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
    try data.write(to: url, options: .atomic)
}

func manage(_ command: String, keepLocation: Bool) throws {
    let fm = FileManager.default, uid = getuid(), domain = "gui/\(uid)"
    switch command {
    case "--install":
        let macos = installedBinary.deletingLastPathComponent()
        try fm.createDirectory(at: macos, withIntermediateDirectories: true)
        try fm.createDirectory(at: launchAgent.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: preferencesBackup.path) {
            CFPreferencesAppSynchronize(preferenceDomain as CFString)
            var old: [String: Any] = [:]
            for key in ["target", "type", "location"] {
                old[key] = preference(key) ?? ["absent": true]
            }
            try writePlist(old, preferencesBackup)
        }
        let source = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        if source != installedBinary.standardizedFileURL {
            // Atomic replacement lets an existing running process finish safely.
            try Data(contentsOf: source).write(to: installedBinary, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedBinary.path)
        }
        try writePlist([
            "CFBundleIdentifier": serviceLabel, "CFBundleName": "ScreenshotClipboard",
            "CFBundleExecutable": "screenshot-clipboard", "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0", "LSUIElement": true,
            "NSDesktopFolderUsageDescription": "Read newly saved screenshots to copy their images to the clipboard."
        ], installedApp.appendingPathComponent("Contents/Info.plist"))
        try run("/usr/bin/codesign", ["--force", "--sign", "-", installedApp.path])
        // Save exactly which values we own, so uninstall preserves subsequent edits.
        var applied: [String: String] = ["target": "file", "type": "png"]
        if !keepLocation {
            applied["location"] = fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path
        }
        let appliedURL = supportDirectory.appendingPathComponent("applied-preferences.plist")
        var owned = applied
        if let previousData = try? Data(contentsOf: appliedURL),
           let previous = try PropertyListSerialization.propertyList(from: previousData, format: nil) as? [String: String] {
            owned = previous.merging(applied) { _, new in new }
        }
        try writePlist(owned, appliedURL)
        for (key, value) in applied {
            CFPreferencesSetAppValue(key as CFString, value as CFString, preferenceDomain as CFString)
        }
        guard CFPreferencesAppSynchronize(preferenceDomain as CFString) else {
            throw NSError(domain: serviceLabel, code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not save screenshot preferences"])
        }
        try writePlist([
            "Label": serviceLabel,
            "ProgramArguments": [installedBinary.path],
            "RunAtLoad": true, "KeepAlive": true, "ThrottleInterval": 10,
            "LimitLoadToSessionType": "Aqua", "ProcessType": "Interactive",
            "StandardOutPath": "/dev/null",
            "StandardErrorPath": supportDirectory.appendingPathComponent("error.log").path
        ], launchAgent)
        try run("/bin/launchctl", ["bootout", "\(domain)/\(serviceLabel)"], allowFailure: true)
        try run("/bin/launchctl", ["enable", "\(domain)/\(serviceLabel)"])
        try run("/bin/launchctl", ["bootstrap", domain, launchAgent.path])
        // Restart the menu-extra host to refresh cached native screenshot settings.
        try run("/usr/bin/killall", ["SystemUIServer"], allowFailure: true)
        print("Installed and started. Screenshots save as PNG and copy automatically.")
        print("If Desktop access is requested, allow it. No Accessibility or Screen Recording access is needed.")
    case "--disable":
        try run("/bin/launchctl", ["disable", "\(domain)/\(serviceLabel)"])
        try run("/bin/launchctl", ["bootout", "\(domain)/\(serviceLabel)"], allowFailure: true)
        print("Disabled, including after login. Screenshot files and clipboard were not changed.")
    case "--enable":
        try run("/bin/launchctl", ["enable", "\(domain)/\(serviceLabel)"])
        try run("/bin/launchctl", ["bootstrap", domain, launchAgent.path], allowFailure: true)
        try run("/bin/launchctl", ["kickstart", "\(domain)/\(serviceLabel)"])
    case "--status":
        try run("/bin/launchctl", ["print", "\(domain)/\(serviceLabel)"], allowFailure: true)
        print("Watched on startup: \(configuredDirectories().map(\.path).joined(separator: ", "))")
    case "--uninstall":
        try run("/bin/launchctl", ["bootout", "\(domain)/\(serviceLabel)"], allowFailure: true)
        // Restore only preferences still equal to the values set by this installer.
        if let data = try? Data(contentsOf: preferencesBackup),
           let old = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let appliedData = try? Data(contentsOf: supportDirectory.appendingPathComponent("applied-preferences.plist")),
           let applied = try PropertyListSerialization.propertyList(from: appliedData, format: nil) as? [String: String] {
            CFPreferencesAppSynchronize(preferenceDomain as CFString)
            for (key, value) in applied where preference(key) as? String == value {
                let saved = old[key]
                let absent = (saved as? [String: Bool])?["absent"] == true
                CFPreferencesSetAppValue(key as CFString, absent ? nil : saved as CFPropertyList?, preferenceDomain as CFString)
            }
            CFPreferencesAppSynchronize(preferenceDomain as CFString)
            try run("/usr/bin/killall", ["SystemUIServer"], allowFailure: true)
        }
        // Only exact utility-owned artifacts are removed. Never touch capture folders.
        for url in [launchAgent, installedApp, preferencesBackup,
                    supportDirectory.appendingPathComponent("applied-preferences.plist"),
                    supportDirectory.appendingPathComponent("error.log")] where fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        print("Uninstalled utility and its configuration. Original screenshot settings restored where unchanged.")
    default: break
    }
}
