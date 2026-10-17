# ScreenshotClipboard performance audit

Baseline: `fbeeda8a654d938839bf59fb39d34121872d4d74`. Measured on 2026-10-16/17, Apple Silicon, macOS 26.5.1 (25F80), Swift 6.0.3; optimized whole-module builds targeting macOS 13. [Raw results and individual latency samples](docs/performance-results/) are checked in. Generated images and binaries remain under temporary directories / ignored `build/`.

## Outcome

The justified performance change is eliminating redundant work on unrelated directory events. A controlled workload of 1,000 scans with an unchanged, tagged, corrupt noisy 4K PNG went from **1,000 full read attempts to zero**, and **3,668.06 ms to 42.35 ms** (98.8% less time). This is a synthetic directory-churn measurement, not a claim that normal screenshot publication is 87 times faster.

Normal screenshot latency remains broadly similar, with mixed results across workloads. There is no demonstrated general reduction in peak memory. PNG validation, owned snapshot reads, eager decoding, and eager PNG/TIFF publication remain intact. An initially promising TIFF encoder substitution was measured end-to-end and rejected.

## Implemented changes

- Directory scans attempt new candidates and candidates whose paths changed. Existing incomplete candidates are retried by their own write/extend/attribute events. This removes repeated xattr reads, full PNG allocations, file reads and validation on unrelated directory changes, along with per-candidate symlink resolution on every scan. Partial writes, late metadata and temporary-file renames still work without polling or delays.
- Ready files are processed immediately in birth order and release candidate slots immediately. A burst of 160 complete files, with reverse-sorted filenames, now publishes all 160 rather than exhausting the 128 incomplete-candidate limit or letting filename order suppress older captures. The limit remains for incomplete files.
- Files deferred because of the candidate limit are no longer marked permanently seen. They can be considered on a later directory event. This is not an unlimited queue: 128 simultaneous incomplete/unrelated candidates can still prevent timely discovery of additional files.
- A scan preserves its original clipboard generation for every discovered candidate, even if an external copy occurs during the first image's decoding. A deterministic regression test verifies that the rest of that batch cannot adopt the new generation and overwrite the user's copy.
- Candidate descriptor identity is checked after opening, avoiding attachment to a replacement inode between directory enumeration and open. All original read-time identity and timestamp checks remain.
- Explicit autorelease pools cover event handlers and each publication, bounding the lifetime of temporary Foundation/AppKit objects within a burst. This is a lifetime improvement; the measurements do not establish lower overall peak RSS.
- Identity pruning can be scheduled above 8,192 entries even when no incomplete candidate remains. A large directory alone does not keep rescheduling cleanup. Memory still scales with entries actually present in watched directories. Cleanup remains one-shot/event-driven, not a polling loop.
- Installation preserves the current save folder by default. `--desktop` explicitly requests Desktop; `--keep-location` remains accepted. Missing/default or already-compatible `target`/`type` settings are left alone. Incompatible settings still become saved PNG output because the utility requires files. SystemUIServer is restarted only if settings changed. Native shortcuts and floating-thumbnail settings are untouched.
- Removing the screenshot preference plist now triggers a reload of default directories instead of leaving a stale location indefinitely. Desktop plus the configured folder remain watched, preserving existing behavior.

## Before/after clipboard latency

Both versions ran the **same original test harness**, sequentially, with the same deterministic image-generation workloads and a real isolated named NSPasteboard. Both passed 449 assertions. No general clipboard writes or installation occurred. Timing begins after the fixture writer closes and sets the screenshot attribute, and ends after publication; it includes actual filesystem event delivery, validation, conversion and pasteboard submission. It excludes native screenshot capture/thumbnail delay and the receiving application's paste operation.

| Workload | n each | Mean before → after (ms) | p95 before → after (ms) | p99 before → after (ms) |
|---|---:|---:|---:|---:|
| 1920×1080 gradient | 30 | 18.67 → 17.45 | 19.80 → 18.71 | 22.32 → 21.89 |
| 3840×2160 gradient | 20 | 75.43 → 77.53 | 79.63 → 83.74 | 80.12 → 84.89 |
| 3840×2160 noisy | 10 | 134.70 → 124.12 | 159.16 → 151.37 | 159.16 → 151.37 |

All samples were below 200 ms in this run. These small sample sizes do **not** establish stable tail-latency improvements: nearest-rank p99 is simply the maximum here. The noisy series also has substantial variability. The machine was not isolated from normal system activity. No statistical significance or universal latency guarantee is claimed.

