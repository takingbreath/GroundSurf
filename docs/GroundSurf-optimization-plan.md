# GroundSurf: generator and performance improvement plan

Prepared 7 October 2026. This records the review before implementation; its estimates remain planning figures. The approved quality-preserving changes are now implemented in GroundSurf 1.3. See GroundSurf-implementation-notes.md for the actual scope, validation, measured generation timings, and memory tradeoff.

## Assessment

The original library is an expressive procedural SVG artwork generator, rather than a renderer designed for continuous wallpaper use. It uses sensible bounded recursion for trees and noise to create natural geometry, but also generates large numbers of small polygons, repeats noise evaluations, and allocates many short-lived arrays and strings. GroundSurf's bounded scenery buffer addresses indefinite retention; the canvas adaptation addresses SVG repaint cost. Neither makes the full pipeline optimally efficient.

The most worthwhile next changes are a mathematically equivalent fast path for 2D noise, reusable geometry commands instead of SVG serialization/parsing, generation ahead of the view, and reducing animation-related process communication. Triangulation replacement is a lower priority in the measured scene.

## Evidence and methodology

The JavaScript tests used this Mac's Node/V8 runtime, a fixed seed, a 1,422-unit viewport, and ten successive 512-unit updates, including initial look-ahead generation. Three runs were used for each initial variant. Geometry was generated but not painted during these generation benchmarks. Node timings are not WKWebView timings and are not end-to-end wallpaper, RAM, GPU, or battery measurements. Fixed-seed hashes compare the full generated SVG output, not just object counts. Initial variants ran sequentially and can be affected by run order and system load; the noise shortcut used alternating baseline/variant runs.

An instrumented baseline recorded 138 main mountains, seven flat mountains, seven distant ridges, about 108,349 polyline emissions, 50,176 leaf/blob calls, 44,654 stroke calls, and 3,146,370 noise calls. Its cumulative ten-view output was 145.4 MB of SVG text; that cumulative benchmark output is not retained by the production app. Wrapper instrumentation adds overhead; its time shares indicate hotspots rather than exact percentages of native runtime.

### Observed hotspots

| Operation | Approximate exclusive share in the instrumented run | Interpretation |
|---|---:|---|
| Perlin noise | 67% | Highest-value generator target; many leaf, texture, and stroke calls |
| Leaf/blob geometry excluding nested noise and output | 11% | Repeated shape construction and trigonometry |
| Stroke geometry excluding nested calls | 6.5% | Array copying, trigonometry, and per-vertex width noise |
| SVG polyline serialization | 3.9% | Separate from the app's subsequent parsing cost |
| Texture construction excluding nested calls | 3.5% | Layer interpolation and temporary coordinate arrays |
| Triangulation excluding recursive/nested calls | 0.3% | Not the main bottleneck for this seed |
| Planner excluding nested noise | 0.1% | Cheap overall despite redundant work |

A single sampled scene produced 53,897 polylines and 1,167,227 vertices in 19.97 MB of SVG. Parsing those coordinates and styles took a median 286 ms across five Node runs, before any actual canvas painting. This shows that even the current canvas adaptation can have a significant boundary-time stall.

### Isolated experiments

| Experiment | Measured result | Output preservation | Confidence and practical meaning |
|---|---|---|---|
| Skip upper-Z interpolation when fractional Z is zero in the noise function | About 17.1% faster generation in an alternating baseline/variant test | Same full SVG hash for tested seed | Strong candidate; one of three variant runs was slower, so more seeds and WebKit validation are required |
| Cache repeated X-only planner noise inside each planning slab | 47,811 noise calls became 21,634 over 20 planning slabs; planner elapsed time roughly halved | Identical plan data and full-scene hash in separate tests | High confidence in reduced planner work, small overall benefit |
| Reject impossible vegetation positions before computing noise | Initial macro median 8.46s versus 9.50s baseline | Same full SVG hash | Initial macro result suggests about 11%, but unpaired run order and system load confound attribution; use a conservative estimate |
| Suppress polyline text emission entirely | Initial macro median 8.45s versus 9.50s | Intentionally no complete artwork | An upper-bound experiment, not a working renderer or validated command backend |

The initial planner-cache macro median was 8.88s versus 9.50s. Its apparent approximately 6.5% whole-run gain is larger than the planner's measured share supports. It should be treated as timing variation, not a promised app improvement.

