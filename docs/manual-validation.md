# Manual Validation Checklist

This checklist records validation that requires real user-authorised media,
physical storage, a specific display, or macOS permission dialogs. It is not
automatically marked as passed by unit tests.

## Photo

- [ ] JPEG: import, thumbnail, edit, export and ICC profile round trip.
- [ ] HEIC: import, thumbnail, edit, export and ICC profile round trip.
- [ ] PNG and TIFF: import, edit and export.
- [ ] sRGB and Display P3: compare preview and exported file on a colour-managed display.
- [ ] Still-image color matrix: for user-authorised JPEG sRGB, JPEG Display P3, HEIC sRGB, HEIC Display P3, PNG and TIFF, run **File → 运行静态图像色彩验证…** into a new user-selected output folder. Retain the report and all new outputs; verify every sRGB/Display P3/Rec.709/Rec.2020 SDR Preview and ImageIO-reopened JPEG/HEIC/TIFF export row. Compare in a ColorSync-aware reference app and record display, macOS, reference app and visible differences. Rec.2020 remains SDR, never an HDR claim; see `docs/still-image-color-validation.md`.
- [ ] Technical LUT: use a user-authorised, correctly declared sRGB/Display P3/Rec.709/Rec.2020 source and LUT; compare the transform with a ColorSync-aware reference application and confirm source files remain unchanged.
- [ ] Technical LUT strength: with a user-authorised LUT whose input and output encodings differ (for example Display P3 → Rec.709), compare 0%, 50% and 100% preview and new-file export with a ColorSync-aware reference. Confirm 0% is the correctly converted untouched branch, 50% is a blend of two output-encoded branches, 100% is the complete LUT result, and every output carries the declared Technical LUT output profile.
- [ ] Technical LUT safety: select correctly catalogued S-Log3, HLG and PQ Technical LUTs and confirm the app rejects application with the stated unsupported-encoding error instead of approximating the result.
- [ ] 24 MP and 48 MP images: sustained slider interaction, cancellation, memory and full-resolution export.
- [ ] Brush mask: on JPEG/HEIC and a user-authorised RAW-derived photo, paint overlapping hard and soft strokes, change size/feather/flow, erase, undo and clear; compare preview with a new-file export at full resolution. Verify strokes remain aligned after window resize, crop/rotate, reopening the asset and switching between horizontal/vertical images.
- [ ] Local-mask transform geometry: on horizontal, vertical and square authorised photos, place a linear, radial and brush mask near visible edges; then combine crop, 90°/180°/270° rotation, straighten and both flips. Drag each visible handle and paint once, reopen the asset, export a new file and confirm each adjustment affects the visually targeted source region rather than the pre-transform screen coordinates.
- [ ] Brush-mask memory: on a 24 MP or 48 MP photo, make several masks and long strokes while observing sustained interaction and memory. Confirm the original remains byte-identical and no bitmap/derived texture is written into Catalog state or beside the source.
- [ ] Vision foreground subject mask: on authorised people, pets and common-object photos with plain and complex backgrounds, apply exposure/contrast/saturation and compare preview with a new-file export. Check hair/fur, transparent or reflective edges, multiple foreground instances and no-subject images. Confirm a failed/no-result request does not alter the whole image, source files remain byte-identical, and no Vision mask is written into Catalog or beside the source.
- [ ] Vision foreground cache/stability: add three Subject masks to one authorised photo, then change exposure, contrast, saturation, temperature, HSL and curves while observing the app's debug/instrumentation output. Confirm one segmentation is shared within each render and an unchanged preview source reuses the derived preview mask; edit/replace the source file or change preview geometry and confirm it is regenerated. Reorder ordinary local masks and confirm the selected subject does not change merely because those mask adjustments run first.
- [ ] Sky-mask boundary: confirm no Sky Mask control is presented. It is deliberately unsupported because the target macOS SDK has no verified local generic Sky Mask request; do not treat a blue-sky heuristic as validation.
- [ ] Similar photos: on user-authorised JPEG, HEIC, PNG and TIFF, include a resized copy, a separately re-exported/recompressed JPEG, a small exposure or colour variant, a visually different photo and (where available) RAW-derived JPEG. Run “查找相似照片”; inspect every Similar Group, score and 256 px review thumbnail. Confirm filename, dimensions, file size, rating, flag, RAW/JPEG marker and capture date match the Inspector without a full-resolution source read. Exercise Select/Preview, 0–5 star, Pick/Reject/clear flag, manual album and stack actions; then move explicitly selected available items to Trash and confirm the confirmation dialog is required. Confirm no action is automatic, no “best photo” decision is claimed, and no source is modified, moved, deleted or uploaded before explicit confirmation.
- [ ] Similar-photo scale and storage: use **File → 运行相似照片基准（开发者）** and retain its text report. Separate its current-Catalog live-media metrics from the 10k/50k/100k Catalog-only rows; do not infer real-image throughput from the generated section. On a 10k+ real catalogue (and, when available, 50k/100k), run the first and cached repeat scan while observing responsiveness, memory, cancellation and external-drive disconnect/reconnect. Cancel while hashing, while switching roots and while grouping; confirm background task state becomes cancelled. Confirm unchanged signatures reuse, changed modification time or file size recomputes, unreadable files are listed as failures rather than assigned a fallback hash, offline roots provide no false hash, and dHash records remain Catalog metadata only.

