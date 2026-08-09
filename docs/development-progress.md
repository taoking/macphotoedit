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

## Phase 5

Status: COMPLETED

Implemented:
- Catalog v7 `photo_presets`：预设以 JSON 保存 Light、Color、HSL、Curves、Detail、Effects 与 LUT（含强度），明确不含 Crop/旋转/翻转；提供创建、重命名、删除、收藏与独立 JSON import/export，导入不会修改外部预设文件。
- 资料库多选“编辑”菜单具备 Copy All、Paste All、Selective Paste、从选中照片创建预设、应用预设、预设管理和批量导出入口。批量粘贴/应用只顺序更新 Catalog EditState，不生成输出文件，且每张保留自己的 Transform/Crop。
- 通用 `PhotoExportOptions` 与实际全分辨率文件导出：JPEG、HEIF（macOS HEIC profile）、TIFF；支持最长边 resize、JPEG/HEIF quality、原名/Edited/连续编号、选择输出文件夹、保留元数据及可选 GPS 移除。
- 统一 Background Task Center 增加照片批量调整/导出任务，显示 queued/running/completed/failed/cancelled 状态、进度、取消入口和最近一份成功/跳过/失败报告。导出严格顺序执行，单项失败会记录后继续下一项。
- 输出冲突支持 overwrite、skip、rename、ask；默认 `rename`。写入先编码临时文件再移动；只有用户明确选择覆盖才替换目标，且无论何种选择都拒绝覆盖引用的原始媒体文件。

Tests:
- `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO test`
- PASS — 30 tests, 0 failures：Phase 0–4 全量回归、v7 preset migration/持久化/rename/favorite/import/export、Crop 不随 preset/copy 覆盖、批量应用单项失败继续且只写 Catalog、JPEG/HEIF/TIFF ImageIO 编码、导出 resize/quality/metadata/GPS 移除与保留、默认重命名、显式覆盖/跳过策略、源文件不可覆盖、缺失单项不终止整批、导出任务状态。

Build:
- `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build`
- PASS — `BUILD SUCCEEDED`。

Acceptance:
- PASS — Preset 覆盖计划要求的全部可复制调色组且不含 Transform；Catalog v7 持久化、JSON import/export、UI 管理和收藏路径均已存在。
- PASS — 多选 Copy/Paste/Selective Paste/Apply Preset 已接入实际 Catalog 写入；自动化验证无效 asset 不会阻断后续项且目标 Crop 仍保持不变。
- PASS — Batch Export 实际逐张读取/渲染/释放内存，生成 JPEG、HEIF（HEIC）和 TIFF；UI 可设置尺寸、质量、命名、输出目录、metadata/GPS 与全部冲突策略。
- PASS — 输出先落地临时文件；默认冲突命名为 `name (2)`，覆盖只能由显式选择触发；自动化验证源 JPEG 的字节不变、导出到源路径即使请求 overwrite 也被拒绝。
- PASS — 任务中心可展示、取消 batch edit/export，并在每项失败后继续；最终报告包含 succeeded/skipped/failed 计数及失败项。

Regression:
- PASS — 同一 30 项测试集回归覆盖 Phase 0 Catalog/目录/任务、Phase 1 bookmark/扫描/增量/离线、Phase 2 分页/评分/Flag/Tag/缩略图、Phase 3 照片编辑/LUT、Phase 4 RAW 模型/格式输出，以及本阶段全部功能。

Manual Verification:
- MANUAL VERIFICATION REQUIRED — 在真实 sandbox App 中用用户授权的 JPEG、HEIC、TIFF、DNG/ARW、外置硬盘目录和实际输出文件夹，验证导出权限、预设面板、拖放/键鼠多选、任务取消、ask 冲突对话框与 overwrite/skip/rename 结果。
- MANUAL VERIFICATION REQUIRED — 用真实 24MP/48MP 照片和 100+ 张批量导出观察逐张内存峰值、GPU 响应、取消时机、EXIF/色彩描述文件保留与 GPS 移除；自动化使用小型临时 JPEG，不能替代硬件/用户媒体测量。
- MANUAL VERIFICATION REQUIRED — 在 HEIF/HEIC 和真实 RAW 的原始元数据上确认系统 ImageIO 可写性、metadata 保留兼容性和视觉质量；不同 macOS/相机可能提供不同编码与 RAW 能力。

Known Limitations:
- 批量导出任务在本阶段为当前运行期任务，应用重启后不恢复未完成队列；视频导出、视频命名策略和视频任务会在后续视频 Phase 增量实现。
- HEIF 由 macOS 当前可用的 HEIC ImageIO encoder 提供；不可用时 UI 会禁用该格式并在服务层返回明确错误，不会伪造输出。
- 自动化无真实用户 RAW/HEIC/外置卷 fixture，相关权限、性能、相机兼容性与显示器视觉检查保留为上述人工验收。

Commit:
- `feat: complete phase 5 presets batch export`

## Phase 6

Status:
- COMPLETED

Implemented:
- Added catalog schema v8 for standard albums, smart albums, album membership, stacks, and cached content hashes.
- Implemented real virtual album membership and smart-album filtering for rating, date, camera, lens, tag, media type, edited state, and RAW state.
- Added burst, RAW/JPEG-pair, and user stack catalog models and management flows.
- Added same-size candidate selection followed by streamed SHA-256 content hashing for exact duplicate detection. Results are informational only and never delete media automatically.
- Added root relinking that retains the original catalog root identity and all associated edits, ratings, tags, albums, and stack memberships.
- Added an explicit, confirmed Move to Trash flow that calls macOS Trash APIs only after validating the selected media remains inside its catalog root; catalog metadata is retained as a missing asset.

Tests:
- `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' test`
- PASS — 34 tests, 0 failures.

Build:
- `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' build`
- PASS — `** BUILD SUCCEEDED **`.

Acceptance:
- PASS — standard and smart albums are virtual catalog references and do not copy source media.
- PASS — smart-album criteria cover the Phase 6 requirements.
- PASS — exact duplicates use size candidates plus cryptographic content hashes; no automatic deletion path exists.
- PASS — stack types and missing-root relinking preserve catalog relationships and edits.
- PASS — deletion requires explicit confirmation and moves only the selected in-root item to Trash.

Regression:
- PASS — all prior catalog, browsing, editing, RAW, preset, batch-export, and share tests pass in the full suite.

Manual Verification:
- MANUAL VERIFICATION REQUIRED — relink a genuinely moved external-media root and confirm retained edits, ratings, tags, albums, and stacks after reopening the app.
- MANUAL VERIFICATION REQUIRED — move expendable user-selected media to macOS Trash, restore it, and validate macOS permission behavior.
- MANUAL VERIFICATION REQUIRED — exercise duplicate hashing on a large removable-media library, including an unplugged root and scoped-access denial.

Known Limitations:
- Visual-similarity analysis is intentionally deferred; exact SHA-256 duplicate results are the only duplicate result shown and never trigger deletion.
- Hashing requires the source root to be accessible. Per-item access or I/O failures are reported rather than treated as duplicates.

Commit:
- `feat: complete phase 6 advanced photo management`

## Phase 7

Status:
- COMPLETED

Implemented:
- Added an explicit documented colour pipeline: Source Color Space → Extended Linear working space → Technical Transform → Creative Adjustments → Creative LUT → Output Transform → Display/Export.
- Added serializable source/output colour descriptors for sRGB, Display P3, Rec.709, Rec.2020, linear spaces and sRGB/linear/Rec.709/S-Log3/HLG/PQ transfer functions. Render boundaries request the selected output `CGColorSpace` so ColorSync performs the output conversion.
- Split Creative and Technical LUTs. Technical LUT import now requires persistent input/output colour-space and transfer-function metadata; selection is rejected unless the source descriptor exactly matches, and Technical LUTs cannot enter the Creative LUT slot.
- Preserved legacy Phase 3–6 edit-state JSON while adding `technicalLUT` and colour-pipeline state. Standard photo and RAW editors expose the same output/HDR and technical-transform state.
- Added extended-range HDR preview rendering as half-float TIFF into an AppKit EDR-enabled layer. SDR paths apply `CIToneMapHeadroom` with a highlight-compression fallback.
- Added selectable SDR output colour space to batch export and cleared copied source profile metadata so the rendered output CGImage owns its selected output profile.
- Deliberately reject HDR still export on the current portable ImageIO path because it lacks a cross-version reliable gain-map writer; the app never writes an 8-bit file while claiming it is HDR.
- Added [color-pipeline.md](color-pipeline.md) documenting the ordering, LUT safety contract and HDR/SDR behavior.

Tests:
- `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO test`
- PASS — 38 tests, 0 failures. Includes legacy edit-state compatibility, Technical LUT persistence, colour-contract rejection, HDR preview TIFF path, false-HDR export rejection, and all Phase 0–6 regressions.

Build:
- `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build`
- PASS — `** BUILD SUCCEEDED **`.

Acceptance:
- PASS — code and documentation explicitly model the required source/working/technical/creative/output order.
- PASS — Technical LUT input/output metadata is persistent and strictly validated; `S-Log3 → Rec.709` cannot be treated as an ordinary Creative LUT or applied to an sRGB source.
- PASS — sRGB, Display P3, Rec.709, Rec.2020 and linear/extended working descriptors are represented; preview/export target output colour spaces through ColorSync.
- PASS — HDR preview uses an EDR-capable AppKit layer and half-float payload; SDR output has a dedicated tone-mapping path and existing SDR tests pass.
- PASS — HDR export is unavailable through the current system ImageIO capability and therefore fails explicitly rather than producing a false HDR file.

Regression:
- PASS — full 38-test suite passes: catalog/indexing/library management, editing/LUT/RAW, presets/batch export, duplicate safety, relink and Trash workflows remain covered.

Manual Verification:
- MANUAL VERIFICATION REQUIRED — on a real HDR-capable Mac display, compare SDR and HDR editor previews with a user-authorized HDR still image; verify EDR headroom, window movement between HDR/SDR displays and system tone mapping.
- MANUAL VERIFICATION REQUIRED — use user-authorized sRGB, Display P3, Rec.709, Rec.2020, S-Log3, HLG and PQ media plus correctly declared Technical LUTs to confirm actual ICC/profile detection and intended visual transforms.
- MANUAL VERIFICATION REQUIRED — when a future macOS ImageIO gain-map writer is available, validate it against real HDR reference stills before changing `supportsHDRExport`; current implementation intentionally rejects that export.

Known Limitations:
- The cross-version ImageIO API path available to this project does not provide a reliable HDR gain-map writer, so HDR still export is deliberately disabled rather than mocked. SDR JPEG/HEIF/TIFF export remains real and selectable by output colour space.
- Automatic tests use generated pixels and cannot measure physical display luminance, monitor ICC calibration, user-media ICC quality, or camera Log metadata fidelity.

Commit:
- `feat: complete phase 7 color management hdr`

## Phase 8

Status:
- COMPLETED

Implemented:
- Catalog v9 扩展 `video_metadata`：持久化并读取音轨数量、色彩原色、传递函数、YCbCr 矩阵与可检测 HDR 标记；既有 duration、codec、尺寸、帧率与创建日期保持兼容。
- `MediaMetadataExtractor` 以 AVFoundation 读取视频/音频轨和首个视频 format description；只在 HLG、PQ/ST 2084 或 BT.2100 线索存在时标记 HDR，缺失元数据保持 unknown，绝不猜测。
- 统一资料库 Inspector 与 Grid 视频卡片展示扩展元数据、时长和 HDR 标记；既有 All/Photos/RAW/Videos/Edited 筛选、评分、Flag、Tag、普通/智能 Album 复用同一真实 Catalog 路径。
- 视频海报帧继续由 `AVAssetImageGenerator` 生成并进入现有缩略图缓存；新增五帧、可取消、逐帧容错的 AVFoundation 胶片条与 Application Support 缓存。缓存键包含文件大小和修改时间，重新扫描到源文件变化时不会复用旧帧。
- 新增 `VideoPreviewSheet` 与 `VideoPlaybackSession`，使用系统 `AVPlayer`/`AVKit.VideoPlayer` 提供播放/暂停、精确 seek、按 Catalog 帧率逐帧前后移动、音量/静音、0.5×/1×/1.5×/2×速率和原生窗口全屏。会话只在预览期间持有 security-scoped root access，并拒绝根目录外路径。
- 新增 [video-library.md](video-library.md)，明确元数据/HDR 检测、缓存、播放和 Phase 9 编辑边界。

Tests:
- `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO test`
- PASS — 40 tests, 0 failures。覆盖 v9 migration、扩展视频元数据 Catalog 往返、资料库筛选/评分/Flag/Tag/Album 回归、胶片条采样、派生缓存持久化与源变更 cache-version 隔离，以及所有既有 Phase 0–7 测试。

Build:
- `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build`
- PASS — `** BUILD SUCCEEDED **`。

Acceptance:
- PASS — duration、codec、dimensions、frame rate、audio tracks、color properties 与 HDR indication 均由 AVFoundation 提取模型、SQLite v9 与 Inspector 实际路径保存/展示；持久化往返测试覆盖新增字段。
- PASS — 视频使用 AVAssetImageGenerator 的真实海报缩略图路径；胶片条按时间轴采样、以 JPEG 派生缓存保存，并对源文件变更自动换用新缓存键，不复制原视频。
- PASS — 视频双击/Space 预览会进入原生 AVPlayer 视图；代码提供 play/pause、seek、frame stepping、volume、fullscreen 与 playback rate，未使用 Web video player。
- PASS — 视频仍由统一 LibraryQuery、Catalog 评分/Flag/Tag/Album 机制管理；Phase 9 的 trim、调色、LUT、合成和导出没有被提前伪实现。

Regression:
- PASS — 全量 40 项测试通过；Phase 0–7 的 Catalog、扫描、离线/书签、照片/RAW 编辑、LUT、预设/批量导出、相册/堆栈/重复检测、ColorSync/HDR still 路径均未回归。

Manual Verification:
- MANUAL VERIFICATION REQUIRED — 在用户授权的本地与外置盘真实 MOV/MP4/M4V（H.264、HEVC、含/不含音轨、不同帧率、旋转视频）上检查海报、五帧胶片条、播放/暂停、拖动、逐帧、音量、倍率、全屏和关闭预览后的权限释放。
- MANUAL VERIFICATION REQUIRED — 使用真实 HLG/PQ/BT.2100 视频在实际 macOS 环境确认 AVFoundation 暴露的 color extensions 与 HDR 标记；本阶段的 HDR 仅为检测/显示，非 HDR 视频编辑或输出验证。
- MANUAL VERIFICATION REQUIRED — 在实际 large/offline video library 中确认胶片条生成/磁盘缓存性能、断开外置卷后的缓存读取和受保护目录的 security-scoped bookmark 行为。

Known Limitations:
- HDR indication 依赖容器/轨道 format description 是否包含 AVFoundation 可见的颜色扩展；未带这些扩展的 HDR 文件会显示为 unknown，而不是被错误标为 SDR/HDR。
- 胶片条是五张 JPEG 派生缓存，旧 cache-version 文件由应用缓存目录自然管理；不存储或修改任何原视频。
- 视频 edit state、trim/crop/rotation/speed、LUT/调色、mute/audio gain、composition 和 H.264/HEVC export 均严格留待 Phase 9/10。

Commit:
- `feat: complete phase 8 video library`

## Phase 9

Status:
- COMPLETED

Implemented:
- Catalog v10 `video_edit_states`：以独立、可重开恢复的 `VideoEditState` 保存 trim、crop、90° rotation、flip、曝光/对比度/饱和度/色温/色调、Creative LUT 与强度、静音、audio gain 和速度；只写 SQLite，绝不写回源视频。
- `VideoFramePipeline` 与照片 `PhotoImagePipeline` 分离，使用 `AVMutableComposition`、`AVMutableVideoComposition` 与 Core Image 对视频帧执行颜色调整、Creative LUT、裁剪、旋转、翻转和 resize；复用 LUT 模型/解析器但不复用照片 renderer。
- AVFoundation composition 将视频和全部可用音轨裁剪到同一时间范围，再共同执行 speed time scale；按轨道 `preferredTransform` 计算显示方向画布，避免旋转源视频被 raw natural size 强制回错误几何。
- 增加真实视频编辑器：从视频预览进入，控件对 state 防抖保存并防抖重建 AVPlayerItem 预览；支持 trim、速度、颜色、crop、四分之一转、双翻转、Creative LUT/强度/导入、静音与音频增益。
- `VideoExportService` 创建唯一临时 MP4 后才 move/显式 replace，拒绝源 URL；支持 H.264、HEVC、原始/最长边 resize、quality preset、命名和冲突策略，进度/取消/错误通过统一 Background Task Center 显示。
- 已检测的 HDR 视频保留 Phase 8 原生播放，但禁止进入本阶段 SDR 编辑/导出，避免错误色彩输出；HDR 视频/Technical LUT 留待 Phase 10。
- 新增 [video-editing.md](video-editing.md) 记录非破坏性状态、AVFoundation 管线、导出安全和验证范围。

