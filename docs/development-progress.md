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
- 端到端检查导出结果保留 H.264 视频轨和 AAC 音轨，输出总时长、视频轨时长和音频轨时长均约为 0.3 秒，音视频差异不超过 0.04 秒；同时检查旋转后 resize 尺寸为 24×32 和源文件字节不变。

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
