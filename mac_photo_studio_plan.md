# Mac Photo Studio — Development Plan

## 1. 产品定位

开发一个原生 macOS 照片管理、照片编辑、RAW 编辑、LUT 与视频处理应用。

目标不是第一版复制 Lightroom Classic、Capture One、Photos、DaVinci Resolve，而是逐阶段做成一个适合个人长期使用的本地媒体工作台：

```text
照片/视频目录
→ 扫描索引
→ 缩略图与元数据
→ 分类 / 筛选 / 评分
→ 非破坏性照片编辑
→ RAW 编辑
→ LUT / Preset
→ 批量处理
→ 视频预览 / 调色 / LUT / 基础剪辑
→ 导出
```

主要特征：

- 原生 macOS App
- 本地优先
- 不依赖云服务
- 不复制原文件为默认策略
- 能管理内置磁盘和外置硬盘上的照片/视频
- 数据库只保存索引、编辑参数和管理信息
- 原媒体文件默认保持原位置
- 编辑为非破坏性
- 支持高分辨率照片和 RAW
- 后续支持视频 LUT、基础调色与剪辑
- 为大规模照片库预留合理性能能力，但不过度企业化

---

# 2. 核心设计原则

优先技术栈：

- Swift
- SwiftUI
- AppKit（仅在 SwiftUI 不适合的桌面交互场景使用）
- Core Image
- Metal-backed CIContext
- CIRAWFilter
- ImageIO
- AVFoundation
- VideoToolbox（需要硬件编解码或性能优化时）
- UniformTypeIdentifiers
- SQLite
- Swift Concurrency

数据库可选择：

- GRDB + SQLite

如果项目希望完全 Apple 原生，也可以直接使用 SQLite3。

不要为了“纯原生”牺牲数据库可靠性和迁移可维护性。

---

# 3. 不做 Managed Library 作为默认模式

第一版默认采用：

```text
Referenced Library
```

即：

用户选择：

```text
/Volumes/Photos
/Volumes/Backup-1/DCIM
~/Pictures
```

应用只建立索引。

不把所有原始照片复制进 App Library。

数据库保存：

- root folder
- relative path
- stable identity hints
- metadata
- thumbnail path
- rating
- flag
- tags
- edit state
- preset relation
- duplicate fingerprints
- media type

优点：

- 外置硬盘友好
- 不产生第二份几 TB 的媒体文件
- Finder 仍然可以直接访问
- 用户可继续使用已有目录结构

以后可以增加可选：

```text
Managed Library
```

但不属于早期阶段。

---

# 4. macOS 文件访问

应用需要支持：

- 内置磁盘
- 外置 SSD
- 外置 HDD
- SD 卡
- 用户选择目录

对于沙盒环境：

用户通过目录选择器授权根目录。

应用保存：

```text
Security-scoped bookmark
```

重新启动 App 后恢复访问。

必须正确：

```text
resolve bookmark
startAccessingSecurityScopedResource
...
stopAccessingSecurityScopedResource
```

处理：

- bookmark stale
- drive disconnected
- folder moved
- volume renamed
- permission lost

数据库不能只保存绝对路径并认为它永远有效。

---

# 5. Catalog

建议：

```text
~/Library/Application Support/<AppName>/
    catalog.sqlite
    thumbnails/
    previews/
    lut/
    presets/
    logs/
```

Catalog 保存索引和编辑状态。

不默认保存原照片。

---

# 6. Media Asset Model

基础模型：

```swift
struct MediaAsset {
    let id: UUID

    var rootID: UUID
    var relativePath: String

    var mediaType: MediaType
    var fileExtension: String

    var fileSize: Int64
    var createdAt: Date?
    var modifiedAt: Date?

    var width: Int?
    var height: Int?

    var duration: Double?

    var cameraMake: String?
    var cameraModel: String?
    var lensModel: String?

    var focalLength: Double?
    var aperture: Double?
    var shutterSpeed: Double?
    var iso: Int?

    var captureDate: Date?

    var rating: Int
    var flag: AssetFlag

    var editStateID: UUID?
}
```

