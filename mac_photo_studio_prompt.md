# Codex Master Prompt — Mac Photo Studio

## 0. 任务

你正在开发一个原生 macOS 照片/视频管理与编辑应用。

项目目标包括：

- Photo Library / Catalog
- Folder / External Drive indexing
- Thumbnail browser
- Rating / Flag / Tag
- Search / Filter
- Non-destructive photo editing
- HSL / Curve / Histogram
- `.cube` LUT
- RAW / Sony ARW / DNG editing
- Presets
- Batch processing
- Duplicate assistance
- Video library
- Video LUT
- Video basic color editing
- Trim / Crop / Speed
- Video export

这是一个个人长期使用的本地应用。

不需要：

- 后端
- Web App
- localhost browser UI
- 登录系统
- 云同步
- 订阅
- 社区
- 企业级权限系统

---

# 1. 项目计划

首先完整阅读：

```text
mac_photo_studio_plan.md
```

如果项目中实际文件名为：

```text
plan.md
```

则读取该文件。

同时读取：

```text
README.md
AGENTS.md
docs/
```

以及全部现有源码。

`mac_photo_studio_plan.md` / `plan.md` 是本项目的阶段需求和验收依据。

---

# 2. 开始前检查

执行：

```bash
git status
git branch --show-current
git log --oneline -10
```

检查：

- 当前分支
- 未提交修改
- Xcode project/workspace
- deployment target
- dependencies
- tests
- existing architecture

不要覆盖用户已有修改。

如果仓库已经存在实现：

优先增量开发。

禁止无理由重建整个项目。

---

# 3. 总开发模式

严格按照 Plan 的 Phase 顺序：

```text
Phase 0
→ TEST
→ BUILD
→ ACCEPTANCE
→ COMMIT

Phase 1
→ TEST
→ BUILD
→ ACCEPTANCE
→ REGRESSION
→ COMMIT

...

直到全部阶段完成
```

一个 Phase 没有通过：

```text
禁止进入下一 Phase
```

失败后：

```text
分析
→ 修复
→ Test
→ Build
→ Re-accept
```

直到通过。

完成一个 Phase 后：

自动进入下一 Phase。

不要问：

```text
是否继续？
```

除非出现无法绕过的外部 blocker。

---

# 4. Development Progress

创建：

```text
docs/development-progress.md
```

记录：

```text
## Phase N

Status:
NOT_STARTED / IN_PROGRESS / BLOCKED / COMPLETED

Implemented:

Tests:

Build:

Acceptance:

Regression:

Manual Verification:

Known Limitations:

Commit:
```

这是阶段执行状态记录。

---

# 5. 技术栈

优先：

- Swift
- SwiftUI
- AppKit where appropriate
- Core Image
- Metal-backed CIContext
- CIRAWFilter
- ImageIO
- AVFoundation
- VideoToolbox if justified
- SQLite
- Swift Concurrency

Catalog 推荐：

```text
SQLite + GRDB
```

如果仓库已有可靠 SQLite 层，则复用。

不要为了替换技术栈重写已有代码。

不要引入：

- Electron
- Flutter
- React Native
- WebView main UI
- local HTTP server
- Firebase
- backend

---

# 6. 原文件原则

这是最高优先级约束。

默认：

```text
Referenced Library
```

应用索引用户已有目录中的照片和视频。

不要默认把所有原图复制进 App container。

禁止：

- 自动修改源照片
- 自动修改 RAW
- 自动覆盖源视频
- 自动移动目录
- 自动删除
- 自动重命名

Edit 必须非破坏性。

---

# 7. 文件访问

macOS App Sandbox 下：

用户通过系统 folder picker 添加 Root Folder。

对长期访问：

使用：

```text
security-scoped bookmark
```

必须实现：

- save bookmark
- resolve
- stale refresh
- startAccessingSecurityScopedResource
- stopAccessingSecurityScopedResource

处理：

- external drive disconnected
- volume renamed
- folder moved
- permission unavailable

不要只依赖绝对路径。

---

# 8. Catalog

应用数据放：

```text
Application Support/
```

建议：

```text
catalog.sqlite
thumbnails/
previews/
lut/
presets/
logs/
```

原照片/视频不复制进这里。

SQLite schema 使用 migration。

禁止：

```text
DROP + recreate DB
```

作为正常版本升级方案。

---

# 9. Phase 0

完成 Foundation：

- macOS App
- DB bootstrap
- migration
- filesystem directories
- logging
- error types
- task model
- tests
- documented build command

然后：

```text
TEST
BUILD
ACCEPTANCE
COMMIT
```

---

# 10. Phase 1 — Catalog + Folder Index

按照 Plan 实现。

重点：