Tests:
- `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO test`
- PASS — 46 tests, 0 failures。新增覆盖 v10 迁移/持久化、Videos 的 Edited 查询、trim/speed、显示方向尺寸、Core Image 颜色与 Creative LUT intensity、真实临时 H.264/HEVC MP4 导出、裁剪尺寸/编码/时长、源文件字节不变及源 URL 覆盖拒绝；临时视频均在系统临时目录生成和清理。

Build:
- `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build`
- PASS — `** BUILD SUCCEEDED **`。

Acceptance:
- PASS — MOV/MP4 的 AVPlayer playback 来自 Phase 8，Phase 9 编辑预览通过独立 `VideoPipeline` 实际生成 composition，不是照片 renderer 或静态 UI。
- PASS — trim、crop、rotation、flip、exposure/contrast/saturation、temperature/tint、Creative LUT/intensity、mute、audio gain 和 simple speed 均具备持久化 state、编辑器控件和实际 composition/export 路径。
- PASS — H.264 与 HEVC 在当前 macOS 的临时真实视频上均成功导出并反读 codec；H.264 测试同时验证 trim+2× speed 后正确 duration、裁剪后 48×48 尺寸及源视频字节不变。
- PASS — 导出报告进度、可取消任务和错误；输出先写唯一临时文件，默认冲突 rename，任何源 URL 目标都会在写入前被拒绝。
- PASS — 旋转源的显示方向尺寸与用户四分之一转经过纯函数覆盖；实际旋转拍摄素材保留为人工核验。

Regression:
- PASS — 全量 46 项测试覆盖 Phase 0–8 的 Catalog/扫描/书签/离线、Grid/评分/Flag/Tag、照片/RAW/LUT、Preset/批量导出、相册/堆栈/重复检测、色彩管理/HDR still 与视频资料库功能，未发现回归。

Manual Verification:
- MANUAL VERIFICATION REQUIRED — 使用用户授权的本地和外置盘 MOV/MP4/M4V（H.264/HEVC、含/不含音轨、不同帧率、竖拍旋转）逐项确认预览、trim、2×/0.5×速度后的音视频同步、crop/flip、色温/色调、LUT 强度、静音/增益、进度与取消。
- MANUAL VERIFICATION REQUIRED — 在真实 4K 长视频与外置卷上观察 AVFoundation 预览/导出的内存、速度、取消时机、security-scoped 权限和输出目录冲突交互；自动化采用短临时视频。
- MANUAL VERIFICATION REQUIRED — HDR 视频只验证原生播放与“禁止 SDR 编辑/导出”的保护；真正 HDR 视频处理、输出和 Technical LUT 属于 Phase 10，需在 HDR 屏和参考素材上验收。

Known Limitations:
- HDR video、Technical LUT、proxy、timeline 多段/切分/重排、fade/transition 和 audio fade 明确不提前实现，留待 Phase 10。
- AVFoundation export preset 可用性取决于当前 macOS、硬件和源素材；服务对不兼容的 HEVC/H.264 组合返回明确错误，不会生成伪文件。当前 CI 所在 macOS 已自动实测两种编码。
- 自动化无真实用户音轨、竖拍、4K、外置盘或 HDR fixture，不能替代上述真实媒体与权限核验；不提交任何视频、数据库或缓存。

Commit:
- `feat: complete phase 9 video editing and lut`

## Phase 10

Status:
- COMPLETED

Implemented:
- `VideoEditState` v2 以可向后兼容的 JSON 默认值持久化画面淡入/淡出和音频淡入/淡出；现有 Phase 9 状态重开时四项新值均为 0。
- `VideoFramePipeline` 在 trim/speed 后的 composition 输出时间线上向黑场淡入/淡出；`AVAudioMix` 对每条可用音轨使用独立音量坡道。短片上两个音频淡化重叠时使用与画面相同的三角包络，避免 AVFoundation 坡道覆盖产生不确定音量。
- 新增 Catalog v11 `video_proxies`：只记录 asset ID、源文件大小/修改时间签名、受控相对派生路径和尺寸；`CatalogPaths` 创建并隔离 Application Support 的 `video-proxies/` 目录，`.gitignore` 排除该缓存。
- `VideoProxyService` 使用真实 AVFoundation H.264 中等质量、最长边最多 1280px 的 MP4 导出生成本地 Proxy；仅签名匹配且文件仍位于受控目录时预览使用 Proxy，失配/缺失自动回退原视频。删除 Proxy 仅删除派生文件和 Catalog 记录。
- 视频预览提供生成/删除 Proxy、Proxy 使用标记、统一可取消后台任务和进度；视频编辑器与最终导出明确要求 `preferProxy: false`，始终读取引用的原视频。HDR 视频继续拒绝进入 SDR 编辑、导出和 Proxy 路径。
- 新增 [advanced-video.md](advanced-video.md)，并更新 [video-editing.md](video-editing.md) 与 README，记录淡化/Proxy 管线、安全边界和人工验证范围。

Tests:
- `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO test`
- PASS — 48 tests, 0 failures。新增覆盖 v11 migration、Proxy 目录、后台任务种类、fade 包络和真实 Core Image 黑场帧、fade 状态持久化、真实临时 H.264 Proxy 的派生路径/签名失效/删除，以及源视频字节不变。

Build:
- `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build`
- PASS — `** BUILD SUCCEEDED **`。存在既有 AVFoundation 弃用 API 警告，但没有编译错误。

Acceptance:
- PASS — 画面 fade 由真实 Core Image composition 在输出时间线上渲染至黑场；音频 fade 由实际 `AVAudioMix` 轨道坡道实现，trim 与 speed 后仍使用输出时长。
- PASS — Proxy 不是占位播放路径：测试实际写出 H.264 MP4，Catalog v11 持久化后重开可读取，签名失配拒绝复用，删除会移除派生文件和记录，且源文件全程字节不变。
- PASS — Proxy 生成/取消/进度接入统一 Background Task Center；预览显示正在使用 Proxy，编辑与最终导出仍锁定原视频。
- PASS — 已检测 HDR 视频明确保持原生播放并拒绝 SDR Proxy/编辑/导出，不会错误产生 SDR 文件。

Regression:
- PASS — 全量 48 项测试覆盖 Phase 0–9：Catalog/扫描/书签/离线、资料库、照片/RAW/LUT、Preset/批量导出、相册/堆栈/重复检测、色彩/HDR still、视频资料库和视频编辑/导出均未回归。

Manual Verification:
- MANUAL VERIFICATION REQUIRED — 使用用户授权的含音轨 MOV/MP4/M4V，听检淡入、淡出以及短片上两个 fade 重叠时的音量包络；自动化环境没有可提交的真实音频 fixture。
- MANUAL VERIFICATION REQUIRED — 在本地与外置卷的真实 4K/长视频上验证 1280px Proxy 的生成时间、进度、取消、重开复用、源文件修改后的回退、预览流畅度和 security-scoped 权限释放。
- MANUAL VERIFICATION REQUIRED — 使用真实 HLG/PQ/BT.2100 参考视频和 HDR 屏确认 HDR 检测及“拒绝 SDR 编辑/导出/Proxy”的保护。真正 HDR video 处理、输出与 Technical LUT 仍不能声称已验证。

Known Limitations:
- Phase 10 的候选能力中，本阶段选择并完成 fade、audio fade 和 Proxy workflow；multi-segment timeline、split、reorder、simple transition、stabilization metadata/options 未实现，保持后续增量能力而非伪装为完整 NLE。
- HDR video 处理/输出和 video Technical LUT 没有可靠的跨版本色彩契约实现，故继续明确拒绝而非错误降为 SDR；这不是已完成的 HDR video 支持。
- 真实 4K、长片、含音轨、旋转、外置盘和 HDR fixture 不进入仓库，自动化的短 H.264 文件不能替代上述人工验收。

Commit:
- `feat: complete phase 10 advanced video`

## Phase 11

Status:
- COMPLETED

Implemented:
- `PhotoEditState` v3 增加按资产持久化的有序 `localMasks`，支持线性与径向渐变蒙版、启用状态、不透明度、归一化几何以及局部曝光/对比度/饱和度。旧 v1/v2 JSON 缺少该字段时以空数组安全解码，并保留原版本标记以避免破坏既有兼容性约定。
- `PhotoImagePipeline` 使用真实 `CILinearGradient` / `CIRadialGradient` 与 `CIBlendWithMask` 顺序合成局部调整；`PhotoColorPipeline` 在全局 creative adjustments 后、Creative LUT 前调用相同阶段，保证预览和全分辨率导出不走两套效果。
- 照片编辑器增加局部蒙版管理界面：添加/选择/启用/删除线性或径向蒙版，编辑坐标、中心、半径、羽化、不透明度及三项局部调整。几何保持在 crop/rotate 前的归一化原图坐标。
- Local masks 保持每张照片独有，不加入 Preset/Copy-Paste 内容，避免将一张图片的蒙版位置悄悄覆盖到另一张；新增 [local-masks.md](local-masks.md) 说明本地隐私、渲染顺序与能力边界。

Tests:
- `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO test`
- PASS — 50 tests, 0 failures。新增覆盖旧 PhotoEditState JSON 的空蒙版兼容、Catalog 重开后的局部蒙版持久化、线性/径向 Core Image 区域像素差异、含局部蒙版的预览/导出一致性、以及 Preset 不覆盖现有局部蒙版。

Build:
- `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build`
- PASS — `** BUILD SUCCEEDED **`。

Acceptance:
- PASS — 线性/径向蒙版不是 UI 占位：它们在真实 Core Image 管线中对不同区域产生经过测试的像素差异，并按有序数组稳定叠加。
- PASS — 编辑状态、PreviewRenderer 和 ExportRenderer 共用 `PhotoColorPipeline`；测试确认带局部蒙版的预览与导出色调一致，原始文件字节不变。
- PASS — 功能完全本地处理，未引入网络、云端上传或远程模型依赖；Preset/Copy-Paste 不覆盖蒙版几何。

Regression:
- PASS — 全量 50 项测试覆盖 Phase 0–10 的 Catalog/扫描/书签/离线、资料库、照片/RAW/LUT、预设/批量导出、管理/色彩/HDR still、视频资料库、视频编辑、fade 和 Proxy 工作流，未发现回归。

Manual Verification:
- MANUAL VERIFICATION REQUIRED — 在用户授权的 JPEG/HEIC、RAW/DNG 与 24MP/48MP 图像上操作局部蒙版 UI，确认预览刷新、滑杆交互、多个蒙版顺序、旋转/裁剪后的视觉位置和完整导出结果；自动化使用临时小图。
- MANUAL VERIFICATION REQUIRED — 在 HDR 与 SDR 屏幕上检查局部曝光配合 EDR/HDR still preview 的视觉结果；自动化只能验证数值渲染，不能测量实际显示亮度或色彩管理质量。

Known Limitations:
- 本阶段只完成 Linear Gradient 和 Radial Gradient；Brush Mask、Subject Mask、Sky Mask、perceptual similarity、semantic search 和 face grouping 未实现，且没有以 mock 或 hardcode 冒充完成。
- 径向蒙版当前为圆形半径加羽化，而非任意椭圆或可变形选择区；蒙版几何使用 inspector 数值滑杆，尚无画布直接拖拽控制点。
- 真机高分辨率、RAW、HDR 显示与多蒙版性能需上述人工核验；不会提交用户照片、RAW、数据库或缓存。

Commit:
- `feat: complete phase 11 local masks`

## Phase 12.1 — Real Color Space Output

Status:
COMPLETED

Implementation:
COMPLETED

Implemented:
- `PhotoColorSpace` 将 Rec.709 和 Rec.2020 映射到 Apple 正式的 `CGColorSpace.itur_709` 与 `CGColorSpace.itur_2020`；不再回退为 sRGB。
- Color pipeline 输出描述正确记录 SDR Rec.709/Rec.2020 的 transfer function；HDR 仍保持扩展线性预览语义，未虚称 HDR 文件导出。
- `ImageFileExporter` 在将临时文件移动至用户选择目录前，以 ImageIO 重开并逐字节核对嵌入 ICC payload；profile 不匹配时导出失败并清理临时文件。
- 新增 `ColorOutputTests`，对 JPEG、HEIF、TIFF 的 sRGB、Display P3、Rec.709 与 Rec.2020 进行真实输出→ImageIO 重开→ICC profile 验证。
- 新增 `docs/manual-validation.md`，覆盖真实照片、Sony A7C II ARW、DNG、含/不含音频视频、外置存储、权限与 HDR 显示验证清单。

Tests:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO test`；52 tests, 0 failures。

Build:
PASS — `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build`；`BUILD SUCCEEDED`。

Acceptance:
PASS — 四个 SDR 输出空间均有正式 ColorSync profile；Rec.709/Rec.2020 与 sRGB ICC profile 自动化验证为不同；三种当前 ImageIO 输出格式均完成 profile round-trip。

Regression:
PASS — 全量 52 项测试覆盖既有 Catalog、扫描、资料库、照片/RAW/LUT、导出、管理、HDR still、视频资料库、视频编辑、Proxy 与局部蒙版功能。

Manual Verification:
MANUAL VERIFICATION REQUIRED — 在已校准 sRGB/Display P3 显示器、真实广色域照片与用户授权的外置存储上比较预览、导出文件和其他 ColorSync 应用的视觉结果。该人工清单详见 `docs/manual-validation.md`。

Production Readiness:
PARTIAL — SDR 输出 ICC 契约已通过自动测试；完整工作空间转换、真实 RAW 色彩契约、HDR 导出和硬件显示测量尚未完成。

Known Limitations:
- Phase 12.2 前，Source→Working Space 仍由 Core Image/ColorSync 在渲染边界处理，尚未实现明确可测试的单一线性工作空间转换。
- HDR gain-map still export、HDR video edit/export 仍明确不支持。

Commit:
- `fix: correct photo color space output`

## Phase 12.2 — Photo Color Pipeline

Status:
COMPLETED

Implementation:
COMPLETED

Implemented:
- 所有照片预览、普通照片全分辨率导出、RAW 预览与 RAW 导出共用 `RendererContextFactory`，明确将 `CIContext.workingColorSpace` 固定为 Extended Linear sRGB，并使用 RGBAh 半浮点中间格式。
- Core Image 现在有明确且统一的实际数据流：Source profile → Extended Linear sRGB working space → Technical Transform → Creative Adjustments → Local Masks → Creative LUT → Transform/Crop → Output ColorSync profile。
- `ColorPipelinePlan` 保留并测试 Source、Working 与 Output descriptor；Rec.2020 SDR 正确使用 Rec.709 transfer function，而非不真实的 sRGB 标注。

Tests:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO test`；54 tests, 0 failures。新增覆盖实际 render context 的 working ICC profile、RGBAh working format 以及 pipeline descriptor。

Build:
PASS — `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build`；`BUILD SUCCEEDED`。

Acceptance:
PASS — 不再依赖未声明的 Core Image 默认值；预览、照片导出、RAW preview/export 使用同一显式线性工作空间，且既有输出 ICC round-trip 继续通过。

Regression:
PASS — 全量 54 项测试覆盖 Phase 0–12.1 的 Catalog、资料库、照片/RAW/LUT、导出、视频、Proxy 与局部蒙版能力。

Manual Verification:
MANUAL VERIFICATION REQUIRED — 在真实 sRGB、Display P3、Rec.709 和 Rec.2020 媒体上与 ColorSync 参考应用比较创意调整、LUT、local mask 与导出结果；参见 `docs/manual-validation.md`。

Production Readiness:
PARTIAL — 普通照片管线已有明确、自动验证的线性 working space；Technical LUT 编码桥接与真实 RAW 的输出 descriptor 仍待后续子阶段验证。

Known Limitations:
- 当前 Technical LUT 的 source/input/output encoding bridge 仍由下一 Phase 12.3 审核并收紧；未声明为已完整支持 Sony S-Log3 / S-Gamut3.Cine。
- HDR gain-map still export、HDR video edit/export 仍明确不支持。

Commit:
- `fix: establish linear photo working space`

## Phase 12.3 — Technical LUT Correctness

Status:
COMPLETED

Implementation:
COMPLETED

Implemented:
- Technical LUT 不再只校验 metadata：对 ColorSync 可表达的标准 SDR contract，先将原始 profile-attached source 实际转换为 metadata.input，再在无隐式 colour matching 的半浮点 context 中执行 cube，最后将 metadata.output 的 ICC profile 附着到 cube 原始输出并送入共用线性 working pipeline。
- 明确支持 sRGB、Display P3、Rec.709、Rec.2020 及相应 standard transfer descriptor；Rec.2020 SDR 默认归一化为 Rec.709 transfer，避免错误标为 sRGB gamma。
- S-Log3、HLG、PQ 或任意非系统 ColorSync profile 可可靠表达的 Technical LUT contract 会在应用前被拒绝并给出明确错误，不会以 sRGB/Rec.709 近似、也不会在错误编码中套用。
- 新增针对 unsupported transfer rejection 和 bridge 输出实际携带 declared output ICC profile 的自动化测试；更新色彩管线与人工核验文档。