实际数据库应使用数据库 row / record 类型，而不是强制完整 Swift struct 一次加载整个库。

---

# 7. 目录与模块

建议：

```text
MacPhotoStudio/
├── App/
│
├── Features/
│   ├── Library/
│   ├── Import/
│   ├── Browser/
│   ├── Viewer/
│   ├── PhotoEditor/
│   ├── RAWEditor/
│   ├── LUTLibrary/
│   ├── Presets/
│   ├── Search/
│   ├── Duplicates/
│   ├── Batch/
│   ├── VideoBrowser/
│   ├── VideoEditor/
│   └── Export/
│
├── Core/
│   ├── Catalog/
│   ├── Filesystem/
│   ├── Metadata/
│   ├── Thumbnail/
│   ├── Imaging/
│   ├── RAW/
│   ├── LUT/
│   ├── Color/
│   ├── Video/
│   └── Tasks/
│
├── Services/
│
├── Persistence/
│
└── Tests/
```

避免巨大：

```text
ContentView.swift
PhotoManager.swift
```

承担所有职责。

---

# 8. 全局开发阶段

推荐顺序：

```text
Phase 0  Foundation
Phase 1  Catalog + Folder Indexing
Phase 2  Photo Library UX
Phase 3  Photo Editing + LUT
Phase 4  RAW Editing
Phase 5  Presets + Batch + Export
Phase 6  Advanced Photo Management
Phase 7  Color Management + HDR
Phase 8  Video Library
Phase 9  Video Editing + LUT
Phase 10 Advanced Video
Phase 11 Local Masks / Smart Features
```

---

# Phase 0 — Foundation

## 目标

建立可靠的 macOS 原生工程基础。

完成：

- macOS SwiftUI App
- App Sandbox
- project structure
- logging
- error model
- database bootstrap
- migration framework
- application support directories
- task model
- tests target
- build scripts / documented xcodebuild command

建立：

```text
CatalogStore
MediaRootStore
BookmarkStore
ThumbnailStore
BackgroundTaskCenter
```

但不要提前实现后续全部功能。

## 验收

- App 可以启动
- DB 可以创建
- migration 可以执行
- Application Support 路径正确
- 单元测试 target 正常
- Debug Build PASS

---

# Phase 1 — Catalog + Folder Indexing

## 目标

真正建立照片/视频目录索引系统。

这是桌面 App 最重要的基础阶段。

## 1.1 Add Folder

用户可以：

```text
File
→ Add Folder to Library
```

选择：

- ~/Pictures
- 外置盘目录
- SD 卡目录

保存 security-scoped bookmark。

---

## 1.2 Scanner

递归扫描：

### Photo

- jpg
- jpeg
- heic
- heif
- png
- tif
- tiff
- dng
- arw

架构上允许后续增加更多 RAW。

### Video

- mov
- mp4
- m4v

后续扩展其他 AVFoundation 支持格式。

---

## 1.3 Incremental Scan

第一次：

```text
Full Scan
```

后续：

```text
Incremental Rescan
```

根据：

- path
- file size
- modification date
- filesystem identity where practical

判断变化。

禁止每次启动都把所有文件重新完整解析。

---

## 1.4 Metadata

ImageIO / AVFoundation 读取：

照片：

- dimensions
- capture date
- camera
- lens
- ISO
- aperture
- shutter
- focal length
- orientation
- color profile if available

视频：

- duration
- dimensions
- frame rate
- codec
- creation date

读取失败：

不得导致整个扫描失败。

---

## 1.5 Background Scanning

扫描不能阻塞 UI。

实现：

```text
Background Task
Progress
Pause
Cancel
Resume/restart
```

至少 Cancel 必须真正生效。

---

## 1.6 Offline Volume

外置盘断开后：

Catalog 记录仍存在。

UI 显示：

```text
Offline
```

而不是删除资产。

磁盘重新连接后允许恢复。

---

## 1.7 Phase 1 验收

验证：

- 添加普通目录
- 添加外置卷目录
- 重启 App 后 bookmark 可恢复
- 扫描至少数千文件时 UI 不冻结
- Rescan 不重复插入
- 新文件能被发现
- 删除文件能标记 missing/offline
- 视频与照片可以同时入库
- Scan Cancel 有效
- DB migration / constraints 正常

