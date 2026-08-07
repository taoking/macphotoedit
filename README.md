# Mac Photo Studio

Mac Photo Studio is a native, local-first macOS application for referenced
photo and video libraries. It indexes user-selected folders and preserves
original media in place.

## Foundation build

Requirements: Xcode 26.6 or later and XcodeGen.

Generate the Xcode project after changing `project.yml`:

```bash
xcodegen generate
```

Build the macOS application without signing:

```bash
xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

Run the unit tests:

```bash
xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

The app stores its catalog, thumbnail/video-filmstrip/Proxy caches, previews, presets, LUTs, and logs
under `~/Library/Application Support/MacPhotoStudio/`. Original media is never
copied there or modified by the app. Video Proxy files are derived H.264 previews
only; editing and export always read the referenced original.