Tests:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`；56 tests, 0 failures。

Build:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`；`BUILD SUCCEEDED`。

Acceptance:
PASS — metadata.input 与 source descriptor 仍严格完全匹配；metadata.output 现在实际参与渲染图的 ICC contract，而不是只记录在 state 中。
PASS — Technical LUT 与 Creative LUT 槽位保持隔离；无可靠系统 bridge 的 Log/HDR transfer 安全拒绝。P0/P1 阻塞问题已修复并复测通过。

Regression:
PASS — 全量 56 项测试覆盖 Phase 0–12.2 的 Catalog、资料库、照片/RAW/LUT、输出 ICC、视频、Proxy 与局部蒙版能力。

Manual Verification:
MANUAL VERIFICATION REQUIRED — 以用户授权且正确声明的 sRGB、Display P3、Rec.709 与 Rec.2020 Technical LUT/reference media 对照 ColorSync-aware 参考应用；并验证 S-Log3、HLG、PQ contract 的拒绝提示。清单见 `docs/manual-validation.md`。

Production Readiness:
PARTIAL — 标准 SDR Technical LUT 已有可执行、可测试的 ColorSync bridge；S-Log3、HLG、PQ 仍有意不支持，直至建立并以真实参考素材验证专用曲线实现。

Known Limitations:
- S-Log3/S-Gamut3.Cine、HLG、PQ Technical LUT 不能套用；应用会安全失败而非错误调色。
- HDR gain-map still export、HDR video edit/export 仍明确不支持。

Commit:
- `fix: enforce technical lut color contracts`

## Phase 12.4 — RAW Color Pipeline

Status:
COMPLETED

Implementation:
COMPLETED

Implemented:
- `RAWImagePipeline` 不再仅返回无来源描述的 `CIRAWFilter.outputImage`。它检查 decoder 返回的 `CIImage.colorSpace`，并仅在 ICC payload 与应用明确支持的 ColorSync profile 完全相符时继续处理。
- 新增 `RAWColorPipeline`：以明确的 Extended Linear sRGB working/output CIContext 与 RGBAh 半浮点格式将 decoder 输出物化为线性工作图，再给它附着同一 ICC profile。RAW preview、全分辨率 render 和导出均将 `.linearWorking` 实际传入 `PhotoColorPipeline`；删除此前 RAW export 的 `sourceColor: .sRGB` 硬编码。
- 未附 profile 或未知 profile 的 CIRAWFilter 输出现在报 `rawColorSpaceUnsupported`，明确拒绝按 sRGB 假设；RAW Technical LUT 因此必须声明 Extended Linear sRGB input，错误 Rec.709/P3/Log contract 会沿用严格拒绝机制。
- 新增 `RAWColorPipelineTests`，覆盖已验证 P3 decoder attachment 到显式 Extended Linear sRGB 的真实 CIContext materialization，以及未知 profile 的安全拒绝。

Tests:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`；58 tests, 0 failures。

Build:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`；`BUILD SUCCEEDED`。

Acceptance:
PASS — RAW source descriptor 不再硬编码为 sRGB；CIRAWFilter decoder attachment 被审计并实际转换为明确、统一的线性 working profile 后才进入普通照片 pipeline。
PASS — RAW preview/export、Creative LUT、Technical LUT 使用同一非破坏性 RAW decode → normalize → PhotoColorPipeline 顺序；未知 profile 安全失败。P0/P1 阻塞问题已修复并复测通过。

Regression:
PASS — 全量 58 项测试覆盖 Phase 0–12.3 的 Catalog、资料库、照片/RAW/LUT、输出 ICC、视频、Proxy 与局部蒙版能力。

Manual Verification:
MANUAL VERIFICATION REQUIRED — 使用用户授权的 Sony A7C II ARW 与 DNG，记录 `CIRAWFilter.outputImage.colorSpace`，逐项验证 decode、WB、exposure、highlight recovery、lens correction、preview、full-resolution export、Creative LUT 与唯一支持的 Extended Linear RAW Technical LUT；同时确认未知/缺失 profile 的拒绝交互。详见 `docs/manual-validation.md`。

Production Readiness:
PARTIAL — 已消除 RAW 的错误 sRGB 标签，并有可测试的显式 ColorSync normalization；不同 macOS、相机与真实 ARW/DNG 的 decoder output profile 仍未在本机以真实素材验证。

Known Limitations:
- 没有将 Sony S-Gamut3.Cine/S-Log3 RAW 或未知 `CIRAWFilter` profile 猜测为 sRGB；它们会明确失败，等待以真实参考素材验证专用色彩契约。
- RAW normalization 会在 decoder 与非破坏性编辑之间物化一张半浮点图；高分辨率 RAW 的内存与性能需按人工清单核验，后续 Phase 12.12 专门处理渲染性能。
- HDR gain-map still export、HDR video edit/export 仍明确不支持。

Commit:
- `fix: implement raw color pipeline`

## Phase 12.5 — Video Geometry / Metadata

Status:
COMPLETED

Implementation:
COMPLETED

Implemented:
- 新增 `VideoGeometry` 作为唯一的显示尺寸计算入口，以视频轨 `naturalSize` 和 `preferredTransform` 计算变换后的正向尺寸，并消除原有与 `VideoFramePipeline` 重复的 helper。
- `MediaMetadataExtractor` 读取并应用 `preferredTransform` 后才写入 Catalog；资料库和 Inspector 通过既有 metadata 路径显示真实竖拍尺寸。
- 编辑 composition 的 render canvas、Proxy 完成后的 metadata 与测试均使用同一个 `VideoGeometry`，避免扫描、播放/编辑、Proxy 与导出各自解释方向。
- 新增真实临时旋转 H.264 MOV fixture：encoded 64×48 且带 90° transform，扫描后的 metadata 正确为 48×64；另覆盖含 translation 的 1920×1080→1080×1920 变换。

Tests:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`；60 tests, 0 failures。专项 `VideoGeometryTests` 2 tests, 0 failures。

Build:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`；`BUILD SUCCEEDED`。

Acceptance:
PASS — Catalog/Inspector 写入经过 transform 的 display dimensions；composition export canvas 与 Proxy metadata 复用同一计算，不再保留并行的 raw-size helper。P0/P1 阻塞问题已修复并完成全量复测。

Regression:
PASS — 全量 60 项测试覆盖 Phase 0–12.4 的 Catalog、资料库、照片/RAW/LUT、导出、视频编辑、fade、Proxy 和局部蒙版能力，未发现回归。

Manual Verification:
MANUAL VERIFICATION REQUIRED — 使用用户授权的 iPhone/Sony 竖拍 MOV/MP4（H.264、HEVC）重新扫描，确认 Catalog、Inspector、Preview、Editor、Proxy 和最终导出均为正确朝向及尺寸；真实素材、设备 metadata 和播放显示不进入仓库。

Production Readiness:
PARTIAL — AVFoundation `preferredTransform` 的自动化 geometry 和 metadata 契约已验证；真实相机文件、非方形像素/变形像素比和外置卷工作流仍需人工核验。

Known Limitations:
- 当前按首个视频轨的 `naturalSize` 和 `preferredTransform` 计算尺寸；多视频轨选择、非方形像素和特殊容器显示矩阵没有在本阶段扩大实现范围。
- HDR video 编辑/导出及真正 HDR video 色彩管线仍明确不支持。

Commit:
- `fix: unify video display geometry`

## Phase 12.6 — Video Preview State

Status:
COMPLETED

Implementation:
COMPLETED

Implemented:
- `VideoPlaybackSession` 在每次编辑 preview 重建 `AVPlayerItem` 前捕获播放头、播放状态、倍率、静音与音量；不再把 `currentTime` 重置为 0。
- 新 item replace 后保留同一个 `AVPlayer`，先以零容差 seek 到旧的输出时间（仅在新的 trim/speed composition 更短时裁剪），再恢复音量/静音与播放倍率/播放状态。
- replacement generation 防止旧的异步 seek completion 在用户又一次滑块调整后覆盖最新 preview；当前 AVFoundation composition 方案不安全地支持原地更新，故选择已实测的 rebuild item + restore state 路径。
- 新增 `VideoPreviewStateTests`，包含真实临时 H.264 item 替换：验证 0.5 秒播放头、1.5×、静音、35% 音量和播放状态均被恢复；不提交任何测试视频。

Tests:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`；62 tests, 0 failures。专项 `VideoPreviewStateTests` 2 tests, 0 failures。

Build:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`；`BUILD SUCCEEDED`。

Acceptance:
PASS — 编辑预览 debounce 后替换 item 会恢复播放时间和所有要求的会话状态，不再跳回开头；连续 replace 的旧 completion 不能覆盖最新状态。P0/P1 阻塞问题已修复并完成复测。

Regression:
PASS — 全量 62 项测试覆盖 Phase 0–12.5 的 Catalog、资料库、照片/RAW/LUT、导出、视频编辑、fade、Proxy、几何 metadata 与局部蒙版能力，未发现回归。

Manual Verification:
MANUAL VERIFICATION REQUIRED — 用用户授权的长视频在约 35 秒处持续调整 exposure、contrast、temperature、LUT strength 和 crop，确认真实 `VideoPlayer` 视觉画面、play/pause、倍率、静音和音量稳定恢复；外置盘、长片和系统 AVFoundation 缓冲行为不进入自动化 fixture。

Production Readiness:
PARTIAL — AVPlayer item replacement state contract 已由真实临时 H.264 自动化验证；真实长片、不同编码、外置卷及用户交互节奏仍需人工核验。

Known Limitations:
- 当前 composition 构建模型不在播放中原地修改 `videoComposition`；它稳定地 replace item 后恢复会话状态，以避免动态 AVFoundation 更新产生未验证的画面/音频行为。
- 新 item 的 end/status/duration/error observer 重绑将在紧接的 Phase 12.7 完成，本阶段没有提前声称已修复。

Commit:
- `fix: stabilize video editor preview`

## Phase 12.7 — PlayerItem Observer

Status:
COMPLETED

Implementation:
COMPLETED

Implemented:
- `VideoPlaybackSession` 新增统一 `observeCurrentItem` / `removeCurrentItemObservers` 生命周期：每次 preview item replace 均撤销旧的结束通知、status、duration、error KVO，再绑定新 item。
- 回调先验证当前 `AVPlayerItem` 身份，避免被替换 item 的延迟 end/status/duration/error 回调篡改当前会话；close 时同样完整解除所有 observer。
- 新 item 可用时更新实际 duration；失败时停止播放并发布 `playbackError`。视频预览和编辑器都显示该错误，不再只留下失真的播放控件状态。
- 新增 `VideoPlaybackSessionTests`，用真实临时 H.264 replacement item 验证 ready 状态、item duration 更新、无错误，以及新 item 的结束通知会将 `isPlaying` 归为 false。

Tests:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`；63 tests, 0 failures。专项 `VideoPlaybackSessionTests` 1 test, 0 failures。

Build:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`；`BUILD SUCCEEDED`。

Acceptance:
PASS — replace 后旧 observer 被撤销、新 observer 被注册；当前 item 到结尾会停止播放，status/duration/error 由同一会话路径管理且错误可见。P0/P1 阻塞问题已修复并完成复测。

Regression:
PASS — 全量 63 项测试覆盖 Phase 0–12.6 的 Catalog、资料库、照片/RAW/LUT、导出、视频编辑、fade、Proxy、几何 metadata、preview state 与局部蒙版能力，未发现回归。

Manual Verification:
MANUAL VERIFICATION REQUIRED — 使用用户授权的长 MOV/MP4 在多次调色/裁剪 preview rebuild 后播放至结尾；同时断开外置卷或移除原文件，确认 Preview/Editor 停止并显示实际 AVFoundation 错误。真实权限、设备和长片缓冲不进入自动化 fixture。

Production Readiness:
PARTIAL — item observer 解绑/重绑、duration 和结束状态已由真实临时 H.264 验证；外置卷断连、损坏/受保护媒体、长片和不同 codec 的 status/error 行为仍需人工核验。

Known Limitations:
- `playbackError` 反映 AVPlayerItem 可见的播放失败；更细的 codec/DRM/网络诊断和恢复策略不在本地 referenced media 的当前范围。
- HDR video 编辑/导出以及 HDR video 色彩管线仍明确不支持。

Commit:
- `fix: rebind video playback item observers`

## Phase 12.8 — Audio Gain

Status:
COMPLETED

Implementation:
COMPLETED — attenuation only; positive gain is intentionally NOT IMPLEMENTED.

Implemented:
- 审核并移除了将 +12 dB 映射到大于 1 `AVAudioMix` volume 的错误实现。`VideoAudioGain` 统一把 audio level 限制为 `-60...0 dB`，线性 volume 永远在 `0...1`。
- 编辑器名称改为“音量 / 衰减”，只显示 `-60...0 dB`，并明确提示正增益需要带 limiter 的独立音频处理管线。
- 旧 `VideoEditState` JSON 的正 gain 在 decode 时归一为 0 dB；渲染管线同样经统一 helper 取值，因此不会因旧 Catalog state 生成超 unity audio mix。
- 新增 `VideoAudioTests`，覆盖 -60/-6/0 dB 转换、+6/+12 dB 安全归一和 legacy JSON 正值迁移；未伪称实际 +dB、limiter、peak 或 normalisation 已实现。

Tests:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`；65 tests, 0 failures。专项 `VideoAudioTests` 2 tests, 0 failures。

Build:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`；`BUILD SUCCEEDED`。

Acceptance:
PASS — UI、持久化解码与 `AVAudioMix` 实现均只输出 0...1 的 attenuation envelope；不会再以 +dB label 或超 unity volume 假装支持正增益。P0/P1 阻塞问题已修复并完成复测。

Regression:
PASS — 全量 65 项测试覆盖 Phase 0–12.7 的 Catalog、资料库、照片/RAW/LUT、导出、视频编辑、fade、Proxy、geometry、preview state、item observer 与局部蒙版能力，未发现回归。

Manual Verification:
MANUAL VERIFICATION REQUIRED — 使用用户授权的含音轨 MOV/MP4 听检 0/-6/-60 dB、mute、trim/speed 后 audio sync 以及淡入淡出；真实音频 fixture、扬声器/耳机响度和外置盘不进入仓库。

Production Readiness:
PARTIAL — attenuation 数学、legacy state 归一和 AVAudioMix 边界已自动验证；含音轨的真实导出/听检仍需人工核验。

Known Limitations:
- Positive gain、limiter、peak metering、normalisation、AVAudioEngine/MTAudioProcessingTap/offline audio render 均为 NOT IMPLEMENTED，不能声称 +6/+12 dB 无削波。
- HDR video 编辑/导出及 HDR video 色彩管线仍明确不支持。

Commit:
- `fix: restrict video audio gain to attenuation`

## Phase 12.9 — Video Export Reliability

Status:
COMPLETED

Implementation:
COMPLETED — export continues to use the existing production AVFoundation composition path; this phase adds an end-to-end audio-bearing fixture rather than a mock.

Implemented:
- 审核 `VideoCompositionBuilder` 与 `VideoExportService`：视频和所有可用音轨先使用同一 trim range 插入 `AVMutableComposition`，再共同 time-scale；`AVMutableVideoComposition` 接收几何、裁剪、翻转、调色、LUT、画面淡入淡出，`AVAudioMix` 接收衰减和音频淡入淡出；`AVAssetExportSession` 写入目标目录的唯一临时 MP4，成功后才移动，且拒绝源 URL 作为目标。
- 新增真实的临时 H.264 MOV + AAC 单声道音轨 fixture（由 `AVAssetWriter` 在测试临时目录生成，不提交媒体文件）。测试输入为带 90° `preferredTransform` 的竖拍视频，应用 trim、2× speed、flip、曝光、音频 -6 dB、画面/音频淡入淡出及最长边 resize。
- 端到端检查导出结果保留 H.264 视频轨和 AAC 音轨，输出总时长和视频轨时长均约为 0.3 秒；音轨起点与视频对齐，且轨道时长的差异不得超过三个实际 AAC access unit。这样既能捕捉真实的时间轴漂移，也不会把 `AVAssetExportSession` 的 encoder priming/padding 元数据量化误判为同步问题；同时检查旋转后 resize 尺寸为 24×32 和源文件字节不变。

Tests:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:MacPhotoStudioTests/VideoExportAudioTests`；1 test, 0 failures。

Build:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`；`BUILD SUCCEEDED`。

