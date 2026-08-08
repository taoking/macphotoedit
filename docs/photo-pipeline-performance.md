# Photo pipeline performance

## Measurement and scope

The Phase 12.12 audit measured the deterministic CPU-side cube work rather
than using a hardware-dependent frame-time threshold. A 33³ RGBA Float cube
contains 35,937 entries and occupies 574,992 bytes. Before this phase, both
`ColorAdjustmentCube` and `ToneCurveCube` created a temporary `[Float]` and
then copied it into `Data` for every effective preview/export render.

The existing editor already coalesces slider input with a 90 ms debounce,
cancels stale render tasks, protects results with a generation token, and the
preview renderer reuses one Metal-backed `CIContext`. Those protections remain
in place; this change addresses the remaining per-render cube allocations.

## Implemented result

- Each cube uses a bounded, thread-safe LRU cache of eight immutable `Data`
  payloads keyed only by values that affect that cube. Editing exposure or
  temperature, for example, does not rebuild an unchanged HSL/white/black or
  tone-curve cube.
- Cube generation writes directly into one `Data` allocation. It no longer
  creates a separate 33³ `[Float]` followed by a copy.
- Tone curves are channel-separable at the cube's 33 input samples. The
  implementation evaluates master/red/green/blue curve values once per input
  coordinate and fills the same 3D layout from those tables.
- `CIColorCube` filters are intentionally created per image graph. Their input
  images are mutable filter parameters and reusing a filter across preview and
  export actors could race or alter an in-flight Core Image graph. Cached
  immutable cube `Data` and the existing reused `CIContext` remove the large
  allocation source without that correctness risk.

Automated diagnostics verify cache-key selectivity, a single 574,992-byte
payload per generated cube, and the eight-entry bound. They do not claim a
universal millisecond/frame-rate gain because Metal device, image size, source
codec, and display configuration vary by Mac.
