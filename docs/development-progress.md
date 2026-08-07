# Development Progress

## Phase 0

Status: COMPLETED

Implemented:
- 原生 macOS SwiftUI App、App Sandbox 与 macOS 15+ Xcode 工程。
- Application Support Catalog 目录（数据库、缩略图、预览、LUT、Preset、日志）创建逻辑。
- SQLite Catalog bootstrap、可追加的事务性 migration framework 与 Foundation schema。
- `CatalogStore`、`MediaRootStore`、`BookmarkStore`、`ThumbnailStore`、`BackgroundTaskCenter`、统一日志和错误模型。
- 单元测试 target，以及 README 中已记录的生成、测试和 Build 命令。

Tests:
- `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO test`
- PASS — 5 tests, 0 failures: Catalog bootstrap/migration/idempotency、目录创建、缩略图缓存与后台任务取消状态。

Build:
- `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build`
- PASS — `BUILD SUCCEEDED`。

Acceptance:
- PASS — App test host 启动并完成 Catalog bootstrap。
- PASS — `catalog.sqlite` 可创建，migration 事务执行且可重复 bootstrap。
- PASS — Application Support 所需目录均已创建。
- PASS — Unit test target 正常运行。
- PASS — Debug macOS Build 成功。

Regression:
- Not applicable; this is the first phase.

Manual Verification:
- None for Phase 0. 真实 folder picker 授权和外置硬盘书签恢复将在 Phase 1 标记并验证。

Known Limitations:
- 媒体根目录持久化、文件扫描和索引 UI 属于 Phase 1，尚未提前实现。

Commit:
- `feat: complete phase 0 foundation`

## Phase 1

Status: COMPLETED

Implemented:
- `File → Add Folder to Library…`（`⌘⇧O`）目录选择入口和资料库根目录状态界面；用户选定目录只保存引用，不复制或移动原始媒体。
- Security-scoped bookmark 创建、持久化、解析、stale bookmark 刷新，以及启动时目录/卷可用性检查。
- SQLite v2/v3 migration：媒体根目录、资产、照片元数据、视频元数据、增量扫描指纹、约束与索引；可修复开发早期的部分 v2 schema。
- 后台递归扫描 jpg/jpeg/heic/heif/png/tif/tiff/dng/arw 与 mov/mp4/m4v；ImageIO/AVFoundation 提取计划要求的照片和视频元数据，单个损坏文件不会中止扫描。
- 基于相对路径、大小、修改时间与文件资源标识的增量处理；批量写入、缺失文件标记、离线卷保留 Catalog 资产。
- 实际 Pause、Resume、Cancel/Restart 扫描控制与进度状态；Cancel 不会将未扫描到的资产误标记为 missing。

Tests:
- `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO test`
- PASS — 14 tests, 0 failures：Catalog migration/约束/增量 upsert/缺失与离线状态、bookmark 重开恢复、引用目录不复制、递归照片与视频扫描、损坏视频元数据容错、元数据尺寸、取消、2,000 个临时媒体文件的批处理扫描，以及 Phase 0 服务回归。

Build:
- `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build`
- PASS — `BUILD SUCCEEDED`。

Acceptance:
- PASS — 普通目录可通过 `MediaRootStore` 添加并持久化；测试确认 Catalog 未生成同名媒体副本。
- PASS — bookmark 在重新打开 Catalog 后可解析恢复。
- PASS — 增量 rescan 不重复插入，新扫描结果更新同一资产，未再次发现的文件保留并标记 `missing`。
- PASS — 照片和视频递归扫描同时入库；无效视频的元数据读取失败被隔离到单个资产。
- PASS — 离线根目录保留已有资产并标记 `offline`，不会删除 Catalog 记录。
- PASS — Pause/Resume/Cancel 使用可取消的扫描控制；取消扫描不会完成缺失标记流程。
- PASS — 2,000 个临时媒体文件以有限批次扫描，扫描在 utility task 中进行；数据库 migration 与约束的自动化测试通过。

Regression:
- PASS — 同一测试命令重新覆盖并通过 Phase 0 的 Catalog bootstrap/migration、Application Support 目录、缩略图缓存和后台任务取消测试（5 项）。