For a larger processing-only sample, both versions read the **same fixture files**, 100 measured calls per image after 3 warmups, using a monotonic clock. This includes full owned reads, CRC/framing, decoding, TIFF conversion, final stat checks and autorelease draining, but excludes events and pasteboard IPC:

| Workload | Mean before → after (ms) | p95 before → after (ms) | p99 before → after (ms) |
|---|---:|---:|---:|
| 1920×1080 | 16.67 → 17.73 | 18.29 → 21.79 | 18.81 → 22.99 |
| 3840×2160 | 65.70 → 63.27 | 70.05 → 66.92 | 71.76 → 72.86 |
| 3840×2160 noisy | 119.44 → 117.30 | 129.03 → 125.32 | 134.06 → 127.51 |

The reader implementation is unchanged in the final version. These differences illustrate run-to-run variation, not a reader optimization.

## Memory, CPU and wakeups

For the identical original integration workloads, `/usr/bin/time -l` reported:

| Metric (whole test process) | Before | After |
|---|---:|---:|
| Maximum RSS | 307,888,128 bytes | 320,143,360 bytes |
| Peak physical footprint | 398,886,160 bytes | 390,022,104 bytes |
| User CPU | 3.70 s | 3.79 s |
| System CPU | 0.70 s | 0.66 s |

These peaks include fixture generation, AppKit readback and the test runner. They are **not** the daemon's idle footprint or a per-screenshot allocation measurement. The 309-call reader stress run reached maximum RSS of 938,393,600 bytes before and 689,422,336 after despite having the same reader code; allocator/framework behavior and system conditions strongly affect this metric. No causal memory reduction is claimed. Large-image decoding and eager TIFF remain significant memory costs.

An isolated watcher harness (empty directory, in-memory clipboard, no preference monitoring) measured 30 seconds after a 2-second warmup. Before/after CPU was 0.001484% / 0.000976%; resident memory at the end was 9,961,472 / 10,043,392 bytes. Each recorded 2 interrupt wakeups and zero package-idle wakeups. These values include measurement/run-loop boundary effects and establish that the watcher was already effectively idle; they do not imply literally zero wakeups or represent a busy Desktop.

The full daemon was also measured, with normal Desktop/configured-folder and preference-directory monitors and a unique named pasteboard, in two sequential 30-second intervals:

| Full-daemon idle metric | Before | After |
|---|---:|---:|
| CPU from kernel counter deltas | 0.000106% | 0.000198% |
| Resident bytes at interval end | 9,879,552 | 9,240,576 |
| Physical footprint at interval end | 2,654,640 bytes | 2,638,256 bytes |
| Interrupt wakeups over 30 s | 1 | 1 |
| Package-idle wakeups over 30 s | 0 | 0 |

CPU time converts Mach absolute-time counters with the measured host timebase (125/3), verified against `getrusage` over a CPU-bound interval; the raw counters and conversion are recorded. The tiny CPU numbers are counter-derived observations, not meaningful comparative precision. Both versions were effectively idle. RSS varies with page residency; this single short run does not establish a persistent memory improvement. Temporary benchmark daemons were stopped after measurement.

## PNG and clipboard experiments rejected

1. **Direct ImageIO TIFF encoding.** A warm-image stage microbenchmark suggested 97.12 ms for NSBitmapImageRep versus 8.04 ms for CGImageDestination on a noisy 4K image. However, stage ordering, image caching and lazy image realization make that comparison unsuitable for predicting the complete path. In the full 100-sample reader experiment, mean times were 17.69/68.96/129.16 ms before versus 19.23/69.89/128.11 ms with direct TIFF, and maximum RSS was 831,619,072 versus 833,929,216 bytes. There was no consistent benefit, so the implementation was reverted. Experimental raw results are retained separately from the final comparison.
2. **Memory mapping.** A warm-cache noisy-4K stage run measured an ordinary Foundation copy read at 3.73 ms, a mapped read plus CRC touch at 1.92 ms, and CRC on existing bytes at 0.82 ms. These are diagnostic stages, not identical operations or production read timings. A mapping is not an immutable snapshot: concurrent overwrite/truncation can alter bytes during validation or fault before post-read checks. Reopening by path also weakens the current descriptor-based identity checks. The modest apparent saving does not justify that correctness risk. The one owned `pread` snapshot, short-read/EINTR handling and before/after stat checks remain.
3. **Deferred TIFF (or PNG).** Apple's [pasteboard data-provider API](https://developer.apple.com/documentation/appkit/nspasteboarditemdataprovider/pasteboard(_:item:providedatafortype:)) supports requested representations, but unmaterialized TIFF would depend on a live provider after copy. Retaining a decoded image increases persistent memory; retaining only PNG requires another decode when TIFF is requested. Graceful shutdown materialization would not handle crashes. This would weaken the existing eager TIFF availability/restart behavior, so no lazy provider was shipped. Both representations are eagerly submitted and require no future file read or service callback.
4. **Skipping CRC or eager decode.** CRC verifies bytes, not successful image decoding. Decode success is not a replacement for explicit framing/CRC validation. All existing checks remain. The terminal-IEND preflight already avoids allocating/reading the full file during an incomplete write. Removing tiny header/tail allocations or replacing Foundation allocation with manual malloc was not justified by the profiles.
5. **Background queues, polling, caches and extra services.** Serial handling already limits concurrent large-image work and simplifies clipboard ordering. Extra workers would require cancellation/backpressure and still serialize AppKit publication. No dependency, background service, recurring readiness timer or polling loop was added.