## Prioritized improvements

Percentages below apply to the named component unless explicitly stated as total-app impact. They overlap and must not be added. Estimates are planning ranges, not guarantees.

| Priority | Improvement | Where and why | Approximate impact | Confidence / tradeoff |
|---|---|---|---|---|
| Essential | Use complete horizontal bounds for visibility and cleanup | `chunkrender` filters origins using a 512-unit margin, although a ridge can extend 1,500 units. Track min/max geometry bounds, including stroke width, rather than guessing from anchors. | Eliminates reproduced early-disappearing ridges; tighter culling may reduce repaint work by 5–20% in some scenes, but is not measured. | High confidence in correctness. Bounds work is a prerequisite for safe tiles. |
| Essential | Always release the render busy flag and preserve the last valid frame | A generator or drawing exception currently leaves `busy=true` forever. Render into a staging buffer, recover with `try/finally`, and avoid immediate retry loops. | Prevents reproduced permanent freeze; near-zero steady-state speed benefit. | High confidence. Staging adds one bounded bitmap. |
| Essential | Preserve every emitted primitive and painting order | Current canvas parser only handles polylines. The library can emit text for building signs; future circles such as a sun would also be ignored. | Restores full library fidelity; no inherent speed gain. | High confidence from source. A new command backend must include text, circles, fill/stroke styles, layering, and paper blending. |
| High | Specialize Perlin noise for 2D/integer-Z calls | Most leaf/texture/stroke calls omit Z. The existing routine calculates the upper Z layer even when its blend weight is zero. Keep the existing 3D path and preserve initialization/RNG order. | Experiment: approximately 17% less generator time for tested workload. Planning target: 10–25% generator reduction, with no appearance change. | Strong measured candidate; validate mixed coordinates, negative coordinates, seeds, and exact outputs. Do not globally memoize millions of random coordinates. |
| High | Store geometry commands once; remove SVG stringify/parse round trip | `poly` formats every coordinate; `render` later splits the same strings back into numbers on every repaint. Use compact numeric buffers, reusable styles, and optionally cached Path2D paths. Keep SVG export as a separate optional serializer. | Potentially removes most of the measured ~285 ms parse-only cost per sampled repaint; likely 5–15% generator saving. Float32 XY payload is ~9.3 MB for the sampled vertices versus ~20 MB serialized scene, before styles/metadata. Total app RAM saving is unmeasured. | High confidence in eliminating conversion, medium confidence in total savings. Rounded coordinates and draw ordering must be preserved. Nested JavaScript point objects or excessive Path2D caches could use more RAM. |
| High | Prepare bounded tiles ahead, reuse already-painted overlap | Current repaint includes all retained visible shapes, and synchronous generation occurs when the view crosses a boundary. Prepare the next tile before it is needed, then move existing bitmaps. | Planning target: 40–80% less repeated repaint work, and substantial reduction in visible boundary stalls. Initial generation cost remains. | Medium confidence. Tiling must include overlapping objects, correct painter order, and enough ahead buffer to avoid seams. Additional bitmap RAM must be capped. |
| High | Move generation off the view's main JavaScript thread | Refactor generator away from DOM globals, run it in a worker, and transfer compact geometry or ImageBitmap data. | Makes scrolling less vulnerable to 100 ms+ generation bursts; total CPU may stay similar or increase slightly due to transfer overhead. | High confidence in architectural isolation; not a guaranteed speedup. Background-worker behavior needs WKWebView testing. |
| High | Lower animation communication cost | Current native timer calls JavaScript 30 times/s for each display. Evaluate a lower pulse rate with compositor interpolation or a tested visible-view animation strategy. | For two displays, 60 animation messages/s could become roughly 8–20/s: 67–87% fewer messages. Estimate 20–60% less native animation overhead, not necessarily equivalent total-app CPU reduction. | Medium confidence. Plain browser animation callbacks already stalled in the desktop setting, so replacing the native timer blindly is unsafe. |
| High | Stop the timer during pause/sleep; separate sleep states | Current timer still fires and returns while paused. One boolean also conflates computer and display sleep; one wake event can clear the other reason. Invalidate/restart the timer and track states independently. | Removes approximately 30 callback wakeups/s while paused; animation work becomes zero. RAM remains allocated unless views are released. | High confidence. Avoid relying only on window occlusion: wallpaper windows can be considered occluded even when their animation is wanted. |
| Medium | Short-circuit vegetation tests and reuse repeated samples | Several mountain passes compute noise before checking whether the row/column can possibly qualify. Middle/bottom vegetation also samples related coordinates repeatedly. | Conservative target: 1–5% total generator saving, potentially higher for dense scenes. Initial macro test showed ~11%, but that is not a reliable isolated prediction. | Medium confidence; fixed-seed output matched in experiment. Preserve random-call order. |
| Medium | Cache constant tree-profile noise and simplify local math | `tree01` rebuilds the same ten pairs of noise values for every tree. `texture` repeats floor/ceil/layer calculations in inner loops; `stroke` computes identical sine/cosine values twice per vertex. | Estimate 1–5% generator saving for relevant scenes; allocation reduction may improve latency more than average CPU. | Medium/low impact confidence. Use small seed-scoped caches; do not replace curve math with approximations without image comparison. |
| Medium | Reduce temporary arrays and accidental globals | `stroke` constructs multiple mapped/concatenated/reversed arrays; texture and recursive trees create repeated copies. Several functions assign scratch variables without declarations. Use local buffers and explicit scopes. | Estimate 5–15% less geometry-processing time in affected functions; possible lower transient RAM and fewer GC pauses. Total-app RAM reduction unmeasured. | Medium confidence. Buffer reuse must respect recursion and returned-array lifetimes. Strict mode cannot simply be enabled until implicit globals are repaired. |
| Medium | Screen-size-aware detail settings | Leaves/bark use fixed 20-step shapes and branch curves use fixed subdivisions regardless of visible size. Provide an optional battery/detail mode with fewer subpixel vertices and distant texture strokes. | Estimate 25–60% fewer vertices and 15–40% less generation/repaint work in lower-detail mode. | Medium/low confidence; intentionally changes artwork. Sampling changes can change RNG consumption and later composition, so per-object seeded RNG or fixed random consumption is needed for stable comparisons. |
| Medium | Share one generator across multiple displays when desired | Each display currently has a separate WebKit scene generator. A shared scene producer plus lightweight display surfaces can avoid duplicating generation. | With two screens, could avoid up to about half of duplicated generation, but drawing/scaling stays per screen. Rough RAM target: 50–150 MiB saving if a WebContent process can be removed; unmeasured. | Low/medium confidence. Requires an architectural change, and sharing a process pool alone does not guarantee fewer processes. Decide whether displays should show shared or independent scenery. |
| Low | Optimize planner repeated local-max tests | The noise field used for `ns(x,y)` actually depends only on X, but is rechecked across Y rows and neighbor coordinates. Slab-local caching is safe; a precomputed height-field/maxima pass is a later option. | Measured ~50% faster planner; conservative 0–2% total generator saving. | High confidence in planner-only saving. Keep placement rules and seeded random sequence intact. |
| Low | Spatially index vegetation-neighbor checks | Middle-tree validation scans all candidates to count neighbors within radius 30, with an early exit. A grid could query only nearby candidates. | Improves asymptotic dense-case behavior from quadratic toward linear; likely <1–3% total benefit at current small candidate counts. | Low confidence in worthwhile total speedup. Profile unusually dense scenes before adding complexity. |
| Low | Reduce triangulation allocations and repeated area math | Recursive ear clipping copies lists and shattering repeatedly calculates lengths/square roots. Use iterative work queues, cross-product triangle area, and fast convex paths where the caller guarantees convexity. | Likely <1–2% total generator saving in this seed; can matter more for foliage-heavy variants. | Low priority from measured share. Replacing the algorithm can change triangle shapes and visible texture; regression images are required. |
| Low | Remove dormant web-page UI and debug routines | Browser controls, mouse listeners, exporters, and debugging functions remain bundled even though wallpaper mode does not use them. | Smaller source and fewer irrelevant listeners; expect <1% ongoing CPU/RAM benefit. | High confidence this is cleanup rather than a major performance win. Preserve licensing and any desired export path. |
| Future | Coordinate rebasing and explicit resource budgets | Horizontal position and sparse-array logical length continue increasing although occupied entries are pruned. Use local tile coordinates and an absolute planning offset; cap tile/cache byte budgets. | Very-long-run numeric robustness and enforceable memory limits; no meaningful short-run speed benefit. | Low urgency at normal scroll speeds. Rebase without changing world-coordinate noise or creating a visible seam. |

