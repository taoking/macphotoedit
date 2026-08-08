# Manual Validation Checklist

This checklist records validation that requires real user-authorised media,
physical storage, a specific display, or macOS permission dialogs. It is not
automatically marked as passed by unit tests.

## Photo

- [ ] JPEG: import, thumbnail, edit, export and ICC profile round trip.
- [ ] HEIC: import, thumbnail, edit, export and ICC profile round trip.
- [ ] PNG and TIFF: import, edit and export.
- [ ] sRGB and Display P3: compare preview and exported file on a colour-managed display.
- [ ] Technical LUT: use a user-authorised, correctly declared sRGB/Display P3/Rec.709/Rec.2020 source and LUT; compare the transform with a ColorSync-aware reference application and confirm source files remain unchanged.
- [ ] Technical LUT safety: select correctly catalogued S-Log3, HLG and PQ Technical LUTs and confirm the app rejects application with the stated unsupported-encoding error instead of approximating the result.
- [ ] 24 MP and 48 MP images: sustained slider interaction, cancellation, memory and full-resolution export.

## RAW

- [ ] Sony A7C II ARW: decode, white balance, exposure, highlight recovery, lens correction, preview, creative LUT and full-resolution export.
- [ ] DNG: decode, RAW controls, crop, LUT and export.
- [ ] RAW color boundary: record the `CIRAWFilter.outputImage` ICC/profile for Sony A7C II ARW and DNG; verify normal preview and full-resolution export carry the expected selected output profile, and that an absent/unknown decoder profile is rejected rather than assumed sRGB.
- [ ] RAW Technical LUT: verify a LUT explicitly declared Extended Linear sRGB input runs after RAW normalization; confirm a mismatched Rec.709/P3/S-Log3 contract is rejected.
- [ ] RAW + JPEG pair: pairing and configured display preference.

## Video

- [ ] iPhone MOV and Sony MP4; H.264 and HEVC; horizontal and vertical material. Confirm Catalog and Inspector show the `preferredTransform` display dimensions (for example 1080×1920 rather than encoded 1920×1080) and that Preview, Editor, Proxy and Export retain that orientation.
- [ ] Material with audio and without audio; 30 fps, 60 fps and 4K sources.
- [ ] Metadata, playback, seek, frame stepping, trim, speed, LUT, crop, rotate, audio, fades, Proxy and export.
- [ ] While playing around 35 seconds, continuously change exposure, contrast, temperature, LUT strength and crop. Confirm each rebuilt preview resumes at the prior output time with the same play/pause state, rate, mute and volume instead of jumping to zero.
- [ ] Confirm trim + speed keeps audio and video in sync, including audio fades.

## Storage and permissions

- [ ] Internal SSD, external SSD, external HDD and SD card.
- [ ] Disconnect, reconnect, rename the volume and restart the app.
- [ ] Confirm security-scoped bookmark recovery and that offline assets retain Catalog data and existing derived thumbnails.

## HDR / display

- [ ] On an HDR-capable macOS display, verify extended-range still preview remains visually correct.
- [ ] Confirm HDR still export and HDR video editing remain unavailable rather than being silently converted or mislabelled.
