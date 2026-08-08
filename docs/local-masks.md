# Local Masks

## Scope and privacy

Phase 11 provides two practical, local-only masks: linear gradients and radial
gradients. The application does not upload, index remotely, or send source
photos to a cloud service. There is no placeholder subject/sky/face model in
this release.

## Non-destructive state

`PhotoEditState` v3 stores an ordered `localMasks` array per asset. Each entry
contains a stable ID, enable state, opacity, normalized geometry and local
exposure, contrast and saturation adjustments. Existing v1/v2 edit JSON
decodes with an empty array while preserving its original version marker, so
older state remains readable without a destructive migration.

Coordinates are normalized to the image extent before crop, rotation and
straighten transforms. Consequently a 1024px preview and a full-resolution
export apply the same part of the referenced original. Local-mask geometry is
intentionally omitted from reusable presets and copy/paste, so a preset cannot
silently place one photo's mask on another.

## Render order

```text
Source / optional RAW stage
→ global creative adjustments
→ ordered local gradient masks
→ Creative LUT
→ crop / rotate / flip
→ selected output colour transform
```

Core Image creates the actual linear or radial grayscale field and blends the
locally adjusted image against the current image with `CIBlendWithMask`.
Preview and export both use `PhotoColorPipeline`, rather than a separate UI
effect implementation.

## Canvas interaction

Phase 12.13 adds direct manipulation to the ordinary photo editor without
changing the stored `LocalMask` schema. The canvas calculates the same
aspect-fitted image rectangle as the AppKit image view and converts between
SwiftUI's top-left coordinates and the persisted bottom-left normalized values.

- Linear masks show start and end handles; dragging either changes direction
  and rotation, while dragging the dashed center line moves both endpoints
  together without changing the gradient vector.
- Radial masks show a center handle, an orange radius ring and a white feather
  ring. Their handles move center, radius and feather independently.
- Geometry is clamped to the normalized image extent. A linear-mask move stops
  at an edge while preserving the distance and direction between its endpoints.
- “显示蒙版覆盖” adds a translucent red display-only field for the selected
  mask. It is neither stored in the edit state nor passed to Core Image or any
  export path.

The Inspector sliders remain available for numerical adjustment. Existing
preview debounce/save behavior is reused when a drag changes the same
non-destructive state.

## Deliberate boundary

Brush strokes, subject/sky segmentation, perceptual similarity, semantic
search and face grouping are not claimed as implemented. They require separate
geometry, Vision-model, quality and privacy validation before they can be added
without becoming mock functionality.