## Important design constraints

- Preserve the original art: compare multiple fixed seeds, full-scene output where feasible, and rendered pixels. The white-mountain regression showed that geometry-only tests do not verify compositing.
- Avoid changing the global PRNG call sequence accidentally. The library replaces Math.random with its seeded generator, and noise-table initialization consumes that sequence. Optimizing random-consuming code or parallelizing objects can change future scenery.
- Keep caches bounded and seed-aware. Caching millions of unique noise coordinates could recreate the memory problem even while accelerating some calls.
- Track memory by the whole app process group, including compressed footprint and GPU helpers. A lower vertex count does not translate directly into equal RAM savings.
- Make painting fidelity explicit: do not merge transparent shapes indiscriminately. Overlaps, alpha, outline order, and paper tint affect the appearance.
- Use a transactional draw path so exceptions cannot clear a valid displayed frame or leave the renderer permanently busy.

## Recommended implementation order

1. Fix visibility bounds, busy/error recovery, unsupported primitive handling, and timer pause/sleep behavior. These are correctness and reliability changes.
2. Implement the tested 2D noise shortcut plus small safe sample/vegetation optimizations. Re-run paired multi-seed benchmarks in WebKit. This gives a useful low-risk generator improvement.
3. Replace SVG round-tripping with a typed drawing-command backend, then add bounded tile reuse and ahead-of-view generation. Measure parsing, drawing, allocation, and peak footprint separately.
4. Test lower animation pulse frequency and worker generation; keep the existing timer fallback until desktop behavior is verified.
5. Offer optional detail/battery mode and consider a shared multi-display renderer only if further memory savings are needed.