Acceptance:
PASS — H.264/HEVC、trim、speed、rotation、crop、flip、LUT、audio、fades 和 resize 均由已有实际导出路径覆盖；新增真实 AAC fixture 证明 trim + speed 后音视频轨都会导出且持续时间同步。P0/P1 阻塞问题已修复并完成复测。

Regression:
PASS — 全量 66 项测试，0 failures，覆盖 Phase 0–12.9 的 Catalog、照片/RAW/LUT、导出、视频编辑、fade、Proxy、几何、preview state、observer、audio attenuation 与实际含音轨导出；未发现回归。

Manual Verification:
MANUAL VERIFICATION REQUIRED — 用用户授权的真实 iPhone/Sony 竖拍 H.264、HEVC 与含音轨素材，在本地/外置卷进行 trim + speed、crop、flip、LUT、resize、音频及双淡入淡出导出；听检 A/V sync、淡入淡出曲线、不同声道布局和真实长片性能。自动化 fixture 不代表实际扬声器/耳机听感或所有编码器硬件路径。

Production Readiness:
PARTIAL — 真实 AAC + H.264 导出已验证轨道存在、编码、竖拍几何、源文件保护及 time-scale A/V 同步；HEVC 含音轨、4K/长片、多声道和外置存储仍需人工验收。

Known Limitations:
- 测试验证的是临时单声道 AAC 轨的存在和时间同步，不测量人耳听感、响度或所有多声道/编码组合。
- HDR video 编辑、导出及 HDR video 色彩管线仍明确不支持；正增益、limiter、peak metering 与 normalisation 仍未实现。

Commit:
- `fix: verify video export audio pipeline`

## Phase 12.10 — HDR Capability Audit

Status:
COMPLETED

Implementation:
COMPLETED — capability declarations and UI labels now distinguish extended-range preview from HDR production support.

Implemented:
- 审核 `HDRPhotoCapabilities`、`ExtendedRangeImageView`、ImageIO still export、HDR video metadata、编辑/导出/Proxy 服务和相关 UI。原有 HDR still gain-map export、HDR video editing/export/Proxy 均保持 `Unsupported`；检测到 HDR 的视频仍只可走原生播放。
- 移除了把扩展范围预览写死为可用的声明。`EDRImageView` 现在读取其实际 window screen 的 `maximumPotentialExtendedDynamicRangeColorComponentValue`，只有 headroom 大于 1 且用户请求扩展范围时才设置 `wantsExtendedDynamicRangeContent`；窗口移动或 backing display 变化时重新评估。
- `.hdr` 持久化值保持兼容，但 UI 改为“扩展范围预览（非 HDR 导出）”。照片/RAW/批量导出文本明确 HDR gain-map 不受支持，避免把 Display P3、Rec.2020、PQ、HLG 或 HDR 标签误读为完成了 HDR 文件工作流。
- 新增集中 `HDRVideoCapabilities`，并将编辑、导出和 Proxy 的服务/UI guard 绑定到明确为 false 的能力；修正旧错误信息中“将在 Phase 10 提供”的过期承诺。
- 更新色彩管线和人工验证文档，明确实际 EDR headroom、HDR 显示器与真实 HLG/PQ 素材只能人工确认。

Tests:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:MacPhotoStudioTests/ColorManagementTests`；9 tests, 0 failures。新增能力审计测试覆盖 SDR/EDR headroom 边界、still gain-map export 与 HDR video capability 均为 Unsupported，以及 UI 标签语义。

Build:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`；`BUILD SUCCEEDED`。

Acceptance:
PASS — 应用不再以固定 true 声称任何显示器均可 EDR；HDR gain-map still export、HDR video editing/export/Proxy 与 video Technical LUT 没有完整实现时均保持明确 Unsupported。P0/P1 阻塞问题已修复并完成全量复测。

Regression:
PASS — 全量 67 项测试，0 failures，覆盖 Phase 0–12.10 的 Catalog、照片/RAW/LUT、SDR 导出、视频编辑/Proxy、实际含音轨导出、EDR headroom 能力策略和 HDR Unsupported guard；未发现回归。

Manual Verification:
MANUAL VERIFICATION REQUIRED — 在真实 HDR 和 SDR 显示器之间移动编辑窗口，检查 EDR headroom、系统 tone mapping 与视觉亮度；以用户授权的 HLG/PQ/BT.2100 still/video 验证 metadata、原生播放及所有 Unsupported guard。此仓库不包含 HDR display、真实 HDR 媒体或 gain-map fixture。

Production Readiness:
PARTIAL — SDR ColorSync 导出和显示器感知的扩展范围预览请求具备明确边界；HDR still gain map、HDR video pipeline、HDR mastering/metadata write 与硬件视觉校准未实现。

Known Limitations:
- EDR headroom 依赖当前窗口所在显示器和 macOS；自动化只验证阈值策略，不能测量实际峰值亮度、色彩或能耗。
- HLG/PQ/Rec.2020 标记不会打开 HDR 编辑、导出、Proxy 或 video Technical LUT；这些功能均为 NOT IMPLEMENTED。

Commit:
- `fix: audit hdr capability boundaries`

## Phase 12.11 — ApplicationModel Refactor

Status:
COMPLETED

Implemented:
- 新增 `VideoEditingCoordinator`，集中构造并调用真实 `VideoEditingService`、`VideoProxyService` 与 `LUTRepository`。播放源解析、安全域内路径校验、编辑状态读写、预览 payload、LUT 查询、导出及 Proxy 生成/删除均经该协调器；`ApplicationModel` 不再直接持有这些视频服务。
- 新增 `TaskCoordinator`，集中管理 `BackgroundTaskCenter` 状态迁移和实际 worker 的注册、释放、取消。视频导出/Proxy、重复项扫描和照片批处理均通过其任务生命周期接口执行。
- `ApplicationModel` 保留 SwiftUI 可观察状态、错误呈现、结果报告和跨域编排，避免一次性重写 UI 调用面。
- 新增架构文档，明确本阶段仅完成 Video/Task 的安全纵向迁移；图库扫描、照片编辑/预设、照片导出/批处理尚未拆成独立 coordinator，未被误报为已完成。
- 新增 `CoordinatorTests`，使用真实 Catalog 和背景任务状态机验证任务生命周期与视频编辑状态持久化，而非 mock 协调器。

Tests:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:MacPhotoStudioTests/CoordinatorTests`；2 tests, 0 failures。

Build:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`；`BUILD SUCCEEDED`。

Acceptance:
PASS — 视频操作均经 `VideoEditingCoordinator` 进入实际服务，后台任务状态和取消 handle 均经 `TaskCoordinator` 管理；`ApplicationModel` 只保留 UI 可观察状态、错误呈现和跨域编排。旧的直接视频服务/任务中心/安全媒体路径引用已检索为零。未发现 P0/P1 阻塞问题。

Regression:
PASS — 全量 69 项测试，0 failures，覆盖 Phase 0–12.11 的 Catalog、资料库、照片/RAW/LUT、SDR 导出、视频编辑/Proxy、音视频导出、播放会话、HDR Unsupported guard 和新增协调器边界；未发现回归。

Manual Verification:
MANUAL VERIFICATION REQUIRED — 在用户授权的本地与外置卷视频上验证：反复生成/移除 Proxy、编辑预览、导出、取消后台任务后，UI 任务状态、错误提示和原文件保护与重构前一致。真实权限、外置卷与长片无法纳入仓库自动化 fixture。

Known Limitations:
- `LibraryCoordinator`、`PhotoEditingCoordinator`、`ExportCoordinator` 仍未实现；本阶段是符合计划“逐步拆分”的 Video/Task 首个垂直切片，而非把整个 `ApplicationModel` 伪装成已完全拆分。
- 协调器不改变既有 HDR video Unsupported 边界、正增益 Unsupported 边界或外置媒体人工验证要求。

Commit:
- `refactor: split video and task coordinators`

## Phase 12.12 — Photo Pipeline Performance

Status:
COMPLETED

Implemented:
- 审核 `ColorAdjustmentCube` 和 `ToneCurveCube`：每个 33³ RGBA Float cube 有 35,937 个条目、574,992 bytes；原实现每次有效渲染均先分配 `[Float]` 再复制为 `Data`。预览已有单一 Metal `CIContext`、90ms debounce、任务取消和 generation guard，因此没有为“性能”提前改写为 Metal shader。
- 为两类 cube 分别增加线程安全的 8-entry LRU `Data` cache，key 只包含会影响该 cube 的白/黑/HSL 或曲线坐标。曝光、色温等无关参数不再重建已有 cube；缓存 payload 是不可变 `Data`，可安全由 preview/export 使用。
- cube 直接写入一次 `Data` 分配，消除临时 `[Float]` 和随后的复制。Tone Curve 利用通道可分离性，预计算 33 个 master/R/G/B 值后填充同一 3D LUT 布局，保持原像素计算结果。
- `CIColorCube` filter 继续每个图像图创建，避免把带可变 input image 的 Core Image filter 跨 preview/export actor 复用而造成竞态；大型 immutable cube data 与现有 `CIContext` 已复用。
- 新增性能说明和确定性缓存诊断测试；该测试验证分配与缓存行为，不将不同 Mac 的 GPU/编解码/显示器条件误报成固定帧率提升。

Tests:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:MacPhotoStudioTests/PhotoPipelinePerformanceTests -only-testing:MacPhotoStudioTests/PhotoEditingTests`；16 tests, 0 failures。新增 2 项验证相关参数 cache key、574,992-byte payload、8-entry 上限和曲线重建路径；已有 HSL/curve 像素测试通过。

Build:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`；`BUILD SUCCEEDED`。

Acceptance:
PASS — 33³ cube 不再在相同相关参数的预览/导出上重复分配或复制；无关 slider 不会使它们失效，曲线生成 CPU 工作已按通道离散预计算。现有 debounce/cancellation/generation guard 和 reused CIContext 保持工作，未发现 P0/P1 阻塞问题。

Regression:
PASS — 全量 71 项测试，0 failures，覆盖 Phase 0–12.12 的 Catalog、资料库、照片/RAW/LUT、色彩管线、HSL/曲线像素输出、导出、视频、HDR guard 和 coordinator 边界；未发现回归。

Manual Verification:
MANUAL VERIFICATION REQUIRED — 使用用户授权的高分辨率 JPEG/HEIC/RAW，连续拖动白/黑/HSL/曲线以及无关的曝光/色温 slider，观察不同 Apple Silicon/Intel Mac、内外接显示器上的交互延迟、内存与视觉一致性。自动化不声称固定毫秒数或跨硬件帧率。

Known Limitations:
- 每个新参数组合仍需要生成一次 33³ cube；8-entry 上限避免无限制内存增长，但无法替代针对任意滑块轨迹的真实硬件 profiling。
- Creative/Technical 导入 LUT 的独立 `cubeData` 物化路径不在本阶段 `ColorAdjustmentCube`/`ToneCurveCube` 的明确范围；未将其伪称为已优化。
- 不引入 custom Metal kernel；现有 Core Image pipeline 的色彩正确性边界保持不变。

Commit:
- `perf: cache photo adjustment cubes`

## Phase 12.13 — Local Mask Canvas UX

Status:
COMPLETED

Implemented:
- 新增照片编辑画布上的真实局部蒙版直接操作：线性蒙版可拖动起点、终点和中线，以调整旋转与位置；径向蒙版可拖动中心、半径和羽化环。拖动直接更新既有、非破坏性的 `PhotoEditState.localMasks` 持久化状态，而不是只移动 UI 占位控件。
- 画布按预览图的 aspect-fit 可见区域计算命中、归一化坐标、半径与羽化，并在 SwiftUI 顶部原点和渲染器底部原点之间转换；线性移动在边界处保留起终点向量。
- 新增“显示蒙版覆盖”开关，在可编辑预览上绘制红色线性/径向提示层。该提示层仅供交互确认，不进入 Core Image 渲染、持久化或导出像素；原有检查器滑块保留作精确数值控制。
- 补充局部蒙版文档和画布几何单元测试，覆盖 aspect-fit 映射、归一化往返、线性整体移动、线段命中距离与径向距离。

Tests:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:MacPhotoStudioTests/LocalMaskCanvasGeometryTests -only-testing:MacPhotoStudioTests/PhotoEditingTests`；17 tests, 0 failures。新增画布几何测试与既有局部蒙版像素/持久化测试均通过。

Build:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`；`BUILD SUCCEEDED`。

Acceptance:
PASS — 线性与径向局部蒙版均可在画布直接操作，修改复用既有可持久化的蒙版数据和真实 Core Image 渲染路径；红色 overlay 明确不改变导出。未发现 P0/P1 阻塞问题。

Regression:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`；全量 74 tests, 0 failures，覆盖 Phase 0–12.13 的 Catalog、资料库、照片/RAW/LUT、局部蒙版、导出、视频、HDR guard、协调器和性能缓存边界；未发现回归。

Manual Verification:
MANUAL VERIFICATION REQUIRED — 使用用户授权的 JPEG/HEIC/RAW，在横图、竖图、正方形图、窗口缩放及并排/原图对照模式中实际拖动所有控制点，核对命中区域、overlay 与最终效果的一致性，并导出确认 overlay 不写入文件。真实媒体、macOS 鼠标事件、显示缩放与权限不能由仓库 fixture 完整模拟。

Known Limitations:
- 本阶段只为已有线性/径向蒙版添加画布 UX；Brush Mask、Subject/Sky Mask 未实现，也没有被标记为完成。
- 画布交互没有以真实 UI 自动化或外部照片视觉截图作为通过依据；该部分保留人工验证。
- RAW 编辑界面当前没有局部蒙版选择器，因此不宣称该界面已暴露相同画布工作流。

Commit:
- `feat: add local mask canvas controls`

## Phase 13 — Brush Mask

Status:
COMPLETED

Implemented:
- `PhotoEditState` 升级为 v4，`LocalMaskKind` 新增真实 `.brush`。每个 brush mask 非破坏性保存 `BrushStroke`：归一化点、半径、hardness、每笔 flow/opacity 与 erase 标记；画笔当前的 size、feather 与 flow 仅作为新笔触配置。没有向 SQLite 写入完整位图、PNG 或派生纹理。
- `BrushMaskRenderer` 在 Preview/Export 当前图像 extent 上以 Core Graphics 栅格化笔触为灰度 mask，再交给既有 `CIBlendWithMask` 与局部 exposure/contrast/saturation 路径。画笔、低流量、羽化和擦除均影响实际像素，且与线性/径向蒙版保持确定性的数组顺序。
- 新增线程安全、内存专用的 LRU 派生纹理缓存：总上限 48 MiB、单项上限 16 MiB；大图导出仍会栅格化当前 render，但不保留该纹理。cache key 含尺寸与所有笔触数据，修改笔触不会误用旧 mask。
- 普通照片编辑器可添加画笔蒙版，直接在 aspect-fit 预览上绘制或擦除，并提供大小、羽化、流量、显示 overlay、撤销最后笔触和清空笔触。新 stroke 复用 Phase 12.13 的归一化坐标转换及状态 debounce/save/render；原始媒体仍只读。
- 新增文档与自动化测试，覆盖 v3 旧渐变解码、v4 vector state 编码、无 bitmap 字段、画笔位置、flow 和 erase 的真实 Core Image 像素输出；同时扩展真实照片/高像素人工验收清单。

Tests:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:MacPhotoStudioTests/PhotoEditingTests -only-testing:MacPhotoStudioTests/LocalMaskCanvasGeometryTests`；20 tests, 0 failures。覆盖新增画笔的持久化兼容、无 bitmap 存储、paint/flow/erase 像素路径及既有画布几何。

Build:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`；`BUILD SUCCEEDED`。

Acceptance:
PASS — Brush Mask 不是 UI 占位：拖动画布创建持久化 vector stroke，渲染时生成实际蒙版并进入与导出相同的 Core Image 合成；paint、erase、size、feather、flow/opacity 均有真实数据与像素路径。未发现 P0/P1 阻塞问题。

Regression:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`；全量 77 tests, 0 failures，覆盖 Phase 0–13 的 Catalog、照片/RAW/LUT、全部局部蒙版、导出、视频、HDR guard、协调器和性能缓存边界；未发现回归。

Manual Verification:
MANUAL VERIFICATION REQUIRED — 按 `docs/manual-validation.md` 使用用户授权的 JPEG/HEIC、RAW 派生照片及 24MP/48MP 图像，验证长笔触、重叠软/硬笔触、擦除、撤销、窗口缩放、横竖构图、裁剪/旋转、重开资产、预览与新文件导出的一致性；同时观察高像素笔触时的内存、交互延迟与原图字节不变。自动化 fixture 不代表真实鼠标/手写板、外置存储、权限或大图性能。

