# RAM optimization — 2026-10-20

The optimized prototype reduces memory without dropping PNG clipboard data, removing drag support, shrinking the screenshot, or leaving a permanent clipboard-provider process running.

## Matched before/after measurements

Same Mac, same 3840 × 2160 / 11,717,944-byte PNG, separate test clipboard, optimized Swift builds. Two fresh baseline runs and two final runs. No screenshot capture, clipboard readback, or preview rendering-to-file inside these measurements. Each process was measured before publication, with preview visible, and after dismissal.

| Physical footprint | Original prototype | Optimized prototype | Reduction |
|---|---:|---:|---:|
| Preview visible, mean | 25.49 MiB | 14.20 MiB | **44.3%** |
| Peak across both phases, mean | 28.59 MiB | 25.02 MiB | **12.5%** |
| Visible preview as share of 8 GiB | 0.311% | 0.173% | |
| Peak as share of 8 GiB | 0.349% | 0.305% | |

Peak is still dominated by moving the full compressed PNG through the clipboard API. Deleting source lines cannot remove that cost. Memory held by the clipboard service, WindowServer and screenshot capture services is outside these process measurements. The existing installed file watcher is unchanged, and these figures should not be compared to its idle memory as equivalent workloads.

PNG publication: baseline **64–71 ms**, optimized **61–72 ms**. Preview window ordering: baseline **286–325 ms**, optimized **391–555 ms**. The additional startup makes the preview later, while copying remains immediate relative to file readiness. These figures exclude capture/selection time.

`/usr/bin/time -l` measured **0.32 CPU seconds** for the timed fresh baseline and **0.24–0.30 CPU seconds** for the final runs, including their measurement waiting periods. No CPU increase was observed, but this small sample is not evidence of a guaranteed CPU or battery improvement. Idle CPU remained below 0.03% of one core. No polling, animation loop, or continuous capture was introduced. Normal operation exits after the five-second preview, so the prototype adds no continuously resident process after dismissal.

## Implementation

1. Capture and eager PNG/file-URL clipboard publication happen before initializing `NSApplication`.
2. `execv` replaces the same process with the preview phase, releasing transfer buffers and caches before creating the window. There is no concurrently resident clipboard helper. The pasted image does not depend on the producer staying alive.
3. Preview still uses the same 440-pixel downsample, displayed within 220 × 160 points, with native file dragging.
4. Normal builds omit resource-counter collection and the extra sampling timer. Measurement builds remain available through the launcher.
5. Fixture generation and independent clipboard checks were moved out of the normal executable into `TestSupport.swift`; the separate old fixture-window source was consolidated there. Duplicate generated executables and failed experiment binaries were deleted. Existing application tests and benchmark evidence were retained because they are useful.

Direct clipboard writes, mapped data and a separate autorelease pool alone did not produce a meaningful RAM reduction. Waiting another main-loop turn also did not help. Neither failed experiment was retained as a separate implementation.

## Validation

- Final measurement and release builds compiled successfully.
- Release build ran against the 4K fixture and exited normally after preview dismissal.
- A separate process, launched after the producer exited, read back exact PNG bytes, the matching file URL, and a usable AppKit image (`NSImage(pasteboard:)`).
- Missing input fails before starting the preview or clearing the clipboard.
- Existing screenshot preferences, installed service, standard shortcuts and source files under `Sources/` were not changed.
- The checkout matches GitHub's HEAD `3a965f8d0b57fad61a78c15a1f7f1d0bd0829be2`. Changes remain local; nothing was published.
- Real Finder drag/drop and paste into individual third-party apps remain manual integration checks, as in the original prototype.

## Evidence and methodology

`build/thumbnail-optimization/` contains baseline source/binary, `baseline-1.jsonl`, `baseline-2.jsonl`, `final-1.jsonl`, `final-2.jsonl`, resource outputs, `validation.txt` and `summary.json`. Generate summaries with:

```sh
python3 Prototypes/Thumbnail/summarize.py build/thumbnail-optimization
```

**Important:** the kernel's lifetime peak-footprint counter resets across `execv`. The report uses the maximum recorded peak from **both** the clipboard and preview phases, not just `/usr/bin/time`'s final-phase footprint. Reporting only that final footprint would incorrectly claim a much larger peak reduction. The two phases are sequential, so their footprints are not added.

CPU snapshots within each phase use Mach timebase conversion. External `time` output supplies total user+system CPU time. Two runs are sufficient to demonstrate the large visible-memory reduction but not to establish power consumption or fine-grained speed differences statistically.

## Bounded lower-level clipboard experiment

A standalone C implementation used public `PasteboardCreate` / `PasteboardPutItemFlavor`, with read-only `mmap` and `CFDataCreateWithBytesNoCopy`. Two runs on the same captured 4K fixture peaked at **24.38 and 24.33 MiB**, versus the current prototype's roughly **25.02 MiB** across phases. The apparent difference is under 3% (less than 0.7 MiB), and includes language/runtime differences; it does not establish a useful improvement in the full app.

Both writes returned success, but a separate AppKit reader could not retrieve the test clipboard's PNG or file URL after producer exit. A subsequent diagnostic found no advertised types. Custom pasteboard naming or lifetime interoperability remains unresolved; this is not evidence that the general system clipboard API is broken. Testing deliberately did not overwrite the user's general clipboard.

**Decision:** retain the verified implementation. No shipping code changed. Stop this experiment rather than spend more investigation time on an unproven sub-megabyte reduction. Raw C source, JSON measurements and reader diagnostic source are in `build/clipboard-experiment/`. This experiment does not establish battery savings, native-thumbnail memory usage, or an earlier native screenshot-access path.
