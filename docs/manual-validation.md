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
- [ ] Brush mask: on JPEG/HEIC and a user-authorised RAW-derived photo, paint overlapping hard and soft strokes, change size/feather/flow, erase, undo and clear; compare preview with a new-file export at full resolution. Verify strokes remain aligned after window resize, crop/rotate, reopening the asset and switching between horizontal/vertical images.
- [ ] Brush-mask memory: on a 24 MP or 48 MP photo, make several masks and long strokes while observing sustained interaction and memory. Confirm the original remains byte-identical and no bitmap/derived texture is written into Catalog state or beside the source.
- [ ] Vision foreground subject mask: on authorised people, pets and common-object photos with plain and complex backgrounds, apply exposure/contrast/saturation and compare preview with a new-file export. Check hair/fur, transparent or reflective edges, multiple foreground instances and no-subject images. Confirm a failed/no-result request does not alter the whole image, source files remain byte-identical, and no Vision mask is written into Catalog or beside the source.
- [ ] Sky-mask boundary: confirm no Sky Mask control is presented. It is deliberately unsupported because the target macOS SDK has no verified local generic Sky Mask request; do not treat a blue-sky heuristic as validation.
- [ ] Similar photos: on user-authorised JPEG, HEIC, PNG and TIFF, include a resized copy, a separately re-exported/recompressed JPEG, a small exposure or colour variant, a visually different photo and (where available) RAW-derived JPEG. Run “查找相似照片”; inspect every Similar Group and score, confirm expected variants are review candidates, obviously different images are not accepted blindly, and no source is modified, moved, deleted or uploaded.
- [ ] Similar-photo scale and storage: on a 10k+ catalogue (and, when available, 50k/100k), run the first and cached repeat scan while observing responsiveness, memory, cancellation and external-drive disconnect/reconnect. Confirm changed source files are recomputed, unreadable files are listed as failures rather than assigned a fallback hash, and dHash records remain Catalog metadata only.

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
- [ ] After several preview rebuilds, let the current item play to its end and confirm the playback control changes back to Play. Also verify that an unreadable or removed source shows a visible playback error rather than leaving the controls in a playing state.
- [ ] Confirm trim + speed keeps audio and video in sync, including audio fades.
- [ ] Export a vertical H.264 and HEVC source with an actual audio track using trim, speed, crop, flip, LUT, resize and both fades. Confirm the finished MP4 contains both tracks, uses the intended codec and has no perceptible A/V drift.
- [ ] With authorised material containing audio, compare 0 dB, -6 dB and -60 dB export/preview attenuation and fade timing. Confirm the UI provides no positive gain control; +6 dB and limiter/normalisation are not implemented.

## Storage and permissions

- [ ] Internal SSD, external SSD, external HDD and SD card.
- [ ] Disconnect, reconnect, rename the volume and restart the app.
- [ ] Confirm security-scoped bookmark recovery and that offline assets retain Catalog data and existing derived thumbnails.

## HDR / display

- [ ] On an HDR-capable macOS display, move the editor window between HDR and SDR screens and verify extended-range still preview only gains EDR headroom on the HDR screen while the SDR screen remains system tone-mapped.
- [ ] Confirm HDR still / gain-map export, HDR video editing, HDR video export and HDR Proxy generation remain unavailable rather than being silently converted or mislabelled; native HDR video playback may remain available.
