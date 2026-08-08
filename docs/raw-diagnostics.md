# RAW Diagnostic

Phase 16.4 adds the developer command **File → 运行 RAW 诊断…**. Choose a
user-authorised `.ARW` or `.DNG`; the command reads that referenced file in
place, creates a temporary full-resolution JPEG only to exercise the export
path, deletes the temporary directory, and opens a small UTF-8 report in:

```text
~/Library/Application Support/MacPhotoStudio/logs/
```

The report contains the file extension and size, `CIRAWFilter` availability,
decoded dimensions, the exact decoder `CIImage` colour-space name, whether its
ICC payload matches a supported `PhotoColorDescriptor`, the recognised decoder
descriptor, the normalised working descriptor, RAW controls exposed by the
same capability check as the editor, preview and temporary export results, and
the reopened export's ICC profile.

The report never embeds a RAW bitmap or image pixels. It records only the
source filename (not a copied source file), keeps no derived image cache, and
does not write sidecars or database records. Its source-integrity field compares
file size and modification date before and after the diagnostic; the rendering
and exporter code also have no source-writing operation.

## Unknown decoder ICC

`CIRAWFilter` does not offer a public output-colour-space setting. The app only
accepts a decoder ICC payload when it exactly equals an explicitly supported
ColorSync profile. An absent or unfamiliar profile is reported and the normal
RAW pipeline fails closed; it is not assumed to be sRGB. A real A7C II report
is evidence for a new mapping only if the returned profile is stable and its
meaning can be independently verified. Do not add a profile-name heuristic or
an approximate conversion merely to make a diagnostic pass.

## Real-file procedure

For each authorised Sony A7C II `.ARW` and DNG, run the File command twice and
choose **sRGB** first, then **Display P3** in its output-colour dialog:

1. Retain both small text reports, then compare each report's output ICC with
   ImageIO/ColorSync-aware inspection.
2. Record the reported decoder ICC name and descriptor. If the descriptor is
   rejected, keep that rejection and attach the report to the investigation.
3. Continue the detailed visual/interaction checks in
   `docs/manual-validation.md`; they remain manual because this repository does
   not contain private ARW/DNG files.