Manual Verification:
- MANUAL VERIFICATION REQUIRED — 在真实 sandbox App 中选择 `~/Pictures`、外置 SSD/HDD 与 SD 卡目录，并在重启后确认系统授权及 bookmark 刷新行为。
- MANUAL VERIFICATION REQUIRED — 真实外置卷断开、重新连接/改名后的 Offline 状态与恢复扫描。
- MANUAL VERIFICATION REQUIRED — 使用真实 HEIC/RAW 和可播放 MOV/MP4 检查相机/镜头、颜色配置、帧率、codec 等元数据；在真实数千至数万文件媒体库中观察 UI 响应。

Known Limitations:
- Phase 2 才会提供缩略图网格、Inspector 和照片浏览；本阶段只提供根目录及扫描状态 UI。
- 自动化性能覆盖为 2,000 个临时 PNG；真实大库、外置硬盘、权限和有效视频文件需要上述人工验收。
- 扫描器跳过目录 package 内部内容，后续格式支持将按计划增量扩展。

Commit:
- `feat: complete phase 1 catalog indexing`

## Phase 2

Status: COMPLETED

Implemented:
- 可调整三栏原生 macOS 资料库界面：Folders、智能相册、Ratings、Flags、Tags Sidebar，惰性分页 Grid，以及可隐藏的 Metadata Inspector。
- `LazyVGrid` 仅为可见单元发起缩略图任务；Catalog 每页读取 250 条轻量索引记录，不读取原始大图。支持缩略图尺寸调整、单选、Command 多选、Shift 范围选择、方向键导航、Space 预览和双击预览。
- 缩略图服务使用 ImageIO 和 AVFoundation：256/512 JPEG 磁盘缓存、64 MiB 上限的 LRU 内存缓存、视图 task cancellation，以及优先读取磁盘缓存以支持 Offline 资产。
- Catalog v4：评分（0–5）、Pick/Reject/Unflagged、标签与资产关系、GPS 元数据、索引和约束；支持标签创建、添加、移除、重命名、删除和筛选。
- 组合 Search/Filter 覆盖 filename、folder、日期、rating、flag、media type、camera、lens、tag 和 root folder；Inspector 展示文件、相机、镜头、EXIF、GPS 与视频元数据。

Tests:
- `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO test`
- PASS — 17 tests, 0 failures：Phase 0/1 全量回归、v4 migration、评分/Flag/Tag 持久化、组合筛选、10,000 条索引记录的 250 条分页读取、256/512 真实 JPEG 缩略图渲染、扫描与离线状态。

Build:
- `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build`
- PASS — `BUILD SUCCEEDED`。

Acceptance:
- PASS — 10,000 条 Catalog 测试以受限页读取；Grid 使用 `LazyVGrid` 与每个可见单元的异步缩略图 task，未批量解码原始大图。
- PASS — 评分、Flag、Tag 的创建/重命名/添加/移除及组合 filter 都通过持久化测试；这些操作仅写 Catalog，不写源媒体元数据。
- PASS — 256px 与 512px 缩略图可由真实 PNG 生成 JPEG；缓存查找先于源文件访问，Offline 资产可复用已有缩略图。
- PASS — Grid 代码实现 Command/Shift 多选、方向键导航、Space/双击预览、0–5/P/X/U 快捷键、Inspector 隐藏与缩略图尺寸调整。
- PASS — Inspector 已接入文件、尺寸、日期、相机、镜头、ISO、光圈、快门、焦距、GPS、视频时长/Codec 数据。

Regression:
- PASS — 同一 17 项测试套件回归覆盖 Phase 0 Catalog/目录/缓存/任务能力和 Phase 1 书签、扫描、增量、照片/视频、取消及 Offline 行为。

Manual Verification:
- MANUAL VERIFICATION REQUIRED — 在真实数千至数万文件资料库中快速滚动、改变缩略图尺寸，确认内存占用和响应性；自动化已验证 10,000 条分页，但不替代桌面渲染测量。
- MANUAL VERIFICATION REQUIRED — 用鼠标与键盘实际检验 Command/Shift 多选、方向键、Space、双击、0–5/P/X/U 快捷键及 Inspector 显示/隐藏。
- MANUAL VERIFICATION REQUIRED — 外置卷断开后的已有缩略图显示，以及真实照片/视频的 Inspector 数据完整性。

Known Limitations:
- Sidebar 的 Albums 为可用的照片/视频智能相册；用户自定义 Album 将在后续管理阶段按产品计划添加。
- 视频在本阶段只生成静态首帧缩略图和元数据；播放、剪辑、LUT/调色属于后续视频阶段。

Commit:
- `feat: complete phase 2 photo library browsing`

## Phase 3

