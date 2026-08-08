# Color Pipeline

Mac Photo Studio uses this ordered, non-destructive photo pipeline:

```text
Source Color Space
→ Technical LUT bridge (only when selected)
→ Working Color Space (Extended Linear sRGB)
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

## SDR output ICC contract

Phase 12.1 maps every selectable SDR output to an Apple-provided ColorSync
space: sRGB, Display P3, ITU-R BT.709, and ITU-R BT.2020. Rec.709 and
Rec.2020 never fall back to sRGB. After ImageIO writes JPEG, HEIF, or TIFF, the
exporter reopens its temporary file and compares the embedded ICC payload with
the requested output profile. A mismatch fails the export before the temporary
file is moved into the user-selected directory.

The Phase 12.1 automated suite verifies this round trip for every supported
SDR format and all four output choices. The following Phase 12.2 section
documents the subsequent source-to-working-space refactor.

## Explicit working space

Phase 12.2 completes that refactor. Every photo `CIContext` is now created
with `CGColorSpace.extendedLinearSRGB` as `workingColorSpace` and `RGBAh` as
the intermediate working format. Core Image therefore color-matches each
profile-attached source into that one working space before executing filter
kernels, and matches from it to the requested output profile at render time.
The same `RendererContextFactory` is used by preview, full-resolution photo
export, RAW preview and RAW export, so those paths do not silently use separate
working-space defaults.

## RAW decoder boundary

Phase 12.4 gives `CIRAWFilter` its own explicit colour boundary. Apple does
not expose a `CIRAWFilter` output-colour-space setting, so the app reads the
actual `outputImage.colorSpace` attachment. It accepts it only when its ICC
payload exactly matches one of this app's ColorSync contracts, then
materialises the decoder result with a half-float `CIContext` whose working and
output spaces are both Extended Linear sRGB. The resulting CIImage is attached
to that linear working profile and enters `PhotoColorPipeline` as
`linearWorking` for RAW preview, full-resolution render and export.

An absent or unfamiliar decoder profile is a hard, descriptive RAW error; it
is never labelled sRGB. Consequently, a RAW Technical LUT must explicitly
declare Extended Linear sRGB input after this normalization. Creative LUTs
continue to run in the shared linear working space. Actual Sony A7C II ARW and
DNG decoder attachments still require the documented manual verification,
because the repository intentionally contains no user RAW fixture.

## LUT safety

Creative LUTs are the existing Phase 3 look LUTs. They run only after the
ordinary creative adjustments.

Technical LUTs are a separate library kind. Importing one requires explicit
input and output colour-space plus transfer-function metadata. At render time
the technical input contract must exactly match the source descriptor. A
technical LUT cannot be selected in the Creative LUT slot. This prevents, for
example, a declared `S-Log3 → Rec.709` transform from being casually applied
to an sRGB JPEG.

### Technical LUT bridge

Phase 12.3 makes the Technical Transform metadata operational rather than
descriptive. For a supported Technical LUT, the source is first rendered by
ColorSync into the declared input encoding. The cube then runs in an unmanaged
half-float context, so it receives and produces the LUT's declared encoded RGB
numbers instead of Extended Linear sRGB values. Its result is re-attached to
the LUT's declared output ICC profile before it rejoins the common Extended
Linear sRGB working pipeline. The downstream preview/export context can
therefore perform the required output-to-working conversion from the actual
LUT result.

This bridge is deliberately limited to descriptors represented by an
Apple-provided ColorSync profile: sRGB, Display P3, Rec.709, Rec.2020 and the
linear variants with their corresponding standard transfer functions. S-Log3,
HLG and PQ do not have a validated bridge in this application; importing their
metadata remains possible for cataloguing, but applying that Technical LUT is
rejected with a clear error. The app does not approximate those curves as
sRGB/Rec.709 or silently apply a cube in the wrong encoding.

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
