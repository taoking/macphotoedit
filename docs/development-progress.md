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