---

# Phase 2 — Photo Library UX

## 目标

把 Catalog 变成可用的照片管理应用。

---

## 2.1 主界面

桌面布局：

```text
┌ Sidebar ┬──────────────────── Grid ────────────────────┬ Inspector ┐
│         │                                              │           │
│Folders  │                 thumbnails                   │ Metadata  │
│Albums   │                                              │ Rating    │
│Ratings  │                                              │ EXIF      │
│Tags     │                                              │           │
└─────────┴──────────────────────────────────────────────┴───────────┘
```

支持 Inspector 隐藏。

---

## 2.2 Thumbnail

异步生成：

- 256px
- 512px

根据 UI 使用适合尺寸。

使用磁盘 cache。

不要把几十万缩略图全部加载进内存。

需要：

- memory cache
- disk cache
- eviction
- lazy loading
- task cancellation

---

## 2.3 Grid

支持：

- 调整 thumbnail size
- 多选
- shift range select
- command select
- double-click preview
- keyboard navigation
- space Quick Look style preview

---

## 2.4 Metadata Inspector

展示：

- file
- folder
- dimensions
- date
- camera
- lens
- ISO
- aperture
- shutter
- focal length
- GPS（如果存在）
- video duration / codec

---

## 2.5 Rating / Flag

支持：

```text
0–5 stars
Pick
Reject
Unflagged
```

快捷键优先。

---

## 2.6 Tags

用户可创建 tag：

例如：

```text
新疆
草原
银河
无人机
家人
待修
已导出
```

支持：

- add
- remove
- rename
- filter

---

## 2.7 Search / Filter

至少支持：

- filename
- folder
- date
- rating
- flag
- media type
- camera
- lens
- tag

组合过滤。

---

## 2.8 Phase 2 验收

- 1 万条 Catalog 浏览不应一次性加载所有大图
- 快速滚动缩略图正常
- Rating/Flag 快捷键可用
- Tag 可持久化
- Filter 结果正确
- Offline asset 仍可以看到已有 thumbnail
- 多选交互符合 macOS 习惯

---

# Phase 3 — Photo Editing + LUT

## 目标

建立与 iOS 版本同源思想的非破坏性照片编辑能力。

---

## 3.1 EditState

```text
Light
Color
Detail
Effects
Transform
LUT
```

支持序列化。

Catalog 每张图片保存独立 EditState。

不修改原文件。

---

## 3.2 Adjustments

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
- Noise Reduction（普通图片先提供合理基础能力）

Effects：

- Vignette

Transform：

- Crop
- Rotate
- Flip
- Straighten

---

## 3.3 HSL

支持：

- Red
- Orange
- Yellow
- Green
- Aqua
- Blue
- Purple
- Magenta

每色：

- Hue
- Saturation
- Luminance

---

## 3.4 Tone Curve

支持：

- Master
- Red
- Green
- Blue

控制点可：

- add
- move
- delete
- reset

---

## 3.5 Histogram

- RGB
- Luminance

基于 Preview。

避免全分辨率实时 histogram。

---

## 3.6 LUT

支持：

- `.cube`
- 17
- 33
- 65

解析：

- TITLE
- LUT_3D_SIZE
- DOMAIN_MIN
- DOMAIN_MAX

分类：

- Built-in
- Imported
- Favorites

支持：

- import
- rename
- delete imported
- LUT strength

必须有 identity LUT test。

---

## 3.7 Preview Pipeline

编辑时使用 downsampled preview。

需要：

- cancellation
- stale-render protection
- long-lived Metal CIContext

放大到 100% 时可请求局部或更高质量 preview。

---

## 3.8 Before / After

支持：

- hold key/button
- side by side
- split view（可在后续细化）

---

## 3.9 Phase 3 验收

- JPEG/HEIC 调色
- HSL
- Curve
- LUT
- Crop
- Before/After
- 重启 App 后编辑状态存在
- 原文件未变化
- Preview 与 Export 色调基本一致
- 24MP / 48MP 图片交互无明显内存灾难

