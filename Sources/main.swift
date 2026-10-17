import AppKit

do {
    let args = Array(CommandLine.arguments.dropFirst())
    let commands = ["--install", "--disable", "--enable", "--uninstall", "--status"]
    if let command = args.first, commands.contains(command) {
        try manage(command, desktop: args.contains("--desktop"))
        exit(0)
    }
    if args.contains("--help") {
        print("""
        screenshot-clipboard [--directory PATH] [--metrics] [--pasteboard NAME]
        screenshot-clipboard --install [--desktop]
        screenshot-clipboard --disable | --enable | --status | --uninstall
        Default: monitor Desktop and the native screenshot save folder.
        --metrics: JSON timing records on stdout (no filenames or image contents).
        --pasteboard: use a named, isolated pasteboard for testing.
        """)
        exit(0)
    }
    func option(_ flag: String) throws -> String? {
        guard let index = args.firstIndex(of: flag) else { return nil }
        guard index + 1 < args.count, !args[index + 1].hasPrefix("--") else {
            throw NSError(domain: serviceLabel, code: 64,
                userInfo: [NSLocalizedDescriptionKey: "Missing value for \(flag)"])
        }
        return args[index + 1]
    }
    let override = try option("--directory"), board = try option("--pasteboard")
    outputMetrics = args.contains("--metrics")
    let pasteboard = board.map { NSPasteboard(name: .init($0)) } ?? .general
    let watcher = ScreenshotWatcher(pasteboard: pasteboard)
    try watcher.watch(override.map { [URL(fileURLWithPath: $0, isDirectory: true)] } ?? configuredDirectories())
    signal(SIGTERM, SIG_IGN); signal(SIGINT, SIG_IGN); signal(SIGHUP, SIG_IGN)
    let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    let reload = DispatchSource.makeSignalSource(signal: SIGHUP, queue: .main)
    for source in [terminate, interrupt] {
        source.setEventHandler { watcher.stop(); exit(0) }; source.resume()
    }
    reload.setEventHandler {
        do { try watcher.watch(override.map { [URL(fileURLWithPath: $0)] } ?? configuredDirectories()) }
        catch { fputs("\(error.localizedDescription)\n", stderr) }
    }
    reload.resume()
    // Preferences are atomically replaced by cfprefsd. Observe their directory,
    // then check this domain's file stamp before reading preferences.
    var preferencesSource: DispatchSourceFileSystemObject?
    if override == nil {
        let prefs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences")
        let fd = open(prefs.path, O_EVTONLY)
        if fd >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
            var lastStamp: String = ""
            source.setEventHandler {
                var s = stat()
                let path = prefs.appendingPathComponent("com.apple.screencapture.plist").path
                let exists = lstat(path, &s) == 0
                let stamp = exists ? "\(s.st_ino):\(s.st_mtimespec.tv_sec):\(s.st_mtimespec.tv_nsec)" : "absent"
                guard stamp != lastStamp else { return }; lastStamp = stamp
                do { try watcher.watch(configuredDirectories()) }
                catch { fputs("\(error.localizedDescription)\n", stderr) }
            }
            source.setCancelHandler { close(fd) }; source.resume(); preferencesSource = source
        }
    }
    withExtendedLifetime((watcher, terminate, interrupt, reload, preferencesSource)) {
        RunLoop.main.run()
    }
} catch {
    fputs("ScreenshotClipboard: \(error.localizedDescription)\n", stderr)
    if CommandLine.arguments.contains("--install") {
        fputs("Run installation from Terminal under your own login, outside restricted agent sandboxes. No sudo needed.\n", stderr)
    } else {
        fputs("Check Files and Folders > Desktop access in System Settings > Privacy & Security.\n", stderr)
    }
    exit(1)
}