Known Limitations:
- 当前画笔读取标准拖动坐标，不读取 Apple Pencil/手写板 pressure、tilt 或速度；已保存笔触只支持撤销最后一笔或清空，尚无单笔重编辑。
- 普通照片编辑器暴露画笔 UI；RAW 编辑器当前没有局部蒙版选择器，因此不宣称已提供同一交互入口。RAW 解码后的照片渲染路径仍可读取持久化的 `PhotoEditState`。
- Subject/Sky Mask 和相似照片检测仍是后续 Phase，未以 UI、mock 或 hardcode 冒充完成。

Commit:
- `feat: add non-destructive brush masks`

## Phase 14 — Subject / Sky Mask

Status:
COMPLETED — foreground subject mask implemented; Sky Mask explicitly unsupported after SDK feasibility audit.

Implemented:
- `LocalMaskKind` 新增 `.subject`，普通照片编辑器提供“添加主体”入口。本机 Vision 前景实例请求在预览和新文件导出共享的 `PhotoImagePipeline` 路径中产生真实灰度蒙版，再由 `CIBlendWithMask` 应用局部曝光、对比度和饱和度；这不是 UI 占位或全图效果。
- `VisionSubjectMaskRenderer` 使用 macOS 14+ 的 `VNGenerateForegroundInstanceMaskRequest`，将所有检测到的显著前景实例缩放并对齐到当前 `CIImage` extent。请求为空或异常时失败关闭，不产生白色替代蒙版，也不对整张图错误应用调整。
- `.subject` 只持久化本阶段的开关、不透明度与局部调整；不保存 Vision 位图、PNG、派生纹理或用户原图。Vision 只在应用进程本地执行，预览/导出时重新计算。
- 新增 `docs/subject-sky-mask-feasibility.md`。已确认目标 SDK 没有经验证的通用本地 Sky segmentation request，因此没有新增 Sky UI、enum、颜色阈值 heuristic 或伪实现。更新局部蒙版和真实媒体人工验收文档。

Tests:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:MacPhotoStudioTests/SmartMaskTests -only-testing:MacPhotoStudioTests/PhotoEditingTests -only-testing:MacPhotoStudioTests/LocalMaskCanvasGeometryTests`；24 tests, 0 failures。覆盖 macOS 15 Vision 能力、无效 source 的失败关闭、蒙版 extent 对齐分支、Catalog 状态 round-trip 和无 Vision bitmap 持久化。

Build:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`；`BUILD SUCCEEDED`。

Acceptance:
PASS — 真实 local-only Vision foreground subject 请求已接入像素渲染；不存在 cloud、mock、hardcode 语义类别或全图回退。Sky Mask 未标为实现，符合 SDK 审核结论和“安全拒绝优于错误调色”原则。

Regression:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`；全量 81 tests, 0 failures。覆盖既有 Catalog、资料库、照片/RAW/LUT、局部蒙版、导出、视频、HDR guard、协调器和性能缓存边界，未发现回归。

Manual Verification:
MANUAL VERIFICATION REQUIRED — 使用用户授权的人像、宠物和常见物体照片，在简单/复杂背景、发丝/毛发、透明或反光物体、多主体、无主体，以及 24 MP / 48 MP 图像上核验选择边缘、无结果失败关闭、预览/新文件导出一致性、性能和原图字节不变；详见 `docs/manual-validation.md`。Sky 功能无需人工验收为“正确”，因本阶段明确不提供。

Known Limitations:
- “主体”仅表示 Vision 显著前景实例，可包含人、动物或物体；没有语义类别选择、单实例 picker、手动 refine 或独立 mask overlay。
- 每次预览/导出重新运行 Vision，未引入持久化/磁盘缓存；复杂和高像素真实照片的延迟需人工检查。
- macOS 目标 SDK 没有经验证的本地通用 Sky Mask API；未捆绑另一个本地 Core ML 模型，因此 Sky Mask 是 NOT IMPLEMENTED，而非部分支持。

Commit:
- `feat: add vision foreground subject masks`

## Phase 15 — Similar Photo Detection

Status:
COMPLETED

Implemented:
- 新增独立的 `asset_perceptual_hashes` Catalog migration（v12）。它只保存本地 `dhash-64-v1`、算法版本和 source file size / modification time；与既有精确重复 SHA-256 表分离，源文件变化时缓存自动失效。
- `SimilarPhotoScanner` 通过 security-scoped access 以 ImageIO 解码可用照片的最多 96 px 缩略图，并在本地 9×8 亮度图上计算真实 64-bit dHash。它可识别缩放、重新导出/轻度 JPEG 压缩和均匀小幅曝光/颜色变化的候选；ImageIO 或栅格化失败会列入 failures，绝不写入全零或其他伪哈希。
- 使用 Hamming distance ≤ 8/64 建立 Similar Group，并以 `(64 - distance) / 64` 展示 0–100 的像素结构相近分数。BK-tree 避免全库 all-pairs 比较；相同哈希仅使用代表连接边，防止大量 burst/重复项造成二次方内存和结果膨胀。
- 资料库工具栏新增“查找相似照片”，由可取消的后台任务驱动；结果页展示相似组、文件对、相似度与 Hamming distance，并明确它只是复核线索。没有相似结果删除、移动、评分、云上传或语义搜索入口。
- 新增 `docs/similar-photo-detection.md` 和真实媒体人工验证项，说明算法、缓存、分组、隐私与非语义边界。

Tests:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:MacPhotoStudioTests/SimilarPhotoDetectionTests -only-testing:MacPhotoStudioTests/AdvancedPhotoManagementTests -only-testing:MacPhotoStudioTests/CatalogStoreTests -only-testing:MacPhotoStudioTests/PhotoEditingTests -only-testing:MacPhotoStudioTests/VideoEditingTests`；34 tests, 0 failures。新增真实 ImageIO 临时 JPEG fixture，覆盖 resize、重新压缩、小幅调色、不同结构排除、Catalog cache reuse、分组/分数和源文件字节不变。

Build:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`；`BUILD SUCCEEDED`。

Acceptance:
PASS — Phase 15 不是 mock：用户动作触发本地解码和真实 dHash，持久化为可失效的紧凑 Catalog metadata，以 Hamming distance 形成 Similar Group 并显示 Similarity Score。默认仅分析/显示，未提供自动或隐式删除；现有移到废纸篓操作仍需独立明确确认。未发现 P0/P1 阻塞问题。

Regression:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`；全量 83 tests, 0 failures。覆盖 Phase 0–15 的 Catalog、资料库、照片/RAW/LUT、局部蒙版、导出、视频、HDR guard、协调器、性能缓存与相似检测，未发现回归。

Manual Verification:
MANUAL VERIFICATION REQUIRED — 在用户授权的 JPEG、HEIC、PNG、TIFF、RAW-derived JPEG 和外置存储上，以真实缩放副本、重新导出的 JPEG、小幅调色、不同图像及 10k+/50k+/100k Catalog 运行首轮/缓存扫描，人工检查 false positive/false negative、取消、响应性、内存、断开重连、失效重算和源文件字节不变；详见 `docs/manual-validation.md`。

Known Limitations:
- dHash 是低分辨率亮度结构比较，不是 Vision feature print、语义搜索、脸部识别或身份结论。大裁剪、旋转、重度修图、非均匀局部编辑可能漏检；重复几何/图形可能误报，用户必须在操作文件前自行检查。
- 当前阈值固定为 Hamming ≤ 8；相似组按连接关系形成，结果页列出构成连接的代表性比较边，而非所有成员两两比较。
- 首次扫描必须读取每张可用照片；真实大型资料库的耗时和内存未在仓库小型 fixture 上测量，保留人工验证。没有引入云端处理或自动删除。

Commit:
- `feat: add local similar photo detection`

## Phase 16.1 — Local Mask Transform Coordinate Correctness

Status:
COMPLETED

Implemented:
- 新增 `PhotoTransformGeometry`，把裁剪、水平/垂直翻转、90°倍数旋转和拉直的 Core Image 仿射变换与正反向归一化坐标映射收敛到一个共享实现。
- `PhotoImagePipeline` 与 `LocalMaskCanvas` 共用该几何契约。画布先将既有 source-space 蒙版映射至变换后的可见预览，再在绘制、拖动和命中时将指针反变换回 source-space；线性、径向和画笔路径均不再直接把变换后预览坐标写入持久化状态。
- 补充局部蒙版文档与真实媒体检查项；状态仍只保存原图归一化几何，不写入原媒体或派生蒙版文件。

Tests:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:MacPhotoStudioTests/PhotoTransformGeometryTests -only-testing:MacPhotoStudioTests/LocalMaskCanvasGeometryTests -only-testing:MacPhotoStudioTests/PhotoEditingTests`；24 tests, 0 failures。新增 3 项几何/像素回归，覆盖 crop、90°/180°/270°、straighten、双翻转及组合变换的 source→display→source 往返，并验证可见画笔落点反映到局部蒙版实际渲染像素。

Build:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`；`BUILD SUCCEEDED`。

Acceptance:
PASS — 渲染器和交互画布使用同一变换数学；局部蒙版不再因裁剪、旋转、拉直或翻转而写入错误的原图坐标。未发现 P0/P1 阻塞问题。

Regression:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`；全量 86 tests, 0 failures，覆盖 Phase 0–15 与本阶段新增回归。

Manual Verification:
MANUAL VERIFICATION REQUIRED — 使用用户授权的横图、竖图和正方形 JPEG/HEIC/RAW 派生图，在裁剪、90°/180°/270°、straighten 与双翻转组合后拖动线性/径向手柄并绘制画笔，重开资产和导出新文件后核对效果仍落在可见目标上；详见 `docs/manual-validation.md`。

Known Limitations:
- 自动化可以验证共享仿射数学和合成像素，但不能替代真实高分辨率媒体、鼠标命中、显示缩放和人工视觉判断。
- 本阶段不改变 RAW 编辑器没有局部蒙版选择器的既有产品边界。

Commit:
- `fc7f312 fix: align local masks with photo transforms`

## Phase 16.2 — Technical LUT Strength Correctness

Status:
COMPLETED

Implemented:
- 修复 `TechnicalLUTProcessor` 的部分强度路径：先把源图物化到声明的 Technical LUT 输入编码，完整 LUT 分支以非托管半精度运行；未处理分支独立 ColorSync 转换至同一声明输出编码后，才进行数值混合，并统一附加该输出 ICC。
- `strength = 0` 不再错误返回保留原输入 profile 的 source；它返回正确转换的未处理输出分支且跳过 cube。`strength = 1` 直接使用完整 LUT 输出，避免无意义的未处理分支转换。
- 保持 S-Log3、HLG、PQ 的安全拒绝边界；未扩展未验证 transfer-function 支持。更新色彩管线文档和真实媒体检查项。

Tests:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:MacPhotoStudioTests/ColorManagementTests -only-testing:MacPhotoStudioTests/PhotoEditingTests`；28 tests, 0 failures。新增非恒等 Display P3 → Rec.709 Technical LUT 断言，独立构造 0%、50%、100% 的正确输出编码参考分支，并核对像素与输出 ICC。

Build:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`；`BUILD SUCCEEDED`。

Acceptance:
PASS — Technical LUT 部分强度不会再混合不同 primaries/transfer 的数值；0% 是正确转换的未处理输出，100% 是完整 LUT，50% 是同输出编码分支混合。未发现 P0/P1 阻塞问题。

Regression:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`；全量 87 tests, 0 failures，覆盖 Phase 0–16.2。

Manual Verification:
MANUAL VERIFICATION REQUIRED — 使用用户授权且有明确 input != output 色彩契约的 LUT（例如 Display P3 → Rec.709）和真实照片，在 0%/50%/100% 比较预览、新文件导出与 ColorSync-aware 参考应用，核对视觉连续性、嵌入 profile 和原图字节不变；详见 `docs/manual-validation.md`。

Known Limitations:
- 部分强度的颜色数学已经由自动化确认，但真实 LUT 的创作意图、显示器表现和第三方参考应用仍需人工判断。
- S-Log3、HLG、PQ 仍被明确拒绝，直到存在经过验证的 transfer-function bridge；本阶段没有以近似实现扩大支持面。

Commit:
- `af42de0 fix: preserve color space in technical LUT blends`

## Phase 16.3 — Subject Mask Stable Source + Cache

Status:
COMPLETED

Implemented:
- 新增可注入的 `SubjectMaskProvider`。它以源文件规范路径、文件大小、修改时间、preview/export rendition、输入 extent 和 Vision request revision 组成键，并以线程安全 LRU 仅保存可丢弃的内存蒙版或失败结果；Preview 最多保留 8 个，full-resolution Export 最多保留 1 个。
- 主体分割的稳定基准明确为“已解码且应用方向后的源图”，在 global creative adjustment、任何 local mask 与 LUT 之前取得。局部蒙版仍按数组顺序合成，但前置蒙版、曝光、对比度、饱和度、色温、HSL 和曲线都不会改变 Vision 输入。
- 同一 render 的多个 Subject Mask 与相同预览源的后续无关 slider render 复用同一 Vision 结果；源签名或输入几何变化会失效。无主体/失败结果缓存为 fail-closed，不会退化为全图调整。
- 缓存只保存派生 `CIImage` 于进程内存；没有向 Catalog SQLite、源媒体目录或持久化缓存写入任何 Subject bitmap。补充局部蒙版和真实媒体人工验证说明。

Tests:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:MacPhotoStudioTests/SubjectMaskProviderTests -only-testing:MacPhotoStudioTests/SmartMaskTests -only-testing:MacPhotoStudioTests/PhotoEditingTests`；26 tests, 0 failures。覆盖三主体蒙版单次生成、局部蒙版顺序稳定、全局 slider 的实际 `PreviewRenderer` 缓存复用和稳定输入、源签名/几何失效、失败关闭以及真实 Vision capability boundary。

Build:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`；`BUILD SUCCEEDED`。

Acceptance:
PASS — Subject Mask 不会再读取逐步经局部或全局调色后的图像；每个 render 的三枚 Subject Mask 只触发一次生成，预览无关 slider 复用有界派生缓存，export 以其自身 full-resolution key 生成/复用。没有 SQLite、磁盘或媒体写入，失败仍关闭。未发现 P0/P1 阻塞问题。

Regression:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`；全量 92 tests, 0 failures，覆盖 Phase 0–16.3 的 Catalog、资料库、照片/RAW/LUT、局部蒙版、导出、视频、HDR guard、协调器与相似照片检测。

Manual Verification:
MANUAL VERIFICATION REQUIRED — 使用用户授权的人像、宠物和常见物体照片，在简单/复杂背景、发丝/毛发、多主体、无主体以及 24 MP / 48 MP 图上添加多个 Subject Mask；实际拖动 global slider、重排局部蒙版、改变预览尺寸、替换/更新源文件，并与 full-resolution 新文件导出比较质量、延迟、内存和原图字节不变。详见 `docs/manual-validation.md`。

Known Limitations:
- Vision foreground selection 仍是显著前景实例，并非语义类别、单实例 picker、手动 refine 或 Sky Mask；真实选择边界由 Apple Vision 和用户照片决定。
- 缓存是有界的进程内存缓存，应用重启后会重新生成；它刻意不以大位图持久化换取性能。高像素真实图像的实际延迟与内存需要人工验证。
- 无可靠 source URL 的内部调用仅共享当前 render 的 transient key；正常文件预览/导出路径使用可失效的文件签名键。

Commit:
- `fix: stabilize subject mask rendering`

## Phase 16.4 — RAW Real-Media Validation Infrastructure

Status:
COMPLETED

Implemented:
- 新增 **File → 运行 RAW 诊断…**。用户选择 ARW/DNG 后可显式选择 sRGB 或 Display P3 作为临时导出目标；`RAWMediaDiagnosticService` 只读源文件、检查 `CIRAWFilter` 和真实 decoder `CIImage`，以可复用 `RAWMediaDiagnosticReport` 记录文件扩展名/大小、解码尺寸、decoder 色彩空间名、ICC payload 严格匹配结果、已识别 `PhotoColorDescriptor`、实际成功预览后的 linear working descriptor、同一能力检查得到的 RAW 控制、预览/导出结果及重新打开临时导出的 ICC。
- 临时 JPEG 导出仅用于实际锻炼 full-resolution RAW export 与 ImageIO ICC 重读，始终位于唯一临时目录并在完成后删除；可选报告仅为 Application Support `logs/` 下的小型 UTF-8 文本，不写入 Catalog、不含位图、不写 sidecar，也不会覆盖/修改 RAW 源文件。
- `RAWCapabilities.availableControlNames` 与 `RAWImagePipeline` 共享一套 `CIRAWFilter` capability probe，避免诊断报告宣称 editor/pipeline 不支持的控制。未知、缺失或不匹配的 decoder ICC 只会被记录并使严格管线失败关闭，绝不假定为 sRGB。
- 新增 `docs/raw-diagnostics.md`，并扩展 Sony A7C II ARW/DNG 的手工流程，覆盖方向、WB、曝光、高光恢复、镜头校正、降噪、锐化/细节、LUT、局部蒙版（适用时）及 sRGB/Display P3 full-resolution 新文件导出。

Tests:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:MacPhotoStudioTests/RAWMediaDiagnosticTests -only-testing:MacPhotoStudioTests/RAWColorPipelineTests -only-testing:MacPhotoStudioTests/PhotoEditingTests`；22 tests, 0 failures。新增测试覆盖非 RAW 失败关闭、报告全部关键字段、日志文本写入、源字节不变和 RAW capability 列表；既有测试覆盖 explicit linear working normalization 与未知 ICC 的无 sRGB fallback 拒绝。