Apple describes [mappedIfSafe](https://developer.apple.com/documentation/foundation/nsdata/readingoptions) as a mapping hint, not a snapshot guarantee. No unsupported assumption about file immutability is used.

## Validation and reproduction

Run the normal regression suite and build:

```sh
zsh scripts/test.sh
zsh scripts/build.sh
```

The final expanded suite passed **1,108 assertions** in the sandbox using its labelled memory sink; the matched 449-assertion runs above separately verified the real pasteboard. Build, code-signature verification, shell syntax checks and installer/executable help passed. Installation was not rerun.

The expanded suite adds preference-preservation tests, decoded PNG/TIFF pixel equivalence, TIFF dimensions/Retina DPI, trailing-byte rejection, no retries on unrelated scans, a clipboard change during decoding, same-batch generation protection, a 160-file reverse-name burst, and restart-without-replay coverage. Existing CRC, partial-write, delayed metadata, atomic rename, symlink and duplicate-event tests remain. The suite uses an explicitly labelled memory sink if pasteboard IPC is unavailable.

Reproduce the matched comparison in an unrestricted macOS Terminal (resource counters / pasteboard IPC can be denied in a sandbox):

```sh
zsh scripts/benchmark.sh fbeeda8a654d938839bf59fb39d34121872d4d74
zsh scripts/benchmark-idle.sh fbeeda8a654d938839bf59fb39d34121872d4d74
```

The first command compiles both versions with identical flags, runs the original harness unchanged on both, then executes processing, directory-churn and isolated-idle workloads sequentially. Results go to `build/performance/`. The second measures temporary full-daemon processes using unique named pasteboards, then stops them. Neither installs or changes preferences. Python 3 is used only to prepare/collect benchmark files, with no packages or production dependency. `Benchmarks/main.swift` contains the exploratory stage benchmark; it is deliberately separate from end-to-end measurements.

## Remaining bottlenecks and limits

- Full decoding and eager TIFF are the principal latency/memory costs, particularly for noisy 4K captures. The 160-million-pixel safety limit permits much larger allocations than 4K. Lowering it would remove supported functionality; unchanged here.
- Vnode directory notifications do not identify the changed filename, so an O(directory entries) scan remains necessary on namespace events. A very large or busy Desktop can still cost CPU. Replacing kqueue with another framework or requesting extra privileges was not justified.
- Clipboard change-count checks cannot make AppKit's clear/write sequence atomic across applications. The final check-to-write race remains; generation checks protect detected changes during preparation. No claim of an impossible cross-process compare-and-swap is made.
- A service restart deliberately establishes a new baseline and does not replay old screenshots. Screenshots created entirely during downtime are not recovered. A missing watched directory still causes launchd retries with its existing throttle.
- The explicit 128-incomplete-candidate bound and 30–60-second expiry can miss extreme or very slow write workloads. No polling or unbounded backlog was introduced to hide that limit.
- Native shortcut-to-paste latency, third-party apps, multi-monitor capture, wide-gamut/HDR fidelity and logout/login should still be checked manually. Native capture benchmarks were skipped because Screen Recording permission was not already granted; no permission was requested. This audit did not install the modified service or change the user's screenshot settings.

## Subsequent installation verification

At the user’s request, the updated app was rebuilt, reinstalled and restarted after the audit. The expanded suite passed all **1,108 assertions with a real isolated NSPasteboard**; see [installation regression results](docs/performance-results/installed-regressions.json). Launchd reported the new process running, and the configured custom screenshot folder was retained. These later installation timings are separate from the matched before/after experiment above.
