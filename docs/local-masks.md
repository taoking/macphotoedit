# Local Masks

## Scope and privacy

Phase 14 adds a fourth practical, local-only mask: Vision foreground subject
selection, beside linear and radial gradients and vector brush strokes. The
application does not upload, index remotely, or send source photos to a cloud
service. The implemented subject mask is Apple Vision's salient foreground
instances, not an unverified semantic class selector. Sky and face models are
not placeholders in this release.

## Non-destructive state

`PhotoEditState` v4 stores an ordered `localMasks` array per asset. Each entry
contains a stable ID, enable state, opacity, normalized geometry and local
exposure, contrast and saturation adjustments. A brush mask stores compact
`BrushStroke` records: normalized points, radius, hardness, per-stroke flow
and an erase flag. A subject mask stores no Vision result: it is regenerated
locally when rendering. No mask stores a source-sized bitmap, encoded PNG, or
derived texture in Catalog SQLite. Existing v1/v2 JSON still decodes with an
empty mask array, and v3 gradient JSON decodes with an empty brush-stroke list,
while preserving its original version marker.

Coordinates are normalized to the image extent before crop, rotation and
straighten transforms. `PhotoTransformGeometry` is the single shared contract
for the Core Image transform and the editor canvas: the canvas first maps a
stored source-normalized point through the complete crop/flip/rotation/
straighten transform, and maps a pointer location back through its inverse
before storing a mask edit. Consequently a 1024px preview and a
full-resolution export apply the same part of the referenced original, even
after combined transforms. Local-mask geometry is intentionally omitted from
reusable presets and copy/paste, so a preset cannot silently place one photo's
mask on another.

## Render order

```text
Source / optional RAW stage
→ global creative adjustments
→ ordered local gradient / brush / Vision foreground masks
→ Creative LUT
→ crop / rotate / flip
→ selected output colour transform
```

Core Image creates the actual gradient or brush grayscale field; Vision creates
the subject foreground field through `VNGenerateForegroundInstanceMaskRequest`.
Each field blends the locally adjusted image against the current image with
`CIBlendWithMask`. Preview and export both use `PhotoColorPipeline`, rather
than a separate UI effect implementation. If Vision finds no foreground or
fails, it applies no adjustment rather than applying one to the whole image.

Subject segmentation taps the decoded, orientation-applied image before global
and local adjustments. Therefore changing exposure, contrast, saturation,
temperature, HSL, curves, or the order of prior local masks neither changes the
Vision input nor starts another request. A `SubjectMaskProvider` keeps a
 disposable LRU cache keyed by standardized source URL, available file-resource
 identifier, file size/modification time, preview/export rendition, input extent
 and Vision request revision. The preview renderer holds at most eight derived
 masks; the full-resolution export renderer holds only one. A no-subject/failed
 result is cached as a fail-closed result. Concurrent calls with the same key
 share one in-flight Vision request, while unrelated keys do not hold a global
 cache lock during their Vision work. These masks are memory-only: no subject
 bitmap is written to Catalog SQLite, beside the source, or to a persistent
 cache. A source revision or input geometry change creates a new key.

## Canvas interaction

Phase 12.13 adds direct manipulation to the ordinary photo editor without
changing the stored `LocalMask` schema. The canvas calculates the same
aspect-fitted image rectangle as the AppKit image view, converts between
SwiftUI's top-left coordinates and the persisted bottom-left normalized values,
and uses the shared transform geometry above rather than treating a transformed
preview as source space.

- Linear masks show start and end handles; dragging either changes direction
  and rotation, while dragging the dashed center line moves both endpoints
  together without changing the gradient vector.
- Radial masks show a center handle, an orange radius ring and a white feather
  ring. Their handles move center, radius and feather independently.
- Stored editable points remain clamped to the normalized source image extent.
  Radius and brush vectors are different: their reference endpoint is allowed
  to exist outside the source or a visible crop, then the photo viewport clips
  the overlay. This avoids shortening an edge radius merely because a point
  mapping would be clamped.
- Radial inner radius/feather and brush width use the exact source-space pixel
  metrics of `CIRadialGradient` and `BrushMaskRenderer` (including their small
  radius floors) after crop, rotation, straighten and flips; the overlay is not
  a crop-width or screen-width approximation.
- “显示蒙版覆盖” adds a translucent red display-only field for the selected
  mask. It is neither stored in the edit state nor passed to Core Image or any
  export path.

The Inspector sliders remain available for numerical adjustment. Existing
preview debounce/save behavior is reused when a drag changes the same
non-destructive state.

## Brush masks

The ordinary photo editor can add a brush mask and paint or erase directly on
the edited preview. Size, feather and flow configure newly created strokes;
the recorded stroke retains its own radius, hardness, opacity and erase mode,
so later UI changes never rewrite an earlier stroke. Undo removes the latest
stroke and Clear removes only this mask's vector strokes.

At preview and export time, `BrushMaskRenderer` rasterizes the normalized
strokes into a grayscale Core Graphics texture matching the current image
extent, then `CIBlendWithMask` applies the same local adjustments used by
gradient masks. This gives the preview's downsampled image and the export's
full-resolution image separate, appropriately sized masks without resampling
or persisting a large bitmap.

Derived textures are memory-only: a thread-safe LRU keeps at most 48 MiB in
total and declines to retain an individual texture larger than 16 MiB. A large
export still rasterizes correctly for that render, then releases its texture.
The cache key includes image dimensions and every stroke value; no texture is
shared after any brush edit. The 90 ms preview debounce, task cancellation and
generation guard continue to coalesce interactive redraws.

## Deliberate boundary

Vision foreground subject selection is implemented, but it has no semantic
class selector, instance picker, manual refine controls or separately rendered
overlay. Sky segmentation, perceptual similarity, semantic search and face
grouping are not claimed as implemented. Sky requires a separately verified
local system API or bundled model; see `docs/subject-sky-mask-feasibility.md`.