Build:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`；`BUILD SUCCEEDED`。

Acceptance:
PASS — 用户可直接选择真实 ARW/DNG、再选择 sRGB 或 Display P3，产生可保存的诊断报告；报告来自实际 CIRAWFilter/Photo/Export 路径，且临时导出删除、源写入路径不存在。未知 decoder ICC 保持拒绝并供调查，不引入 heuristic 或未经验证的 Sony mapping。未发现 P0/P1 阻塞问题。

Regression:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`；全量 94 tests, 0 failures，覆盖 Phase 0–16.4 的 Catalog、资料库、照片/RAW/LUT、色彩管线、局部蒙版、导出、视频、HDR guard 与相似照片检测。

Manual Verification:
MANUAL VERIFICATION REQUIRED — 仓库不包含私有 Sony A7C II ARW、DNG 或大型 RAW。使用用户授权文件运行 File → 运行 RAW 诊断…，保留报告并按 `docs/raw-diagnostics.md` 与 `docs/manual-validation.md` 验证真实 decoder ICC、方向、全部实际可用控制、preview、LUT、local masks（适用时）、sRGB/Display P3 full-resolution export 和原文件字节不变。若 A7C II ICC 未匹配严格契约，只记录实际 profile；在独立验证前不添加映射。

Known Limitations:
- 自动化只能验证诊断服务的安全失败、文本报告、能力列表和现有合成色彩契约，不能伪造 Sony/DNG decoder 输出或声称真实相机支持全部 CIRAWFilter control。
- 诊断的 full-resolution 临时导出有意会占用真实 RAW 的 CPU/内存和时间；它是开发/验证动作，而不是交互式预览的快捷路径。
- Source integrity 字段比较文件大小和修改时间；不额外计算昂贵的全文件哈希。渲染与导出 API 不包含源写入操作，真实文件 byte-identical 检查仍列为人工验证。

Commit:
- `feat: add RAW media diagnostics`

## Phase 16.5 — Still Image Color Real Validation

Status:
COMPLETED

Implemented:
- 新增 **File → 运行静态图像色彩验证…**。用户授权 JPEG、HEIC/HEIF、PNG 或 TIFF 源文件与输出文件夹后，`StillImageColorDiagnosticService` 只读源图，并在唯一新建的用户输出子目录中，对 sRGB、Display P3、Rec.709、Rec.2020 SDR 分别执行真实 preview 及 JPEG、HEIF/HEIC（系统支持时）、TIFF full-resolution export。
- 每个 preview 的编码数据和每张新导出图均由 ImageIO 重新打开；报告记录实际 profile 名、严格 ICC payload 与请求输出的匹配结果、输入 descriptor、输出目录与源签名。任何缺失或未知的源 ICC 都会被记录并停止矩阵，不会猜测为 sRGB。
- 新增 `docs/still-image-color-validation.md` 与详细手工清单。Rec.2020 明确保持 BT.709 transfer 的 SDR 路径，绝不声称 HDR、PQ、HLG 或 gain-map 导出。

Tests:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:MacPhotoStudioTests/StillImageColorDiagnosticTests -only-testing:MacPhotoStudioTests/ColorOutputTests`；4 tests, 0 failures。新增测试创建带 sRGB ICC 的临时 PNG，并实际执行四种 preview、每个系统支持 JPEG/HEIF/TIFF encoder、逐项 ImageIO 重读与源字节不变；覆盖不支持输入的失败关闭。既有全输出格式 ICC round-trip 测试保留。

Build:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`；`BUILD SUCCEEDED`。

Acceptance:
AUTOMATED PASS — 诊断命令、全 SDR 输出矩阵、ImageIO 重读与严格 ICC 验证已实际运行；所有输出都在用户选定目录的新子目录中，不会覆盖来源或已有文件。未发现 P0/P1 自动化阻塞问题。

Regression:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`；全量 96 tests, 0 failures，覆盖 Phase 0–16.5 的 Catalog、资料库、照片/RAW、LUT、色彩、局部蒙版、视频、HDR guard 与相似照片检测。

Manual Verification:
MANUAL VERIFICATION REQUIRED — 当前仓库不含用户的 JPEG sRGB/P3、HEIC sRGB/P3、PNG、TIFF 或真实色彩管理显示器。按 `docs/still-image-color-validation.md` 对每种来源运行命令，使用 ColorSync-aware 参考应用进行视觉比较并记录显示器/系统/应用；这不能由合成 PNG 自动测试替代。

Known Limitations:
- 自动化验证的是带精确 sRGB ICC 的临时 PNG 及系统当前 encoder；真实 JPEG/HEIC P3 profile、第三方 profile、显示器色域和视觉结果必须人工验证。
- PNG 作为真实输入被检查；当前产品导出格式仍为 JPEG、HEIF/HEIC、TIFF，不虚称生成 PNG 导出。
- Rec.2020 行为是 SDR，HDR still/gain-map 输出仍不支持。

Commit:
- `feat: add still image color validation`

## Phase 16.6 — Video Real-Media Validation

Status:
COMPLETED

Implemented:
- 扩展 `VideoPreviewStateTests`，以真实临时 H.264 MOV 连续替换三次 `AVPlayerItem`，验证 seek/逐帧、播放头、播放状态、倍率、静音/音量恢复；旧 item 的结束通知被忽略，而最新 item 的 observer 能正确停止播放。
- 扩展实际 H.264 导出测试：带 Creative LUT、裁剪和 resize 的导出重新从 AVFoundation 取帧并核对 LUT 色彩与输出尺寸；已有真实 AAC 路径继续核对 trim + speed + 画面/音频 fade 后音视频轨时长同步、竖向 transform/resize、Proxy 与源字节不变。
- 新增 `docs/video-real-media-validation.md`，并把 iPhone MOV、Sony MP4、H.264/HEVC、横竖向、30/60 fps、4K、有/无音轨以及三类高风险组合纳入人工验证矩阵。音频仍严格仅支持 `-60 dB ... 0 dB` 衰减，未新增正增益。

Tests:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:MacPhotoStudioTests/VideoEditingTests -only-testing:MacPhotoStudioTests/VideoExportAudioTests -only-testing:MacPhotoStudioTests/VideoPlaybackSessionTests -only-testing:MacPhotoStudioTests/VideoPreviewStateTests -only-testing:MacPhotoStudioTests/VideoAudioTests -only-testing:MacPhotoStudioTests/VideoGeometryTests -only-testing:MacPhotoStudioTests/VideoLibraryTests`；20 tests, 0 failures。

Build:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`；`BUILD SUCCEEDED`。

Acceptance:
AUTOMATED PASS — 所有不依赖私有素材的 AVFoundation 路径均以临时 H.264/AAC 媒体实际执行；新 observer、播放状态、音画同步、方向/resize、LUT+crop export、Proxy 与衰减限制均有回归。未发现 P0/P1 自动化阻塞问题。

Regression:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`；全量 98 tests, 0 failures，覆盖 Phase 0–16.6 的 Catalog、资料库、照片/RAW、LUT、色彩、局部蒙版、视频、HDR guard 与相似照片检测。

Manual Verification:
MANUAL VERIFICATION REQUIRED — 仓库不含 iPhone MOV、Sony MP4、真实 HEVC、4K、60 fps、长视频、真实听感环境或外置盘素材。按 `docs/video-real-media-validation.md` 执行矩阵，尤其检查 35 秒附近连续 preview rebuild、设备 codec 兼容性与实际 A/V 同步。

Known Limitations:
- 自动化临时 H.264/AAC 不能替代 iPhone/Sony 编码差异、长时播放、4K 性能、外置存储和真实听感。
- HEVC 仍受当前 macOS/源视频可用 export preset 限制；不支持时明确失败。
- HDR 视频编辑/Proxy/导出和正音频增益仍不支持，绝不伪称完成。

Commit:
- `test: strengthen video media validation`

## Phase 16.7 — External Storage Validation

Status:
COMPLETED

Implemented:
- 新增统一的媒体根目录可用性诊断与文本报告；它记录 bookmark 生命周期、security-scoped access、目录资源值和卷信息，并让启动检查与扫描入口复用同一判断。
- 断开的根目录只变为 offline、保留 Catalog 与派生资产；bookmark 失败但上次路径仍存在时明确标记 permissionRequired，避免把权限问题伪装成卷已拔出。
- `File → 运行媒体根目录可用性诊断` 会将每个根目录的报告写入 Application Support logs，并在 Finder 中显示；没有复制、移动、覆盖或删除任何用户媒体。
- 修正实际 H.264/AAC 导出回归：同步检查以音视频起点与 composition/video 时长为准，并仅允许有限 AAC encoder packet-padding 尾部，消除把容器编码细节误判为 A/V drift 的不稳定失败。

Tests:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:MacPhotoStudioTests/MediaRootAvailabilityDiagnosticTests -only-testing:MacPhotoStudioTests/VideoExportAudioTests`；4 tests, 0 failures。真实临时 bookmark/目录验证 online 报告、目录移除后 Catalog 保留、离线扫描失败但不把资产改为 missing，以及 AAC packet-padding 下的同步契约。

Build:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`；`BUILD SUCCEEDED`。

Acceptance:
AUTOMATED PASS — 统一诊断记录路径、bookmark 解析/stale、scope 启动结果、卷与 URL resource values；断开后只标记 offline 并保留记录，扫描在 `finishScan` 前失败，不会产生错误 missing。未发现 P0/P1 自动化阻塞问题。

Regression:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`；全量 101 tests, 0 failures，覆盖 Phase 0–16.7 的 Catalog、资料库、照片/RAW、LUT、色彩、局部蒙版、视频、HDR guard、相似照片检测与外置存储诊断。

Manual Verification:
MANUAL VERIFICATION REQUIRED — 真实 internal SSD、external SSD/HDD、SD card、断连、改名、重连和 sandbox 授权必须按 `docs/external-storage-validation.md` 人工验证。

Known Limitations:
- 自动化临时目录不能代表真实可移动卷、设备休眠、Finder 重命名或权限弹窗。
- 重新连接后仍需要 rescan 才会将已有 offline 资产恢复为可编辑/可导出；诊断不会猜测每个源文件已经在原路径恢复。

Commit:
- `feat: add external storage diagnostics`

## Phase 16.8 — Similar Photo Large-Library Benchmark

Status:
COMPLETED

Implemented:
- 相似扫描现在记录候选查询、真实 ImageIO/dHash decode attempt、hash reuse/new hash、分组、总耗时、组/失败数和采样 RSS；File → `运行相似照片基准（开发者）` 先扫描当前 Catalog 的真实媒体指标，再写入 10k/50k/100k 隔离 Catalog-only 基准报告。
- 基准的 Catalog-only 段会真实创建、读取和清理临时 SQLite rows，并在内存中运行分组；它明确不读 ImageIO、不访问外置卷且不宣称真实图片吞吐。fixture 包含跨四个 16-bit block 的八位差异对。
- 50k 随机 dHash profile 证明 BK-tree range traversal 是大型库热点。小库仍使用 dHash + BK-tree；≥25k 且阈值≤8 时改用精确 4×16-bit Hamming candidate index。距离≤8 的任意 pair 至少有一个 block 相差≤2，枚举后再做完整 64-bit 精确验证，因此没有阈值内漏检。
- 扫描在根目录解析、ImageIO hash 前后及分组每 128 项均检查取消；缓存签名保持 file size + modifiedAt，offline/missing 资产不会作为有效 hash 参与比较。
- 新增 `docs/similar-photo-benchmark.md`，并更新相似检测和人工验证文档，区分生成 Catalog 规模与真实媒体测试。

Tests:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:MacPhotoStudioTests/SimilarPhotoDetectionTests -only-testing:MacPhotoStudioTests/SimilarPhotoBenchmarkTests`；4 tests, 0 failures。实际执行 10k/50k/100k 隔离 Catalog-only fixture（17.18 秒，无固定耗时断言），覆盖跨 block distance-8 分组、缓存 reuse/modifiedAt/file-size 失效、offline 无 false hash，以及 hash/root-switch/grouping cancellation。

Build:
PASS — `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`；`BUILD SUCCEEDED`。

Acceptance:
AUTOMATED PASS — 所有要求的计时/计数/报告字段、开发者入口、三档生成规模、真实媒体与 Catalog-only 区分、取消路径和缓存失效均有实际代码与自动化验证。采样 profile 所确认的 BK-tree 大库瓶颈已用可证明完整的本地 Hamming index 处理；未引入 AI/semantic search、云端、自动删除或源文件写入。未发现 P0/P1 自动化阻塞问题。

Regression:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`；全量 103 tests, 0 failures（20.42 秒）。覆盖 Phase 0–16.8 的 Catalog、资料库、照片/RAW/LUT、色彩、局部蒙版、视频、HDR guard、外置存储和相似照片路径。

Manual Verification:
MANUAL VERIFICATION REQUIRED — 必须用用户授权的真实 10k/50k/100k JPEG/HEIC/PNG/TIFF/RAW-derived 媒体及 internal/external SSD/HDD/SD card 执行 `docs/similar-photo-benchmark.md` 与 `docs/manual-validation.md`：分别保留 live-media 与 Catalog-only 报告，确认响应性、RSS、误报/漏报、hash/root-switch/grouping 取消后的任务状态、offline/reconnect 和原文件字节不变。

Known Limitations:
- 生成 10k/50k/100k 结果只证明 SQLite Catalog 与内存 grouping 规模；并不代表同数目的真实 ImageIO decode、RAW、外置盘、权限或 UI 性能。
- dHash 仍然只是低分辨率亮度结构比较；重度 crop/rotation/非均匀修图可漏检，重复几何图案可误报。当前阈值仍固定为 Hamming ≤8，绝不作语义或“最佳照片”结论。
- 大库精确 Hamming index 为当前阈值优化；若未来改变阈值或比较模型，必须重新证明无漏检和执行新的 profile/benchmark，不能将该结果外推。

Commit:
- `feat: benchmark large similar-photo libraries`

## Phase 16.9 — Similar Group Review UX

Status:
COMPLETED

Implemented:
- 将原有的文本 pair 列表替换为按 Similar Group 横向展示的可视化审阅卡片。卡片显示 ThumbnailStore 的 256 px 缩略图、文件名、尺寸、Catalog 文件大小、评分、Flag、RAW/JPEG 指示符及拍摄日期；无 Catalog metadata 时明确提示，绝不为结果 UI 解码全分辨率原图。
- 新增仅从 Catalog 读取的相似审阅 metadata 查询，并由 ApplicationModel 保持 Similar Group 的原始顺序；大组件按 900 个 ID 分批查询，避免 SQLite bind-variable 上限。
- 审阅选择独立于当前资料库分页。用户可显式同步选中资料库项目、打开缩略图预览、设置 0–5 星、Pick/Reject/取消标记、加入已有手动相册、创建 stack，或将可用的已选条目移到 Trash。Trash 一律先显示确认对话框；没有 keeper 评分、AI 表述或自动操作。
- 更新 `docs/similar-photo-detection.md` 与 `docs/manual-validation.md`，明确缩略图上限、可用操作、确认边界和真实媒体人工验证方式。

Tests:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:MacPhotoStudioTests/SimilarPhotoReviewTests -only-testing:MacPhotoStudioTests/AdvancedPhotoManagementTests -only-testing:MacPhotoStudioTests/SimilarPhotoDetectionTests`；8 tests, 0 failures。新回归以没有任何媒体文件的 901 条 Catalog 记录验证分批 metadata 读取、RAW/评分/Flag/尺寸展示字段，现有 tests 覆盖相册、stack、相似扫描与源文件保护。

Build:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`；`BUILD SUCCEEDED`。

Acceptance:
AUTOMATED PASS — 相似组以缩略图和完整要求的 Catalog metadata 审阅；预览和全部修改性操作均使用已有安全服务，Trash 要求明确选择和确认。901-ID 查询测试证明大结果不会触发单次 SQL 参数上限，且不依赖原始媒体读取。未发现 P0/P1 自动化阻塞问题。

Regression:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`；全量 104 tests, 0 failures（25.94 秒），覆盖 Phase 0–16.9 的 Catalog、资料库、照片/RAW/LUT、色彩、局部蒙版、视频、HDR guard、外置存储和相似照片路径。