- Add Folder
- security-scoped bookmark
- recursive scan
- image/video discovery
- metadata
- incremental rescan
- cancel
- offline volume

照片格式至少：

```text
jpg jpeg heic heif png tif tiff dng arw
```

视频至少：

```text
mov mp4 m4v
```

不要因为单个坏文件导致整个 Scan 失败。

---

# 11. Scanner Architecture

建议：

```text
MediaScanner
MetadataExtractor
CatalogWriter
ScanCoordinator
```

扫描与 DB 写入不要全部在 MainActor。

但 UI progress 必须安全更新。

避免一次创建几十万个 Swift Task。

使用：

- bounded concurrency
- batch DB transaction

而不是：

```text
Task per file forever
```

---

# 12. Incremental Scan

至少依据：

- relative path
- file size
- modification date

并在适合情况下利用 file resource identifier。

Rescan：

- unchanged → skip expensive metadata
- changed → refresh
- new → insert
- missing → mark missing/offline

禁止重复记录。

---

# 13. Phase 2 — Photo Library UX

实现符合 macOS 桌面操作习惯的：

```text
Sidebar
Grid
Inspector
Toolbar
```

支持：

- thumbnail resize
- multi-select
- Shift range
- Command select
- keyboard
- Space preview
- double-click viewer

不要把 iPhone bottom-tab UI 原样搬到 Mac。

---

# 14. Thumbnail

使用：

- lazy generation
- disk cache
- memory cache
- cancellation

Grid 不得一次载入所有 full-resolution images。

要支持数万资产 Catalog。

不需要为百万级数据过度复杂化。

---

# 15. Rating / Flag / Tag

实现：

```text
0–5 stars
Pick
Reject
Tag
```

提供合理 keyboard shortcut。

操作只更新 Catalog。

不修改源照片 metadata。

后续如果增加 metadata write-back，必须做成显式功能。

---

# 16. Phase 3 — Photo Editing

建立：

```text
PhotoEditState
PhotoImagePipeline
PreviewRenderer
ExportRenderer
```

EditState Codable。

Catalog 保存 edit state。

Preview / Export 严格分离。

---

# 17. Preview Pipeline

Preview：

```text
Source
→ decode/downsample
→ edit pipeline
→ display
```

不要对 24MP/48MP 图片每次 slider 都执行 full render。

需要：

- render cancellation
- generation/token
- stale result protection
- long-lived CIContext

---

# 18. Photo Adjustments

至少：

Light：

- Exposure
- Contrast
- Highlights
- Shadows
- Whites
- Blacks

Color：

- Temperature
- Tint
- Saturation
- Vibrance

Detail：

- Sharpness
- Noise Reduction where reasonable

Effects：

- Vignette

Transform：

- Crop
- Rotate
- Flip
- Straighten

---

# 19. HSL

支持：

```text
Red
Orange
Yellow
Green
Aqua
Blue
Purple
Magenta
```

每个：

```text
Hue
Saturation
Luminance
```

如果 Core Image 原生 filter 无法实现准确 HSL：

评估：

```text
CIColorKernel
Metal
```

不要用明显错误的色相模拟方式只为了功能存在。

---

# 20. Tone Curve

支持：

- Master
- R
- G
- B

控制点可序列化。

支持：

- add
- move
- delete
- reset

---

# 21. Histogram

- RGB
- luminance

基于 Preview。

节流。

不要对 full resolution 每次实时计算。

---

# 22. LUT

支持标准 `.cube`。

模块：

```text
LUTModel
CUBEParser
LUTRepository
LUTProcessor
LUTPreviewCache
```

支持：

```text
TITLE
LUT_3D_SIZE
DOMAIN_MIN
DOMAIN_MAX
```

至少：

```text
17
33
65
```

错误文件不得 crash。

---

# 23. Identity LUT

必须测试：

```text
Identity17
Identity33
```

应用前后结果应基本一致。

如果 Identity LUT 不正确：

不得把 LUT 模块标记完成。

---

# 24. LUT Intensity

```text
0 = no LUT
1 = full LUT
```

通过 base/lut result blend。

不要为了每次 intensity 修改重新生成 cube data。

---

# 25. Phase 4 — RAW

目标：

- DNG
- Sony ARW

使用系统当前：

```text
CIRAWFilter
```

实现之前先检查当前 macOS SDK 的实际 API。

不要使用过时教程中的 API 名称而不验证。

---

# 26. RAW Pipeline

保持：

```text
RAW Decode
→ RAW Adjustments
→ Standard Photo Edit
→ LUT
→ Effects
→ Export
```

RAW adjustments 和普通 photo adjustments 分开。

---

# 27. RAW Preview

