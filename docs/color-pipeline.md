# Color Pipeline

Mac Photo Studio uses this ordered, non-destructive photo pipeline:

```text
Source Color Space
→ Working Color Space (Extended Linear sRGB)
→ Technical Transform
→ Creative Adjustments
→ Creative LUT
→ Output Transform
→ Display / Export
```

The source descriptor is inferred from the catalogued image profile where
available. It records both colour primaries (`sRGB`, Display P3, Rec.709,
Rec.2020, linear variants) and transfer function (`sRGB`, linear, Rec.709,
S-Log3, HLG, PQ). Core Image retains the source ICC attachment through the
graph, and the renderer requests the selected output `CGColorSpace` so
ColorSync performs the display/export boundary conversion.

## LUT safety

Creative LUTs are the existing Phase 3 look LUTs. They run only after the
ordinary creative adjustments.

Technical LUTs are a separate library kind. Importing one requires explicit
input and output colour-space plus transfer-function metadata. At render time
the technical input contract must exactly match the source descriptor. A
technical LUT cannot be selected in the Creative LUT slot. This prevents, for
example, a declared `S-Log3 → Rec.709` transform from being casually applied
to an sRGB JPEG.

## HDR and SDR

The HDR editor path renders a half-float TIFF preview into an AppKit layer with
`wantsExtendedDynamicRangeContent` enabled. On an HDR-capable display this
preserves extended-range content; macOS performs the appropriate mapping on an
SDR display. SDR output applies `CIToneMapHeadroom` when available, with a
highlight-compression fallback.

The current portable ImageIO encoder path intentionally reports HDR still
export as unavailable: it does not have a cross-version reliable HDR gain-map
writer. Selecting HDR export fails clearly rather than creating an 8-bit
JPEG/HEIC/TIFF incorrectly labelled as HDR. SDR JPEG, HEIF and TIFF exports
remain supported and take the user-selected output colour space.
