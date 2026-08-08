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