---

# Phase 4 — RAW Editing

## 目标

支持相机 RAW，重点包括 Sony ARW 和 DNG。

---

## 4.1 RAW Pipeline

```text
RAW File
→ CIRAWFilter
→ RAW Adjustments
→ Standard Photo Pipeline
→ Creative LUT
→ Output
```

RAW 参数不得和普通调色参数混成无边界的一层。

---

## 4.2 RAW Parameters

根据 CIRAWFilter 当前系统能力实现合理参数集合：

- exposure
- temperature
- tint
- noise reduction
- sharpness
- contrast/local tone where supported
- detail
- lens corrections where available

不要伪造系统并不支持的功能。

---

## 4.3 Fast Preview

RAW 打开：

1. 快速显示 embedded preview / lower quality render（如果合适）
2. 后续生成高质量 preview
3. Export 时重新执行 full RAW pipeline

避免一打开 ARW 就完整渲染全分辨率。

---

## 4.4 RAW + JPEG Pair

识别：

```text
DSC00123.ARW
DSC00123.JPG
```

允许作为 Pair 显示。

可配置：

- show both
- group pair
- prefer RAW

---

## 4.5 RAW Export

支持至少：

- JPEG
- HEIF
- TIFF（建议此阶段增加）

后续可增加更专业格式。

---

## 4.6 Phase 4 验收

测试真实：

- DNG
- Sony ARW

验证：

- metadata
- preview
- RAW adjustment
- LUT
- full resolution export
- orientation
- memory
- cancellation

如果测试文件缺少，必须明确 MANUAL VERIFICATION REQUIRED，不得假装通过。

---

# Phase 5 — Presets + Batch + Export

## 目标

提高旅行/大量照片处理效率。

---

## 5.1 Presets

保存：

- Light
- Color
- HSL
- Curves
- Detail
- Effects
- LUT
- LUT intensity

默认不包含：

- Crop

支持：

- create
- rename
- delete
- favorite
- import/export

---

## 5.2 Copy / Paste

支持：

- Copy All
- Paste All
- Selective Paste

多选照片可批量 Paste。

---

## 5.3 Batch Apply

多选：

```text
100 photos
→ Apply Preset
```

只修改 Catalog EditState。

不会立刻生成 100 个输出文件。

---

## 5.4 Batch Export

支持：

- JPEG
- HEIF
- TIFF
- resize
- quality
- naming rule
- output folder
- keep metadata
- optional remove GPS

任务系统：

- queued
- running
- succeeded
- failed
- cancelled

单张失败不应让整批崩溃。

---

## 5.5 Export Collision

文件重名：

- overwrite
- skip
- rename
- ask

默认安全策略：

```text
rename
```

不要默默覆盖。

---

# Phase 6 — Advanced Photo Management

## 目标

增加真正有价值的照片整理能力。

---

## 6.1 Albums / Collections

Catalog 虚拟集合。

不移动原文件。

支持：

- Album
- Smart Album

Smart Album 条件：

- rating
- date
- camera
- lens
- tag
- media type
- edited
- RAW

---

## 6.2 Duplicate Detection

分两层：

### Exact Duplicate

使用：

- file size
- cryptographic content hash

不要一开始对全库所有 TB 文件强制 SHA-256。

先进行 candidate grouping，再 hash。

### Visual Similarity

后续：

- perceptual hash
- Vision feature print

用于：

- 连拍
- 导出副本
- resize copies
- 相似照片

不要把 visual similarity 当作可以自动删除文件的充分条件。

---

## 6.3 Stacks

允许：

- Burst stack
- RAW/JPEG pair
- user stack

---

## 6.4 Missing File Relink

目录移动后：

```text
Locate Missing Folder
```

重新建立 root mapping。

不要因为路径变化就丢失 rating/edit/tag。

---

## 6.5 Safe Delete

建议默认：

```text
Move to Trash
```

而不是永久删除。

批量删除必须明确用户动作。

---

# Phase 7 — Color Management + HDR

## 目标

系统解决专业色彩和 Technical LUT。

---