A reasonable planning target for phases 2–4 is 15–35% less generator CPU, much shorter redraw stalls, and fewer animation wakeups while preserving full-detail art. That target is not a measured combined result, and the individual ranges cannot be added. The best total RAM reduction is still uncertain; approximately 300 MiB from the earlier two-screen test should not be promised to halve without a shared-renderer prototype.

## Acceptance checks before shipping changes

Use several deterministic seeds including dense vegetation, flat land, wide distant ridges, boats, and buildings. Compare colors, painter order, text/circle support, and tile seams. Measure time separately for planning, noise/geometry, encoding, transfer, and drawing. Record startup peaks, steady footprint, and section-generation spikes over at least a 30–60 minute run, then a longer unattended test before claiming long-run stability. Check pause, sleep/wake, display changes, recovery from rendering-process termination, and sustained scrolling. Verify that caches and placement data stay within explicit limits.

## Existing runtime evidence and limitations

The earlier native two-screen check averaged 301 MiB physical footprint, with sampled totals of 240–376 MiB, over 5.86 minutes. It included a scene reset and is not proof of an uninterrupted plateau or absence of slow leaks. Average sampled CPU was 11.3% of one core. The machine was under other memory load, and test instrumentation contributes overhead. Today's generator benchmarks do not supersede those native observations and do not establish battery impact.

Raw benchmark evidence is included in GroundSurf-optimization-evidence.json. The noise benchmark’s individual baseline times were 9.86, 9.16, and 9.62 seconds; variant times were 7.98, 9.27, and 7.81 seconds. These illustrate real timing variance. Source reviewed: GroundSurfSource/landscape.html and GroundSurfSource/main.swift. Experimental scripts and modified contexts stayed in the work directory.

## GroundSurf 1.3 implementation status

Implemented: full bounds, transactional frame commit and error recovery, primitive handling, equivalent noise shortcut, typed command buffers, background worker generation/painting with compatibility fallback, one prepared frame ahead, pause/sleep timer removal, separate sleep states, slab-local planner cache, vegetation guards, seed-scoped tree profiles, local scratch declarations, repeated trigonometry/layer math reuse, and dormant browser UI removal.

The frame-ahead change is not an overlap-reusing tile renderer. Lower pulse frequency, shared multi-display production, broad array pooling, spatial indexing, triangulation changes, detail modes, coordinate rebasing, and hard byte budgets remain deferred. The final notes distinguish preserved visual behavior from correctness fixes and document that lower total RAM has not been established.