Status: COMPLETED

Implemented:
- Catalog v5 `photo_edit_states` migration；每张照片的 `PhotoEditState` 以稳定 JSON 单独保存并在重新打开 Catalog 后恢复。编辑仅写 Catalog，绝不写回、移动、重命名或覆盖原始照片。
- `PhotoImagePipeline` 提供曝光、对比度、高光、阴影、白/黑色阶、色温、色调、饱和度、自然饱和度、锐化、降噪、暗角、裁剪、旋转、翻转及校正；HSL 使用 33³ 色彩立方体的 RGB↔HSL 变换，曲线支持 Master/R/G/B 可序列化控制点的添加、移动、删除和重置。
- 建立彼此独立的 `PreviewRenderer` 与 `ExportRenderer`：均使用长期存活的 Metal CIContext 和同一编辑管线；前者在编辑前限制预览尺寸，采用取消、90ms 防抖和 generation token 阻止过期渲染覆盖最新结果，直方图仅基于最大 512px 预览采样。
- `.cube` LUT parser 支持 TITLE、LUT_3D_SIZE、DOMAIN_MIN、DOMAIN_MAX 和 17/33/65 维；实现 LUT 强度、identity 内置 LUT、导入副本、重命名、删除导入项及收藏。无效/损坏 LUT 在解析阶段拒绝，原始 `.cube` 不会被改动。
- 从照片预览打开真实编辑器，提供色彩/细节/变换/HSL/曲线/LUT 控件、RGB+亮度直方图、按住查看原图和并排 Before/After；所有滑块编辑会防抖持久化并刷新预览。

Tests:
- `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO test`
- PASS — 23 tests, 0 failures：既有 Phase 0–2 回归，v5 migration/重启恢复，17/33 identity parser，坏 LUT 拒绝，identity LUT 像素恒等与强度 0，LUT 导入/重命名/收藏/删除，HSL/曲线/白黑色阶/裁剪像素管线，Preview/Export 色彩一致性、预览直方图和源文件字节不变。

Build:
- `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build`
- PASS — `BUILD SUCCEEDED`。

Acceptance:
- PASS — JPEG/PNG 自动化路径通过真实 Core Image Preview/Export 渲染；JPEG 与 HEIC 使用同一 ImageIO/Core Image 入口，HEIC 真机文件验证列为人工项。
- PASS — HSL 八色、Master/R/G/B 曲线、.cube LUT、裁剪与旋转/翻转、按住与并排 Before/After 均已有实际数据和 UI 路径，不是占位实现。
- PASS — 编辑状态通过 SQLite v5 保存并在 Catalog 重开后恢复；测试验证源 PNG 和源 `.cube` 的字节完全不变。
- PASS — Preview 在编辑前 downsample，Export 不 downsample；自动化像素比较确认相同尺寸输入上的颜色结果在 JPEG 编码容差内一致。
- PASS — LUT 解析与渲染、错误处理、缓存目录写入均不依赖用户媒体副本。

Regression:
- PASS — 全量 23 项测试覆盖 Phase 0 Catalog/目录/任务，Phase 1 bookmark/扫描/增量/离线，Phase 2 分页/评分/Flag/Tag/缩略图，及本阶段编辑渲染。
- PASS — 发现并修复既有标签测试对 SQLite `REAL` 往返纳秒精度的脆弱断言，改为验证持久化产品语义（tag ID 与名称）。

Manual Verification:
- MANUAL VERIFICATION REQUIRED — 用真实 JPEG、HEIC 和用户授权/外置磁盘目录，在桌面 App 中打开编辑器并完成滑块、HSL、曲线控制点、LUT 导入/删除、按住原图与并排比较的交互验证。
- MANUAL VERIFICATION REQUIRED — 在真实 24MP/48MP JPEG/HEIC 上持续拖动滑块、切换 100% 预览，观察内存、GPU 和过期渲染保护；自动化覆盖的是小图像与 downsample 行为，不能替代硬件测量。
- MANUAL VERIFICATION REQUIRED — 在含非默认色彩描述文件的真实照片上确认 Preview/Export 的视觉一致性与用户显示器上的颜色表现。

Known Limitations:
- RAW/ARW/DNG 开发、相机解码参数、100% 局部预览和 RAW 专属验证属于 Phase 4，不提前以普通图像管线替代。
- 写入用户选择目录的成品导出、Preset 与 Batch 属于 Phase 5；本阶段的 ExportRenderer 只负责全分辨率无损源读取和内存中结果，不会创建或覆盖任何用户文件。