不要一打开 RAW 就 full-size blocking render。

优先：

- quick preview
- progressively better preview
- full-quality export

如系统提供 embedded thumbnail/preview，可合理使用。

---

# 28. RAW Tests

如果仓库没有可合法提交的真实 ARW 测试资产：

不要提交用户照片。

可以：

- unit test parser/state
- 使用小型可公开测试 fixture（如果已有）
- 标记真实 ARW 为 MANUAL VERIFICATION

绝不把个人照片 commit 到 repo。

---

# 29. Phase 5 — Presets + Batch

实现：

Preset：

- save
- rename
- delete
- favorite
- import/export

Copy/Paste：

- all
- selective

Batch：

- apply preset
- apply LUT
- export

---

# 30. Batch Architecture

统一 Background Task Center。

禁止：

```text
同时加载 100 张 48MP 图片
```

采用：

- sequential
- or bounded concurrency

控制内存。

单项失败继续其他任务。

最终报告失败项目。

---

# 31. Export

照片至少：

- JPEG
- HEIF
- TIFF

设置：

- original
- resized
- quality
- metadata
- optional GPS removal
- naming

重名默认：

```text
rename
```

禁止静默覆盖。

---

# 32. Phase 6 — Management

按照 Plan 实现：

- Albums
- Smart Albums
- Duplicates
- Stacks
- Relink
- Safe Delete

---

# 33. Duplicate Safety

Exact duplicate 可以依赖：

- size candidate
- content hash verification

不要只用 filename。

Visual similarity：

只作为：

```text
candidate
```

绝不能直接作为自动删除依据。

任何删除：

用户明确选择。

默认 Move to Trash。

---

# 34. Phase 7 — Color Management

进入这一阶段以后：

不要凭感觉处理：

- Display P3
- Rec.709
- S-Log3
- HLG
- HDR

必须在代码和 docs 明确：

```text
Input
Working
Technical Transform
Creative Transform
Output
```

---

# 35. Creative / Technical LUT

实现：

```swift
enum LUTKind {
    case creative
    case technical
}
```

Technical LUT 应有 input/output metadata。

不能把 Log Technical LUT 当普通 Creative LUT。

---

# 36. Phase 8 — Video Library

完善视频：

- metadata
- poster thumbnail
- filmstrip optional
- playback
- rating
- tag
- search/filter

使用：

```text
AVFoundation
AVPlayer
```

不要使用 Web video player。

---

# 37. Phase 9 — Video Edit

建立独立：

```text
VideoEditState
VideoPipeline
VideoExportService
```

不要把 PhotoImagePipeline 强行改造成同时处理视频。

共享：

- LUT model
- parameter definitions when appropriate
- color metadata

---

# 38. Video Basic Features

至少：

- trim
- crop
- rotate
- flip
- basic exposure/contrast/saturation
- LUT
- LUT intensity
- mute
- audio gain
- simple speed

不要求第一版做专业 NLE。

---

# 39. AVFoundation

优先使用系统 AVFoundation。

需要 frame-level processing 时：

评估：

- AVVideoComposition
- AVVideoCompositing
- Core Image
- Metal

选择最小且可靠的方案。

不要提前自研完整视频引擎。

---

# 40. Video Export

至少支持合理的：

```text
H.264
HEVC
```

基于当前系统能力选择 preset / exporter / reader-writer。

支持：

- progress
- cancel
- error

保持：

- orientation
- audio sync
- trim duration

原视频永远不覆盖。

---

# 41. Phase 10 — Advanced Video

只在 Phase 9 稳定后：

- split
- reorder
- simple timeline
- fade
- simple transition
- audio fade
- proxy workflow
- HDR video

不要把项目变成 Premiere clone。

---

# 42. Phase 11 — Local Masks / Smart

最后再考虑：

- gradient mask
- radial mask
- brush
- subject
- sky
- similarity
- local semantic search
- face grouping

默认本地处理。

不要建立云端依赖。

---

# 43. UI 原则

macOS 桌面优先。

合理使用：

- NavigationSplitView
- Table
- Grid
- Inspector
- Toolbar
- ContextMenu
- Commands
- keyboard shortcuts

如果 SwiftUI 在：

- high-performance grid
- complex key handling
- image canvas
- drag/drop

存在明显限制，可以局部使用 AppKit。

不需要为了“100% SwiftUI”牺牲桌面体验。

---

# 44. Concurrency

重点检查：

- scanner
- thumbnail
- metadata
- RAW preview
- photo render
- hashing
- video frame processing
- export

禁止全部放 MainActor。

同时避免 unbounded Task。

建立明确 cancellation。

---

# 45. Database

所有 schema 改动：

使用 migration。

重点：

