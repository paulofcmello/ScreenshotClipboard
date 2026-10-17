# Architecture and measurement

[Back to the README](../README.md)

`DispatchSource` uses macOS vnode notifications (kqueue) for directory creation/rename events and per-candidate write/extend/attribute events. There is no screenshot polling, FSEvents batching, readiness sleep, Spotlight indexing dependency, or shortcut replacement. New files are checked immediately. Incomplete files are checked again only when their own vnode changes or their path changes; unrelated directory events do not reread pending images. Completed captures are handled in birth order and immediately release their candidate slots, so a ready burst can exceed the incomplete-file limit. A single one-shot cleanup task releases unused candidate descriptors after approximately 30–60 seconds; it never delays copying. At most 128 incomplete candidates are retained concurrently. A housekeeping task also prunes removed identities above the 8,192-entry threshold, even when every capture completed immediately; a large directory alone does not reschedule that task indefinitely.

Recognition requires the binary plist extended attribute `com.apple.metadata:kMDItemIsScreenCapture` to be true. Filenames and system language do not matter. Existing files, old files moved into the folder, symlinks, ordinary PNGs, and corrupt/incomplete PNGs are ignored. A screenshot copied by another app can retain this metadata; a newly created copy with fresh timestamps cannot always be distinguished from a native capture without observing the capture process. This utility deliberately avoids that extra access.

Before publication, the utility reads an immutable snapshot through a file descriptor, verifies PNG framing and every chunk CRC through Apple's system zlib, requires the terminal IEND chunk, eagerly decodes through ImageIO, prepares PNG and TIFF image representations, and checks file identity, size, modification time, and change time again. A concurrent change rejects the snapshot. Original PNG bytes (including Retina pixels, alpha, DPI and color metadata) are placed on `NSPasteboard`, plus TIFF for broader app support. No path/file URL is placed on the clipboard. Files are never modified by the watcher.

Captures are handled on one serial main queue, with autorelease pools around event handling and individual publications. A newer capture cannot be replaced by an older candidate that finishes late. Every successful capture replaces the previous clipboard image, as with normal screenshot copying; multi-monitor files are handled individually and the last one wins. There is no screenshot history.

The watcher observes pasteboard `changeCount` when a candidate is discovered and before publication. If another app changes the clipboard while that candidate is being prepared, the candidate is skipped to preserve the newer content. It cannot observe a change that occurs before the file's first event. AppKit provides no atomic compare-and-swap transaction across applications, so a tiny final check-to-write race is unavoidable. PNG completeness is established from the format and stable snapshot, not an unreliable assumption that a create event means the writer has closed.

The screenshot preference plist directory is also monitored for location changes; **SIGHUP** reloads the location explicitly. If a watched folder is removed/renamed, the process exits and launchd retries with a 10-second throttle. Restore a missing folder or choose a valid save location. Only events cause work while idle. Image decoding and TIFF generation use transient memory proportional to screenshot dimensions. Very large captures, heavy system load, delayed metadata, or slow/network/cloud-backed save folders can exceed 200 ms; this is a best-effort target, not a real-time scheduling guarantee.

## Live timing

To inspect live production timing, first disable the agent, then run one foreground instance:

```sh
./build/screenshot-clipboard --disable
./build/screenshot-clipboard --metrics
```

Take native screenshots. Each `copied` JSON record reports `processingMs` and `mtimeToClipboardMs`. The latter includes the interval after the last file data modification, filesystem delivery, metadata availability, validation, and pasteboard submission. Modification time is an approximation of write completion, not an exact writer-close timestamp. It is useful as a conservative proxy on local APFS with unchanged timestamps. Stop with **Control+C**, then restore background operation:

```sh
./build/screenshot-clipboard --enable
```

Errors appear in `~/Library/Application Support/ScreenshotClipboard/error.log`. Normal background operation records no screenshots, filenames, or image contents and does not accumulate timing logs.

## References

Apple documents file saving and clipboard capture as alternative native destinations, with the Control modifier selecting the clipboard: [Take a screenshot on Mac](https://support.apple.com/en-ie/102646). Apple's [Dispatch filesystem events](https://developer.apple.com/documentation/dispatch/dispatchsource/filesystemevent) provide write, extend, attribute, and rename notifications. [NSPasteboard](https://developer.apple.com/documentation/appkit/nspasteboard) provides native image transfer; [ImageIO status](https://developer.apple.com/documentation/imageio/cgimagesourcegetstatus(_:)) complements explicit PNG integrity validation.

The [clipboard-screenshot repository](https://github.com/stevederico/clipboard-screenshot) demonstrates the same file-watcher approach using shell/AppleScript. This implementation uses a persistent Swift process to avoid per-capture subprocess startup and sleep delays. [REA](https://github.com/rea-tools/rea) is a reverse-engineering toolkit; no reverse engineering or additional runtime is needed for these public macOS APIs. No code was copied from either project.

See [PERFORMANCE_AUDIT.md](../PERFORMANCE_AUDIT.md) for measured comparisons and the reasons eager TIFF and owned PNG snapshots were retained.