Manual Verification:
MANUAL VERIFICATION REQUIRED — 需要用户授权的 JPEG/HEIC/PNG/TIFF/RAW-derived 文件，在真实 macOS UI 检查缩略图视觉、元数据、Preview、评分/Flag/相册/stack 操作，以及 Trash 的确认弹窗和原文件字节不变；按 `docs/manual-validation.md` 执行。

Known Limitations:
- 相似分数仍只是 dHash 结构接近度；不会也不能代表场景、身份或“最佳照片”。
- 离线/已移除 Catalog 项目不会回读原图，卡片会报告 metadata 不可用；实际缩略图质量、真实大组滚动性能与 Finder Trash 行为需人工验证。
- 当前只提供已有手动相册目标和 stack 创建，不创建自动相册或基于启发式的 keeper 建议。

Commit:
- `feat: add visual similar photo review`

## Phase 16.10 — ApplicationModel Incremental Refactor

Status:
COMPLETED

Implemented:
- 新增 `PhotoEditingCoordinator`，由它组合 `PhotoEditingService` 和 `PresetRepository`，统一承担照片/RAW edit state、预览渲染、RAW 导出、LUT 操作、预设 CRUD/import/export、批量预设应用与实际批量照片导出。
- `ApplicationModel` 移除对两个具体照片服务的直接持有，改为持有单一 coordinator；既有 SwiftUI-facing 方法名称、返回值、错误呈现、任务状态、进度、输出目录 security-scope 与 collision dialog 均保持不变，只作为转发与 UI orchestration 层。
- 扩展 coordinator 边界测试，以无原始媒体的真实临时 Catalog 验证 Photo/RAW 状态持久化、从当前 edit state 创建预设、预设重命名/收藏与批量 preset application。更新 `docs/application-architecture.md`，明确当前已完成和仍待拆分的边界。

Tests:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:MacPhotoStudioTests/CoordinatorTests -only-testing:MacPhotoStudioTests/PhotoEditingTests -only-testing:MacPhotoStudioTests/RAWColorPipelineTests -only-testing:MacPhotoStudioTests/RAWMediaDiagnosticTests`；25 tests, 0 failures。

Build:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`；`BUILD SUCCEEDED`。

Acceptance:
AUTOMATED PASS — `ApplicationModel` 的照片相关 UI 方法保留为稳定 forwarding API，但不再直接组合 `PhotoEditingService` 或 `PresetRepository`。照片、RAW、LUT、预设、批处理与 collision UI 的职责边界清晰；没有改变任何原始媒体读写契约。未发现 P0/P1 自动化阻塞问题。

Regression:
PASS — `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`；全量 105 tests, 0 failures（20.82 秒），覆盖 Phase 0–16.10 的 Catalog、资料库、照片/RAW/LUT、色彩、局部蒙版、视频、HDR guard、外置存储、相似照片与 coordinator 路径。

Manual Verification:
NOT REQUIRED — 此阶段仅为不改变 UI-facing API 或媒体行为的服务组合重构；所有变更均由自动化 coordinator、照片、RAW、LUT、导出和全量回归覆盖。已有真实媒体人工验证项继续适用，未在本阶段新增硬件依赖。

Known Limitations:
- `ApplicationModel` 仍直接负责资料库 root/scan/catalog refresh、缩略图与部分高级资料库操作，以及照片导出任务/冲突对话框的 presentation orchestration；这是刻意保留的后续小切片，而非未声明的完成状态。
- Coordinator 不改变底层 decoder、LUT、RAW、渲染或外置存储的能力边界；这些真实媒体与硬件验证仍以已有文档为准。

Commit:
- `refactor: extract photo editing coordinator`

## Phase 16.11 — CI / Regression Gate

Status:
COMPLETED

Implemented:
- 新增公开仓库的 `.github/workflows/macos-regression.yml`。它在 `main` push、针对 `main` 的 PR 和手动触发时，使用 `macos-26`，明确选择 `/Applications/Xcode_26.6.app`，通过 Homebrew 安装 XcodeGen，运行完整 unsigned macOS test 和 Debug build。
- 工作流最小权限为 `contents: read`，没有 secrets、媒体上传或生成文件归档。`docs/**` 和 `plan.md` 的纯文档 push 不重复消耗 macOS runner；任何代码、工程或 workflow 变化仍会触发门禁。
- 新增 `docs/ci.md`，并在 README 中链接，记录本地与 GitHub-hosted runner/Xcode 矩阵以及工具链漂移时的可见失败策略。
- 首次远端运行 `31267655377` 真实暴露了 AAC 轨时长元数据的跨 runner 量化差异：`VideoExportAudioTests` 的固定 −40 ms 下限会把三个 AAC access unit 以内的 encoder priming/padding 误判为 A/V 失步。测试现改为读取实际输出 AAC access-unit size 和 sample rate，以三个 packet 为严格、可解释的双向边界；仍检查音轨存在、起点与视频对齐及输出/视频时长。该修复已由最终远端 run 验证。
- 第二次远端运行 `31267896166` 继续执行到 `VideoPlaybackSessionTests`，并显示该测试在 `AVPlayerItem.status` 变为 ready 后、KVO 回调异步回填时长前就读取 `session.duration`。测试现等待 ready 和非零时长两个真实完成条件，仍严格断言时长为 1 秒以及新 item 的结束观察者行为；不会掩盖加载失败或错误时长。
- 修复提交 `a50ee9179b93cf36e8a454ca563b31e70408120e` 的 GitHub-hosted `macos-26` run `31268156293` 已真实通过，选择的工具链为 Xcode 26.6（17F113）、XcodeGen 2.46.0。工作流完整运行 test 与 Debug build，不依赖 secrets 或用户媒体。

Tests:
PASS — `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/macos-regression.yml')"`；workflow YAML 解析成功。`xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:MacPhotoStudioTests/VideoExportAudioTests`；1 test, 0 failures。`VideoPlaybackSessionTests` 连续运行 5 次，均为 1 test, 0 failures。完整本地 `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`；全量 105 tests, 0 failures（22.72 秒）。GitHub Actions run `31268156293`：105 tests, 0 failures（62.10 秒）。

Build:
PASS — 本地 `xcodegen generate && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`；`BUILD SUCCEEDED`。GitHub Actions run `31268156293` 的同一 unsigned Debug build 也为 `BUILD SUCCEEDED`。

Acceptance:
PASS — 公开仓库拥有可复现的 macOS 门禁；最新 GitHub-hosted `macos-26` job 在 Xcode 26.6 上完成完整 105 项测试和 unsigned Debug build（均成功）。前两次真实失败已被定位、修复并由最终 run 验证，未被隐藏。

Regression:
PASS — 本地全部 105 项自动化回归通过；GitHub-hosted 105 项测试与 Debug build 也通过。局部回归还包括 `VideoPlaybackSessionTests` 的 5 次连续通过。

Manual Verification:
NOT REQUIRED — 本阶段 CI workflow 不读取真实媒体，也不依赖外置盘、HDR 屏幕或权限弹窗。已有真实媒体/硬件人工验证项继续适用。

Known Limitations:
- GitHub-hosted runner image 会更新；workflow 故意固定 `macos-26` 和 Xcode 26.6 path，镜像移除该 path 会失败并要求显式更新矩阵。
- CI 只覆盖软件自动化门禁；真实 RAW、外置存储、HDR 显示和权限验证仍按 `docs/manual-validation.md` 的 `MANUAL VERIFICATION REQUIRED` 执行。

Commit:
- `ci: add macos regression gate`
- `test: account for AAC export packet quantization`
- `test: wait for playback item metadata`
- `docs: record CI verification`

## Phase 16.12 — Correctness Audit Fix

Status:
COMPLETED — local and GitHub-hosted automated acceptance passed.

Implemented:
- 16.12.1 — `PhotoTransformGeometry` now distinguishes bounded editable points from unbounded source points and vectors. `LocalMaskCanvas` derives radial/brush display sizes from unbounded source-pixel vectors, not a clamped radius endpoint. It matches `CIRadialGradient`'s separate inner-radius/feather 1 px floors and `BrushMaskRenderer`'s rounded texture dimensions/0.5 px floor; viewport clipping, rather than geometric shortening, hides portions outside an image or crop. Stored `LocalMask` source-normalized state and schema are unchanged.
- 16.12.2 — `SubjectMaskProvider` now registers a per-key in-flight request under a short cache lock, runs Vision outside the global lock, then publishes one bounded-LRU result and wakes same-key waiters. Distinct source keys can generate concurrently; a generated `nil` remains one shared fail-closed cached result.
- 16.12.3 — subject-mask source revisions now include an available filesystem resource identifier in addition to standardized path, size and modification time. No full-file hash is performed. The persistent similar-photo dHash cache is deliberately deferred: adding the identifier there requires a Catalog migration and compatibility coverage, so the existing size/modification signature remains unchanged in this audit.
- 16.12.4 — CI downloads XcodeGen 2.46.0 from its official release, verifies SHA-256, pins `actions/checkout` to v4.2.2's full commit SHA, and checks the generated `project.pbxproj` after every XcodeGen invocation. A local generation with the same XcodeGen 2.46.0 produced no project drift.

Tests:
PASS — `PATH=/tmp/macphotoedit-phase-16-12-xcodegen/xcodegen/bin:$PATH xcodegen generate` followed by `git diff --exit-code -- MacPhotoStudio.xcodeproj/project.pbxproj`; no generated-project drift. `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:MacPhotoStudioTests/PhotoTransformGeometryTests -only-testing:MacPhotoStudioTests/LocalMaskCanvasGeometryTests -only-testing:MacPhotoStudioTests/PhotoEditingTests -only-testing:MacPhotoStudioTests/SubjectMaskProviderTests -only-testing:MacPhotoStudioTests/SmartMaskTests`; 40 tests, 0 failures. New coverage exercises all image-edge/corner radial and brush vectors across crop/rotation/straighten/flips, a crop-edge pixel render, same-key sharing, different-key concurrency, failure caching, LRU retention and file-resource-identifier keying. GitHub Actions run `31318605032` on `macos-26` / Xcode 26.6 / XcodeGen 2.46.0 ran 113 tests, 0 failures.

Build:
PASS — `PATH=/tmp/macphotoedit-phase-16-12-xcodegen/xcodegen/bin:$PATH xcodegen generate && git diff --exit-code -- MacPhotoStudio.xcodeproj/project.pbxproj && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`; `BUILD SUCCEEDED`. GitHub Actions run `31318605032` completed the matching unsigned Debug build with `BUILD SUCCEEDED`.

Acceptance:
PASS — no P0/P1 correctness blocker remains in the audited local-mask radius path: the overlay/rings use the same source-space metric as rendering without altering persisted masks, and the pixel integration test proves a displayed crop-edge radial region modifies the matching pipeline pixels. The subject provider retains duplicate suppression and bounded LRU behavior while removing global Vision serialization. The checked-in CI configuration is reproducible and rejects stale generated project files. Branch-protection inspection on 2026-08-09 found `main` unprotected with no applicable rulesets; the regression workflow exists but is not claimed as a required pre-merge check.

Regression:
PASS — `PATH=/tmp/macphotoedit-phase-16-12-xcodegen/xcodegen/bin:$PATH xcodegen generate && git diff --exit-code -- MacPhotoStudio.xcodeproj/project.pbxproj && xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`; full 113 tests, 0 failures. GitHub-hosted run `31318605032` independently passed the same 113 tests and Debug build. Existing Xcode warnings and host-service logs did not fail any test.

Manual Verification:
MANUAL VERIFICATION REQUIRED — on user-authorized horizontal, vertical and square JPEG/HEIC/RAW-derived images, compare large radial and brush overlays with new-file exports at every edge/corner and across crop boundaries, crop+rotation, crop+flip and crop+straighten+flip. Confirm 24/48 MP memory behavior, real Vision behavior and no source-file change according to `docs/manual-validation.md`; automated synthetic pixels cannot validate those media/display conditions.

Known Limitations:
- The persistent similar-photo dHash cache still uses source size + modification time only. Its resource-identifier addition is deferred pending a deliberately scoped Catalog migration; no existing cache metadata was changed or invalidated speculatively.
- CI's software gate cannot validate user media, external storage, macOS permissions, real Vision segmentation quality or HDR displays; GitHub-hosted run `31318605032` only verifies the automated software contract.

Commit:
- `fix: preserve local mask radius at image edges`
- `perf: improve subject mask cache handling`
- `ci: pin macos regression dependencies`
- `docs: record phase 16.12 audit fixes`
- `docs: finalize phase 16.12 CI verification`

## UI/UX Redesign Phase 1 — UI-1.1 Empty-library onboarding

Status:
COMPLETED

Implemented:
- Replaced the generic empty-library message with a focused onboarding state:
  “开始建立你的照片资料库”, an explanation of the referenced-folder model,
  and the exact safety boundary that originals are neither copied nor changed.
- Added a prominent “选择照片或视频文件夹…” CTA wired directly to the existing
  `presentAddFolderPanel` workflow. It opens the real macOS folder picker and
  never claims an unsupported import or copy operation.
- Added visible safety text and an accessibility hint for the CTA. The
  existing no-results / clear-filter state remains separate for libraries that
  already have roots.

Tests:
- PASS — `xcodegen generate`
- PASS — `git diff --exit-code -- MacPhotoStudio.xcodeproj/project.pbxproj`
- PASS — `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`; 113 tests, 0 failures. Existing LMDB map-size warnings were emitted by the test host but did not fail any test.

Build:
- PASS — `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`; `BUILD SUCCEEDED`.

Acceptance:
- PASS — Empty library presents the required clear title, referenced-library explanation, centered real CTA, and safety copy.
- PASS — The CTA reuses the existing secure folder-reference flow; no raw-media copy, move, or modification behavior was introduced.

Regression:
- PASS — Full automated suite remains at 113 tests with 0 failures; generated Xcode project has no drift.

Manual Verification:
- PASS — Launched the current Debug app with an empty Catalog and inspected the rendered window and accessibility tree. The title, description, safety copy, button label, and accessibility hint are present. No folder was selected, so no user media or permissions were touched.

Known Limitations:
- A true media-root scan requires a user-authorised folder and is intentionally deferred to the later add-media flow verification; this onboarding change does not alter scanner behavior.

Commit:
- `feat: redesign empty library onboarding`

## UI/UX Redesign Phase 1 — UI-1.2 Library toolbar hierarchy

Status:
COMPLETED

Implemented:
- Moved library-level controls into the native macOS window toolbar: visible
  “添加媒体文件夹”, a disabled-without-roots rescan menu, search, filter,
  thumbnail size, and inspector visibility.
- The rescan menu is backed by the existing `ScanCoordinator`: it can scan all
  recorded roots or one named root. The new all-roots action only starts the
  established referenced-root scans and never writes source media.
- Reduced the content header to a compact status bar. Existing selection
  operations are grouped under real “整理” and “编辑” menus, while duplicate
  and similar-photo operations are grouped under “分析”; no operational route
  was removed.
- The product has no implemented list-view or user-selectable sort behavior,
  so neither was represented as a misleading toolbar control.

Tests:
- PASS — `xcodegen generate`
- PASS — `git diff --exit-code -- MacPhotoStudio.xcodeproj/project.pbxproj`
- PASS — `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`; 113 tests, 0 failures. Existing LMDB map-size host warnings did not cause a test failure.

Build:
- PASS — `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`; `BUILD SUCCEEDED`.

Acceptance:
- PASS — Add media, rescan, search, filter, thumbnail-size and inspector controls are visible from a native toolbar without menu-bar discovery.
- PASS — Every exposed action maps to existing behavior; rescan is correctly unavailable before a referenced root exists, and there are no fake sort or list controls.

Regression:
- PASS — Full automated suite remains at 113 tests with 0 failures; generated Xcode project has no drift.

Manual Verification:
- PASS — Restarted the current Debug app and inspected the rendered toolbar and accessibility tree. The toolbar exposes add media, disabled no-root rescan, search, filter, thumbnail-size and inspector controls with labels/help. No folder picker or scan was invoked.

Known Limitations:
- A real multi-root rescan remains `MANUAL VERIFICATION REQUIRED` with user-authorised local and external media roots; this UI work reuses the established scanner and does not change its permission or source-safety contract.

Commit:
- `feat: improve library toolbar hierarchy`

## UI/UX Redesign Phase 1 — UI-1.3 Sidebar information architecture

Status:
COMPLETED

Implemented:
- Reorganized the sidebar into clear `资料库`, `来源`, `整理`, and `筛选`
  sections. Existing all-media/photo/video navigation remains at the top;
  referenced roots now live under the explicit source model.
- The no-root source state points to the visible toolbar action rather than
  implying a file-copy import. Root rescan and relink remain real context-menu
  actions, avoiding a redundant row-level rescan icon.