## 7.1 Color Pipeline

明确：

```text
Source Color Space
→ Working Color Space
→ Technical Transform
→ Creative Adjustments
→ Creative LUT
→ Output Transform
→ Display / Export
```

支持/评估：

- sRGB
- Display P3
- Rec.709
- Linear working spaces
- extended range
- HDR

---

## 7.2 LUT Kind

```swift
enum LUTKind {
    case creative
    case technical
}
```

Technical LUT metadata：

- input color space
- output color space
- expected transfer function

禁止把：

```text
S-Log3 → Rec.709
```

当普通 Creative LUT 随便套到 sRGB JPEG。

---

## 7.3 HDR Photo

在 SDR pipeline 稳定后增加：

- HDR preview
- SDR tone mapping
- HDR export where system APIs permit

HDR 功能不得破坏 SDR。

---

# Phase 8 — Video Library

## 目标

在已有 Catalog 中正式支持视频管理。

虽然 Phase 1 已扫描视频，这一阶段完善视频专属体验。

---

## 8.1 Video Metadata

保存/展示：

- duration
- codec
- dimensions
- frame rate
- audio tracks
- color properties
- HDR indication where detectable

---

## 8.2 Video Thumbnail

生成：

- poster frame
- optional filmstrip thumbnails

缓存。

---

## 8.3 Playback

原生 AVPlayer。

支持：

- play/pause
- seek
- frame stepping where practical
- volume
- fullscreen
- playback rate

---

## 8.4 Video Filter/Search

统一照片库：

```text
All
Photos
RAW
Videos
Edited
```

视频同样支持：

- rating
- flag
- tags
- albums

---

# Phase 9 — Video Editing + LUT

## 目标

实现实用的基础视频调色和处理，而不是做完整 NLE。

---

## 9.1 Non-destructive Video Edit State

保存：

```text
trim
crop
rotation
speed
adjustments
lut
lutIntensity
audioGain
```

不直接修改原视频。

---

## 9.2 Basic Video Editing

支持：

- Trim start/end
- Crop
- Rotate
- Flip
- Basic exposure / contrast / saturation
- Temperature/tint if pipeline supports correctly
- LUT
- LUT intensity
- Mute
- Audio gain
- Simple speed adjustment

---

## 9.3 Video Preview

AVFoundation pipeline。

照片 ImagePipeline 与 VideoPipeline 分离。

可以共享：

- LUT parser
- adjustment definitions
- color management metadata

不强行共享 renderer。

---

## 9.4 Export

支持合理的：

- H.264
- HEVC

根据平台能力和源文件允许：

- preserve resolution
- resize
- quality/preset

导出必须：

- progress
- cancel
- error reporting

---

## 9.5 Phase 9 验收

至少：

```text
MOV/MP4
→ playback
→ trim
→ LUT
→ intensity
→ exposure/saturation
→ export
```

输出：

- 音视频同步
- orientation 正确
- duration 正确
- 不覆盖原视频

---

# Phase 10 — Advanced Video

## 目标

只增加个人使用价值高的能力。

候选：

- multi-segment simple timeline
- clip split
- clip reorder
- fade
- simple transition
- audio fade
- video stabilization metadata/options if feasible
- HDR video
- technical LUT
- proxy workflow for 4K/large files

明确不优先：

- 多机位
- Fusion-like compositor
- 专业音频 DAW
- 大型 title system
- 完整 DaVinci/Premiere 替代

---

# Phase 11 — Local Masks / Smart Features

## 目标

在核心编辑和管理成熟后再增加智能功能。

照片候选：

- Linear Gradient
- Radial Gradient
- Brush Mask
- Subject Mask
- Sky Mask

管理候选：

- perceptual similarity
- semantic search
- face grouping（如果个人确实需要）

必须：

- 本地处理优先
- 不把用户照片默认上传云端

---

# 9. 编辑 Pipeline 的复用原则

## Photo

```text
Decoded Image
→ RAW stage if RAW
→ Global adjustments
→ HSL / Curve
→ LUT
→ detail/effects
→ transform
→ output
```

## Video

