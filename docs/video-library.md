# Video Library

Phase 8 extends the existing referenced-media catalog without copying, modifying,
or exporting original video files. Video editing and export are intentionally
outside this phase.

## Catalog metadata

`video_metadata` stores dimensions, duration, frame rate, codec, creation date,
audio-track count, color primaries, transfer function, YCbCr matrix, and a
conservative HDR indication. The HDR flag is set only when AVFoundation format
description extensions identify HLG, PQ/ST 2084, or BT.2100-related properties;
missing metadata remains unknown rather than being guessed.

## Thumbnails and filmstrips

The existing `ThumbnailLoader` asks `AVAssetImageGenerator` for a transformed
poster frame and stores the JPEG thumbnail in the disk thumbnail cache. Opening
a video also requests a five-frame filmstrip. The filmstrip samples the timeline
from the poster frame to the end, tolerates an unavailable individual sample,
and caches only generated JPEG frames in Application Support's
`video-filmstrips` directory. Neither cache contains a copy of the original
video.

## Playback

`VideoPreviewSheet` uses the system `AVPlayer`/`AVKit.VideoPlayer`. Its custom
controls provide play/pause, exact-tolerance seek, one-frame forward/backward
stepping using catalog frame rate (30 fps fallback when unavailable), volume and
mute, 0.5x/1x/1.5x/2x playback rates, and the active window's native full-screen
toggle. A security-scoped root access session remains open only while the video
preview is open; source paths are checked to remain inside the catalog root.

## Phase boundary

This phase deliberately has no video edit state, trim, LUT, colour transform,
video compositing, or video export. Those features require a separate
AVFoundation pipeline and belong to Phase 9 and later.