- Grouped existing albums, smart albums, stacks, and tags under `整理` with
  existing create/rename/delete behavior unchanged. Ratings and flags are now
  compact filter menus (including a real no-limit reset); RAW/JPEG display
  selection remains the existing picker.

Tests:
- PASS — `xcodegen generate`
- PASS — `git diff --exit-code -- MacPhotoStudio.xcodeproj/project.pbxproj`
- PASS — `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`; 113 tests, 0 failures. Existing LMDB map-size host warnings did not cause a test failure.

Build:
- PASS — `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`; `BUILD SUCCEEDED`.

Acceptance:
- PASS — The actual sidebar expresses library type, source folders, and organization without fake destinations; selection presentation and all existing actions remain available.
- PASS — The source empty state is useful, while root-specific maintenance remains discoverable from each root's context menu and does not duplicate the toolbar.

Regression:
- PASS — Full automated suite remains at 113 tests with 0 failures; generated Xcode project has no drift.

Manual Verification:
- PASS — Restarted the current Debug app and inspected the rendered sidebar and accessibility tree. All four groups, the empty-source guidance, create controls, and compact filter entries are present. No media root, folder picker, or scan was invoked.

Known Limitations:
- Showing populated albums, tags, stacks, unavailable roots, and actual context menus with user media remains `MANUAL VERIFICATION REQUIRED`; the data paths are unchanged and covered by existing Catalog tests.

Commit:
- `feat: reorganize library sidebar`

## UI/UX Redesign Phase 1 — UI-1.4 Inspector states

Status:
COMPLETED

Implemented:
- `LibraryInspectorView` now receives the existing media-root state and
  distinguishes an empty library from an unselected item.
- An empty library shows the concise “尚未添加媒体” guidance; a library with
  sources but no selection shows “未选择媒体项目” and names the metadata,
  rating, flag and tag information available after selection.
- The existing full selected-item inspector, its close action, management
  controls and metadata rendering remain unchanged. The existing toolbar still
  provides the minimal native hide/show behavior.

Tests:
- PASS — `xcodegen generate`
- PASS — `git diff --exit-code -- MacPhotoStudio.xcodeproj/project.pbxproj`
- PASS — `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`; 113 tests, 0 failures. Existing LMDB map-size host warnings did not cause a test failure.

Build:
- PASS — `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`; `BUILD SUCCEEDED`.

Acceptance:
- PASS — Empty-library and no-selection states have separate, intentional copy while selected-item behavior is preserved.
- PASS — The inspector remains collapsible via the existing native toolbar control; no navigation rewrite was introduced.

Regression:
- PASS — Full automated suite remains at 113 tests with 0 failures; generated Xcode project has no drift.

Manual Verification:
- PASS — Restarted the current Debug app with an empty Catalog and inspected the new empty-library inspector copy through the rendered UI and accessibility tree.
- MANUAL VERIFICATION REQUIRED — With a user-authorised media root, inspect the no-selection and selected-item variants using real catalogued photo/video metadata. No media root was added during this UI validation.

Known Limitations:
- The no-selection copy is selected from the existing media-root state, not from a new Catalog count query; it correctly avoids a new data-loading path but cannot distinguish an in-progress empty scan from a completed root with no supported files.

Commit:
- `feat: improve inspector empty states`

## UI/UX Redesign Phase 1 — UI-1.5 Native desktop density and responsive layout polish

Status:
COMPLETED

Implemented:
- Set the native macOS window's first-launch default to 1180×720 and raised the
  working layout floor to 960×620, preserving a usable three-column library
  workspace rather than introducing a custom responsive shell.
- Rebalanced the existing split-view constraints: source navigation is compact
  but readable, the browser receives the primary working width, and the
  inspector remains a bounded secondary pane.
- Tightened grid and status-bar spacing with system materials and semantic
  colors only. Empty onboarding now has a deliberate maximum reading width
  instead of stretching across wide windows.

Tests:
- PASS — `xcodegen generate`
- PASS — `git diff --exit-code -- MacPhotoStudio.xcodeproj/project.pbxproj`
- PASS — `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`; 113 tests, 0 failures. Existing LMDB map-size host warnings did not cause a test failure.

Build:
- PASS — `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`; `BUILD SUCCEEDED`.

Acceptance:
- PASS — The first-launch size, sidebar/browser/inspector proportions and
  minimum workspace dimensions support the intended native desktop hierarchy.
- PASS — Density changes use standard SwiftUI/AppKit sizing and materials; no
  custom visual system or simulated responsive behavior was introduced.

Regression:
- PASS — Full automated suite remains at 113 tests with 0 failures; generated Xcode project has no drift.

Manual Verification:
- PASS — Restarted the current Debug app and inspected the rendered empty
  library at its native window size. The three panes, compact status bar,
  toolbar, onboarding reading width, and inspector align without overlap.
- MANUAL VERIFICATION REQUIRED — Resize a populated library through the
  960×620 minimum on both laptop and desktop displays, then confirm actual
  thumbnail density and long localized metadata remain readable. No user media
  was added during this validation.

Known Limitations:
- Window restoration is controlled by macOS; users with a previously restored
  window may not observe the new default until creating a new window or
  clearing the app's restored state. The minimum dimensions still apply.

Commit:
- `style: refine library workspace layout`

## UI/UX Redesign Phase 1 — UI-1.6 Add-media / scan flow clarity

Status:
COMPLETED

Implemented:
- Clarified the existing native folder picker as “添加媒体文件夹”, with an
  explicit “添加到资料库” confirmation and concise security-scoped,
  reference-only safety text. Cancellation still returns without any Catalog,
  bookmark, or source-media change.
- Traced and retained the established path: picker → `MediaRootStore` secure
  bookmark → Catalog root persistence → `ScanCoordinator` → periodic library
  refresh. No file-copy or alternate import path was added.
- Added safe duplicate-root registration: the same normalized, symlink-resolved
  folder reuses its existing referenced root and starts the established rescan
  rather than creating a duplicate Catalog root.
- Surface real `ScanCoordinator` state in the library status bar: preparation,
  scanning counts, paused/resume, cancellation, brief completion feedback and
  actionable persistent failure details. These controls call the existing
  pause/resume/cancel APIs; they do not simulate progress.

Tests:
- PASS — `xcodegen generate`
- PASS — `git diff --exit-code -- MacPhotoStudio.xcodeproj/project.pbxproj`
- PASS — `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:MacPhotoStudioTests/CatalogIndexingTests test`; 5 tests, 0 failures, including the new duplicate-root registration test.
- PASS — `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`; 114 tests, 0 failures. The single-count increase is the focused duplicate-root test. Existing LMDB map-size host warnings did not cause a test failure.

Build:
- PASS — `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`; `BUILD SUCCEEDED`.

Acceptance:
- PASS — The visible add-media command opens the real directory-only picker
  with clear referenced-library semantics and a meaningful confirmation label.
- PASS — Duplicate selection cannot create another root record; the focused
  automated test verifies the same root ID is reused and the Catalog has one
  root only.
- PASS — UI scan presentation is driven by real scan statuses and real control
  methods; errors and offline/permission failures continue to use the existing
  Catalog availability and error handling paths.

Regression:
- PASS — Full automated suite now has 114 tests with 0 failures; generated Xcode project has no drift.

Manual Verification:
- PASS — Launched the current Debug app, opened the toolbar add-media command,
  inspected the native picker title, safety message and “添加到资料库” button,
  then pressed Cancel. The library remained empty and no folder was selected.
- MANUAL VERIFICATION REQUIRED — With a user-authorised photo/video folder,
  verify selected-folder feedback, live scan counts, pause/resume/cancel,
  post-scan thumbnails, duplicate folder selection, an unavailable external
  root and a permission-relink recovery. No real root was registered during
  this validation.

Known Limitations:
- Scan progress is intentionally count-based because the scanner enumerates a
  filesystem stream and has no reliable total before traversal; no misleading
  percentage is shown.
- Real external-volume availability and macOS security-scoped permission
  recovery require the user’s hardware and permission context.

Commit:
- `fix: streamline add media folder flow`

## UI/UX Redesign Phase 1 — UI-1.7 Drag-and-drop feasibility decision

Status:
DEFERRED — safety decision completed; no drag-and-drop capability was added.

Implemented:
- Audited the current library, folder-registration and bookmark paths. There is
  no existing drag-and-drop handler, and the only verified persistent-access
  route is the user-selected `NSOpenPanel` folder URL → `MediaRootStore` secure
  bookmark → Catalog root path.
- Intentionally kept the UI free of drop zones and drag-and-drop wording. This
  prevents a user from believing that an arbitrary drop is a durable,
  source-safe library registration when that contract has not been established.

Tests:
- PASS — `xcodegen generate`
- PASS — `git diff --exit-code -- MacPhotoStudio.xcodeproj/project.pbxproj`
- PASS — `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`; 114 tests, 0 failures. Existing LMDB map-size host warnings did not cause a test failure.

Build:
- PASS — `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`; `BUILD SUCCEEDED`.

Acceptance:
- DEFERRED — Apple documents drag-and-drop bookmark creation as unscoped when
  there is no containing document. The current app persists only security-
  scoped bookmarks and has no App Sandbox bookmark entitlement configuration;
  accepting dropped URLs therefore cannot be shown to preserve access after
  relaunch or permission changes without a separately designed access model.
- DEFERRED — Individual photo/video drops have no existing ownership or
  referenced-root model. Supporting them would create the forbidden second
  import architecture or require a broader Catalog/permission redesign.

Regression:
- PASS — No application source or project configuration changed for this
  decision; full automated suite remains at 114 tests with 0 failures.

Manual Verification:
- NOT APPLICABLE — No drag-and-drop target is intentionally exposed. Existing
  folder-picker behavior remains the only supported and manually verifiable
  media-root registration path.

Known Limitations:
- Future drag-and-drop work must first define and test a persistent permission
  contract for dropped folders, including App Sandbox entitlement policy,
  security-scoped bookmark lifecycle, rejected payload feedback and external
  volume recovery. It must not merely call the folder-add method with an
  `NSItemProvider` URL.

Commit:
- `docs: record drag and drop deferral`

## UI/UX Redesign Phase 1 — UI-1.8 Accessibility and final regression audit

Status:
COMPLETED

Implemented:
- Audited the changed onboarding, toolbar, scan feedback, sidebar and inspector
  controls for native labels, disabled states, focusable system controls,
  tooltips and semantic SwiftUI materials/colors.
- Added explicit VoiceOver names for the inspector close action, every rating
  action, add/remove tag actions and an unavailable source indicator. Replaced
  the inspector's remaining English `Flag` label with `标记`; the tag add menu
  now uses a visible native `Label("添加标签", systemImage: "plus")` rather
  than relying on a system icon name.
- Preserved native controls and dynamic system colors. No custom palette,
  contrast override, source-media operation or layout rewrite was introduced.

Tests:
- PASS — `xcodegen generate`
- PASS — `git diff --exit-code -- MacPhotoStudio.xcodeproj/project.pbxproj`
- PASS — `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`; 114 tests, 0 failures. Existing LMDB map-size host warnings did not cause a test failure.

Build:
- PASS — `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`; `BUILD SUCCEEDED`.

Acceptance:
- PASS — Changed icon-only actions expose a clear VoiceOver name and tooltip;
  visible controls retain their native keyboard-focus behavior and disabled
  states remain truthful.
- PASS — The UI uses SwiftUI semantic system materials/colors and works in the
  current light system appearance without added hard-coded theme styling.
- PASS — The final suite and Debug product build preserve existing functionality.

Regression:
- PASS — Full automated suite remains at 114 tests with 0 failures; generated Xcode project has no drift.

Manual Verification:
- PASS — Empty-library onboarding, safety copy, toolbar and unselected
  inspector state were inspected in the current Debug app during UI-1.1 through
  UI-1.5 validation.
- PASS — Non-destructively selected one item from an already catalogued local
  library and inspected the grid, sidebar, toolbar, selected-item inspector,
  ratings, `标记`, and the accessibility tree. No source file, rating, flag,
  tag, scan or trash action was changed.
- PARTIAL — The default desktop layout was visually inspected. Resizing a
  populated library at the minimum, laptop and large-desktop dimensions remains
  `MANUAL VERIFICATION REQUIRED` on the user's displays.
- PASS — Light appearance was inspected using native semantic controls.
- MANUAL VERIFICATION REQUIRED — Dark mode and increased-contrast appearance
  require the user's system accessibility/display settings; they were not
  changed during this task.

Known Limitations:
- Real media-root scan progress, external-volume loss/relink, exact
  small-window readability, Dark Mode and increased-contrast quality require
  user-authorised media, hardware and system settings. They remain in
  `docs/manual-validation.md` scope and are not claimed as automated passes.
- Drag-and-drop remains deliberately deferred per UI-1.7 until a persistent
  security-scoped dropped-folder access model is designed and verified.

Commit:
- `fix: improve library accessibility`

## UI/UX Redesign Phase 2 — Workspace & Interaction Redesign

Status:
IN PROGRESS

Baseline:
- `c5fc067` (`fix: improve library accessibility`), clean tracked worktree;
  the five untracked prompt documents are user-authored inputs and are excluded
  from all commits.

Audit:
- The ready library was rooted in an `HSplitView` with only minimum dimensions.
  Its containing hierarchy did not explicitly claim the available window height,
  so the working area could collapse to its content height and leave large
  vertical whitespace.
- Sidebar rows are plain buttons with hand-applied accent text. They do not use
  native list selection, so the active location has a weak and nonstandard
  selection treatment.
- The inspector is a permanent third split pane by default, even with no
  selection. It competes with the grid for width and makes an infrequently used
  metadata surface feel primary.
- The current always-visible status strip mixes hierarchy levels: count and
  selection actions are primary/contextual, while duplicate analysis is a
  low-frequency capability that should be moved to a More menu.
- Existing interaction behavior is retained as the starting contract: single
  click selects; Command-click toggles; Shift-click selects a contiguous range;
  Space opens the existing quick preview for one selected item; double-click
  opens the same existing preview (whose photo path exposes Edit and whose
  video path opens the existing video preview); Return has no activation
  behavior; the thumbnails have no context menu. Arrow up/down currently use a
  fixed four-item offset, which is not tied to the adaptive grid geometry.

Planned validation:
- Each UI2 item is implemented and accepted before the next item; each logical
  stage runs XcodeGen/project-drift validation, the full macOS test suite, and
  a Debug macOS build before its independent commit.
- Visual and hardware-dependent checks are recorded as manual verification,
  never inferred from automated results or sample media.

### UI-2.1 — Full-height native workspace shell

Status:
COMPLETED

Implemented:
- Replaced the content-sized three-way `HSplitView` root with a native
  `NavigationSplitView` and its standard `.inspector` attachment. The sidebar
  and primary browser now receive the window's normal split-view layout rather
  than being bounded by the browser's content height.
- Retained the established 960×620 minimum working size and the existing
  browser, Catalog, preview/editor, scan and selection call paths. The
  inspector is now a native secondary surface and defaults to on-demand rather
  than claiming width for a no-selection state at first launch.
- Removed an attempted infinite-size frame after test-host validation showed it
  could cause an AppKit constraint-update loop. Native `NavigationSplitView`
  already fills its window; the minimum-only constraint is stable.

Tests:
- PASS — `xcodegen generate`
- PASS — `git diff --exit-code -- MacPhotoStudio.xcodeproj/project.pbxproj`
- PASS — `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`; 114 tests, 0 failures. Existing LMDB map-size host warnings did not fail the suite.

Build:
- PASS — `xcodebuild -project MacPhotoStudio.xcodeproj -scheme MacPhotoStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`; `BUILD SUCCEEDED`.

Acceptance:
- PASS — The ready library uses a native sidebar/detail workspace and no longer
  relies on the content-sized root `HSplitView` that produced vertical unused
  space.
- PASS — The inspector is a native secondary presentation and can be hidden so
  the primary grid regains the available width. It will receive its focused
  final audit in UI2.5.

Regression:
- PASS — The full 114-test suite, project-drift check and Debug build pass
  after correcting the two discovered layout blockers: SwiftUI `frame`
  argument ordering and the redundant infinite-size constraint loop.

Manual Verification:
- PASS — Launched the Debug application against the existing local Catalog and
  inspected the rendered populated workspace. Sidebar and grid filled the
  window continuously; closing the native inspector enlarged the grid without
  overlap or blank vertical bands. No source, Catalog, scan or management
  action was invoked.
- MANUAL VERIFICATION REQUIRED — Verify the same behavior at the 960×620
  minimum and at laptop/large-display widths on the user's displays.

Known Limitations:
- macOS persists a user's existing inspector visibility preference. The new
  false default applies when no prior `library.showsInspector` preference has
  been stored; an already-open inspector remains visible until the user closes
  it, then stays on-demand.

Commit:
- `fix: make library workspace fill the window` (this checkpoint commit)