```text
Decoded Frame
→ video color transform
→ global adjustments
→ LUT
→ transform
→ encode/display
```

共享：

- parameter models where semantics identical
- LUT parser/repository
- color metadata
- presets where compatible

不共享：

- high-level renderer
- scheduling
- decode/encode
- video timeline state

---

# 10. 数据库建议

主要表：

```text
media_roots
media_assets
photo_metadata
video_metadata
thumbnails
edit_states
raw_edit_states
tags
asset_tags
albums
album_assets
presets
duplicate_fingerprints
background_tasks
schema_migrations
```

不要把大型 thumbnail/blob 全部直接塞数据库。

缩略图推荐文件 cache + DB path/status。

---

# 11. Background Task Center

统一处理：

- folder scan
- metadata extraction
- thumbnail generation
- preview generation
- duplicate hashing
- batch export
- video export

任务状态：

```text
queued
running
paused
cancelled
failed
completed
```

避免每个 Feature 自己写一套不可控制的 Task。

但也不要引入复杂分布式队列思想。

这是本机 App。

---

# 12. 性能目标

测试规模逐步覆盖：

```text
1,000 assets
10,000 assets
50,000 assets
100,000 assets
```

不要求为了百万级做过度优化。

重点检查：

- Catalog query
- grid scrolling
- thumbnail generation
- memory
- scan resume
- search
- full resolution render
- RAW preview
- batch export
- 4K video playback/export

---

# 13. 数据安全

最重要原则：

```text
原文件安全 > 所有功能
```

默认：

- 非破坏性
- 不自动移动
- 不自动改名
- 不自动删除
- 不覆盖
- 不写回 RAW

任何 destructive operation 都必须有明确用户动作。

---

# 14. Sidecar / Portability

中后期建议增加：

```text
optional sidecar
```

例如：

```text
IMG_1234.ARW
IMG_1234.appname.json
```

可以保存：

- rating
- edit state
- tags

但第一版优先 Catalog。

Sidecar 属于后续增强，不应拖慢 Phase 1。

---

# 15. 自动化验收规则

每个 Phase 执行：

```text
CODE
→ TEST
→ BUILD
→ ACCEPTANCE
→ REGRESSION
→ COMMIT
→ NEXT PHASE
```

任何 P0 验收失败：

不得进入下一阶段。

创建：

```text
docs/development-progress.md
```

记录：

- phase status
- tests
- build
- commit
- manual verification
- known limitations

---

# 16. 真机/真实资源验证

以下内容可能无法完全自动测试：

- 外置硬盘 reconnect
- 大型 RAW
- Sony ARW rendering
-真实 HDR 显示
- 特定视频 codec
- 4K/10-bit/HDR video
- Photos / Finder 权限交互

不得假装 PASS。

标记：

```text
MANUAL VERIFICATION REQUIRED
```

---

# 17. 第一版最重要里程碑

## Milestone A — Library

完成：

```text
Phase 0–2
```

效果：

一个真正能索引和整理本地/外置硬盘照片的 macOS 照片管理 App。

## Milestone B — Photo Studio

完成：

```text
Phase 3–5
```

效果：

照片、RAW、LUT、Preset、批量导出基本完整。

## Milestone C — Media Studio

完成：

```text
Phase 6–9
```

效果：

照片管理成熟，并能统一管理和基础处理视频。

---

# 18. 长期完成标准

最终应该做到：

- 添加多个目录/硬盘
- 快速索引
- 外置盘离线后 Catalog 仍保留
- 高效浏览缩略图
- 星级/Flag/Tag/Album
- 元数据搜索
- JPEG/HEIC 编辑
- RAW/ARW/DNG 编辑
- HSL/Curve
- LUT
- Preset
- 批量编辑/导出
- 重复照片辅助识别
- Video Library
- 视频 LUT
- 视频基础调色
- Trim/Crop/Speed
- 视频导出
- 全过程不破坏原媒体

项目成功标准不是“功能最多”，而是：

```text
本地照片资产安全
+
Catalog 稳定
+
编辑结果可靠
+
大图/RAW 性能可接受
+
视频功能实用
+
长期可维护
```
