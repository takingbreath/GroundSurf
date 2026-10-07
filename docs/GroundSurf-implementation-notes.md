# GroundSurf 1.3: quality-preserving performance changes

Implemented 7 October 2026. The app retains the original full-detail drawing rules, seeded random-call sequence, coordinate rounding, colors, paper tint, painting order, scrolling speeds, author credit, and icon.

## What changed

- **Faster noise and local calculations.** Skip an upper-Z interpolation whose contribution is exactly zero. Cache repeated planner samples within each planning slab and ten pairs of tree-profile noise values within a scene. Check impossible vegetation positions before evaluating noise. Reuse identical trigonometry and texture-layer calculations. Declare scratch variables locally. No octaves, texture strokes, leaves, or vertices were removed.
- **Reusable numeric drawing commands.** Generate and retain coordinate buffers once instead of building large SVG coordinate strings and parsing them again at every redraw. Float64 storage preserves the old serializer's rounded coordinates exactly. Short composition tokens preserve the library's nested painter order. Text and circles are also supported. The original SVG serializer remains available for validation.
- **Background generation and painting.** A worker prepares scenery off the view's main JavaScript thread. On this Mac, it also paints through OffscreenCanvas and transfers an ImageBitmap. The compatibility path still generates in the worker, then paints commands on the view thread. The app remains entirely offline with its worker embedded in the bundled HTML.
- **One prepared frame ahead.** The view normally requests the next frame halfway to the 512-unit frame boundary. It holds only the displayed frame and one completed future result, with one ordinary outstanding request. This reduces the chance that scenery generation interrupts scrolling. It does not reuse painted overlap as a tile system would.
- **Correct visibility and retention.** Determine visibility from complete horizontal geometry bounds, including stroke margins, instead of an object's anchor. A wide distant ridge stays visible until its last pixels pass. Old geometry and placement records are removed behind the buffer; sample caches remain small or local.
- **Recoverable drawing failures.** Paint into a staging canvas and commit only a complete frame. Release pending state on errors, retain the previous frame, and retry with a delay. A fatal worker error reloads the page. Superseded bitmap results are closed, replaced canvas backing stores are released, and workers terminate when the page leaves.
- **No animation timer while paused or asleep.** Invalidate the native timer and restart it on resume. Track computer sleep and display sleep separately so one wake event cannot clear the other sleep reason. Running animation retains its existing 30 Hz pulse and speed.
- **Smaller wallpaper-only bundle.** Removed dormant browser controls and mouse listeners. Generator attribution and the original MIT license remain included.

## Validation

| Check | Result | What it establishes |
|---|---|---|
| Three fixed seeds: GroundSurf-profile, dense-forest, river-boats | Identical full generated SVG hashes and byte counts before/after | The tested geometry, styles, random sequence, and object ordering were preserved. |
| Command decoding for a fixed complete scene | 61,715 polylines matched the previous SVG coordinates/styles/order exactly | Numeric command storage preserves generated primitives. |
| Native WebKit image comparison, 1024 × 768, seed GroundSurf-quality | Zero differing pixels for both worker painting and compatibility painting | The tested rendered frame, including tint and compositing, is unchanged. This is not proof for every possible seed or display configuration. |
| 100 forward sections, 51,200 coordinate units | Passed retained-object, placement-record, and geometry-size checks | Scene data did not grow with distance in this test. Sampled geometry payload was roughly 8–20 MiB; this excludes object metadata, bitmaps, WebKit, and native process memory. |
| Wide-ridge visibility and injected generator exception | Passed bounds test and recovered on a later request | Previously reproduced disappearance/freeze cases are handled. |
| Native pause and sleep-state harness | Passed pause/resume and overlapping sleep/wake checks | The animation timer stops until every pause/sleep reason is cleared. |
| Packaging | Compiled for Apple Silicon/macOS 13+, verified ad-hoc signature in the build bundle and extracted ZIP | Package is ready for local use. |

The three isolated Node generation runs fell from 5.24 to 3.88 seconds, 2.76 to 2.22 seconds, and 3.07 to 2.27 seconds: **approximately 20–26% faster in these tests**. These compare generator work through the original SVG validation path. They are single runs per seed, subject to system load and runtime variation, and do not establish the percentage reduction in total app CPU. The production command path additionally removes the old repeated coordinate-string parsing.

Raw results are in [GroundSurf-validation.json](GroundSurf-validation.json).

## Memory and remaining limits

Preparing ahead uses another bounded image buffer. A raw full-frame RGBA buffer at the tested desktop sizes costs about 14–15 MiB per display; staging, worker canvas backing stores, and WebKit overhead can add more. Typed commands avoid serialized scene strings, but **lower total RAM has not been established**.

A short two-screen snapshot of the new architecture measured about 398 MiB for the native app, GPU helper, and two content processes, excluding its networking helper. The earlier build averaged 301 MiB over a different short run. These are different seeds and sampling methods, so they cannot be used as a paired performance comparison. They do show why a RAM reduction should not be promised. Neither proves long-run stability or absence of slow leaks.

The new build has not completed a 30–60 minute memory/battery benchmark or overnight soak. Multi-display hot-plug, Spaces transitions, and actual hardware sleep/wake cycles still need broader testing; the timer-state logic was tested directly. The fallback paints on the main thread and can still pause scrolling during a redraw on systems lacking worker canvas support.

## Deferred options

Detail reduction, fewer noise octaves, altered random sampling, merged transparent shapes, and triangulation changes were excluded because they can change the artwork. Lower animation pulse frequency requires interpolation testing to preserve smoothness. Overlap-reusing tiles and a shared multi-display producer remain architectural options for further savings, rather than claims about this release. Coordinate rebasing and hard byte budgets remain long-run robustness work; current cleanup bounds occupied data, not absolute world coordinates.

## Source and installation

Unzip the universal ZIP from [the release](https://github.com/takingbreath/GroundSurf/releases/tag/v1.3.0), move GroundSurf.app to Applications, and open it. The build is ad-hoc signed for local use. Rebuild using scripts/package.sh with Apple's Command Line Tools and Python 3 installed; assemble.py embeds the generator, worker, painter, and viewer into one offline HTML resource. No Python is needed to run the finished app.

Original artwork generator: [Lingdong Huang's shan-shui-inf](https://github.com/LingDong-/shan-shui-inf), MIT license. GroundSurf by Akhilesh Khajuria.