## RAW

- [ ] Sony A7C II ARW: run **File → 运行 RAW 诊断…** and retain the Application Support/logs text report; then verify decode, orientation, white balance, exposure, highlight recovery (when reported), lens correction (when reported), luminance/color noise reduction (when reported), RAW sharpness/detail/local tone (when reported), preview, creative LUT, local masks when applicable, crop/rotate and full-resolution new-file export. Repeat new-file export for sRGB and Display P3; confirm the source remains byte-identical.
- [ ] DNG: run the same diagnostic and retain its report; verify decode, orientation, every reported RAW control, crop/rotate, creative LUT, local masks when applicable and full-resolution sRGB/Display P3 new-file export. Confirm the source remains byte-identical.
- [ ] RAW color boundary: record the diagnostic's `CIRAWFilter.outputImage` ICC/profile, exact ICC-payload match result, recognised descriptor, normalised working descriptor and reopened output ICC for Sony A7C II ARW and DNG. Verify normal preview and full-resolution export carry the selected output profile, and that an absent/unknown decoder profile is rejected rather than assumed sRGB. Do not add a mapping until a stable real decoder profile is independently validated; see `docs/raw-diagnostics.md`.
- [ ] RAW Technical LUT: verify a LUT explicitly declared Extended Linear sRGB input runs after RAW normalization; confirm a mismatched Rec.709/P3/S-Log3 contract is rejected.
- [ ] RAW + JPEG pair: pairing and configured display preference.

## Video

- [ ] Real-media matrix: iPhone MOV, Sony MP4, H.264, HEVC, horizontal, vertical, 30 fps, 60 fps, 4K, with audio and without audio. Confirm Catalog and Inspector show the `preferredTransform` display dimensions (for example 1080×1920 rather than encoded 1920×1080) and that Preview, Editor, Proxy and Export retain that orientation.
- [ ] For every available matrix item, validate metadata dimensions, playback, seek, frame step, trim, speed, crop, rotate, both flips, Creative LUT, `-60/-6/0 dB` audio attenuation, video fade, audio fade, Proxy and new-file export. Do not expect or claim positive audio gain.
- [ ] Exercise `trim + speed + audio`, `vertical + resize`, and `LUT + crop + export`; reopen each MP4 and check video/audio tracks, output dimensions, duration and perceptible A/V synchronization.
- [ ] While playing around 35 seconds, continuously change exposure, contrast, temperature, LUT strength and crop. Confirm each rebuilt preview resumes at the prior output time with the same play/pause state, rate, mute and volume instead of jumping to zero; old item end notifications must not change the latest preview state.
- [ ] After several preview rebuilds, let the current item play to its end and confirm the playback control changes back to Play. Also verify that an unreadable or removed source shows a visible playback error rather than leaving the controls in a playing state.
- [ ] Confirm trim + speed keeps audio and video in sync, including audio fades.
- [ ] Export a vertical H.264 and HEVC source with an actual audio track using trim, speed, crop, flip, LUT, resize and both fades. Confirm the finished MP4 contains both tracks, uses the intended codec and has no perceptible A/V drift.
- [ ] With authorised material containing audio, compare 0 dB, -6 dB and -60 dB export/preview attenuation and fade timing. Confirm the UI provides no positive gain control; +6 dB and limiter/normalisation are not implemented.
- [ ] Follow `docs/video-real-media-validation.md` to record the device, macOS, display, codec, frame rate and all outcomes/limitations for each authorised source.

## Storage and permissions

- [ ] 对 internal SSD、external SSD、external HDD 与 SD card 依次添加文件夹、重启并运行 **File → 运行媒体根目录可用性诊断**；记录 bookmark 解析/stale、security-scoped access、目录读写、卷名/UUID 与 online 状态。
- [ ] 每种设备均执行 disconnect → restart → offline Catalog → reconnect same drive → diagnostic → rescan → edit → new-file export；离线时必须保留 Catalog 组织与既有派生缩略图，重新扫描后必须恢复源文件操作。
- [ ] 逐一 rename volume → reconnect → restart → diagnostic → rescan。确认报告呈现新卷名和可核对的 UUID；如需要重新授权，只使用“重新定位文件夹…”，并核对资产 ID、编辑、评分、标签、相册与堆栈没有被清除。
- [ ] 按 `docs/external-storage-validation.md` 保留每块真实设备的报告、操作系统、连接方式和结果；路径缺失应为 offline，路径仍存在但 bookmark 无法恢复应为 permissionRequired。

## HDR / display

- [ ] On an HDR-capable macOS display, move the editor window between HDR and SDR screens and verify extended-range still preview only gains EDR headroom on the HDR screen while the SDR screen remains system tone-mapped.
- [ ] Confirm HDR still / gain-map export, HDR video editing, HDR video export and HDR Proxy generation remain unavailable rather than being silently converted or mislabelled; native HDR video playback may remain available.
