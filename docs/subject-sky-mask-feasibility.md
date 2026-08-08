# Subject / Sky Mask Feasibility

## Decision

Phase 14 implements a real, local **foreground subject** mask. It does not
claim a semantic subject class selector and it does not implement Sky Mask.

The project targets macOS 15. The installed target SDK exposes Vision's
`VNGenerateForegroundInstanceMaskRequest` (available on macOS 14 and later).
The request yields foreground instance identifiers and can generate a scaled
grayscale mask for all detected foreground instances. This is the Apple
system API used by `VisionSubjectMaskRenderer`; it runs in the app process and
does not require a cloud service or upload source media.

## Implemented subject workflow

1. A `LocalMask(kind: .subject)` persists only enable state, opacity and local
   adjustments in `PhotoEditState` / Catalog.
2. At preview and export render time, the same Vision request analyses the
   current Core Image source and returns a scaled foreground mask.
3. The result is aligned to the source extent and used by the existing
   `CIBlendWithMask` local-adjustment path.
4. If Vision returns no instance or the request throws, rendering fails closed:
   the mask applies no adjustment. It never falls back to an all-white mask.

No mask bitmap, Vision result, source photo, or derived texture is written to
SQLite or uploaded. Re-running Vision at render time is intentional so that
the non-destructive state remains compact and the preview/export use the same
code path.

## Sky Mask boundary

The audited target SDK does not expose a verified public macOS Vision request
for generic sky segmentation. A colour-threshold heuristic would fail on
clouds, sunsets, water, architecture and blue objects; shipping that as Sky
Mask would violate the product requirement against mock functionality.

Accordingly, this release exposes no Sky Mask button, enum case, heuristic or
hard-coded substitute. A future Sky feature needs a bundled, versioned local
model with licensing, accuracy, memory/performance and real-media validation,
or a verified future Apple system API. It must remain local-only.

## Required real-media validation

Use authorised images of people, pets and common objects against plain and
complex backgrounds. Check hair/fur edges, transparent or reflective objects,
multiple foreground instances, no-subject images, preview/export consistency,
performance on 24 MP / 48 MP images and that original bytes remain unchanged.
These checks cannot be proven with synthetic unit-test fixtures.