Commit:
- `feat: complete phase 3 photo editing and lut`

## Phase 4

Status: COMPLETED

Implemented:
- Catalog v6 `raw_edit_states` migration：RAW 专属 `RAWEditState` 与 Phase 3 的 `PhotoEditState` 分表保存、独立恢复；不改变或复制 ARW/DNG 源文件。
- 基于 `CIRAWFilter` 的实际解码管线：`RAW → RAW 调整 → 标准 PhotoImagePipeline → LUT → Output`。曝光、色温、色调、阴影偏移，以及系统声明支持时的亮度/色彩降噪、锐化、局部对比、细节、局部色调、镜头校正和高光恢复均由能力查询门控，未支持参数不会写入 filter。
- RAW 预览使用 draft 模式和最大像素尺寸限制；每次全分辨率导出均重新执行非 draft RAW 解码。渲染任务具有 debounce、取消检查和 generation token，避免过期预览覆盖新结果。
- 新增 RAW 编辑器入口、参数控件、创意 LUT 选择/导入和 RAW 专属导出菜单；导出通过 NSSavePanel 只创建新文件，拒绝已有目标文件，支持 JPEG、HEIF（macOS HEIC profile）和 TIFF。
- RAW+JPEG 依据同 root、同目录、同 filename stem 配对；资料库可持久配置“同时显示”“组合显示”“优先显示 RAW”，组合模式在 RAW 卡片标识 `RAW+JPEG`，不会删除或修改隐藏的 JPEG 记录。

Tests:
- `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`
- PASS — 25 tests, 0 failures：Phase 0–3 全量回归、v6 RAW 状态持久化/重开恢复、RAW+JPEG root/目录/stem 配对边界、JPEG/HEIF(HEIC)/TIFF 实际 ImageIO 编码并反读验证格式，以及既有编辑、LUT、扫描、资料库和缩略图测试。

Build:
- `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`
- PASS — `BUILD SUCCEEDED`。

Acceptance:
- PASS — RAW 调整模型、SQLite v6 持久化、`CIRAWFilter` 能力门控和 RAW/标准照片/LUT 的严格阶段顺序已实现；普通照片编辑状态仍保持独立边界。
- PASS — 预览路径传入 draft + 缩放限制，RAW 导出路径固定以 `draft: false`、无像素限制重新解码；两条路径均在渲染前后检查取消。
- PASS — RAW 编辑器具有真实的能力限定控件、LUT 选择和保存面板；ImageIO 已实测生成并读取 JPEG、macOS HEIF/HEIC 与 TIFF 新文件，目标已存在时拒绝写入。
- PASS — ARW/DNG 与 JPG/JPEG 同名配对的三种显示策略、跨目录/跨 root 不误配、显示不破坏原 Catalog 记录均由单元测试验证。

Regression:
- PASS — 全量 25 项测试通过，覆盖 Phase 0 Catalog/任务、Phase 1 书签/扫描/增量/离线、Phase 2 分页/评分/Flag/Tag/缩略图，及 Phase 3 编辑/LUT 管线。

Manual Verification:
- MANUAL VERIFICATION REQUIRED — 仓库不包含真实 DNG 或 Sony ARW（且 `.dng`/`.arw` 被忽略），因此需要用用户授权的真实 DNG 和 ARW 验证 ImageIO 元数据、`CIRAWFilter` 解码、方向、可用参数集合、嵌入式/草稿预览和全分辨率导出。
- MANUAL VERIFICATION REQUIRED — 在真实 24MP/48MP RAW、外置盘/安全作用域目录及不同相机型号上持续调整参数和取消渲染，观察内存、GPU、权限和响应性；需要确认 LUT 与 JPEG/HEIF(HEIC)/TIFF 导出的视觉结果。

Known Limitations:
- 可见 RAW 控件严格受当前 macOS `CIRAWFilter` 能力限制；不同相机、系统版本和 RAW 文件会暴露不同集合，未支持功能不会被模拟。
- 本阶段提供单个 RAW 的真实导出；通用导出任务队列、命名模板、批处理和非 RAW 导出工作流仍属于 Phase 5。
- 自动化没有真实 RAW fixture，不能替代上述硬件、相机和外置存储人工验收；源媒体只会读取，测试未提交任何照片、RAW、视频、数据库或缓存。

Commit:
- `feat: complete phase 4 raw editing`