- indexes
- uniqueness
- foreign keys
- transactions

常用查询字段建立 index：

例如：

- root_id
- relative_path
- media_type
- capture_date
- rating
- flag

不要盲目给所有字段建 index。

---

# 46. 性能测试

逐步验证：

```text
1K
10K
50K
100K
```

Asset。

重点不是制造 benchmark 数字，而是发现：

- N+1 DB
- giant in-memory arrays
- thumbnail leaks
- slow scrolling
- unbounded concurrency
- slow filter query

---

# 47. 破坏性操作

涉及：

- delete
- move
- rename
- overwrite

必须：

- 用户显式触发
- 明确目标
- 失败可恢复
- 错误清楚

Delete 默认：

```text
Trash
```

而非 unlink。

---

# 48. Tests

根据阶段逐步增加：

Catalog：

- migration
- duplicate insertion
- root
- scan diff

Filesystem：

- bookmark model
- path resolution

Metadata：

- valid
- corrupted

Photo：

- EditState
- mapper
- LUT
- identity LUT
- pipeline smoke

RAW：

- state
- supported pipeline behavior

Batch：

- cancellation
- partial failure

Video：

- edit state
- trim math
- duration
- export configuration

---

# 49. Build

每个 Phase 都必须执行真实 macOS Build。

先自动发现：

- project
- workspace
- scheme

然后执行正确 `xcodebuild`。

例如：

```bash
xcodebuild \
  -scheme <Scheme> \
  -destination 'platform=macOS' \
  build
```

不要机械复制 scheme 示例。

---

# 50. Stage Acceptance

每阶段输出：

```text
PHASE N ACCEPTANCE

Implementation:
PASS/FAIL

Tests:
PASS/FAIL

Build:
PASS/FAIL

Regression:
PASS/FAIL

Manual Verification:
...

Known Limitations:
...
```

任何 P0 FAIL：

继续修。

不进入下一 Phase。

---

# 51. Commit

每个 Phase 完成后：

```bash
git status
git diff --stat
git diff
```

确保没有：

- personal photos
- video assets
- DerivedData
- build
- secrets
- large temporary files
- generated cache
- local catalog.sqlite

然后 commit。

建议：

```text
feat: complete phase 1 catalog indexing
feat: complete phase 2 photo library browsing
feat: complete phase 3 photo editing and LUT
...
```

不要自动 push。

---

# 52. Regression

从 Phase 2 开始：

每阶段必须回归已有核心能力。

例如 Phase 9 Video Editing 完成后，仍不能破坏：

- folder scan
- grid
- photo editing
- RAW
- LUT
- batch
- search

---

# 53. External Blocker

只有这些类型可以真正阻断：

- Xcode missing
- SDK missing
- signing requirement impossible locally
- required physical external drive unavailable
- required RAW/video test file unavailable
- OS permission must be manually granted

遇到：

标记：

```text
EXTERNAL BLOCKER
```

并完成所有其他不受影响工作。

不要因为一个真机测试不能自动执行，就停止整个项目。

---

# 54. 不允许的“完成”

以下不算完成：

- UI 有按钮但没有功能
- TODO
- hardcoded demo
- Fake sample only
- compiler 没跑
- test 没跑
- identity LUT 错误
- export 用 preview upscale
- scanner 每次重复插入
- delete 直接永久 unlink 无保护

---

# 55. 最终验收

全部 Phase 完成后：

执行项目级回归：

```text
Catalog
External Roots
Thumbnail
Metadata
Rating/Tags
Search
JPEG/HEIC edit
HSL
Curves
LUT
RAW
Preset
Batch
Duplicates
Color management
Video library
Video edit
Video export
Persistence
Offline disk behavior
```

运行：

```text
Tests
Build
```

然后：

```bash
git status
git log --oneline
```

---

# 56. 最终报告

输出：

```text
PROJECT DEVELOPMENT COMPLETE
```

并列出：

- Completed phases
- Commit hashes
- Architecture
- Database schema summary
- Catalog behavior
- Photo pipeline
- RAW pipeline
- LUT pipeline
- Video pipeline
- Test results
- Build results
- Performance notes
- Manual verification still required
- Known limitations
- Technical debt
- Recommended real-world verification checklist

---

# 57. 开始

现在：

1. 阅读 `mac_photo_studio_plan.md` / `plan.md`
2. 阅读当前仓库
3. 检查 Git
4. 创建 `docs/development-progress.md`
5. 找到最早未完成 Phase
6. 标记 IN_PROGRESS
7. 开发
8. 测试
9. Build
10. 验收
11. Commit
12. 自动进入下一阶段

持续执行，直到所有阶段完成或者出现真正无法绕过的外部阻塞。
