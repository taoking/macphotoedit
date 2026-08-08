import AppKit
import SwiftUI

struct AssetBrowserView: View {
    @ObservedObject var model: ApplicationModel
    let assets: [LibraryAssetRecord]
    let groupedRAWAssetIDs: Set<UUID>
    @Binding var query: LibraryQuery
    @Binding var selectedAssetIDs: Set<UUID>
    @Binding var selectionAnchor: UUID?
    @Binding var previewAsset: LibraryAssetRecord?
    @Binding var thumbnailSize: CGFloat
    @Binding var showsInspector: Bool
    var gridIsFocused: FocusState<Bool>.Binding
    let addFolder: () -> Void
    let setRating: (Int) -> Void
    let setFlag: (AssetFlag) -> Void
    let addTag: (TagRecord) -> Void
    let addToAlbum: (AlbumRecord) -> Void
    let removeFromCurrentAlbum: () -> Void
    let createStack: (AssetStackKind, String) -> Void
    let removeFromCurrentStack: () -> Void
    let scanExactDuplicates: () -> Void
    let scanSimilarPhotos: () -> Void
    let moveToTrash: ([LibraryAssetRecord]) -> Void
    let select: (UUID, NSEvent.ModifierFlags) -> Void
    let moveSelection: (Int) -> Void
    @State private var showingFilters = false
    @State private var showsPresetNameSheet = false
    @State private var showsPresetManager = false
    @State private var showsSelectivePaste = false
    @State private var showsBatchExport = false
    @State private var showsStackCreator = false
    @State private var showsDuplicateResults = false
    @State private var showsTrashConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if assets.isEmpty, !model.isLoadingLibraryAssets {
                emptyState
            } else {
                grid
            }
        }
        .focused(gridIsFocused)
        .focusable()
        .onKeyPress { keyPress in
            handleKeyPress(keyPress)
        }
        .sheet(isPresented: $showsPresetNameSheet) {
            if let asset = selectedPhotoAssets.first {
                PresetNameSheet(asset: asset, model: model)
            }
        }
        .sheet(isPresented: $showsPresetManager) {
            PresetManagerSheet(model: model)
        }
        .sheet(isPresented: $showsSelectivePaste) {
            SelectivePasteSheet(model: model, assetIDs: selectedPhotoAssets.map(\.id))
        }
        .sheet(isPresented: $showsBatchExport) {
            BatchExportSheet(model: model, assets: selectedPhotoAssets)
        }
        .sheet(isPresented: $showsStackCreator) {
            StackCreatorSheet(assets: selectedAssets, create: createStack)
        }
        .sheet(isPresented: $showsDuplicateResults) {
            DuplicateResultsSheet(
                model: model,
                selectAssetInLibrary: { assetID in
                    selectedAssetIDs = [assetID]
                    selectionAnchor = assetID
                    Task { await model.loadTags(for: assetID) }
                },
                openPreview: { asset in previewAsset = asset }
            )
        }
        .confirmationDialog(
            "将所选原始文件移到废纸篓？",
            isPresented: $showsTrashConfirmation,
            titleVisibility: .visible
        ) {
            Button("移到废纸篓（\(selectedAssets.count) 项）", role: .destructive) {
                moveToTrash(selectedAssets)
            }
        } message: {
            Text("此操作会请求 macOS 将实际源文件移到废纸篓，不会永久删除。Catalog 中的评分、标签和编辑记录会保留，以便恢复文件后继续使用。")
        }
    }

    private var toolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                TextField("按文件名、文件夹、相机或镜头搜索", text: searchTextBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 180, idealWidth: 260, maxWidth: 360)
                Button {
                    showingFilters.toggle()
                } label: {
                    Label("筛选", systemImage: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .popover(isPresented: $showingFilters, arrowEdge: .bottom) {
                    LibraryFilterPopover(query: $query)
                        .padding()
                }
                Spacer()
                Slider(value: $thumbnailSize, in: 116...260, step: 4)
                    .frame(width: 120)
                    .accessibilityLabel("缩略图大小")
                Image(systemName: "rectangle.grid.2x2")
                    .foregroundStyle(.secondary)
                Button {
                    showsInspector.toggle()
                } label: {
                    Label(showsInspector ? "隐藏检查器" : "显示检查器", systemImage: "sidebar.right")
                }
                .help(showsInspector ? "隐藏检查器" : "显示检查器")
            }

            HStack(spacing: 8) {
                Text("\(assets.count) 个显示项目")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.hasMoreLibraryAssets {
                    Text("惰性加载中")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !selectedAssetIDs.isEmpty {
                    Menu {
                        ForEach(0...5, id: \.self) { rating in
                            Button("\(rating) 星") { setRating(rating) }
                        }
                    } label: {
                        Label("评分", systemImage: "star")
                    }
                    Menu {
                        Button("选取") { setFlag(.pick) }
                        Button("拒绝") { setFlag(.reject) }
                        Button("取消标记") { setFlag(.unflagged) }
                    } label: {
                        Label("标记", systemImage: "flag")
                    }
                    Menu {
                        ForEach(model.tags) { tag in
                            Button(tag.name) { addTag(tag) }
                        }
                    } label: {
                        Label("添加标签", systemImage: "tag")
                    }
                    Menu {
                        let manualAlbums = model.albums.filter { $0.kind == .album }
                        if manualAlbums.isEmpty {
                            Text("请先在侧边栏创建相册")
                        } else {
                            ForEach(manualAlbums) { album in
                                Button(album.name) { addToAlbum(album) }
                            }
                        }
                    } label: {
                        Label("添加到相册", systemImage: "rectangle.stack.badge.plus")
                    }
                    if query.albumID != nil {
                        Button("从当前相册移除", role: .destructive, action: removeFromCurrentAlbum)
                    }
                    Button {
                        showsStackCreator = true
                    } label: {
                        Label("创建堆栈", systemImage: "square.stack.3d.up")
                    }
                    .disabled(selectedAssets.count < 2)
                    if query.stackID != nil {
                        Button("从当前堆栈移除", role: .destructive, action: removeFromCurrentStack)
                    }
                    Menu {
                        Button("复制所有调整") {
                            guard let asset = selectedPhotoAssets.first else { return }
                            Task { _ = await model.copyPhotoEdits(from: asset.id) }
                        }
                        .disabled(selectedPhotoAssets.count != 1)
                        Button("从所选照片创建预设…") {
                            showsPresetNameSheet = true
                        }
                        .disabled(selectedPhotoAssets.count != 1)
                        Divider()
                        Menu("粘贴调整") {
                            Button("粘贴全部调整") {
                                Task { _ = await model.pastePhotoEdits(to: selectedPhotoAssets.map(\.id)) }
                            }
                            Button("选择性粘贴…") { showsSelectivePaste = true }
                        }
                        .disabled(!model.hasCopiedPhotoEdits || selectedPhotoAssets.isEmpty)
                        Menu("应用预设") {
                            if model.photoPresets.isEmpty {
                                Text("尚无预设")
                            } else {
                                ForEach(model.photoPresets) { preset in
                                    Button(preset.name) {
                                        Task { _ = await model.applyPhotoPreset(preset, to: selectedPhotoAssets.map(\.id)) }
                                    }
                                }
                            }
                        }
                        .disabled(selectedPhotoAssets.isEmpty)
                        Divider()
                        Button("管理预设…") { showsPresetManager = true }
                        Button("批量导出照片…") { showsBatchExport = true }
                        .disabled(selectedPhotoAssets.isEmpty)
                    } label: {
                        Label("编辑", systemImage: "slider.horizontal.3")
                    }
                    BatchTaskStatusSummary(model: model)
                    Text("已选择 \(selectedAssetIDs.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(role: .destructive) {
                        showsTrashConfirmation = true
                    } label: {
                        Label("移到废纸篓", systemImage: "trash")
                    }
                }
                Button {
                    scanExactDuplicates()
                    showsDuplicateResults = true
                } label: {
                    Label("查找精确重复项", systemImage: "doc.on.doc")
                }
                Button {
                    scanSimilarPhotos()
                    showsDuplicateResults = true
                } label: {
                    Label("查找相似照片", systemImage: "rectangle.3.group")
                }
                Button {
                    showsDuplicateResults = true
                } label: {
                    Label("重复/相似结果", systemImage: "list.bullet.rectangle")
                }
                .disabled(model.latestDuplicateScanReport == nil && model.latestSimilarPhotoScanReport == nil)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: thumbnailSize, maximum: thumbnailSize + 26), spacing: 12)],
                spacing: 14
            ) {
                ForEach(assets) { asset in
                    AssetThumbnailCell(
                        asset: asset,
                        selected: selectedAssetIDs.contains(asset.id),
                        groupedRAWPair: groupedRAWAssetIDs.contains(asset.id),
                        displaySize: thumbnailSize,
                        thumbnailPixelSize: thumbnailSize <= 180 ? 256 : 512,
                        model: model,
                        select: { select(asset.id, NSEvent.modifierFlags) },
                        preview: { previewAsset = asset }
                    )
                    .onAppear {
                        if asset.id == assets.last?.id {
                            Task { await model.loadMoreLibraryAssets() }
                        }
                    }
                }
                if model.isLoadingLibraryAssets {
                    ProgressView()
                        .padding()
                }
            }
            .padding(16)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(model.mediaRoots.isEmpty ? "尚未添加媒体文件夹" : "没有符合条件的媒体", systemImage: model.mediaRoots.isEmpty ? "folder.badge.plus" : "line.3.horizontal.decrease.circle")
        } description: {
            Text(model.mediaRoots.isEmpty ? "从“文件 → 添加文件夹到资料库…”选择目录。原始媒体不会被复制或修改。" : "调整搜索或筛选条件，或重新扫描资料库。")
        } actions: {
            if model.mediaRoots.isEmpty {
                Button("添加文件夹…", action: addFolder)
            } else if hasActiveFilters {
                Button("清除筛选") { query = .all }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { query.searchText ?? "" },
            set: { query.searchText = $0.isEmpty ? nil : $0 }
        )
    }

    private var hasActiveFilters: Bool {
        query != .all
    }

    private var selectedPhotoAssets: [LibraryAssetRecord] {
        assets.filter { selectedAssetIDs.contains($0.id) && $0.mediaType == .photo }
    }

    private var selectedAssets: [LibraryAssetRecord] {
        assets.filter { selectedAssetIDs.contains($0.id) }
    }

    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        switch keyPress.key {
        case .leftArrow:
            moveSelection(-1)
            return .handled
        case .rightArrow:
            moveSelection(1)
            return .handled
        case .upArrow:
            moveSelection(-4)
            return .handled
        case .downArrow:
            moveSelection(4)
            return .handled
        default:
            break
        }

        switch keyPress.characters.lowercased() {
        case "0", "1", "2", "3", "4", "5":
            if let rating = Int(keyPress.characters) { setRating(rating) }
            return .handled
        case "p":
            setFlag(.pick)
            return .handled
        case "x":
            setFlag(.reject)
            return .handled
        case "u":
            setFlag(.unflagged)
            return .handled
        case " ":
            if selectedAssetIDs.count == 1, let selectedID = selectedAssetIDs.first {
                previewAsset = assets.first(where: { $0.id == selectedID })
                return .handled
            }
            return .ignored
        default:
            return .ignored
        }
    }
}

private struct StackCreatorSheet: View {
    let assets: [LibraryAssetRecord]
    let create: (AssetStackKind, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var kind = AssetStackKind.user
    @State private var title = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("创建堆栈")
                .font(.headline)
            Picker("堆栈类型", selection: $kind) {
                ForEach(AssetStackKind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            TextField("堆栈名称（可选）", text: $title)
                .textFieldStyle(.roundedBorder)
            Text("将建立 \(assets.count) 个 Catalog 项目的虚拟堆栈；不会移动或合并原始文件。RAW + JPEG 类型仅接受同名的一对 RAW 与 JPEG。")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("创建") {
                    create(kind, title)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 410)
    }
}

private struct DuplicateResultsSheet: View {
    @ObservedObject var model: ApplicationModel
    let selectAssetInLibrary: (UUID) -> Void
    let openPreview: (LibraryAssetRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reviewAssetsByID: [UUID: LibraryAssetRecord] = [:]
    @State private var selectedReviewAssetIDs: Set<UUID> = []
    @State private var isLoadingReviewAssets = false
    @State private var showsStackCreator = false
    @State private var showsTrashConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("重复与相似照片")
                    .font(.headline)
                Spacer()
                Button("完成") { dismiss() }
            }
            Text("精确重复项先按文件大小分组，再以 SHA-256 确认。相似照片使用仅本地 dHash 的 Hamming 距离作为复核线索；两类分析都不会删除、移动或上传原始文件。")
                .font(.callout)
                .foregroundStyle(.secondary)
            similarReviewActions
            List {
                exactDuplicateSection
                similarPhotoSection
            }
            .frame(minHeight: 420)
            if isScanning {
                ProgressView("正在本地分析照片…")
            } else if model.latestDuplicateScanReport == nil && model.latestSimilarPhotoScanReport == nil {
                ContentUnavailableView("尚未运行重复或相似照片检测", systemImage: "rectangle.3.group")
            }
        }
        .padding(20)
        .frame(width: 980, height: 720)
        .task(id: reviewAssetIDs) {
            await loadReviewAssets()
        }
        .sheet(isPresented: $showsStackCreator) {
            StackCreatorSheet(assets: selectedReviewAssets) { kind, title in
                Task {
                    _ = await model.createStack(kind: kind, title: title, assets: selectedReviewAssets)
                }
            }
        }
        .confirmationDialog(
            "将所选原始文件移到废纸篓？",
            isPresented: $showsTrashConfirmation,
            titleVisibility: .visible
        ) {
            Button("移到废纸篓（\(selectedReviewAssets.count) 项）", role: .destructive) {
                moveSelectedReviewAssetsToTrash()
            }
        } message: {
            Text("此操作会请求 macOS 将实际源文件移到废纸篓，不会永久删除。Catalog 中的评分、标签和编辑记录会保留；相似检测不会自动处理任何项目。")
        }
    }

    private var isScanning: Bool {
        model.batchTasks.contains {
            ($0.kind == .duplicateHashing || $0.kind == .perceptualHashing) && !$0.state.isTerminal
        }
    }

    @ViewBuilder
    private var exactDuplicateSection: some View {
        if let report = model.latestDuplicateScanReport {
            Section("精确重复项") {
                Text("候选 \(report.candidateCount) 个；新计算 \(report.hashedCount) 个；复用有效哈希 \(report.reusedHashCount) 个；确认组 \(report.groups.count) 组。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(report.groups) { group in
                    Section("\(ByteCountFormatter.string(fromByteCount: group.fileSize, countStyle: .file)) · \(group.assets.count) 个项目") {
                        ForEach(group.assets) { asset in
                            Text(asset.relativePath)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
                if !report.failures.isEmpty {
                    Section("精确重复项无法验证") {
                        ForEach(report.failures, id: \.self) { failure in
                            Text(failure)
                                .foregroundStyle(.orange)
                                .textSelection(.enabled)
                        }
                    }
                }
                if report.groups.isEmpty {
                    Text("未发现已验证的精确重复项")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var similarPhotoSection: some View {
        if let report = model.latestSimilarPhotoScanReport {
            Section("相似照片（dHash）") {
                Text("候选 \(report.candidateCount) 张；新计算 \(report.hashedCount) 张；复用有效哈希 \(report.reusedHashCount) 张；相似组 \(report.groups.count) 组。缩略图来自本地 ThumbnailStore；分数是 dHash 像素结构接近度，不是语义识别或删除建议。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isLoadingReviewAssets {
                    ProgressView("正在读取相似组的 Catalog 元数据…")
                }
                ForEach(report.groups) { group in
                    SimilarPhotoGroupReviewCard(
                        group: group,
                        assets: reviewAssets(for: group),
                        model: model,
                        selectedAssetIDs: selectedReviewAssetIDs,
                        toggleSelection: toggleReviewSelection,
                        openPreview: openPreview
                    )
                }
                if !report.failures.isEmpty {
                    Section("相似照片无法分析") {
                        ForEach(report.failures, id: \.self) { failure in
                            Text(failure)
                                .foregroundStyle(.orange)
                                .textSelection(.enabled)
                        }
                    }
                }
                if report.groups.isEmpty {
                    Text("未发现达到当前 dHash 阈值的相似照片")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var similarReviewActions: some View {
        if !selectedReviewAssets.isEmpty {
            HStack(spacing: 8) {
                Text("相似组已选择 \(selectedReviewAssets.count) 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("打开预览") {
                    if let asset = selectedReviewAssets.first {
                        openPreview(asset)
                    }
                }
                Menu("评分") {
                    ForEach(0...5, id: \.self) { rating in
                        Button("\(rating) 星") { updateReviewRating(rating) }
                    }
                }
                Menu("标记") {
                    Button("选取") { updateReviewFlag(.pick) }
                    Button("拒绝") { updateReviewFlag(.reject) }
                    Button("取消标记") { updateReviewFlag(.unflagged) }
                }
                Menu("添加到相册") {
                    let manualAlbums = model.albums.filter { $0.kind == .album }
                    if manualAlbums.isEmpty {
                        Text("请先在侧边栏创建相册")
                    } else {
                        ForEach(manualAlbums) { album in
                            Button(album.name) { addReviewAssets(to: album) }
                        }
                    }
                }
                Button("创建堆栈…") { showsStackCreator = true }
                    .disabled(selectedReviewAssets.count < 2)
                Button("移到废纸篓", role: .destructive) {
                    showsTrashConfirmation = true
                }
                Spacer()
                Button("取消选择") { selectedReviewAssetIDs.removeAll() }
                    .buttonStyle(.borderless)
            }
            .controlSize(.small)
        }
    }

    private var reviewAssetIDs: [UUID] {
        guard let groups = model.latestSimilarPhotoScanReport?.groups else { return [] }
        var seen: Set<UUID> = []
        return groups.flatMap(\.assets).compactMap { candidate in
            seen.insert(candidate.id).inserted ? candidate.id : nil
        }
    }

    private var selectedReviewAssets: [LibraryAssetRecord] {
        reviewAssetIDs.compactMap { assetID in
            guard selectedReviewAssetIDs.contains(assetID) else { return nil }
            return reviewAssetsByID[assetID]
        }
    }

    private func reviewAssets(for group: SimilarPhotoGroup) -> [LibraryAssetRecord] {
        group.assets.compactMap { reviewAssetsByID[$0.id] }
    }

    private func loadReviewAssets() async {
        guard !reviewAssetIDs.isEmpty else {
            reviewAssetsByID = [:]
            selectedReviewAssetIDs.removeAll()
            return
        }
        isLoadingReviewAssets = true
        let assets = await model.similarPhotoReviewAssets(for: reviewAssetIDs)
        guard !Task.isCancelled else { return }
        reviewAssetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        selectedReviewAssetIDs.formIntersection(Set(reviewAssetsByID.keys))
        isLoadingReviewAssets = false
    }

    private func toggleReviewSelection(_ asset: LibraryAssetRecord) {
        if selectedReviewAssetIDs.contains(asset.id) {
            selectedReviewAssetIDs.remove(asset.id)
        } else {
            selectedReviewAssetIDs.insert(asset.id)
            selectAssetInLibrary(asset.id)
        }
    }

    private func updateReviewRating(_ rating: Int) {
        let assets = selectedReviewAssets
        Task {
            await model.setRating(rating, for: assets.map(\.id))
            await loadReviewAssets()
        }
    }

    private func updateReviewFlag(_ flag: AssetFlag) {
        let assets = selectedReviewAssets
        Task {
            await model.setFlag(flag, for: assets.map(\.id))
            await loadReviewAssets()
        }
    }

    private func addReviewAssets(to album: AlbumRecord) {
        let assetIDs = selectedReviewAssets.map(\.id)
        Task { await model.addAssets(assetIDs, toAlbum: album) }
    }

    private func moveSelectedReviewAssetsToTrash() {
        let assets = selectedReviewAssets.filter { $0.availability == .available }
        Task {
            let report = await model.moveAssetsToTrash(assets)
            if let report {
                selectedReviewAssetIDs.subtract(report.movedAssetIDs)
                await loadReviewAssets()
            }
        }
    }
}

private struct SimilarPhotoGroupReviewCard: View {
    let group: SimilarPhotoGroup
    let assets: [LibraryAssetRecord]
    @ObservedObject var model: ApplicationModel
    let selectedAssetIDs: Set<UUID>
    let toggleSelection: (LibraryAssetRecord) -> Void
    let openPreview: (LibraryAssetRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("相似组 · \(group.assets.count) 张", systemImage: "rectangle.3.group")
                    .font(.headline)
                Spacer()
                Text("最高相似度 \(group.highestSimilarityScore)%")
                    .font(.subheadline.weight(.semibold))
            }
            if assets.isEmpty {
                ContentUnavailableView(
                    "相似组元数据不可用",
                    systemImage: "externaldrive.badge.xmark",
                    description: Text("Catalog 记录可能已被移除；不会为结果 UI 读取全分辨率原文件。")
                )
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(assets) { asset in
                            SimilarPhotoReviewThumbnail(
                                item: SimilarPhotoReviewItem(asset: asset),
                                selected: selectedAssetIDs.contains(asset.id),
                                model: model,
                                toggleSelection: { toggleSelection(asset) },
                                openPreview: { openPreview(asset) }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(minHeight: 255)
            }
            if !group.matches.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("形成分组的连接")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(group.matches) { match in
                        Text("\(match.first.relativePath) ↔ \(match.second.relativePath) · \(match.similarityScore)% · Hamming \(match.hammingDistance)/64")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct SimilarPhotoReviewThumbnail: View {
    let item: SimilarPhotoReviewItem
    let selected: Bool
    @ObservedObject var model: ApplicationModel
    let toggleSelection: () -> Void
    let openPreview: () -> Void
    @State private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color(nsColor: .windowBackgroundColor))
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .frame(width: 164, height: 124)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                Button(action: toggleSelection) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : .white)
                        .font(.title3)
                        .padding(5)
                        .background(.black.opacity(0.42), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(6)
            }
            Text(item.asset.filename)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text("\(item.dimensionsText) · \(item.fileSizeText)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("\(item.ratingText) · \(item.flagText)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(item.formatText)
                .font(.caption2.weight(.medium))
                .foregroundStyle(RAWFormat.isRAW(item.asset.fileExtension) ? .orange : .secondary)
            Text(item.asset.displayDate?.formatted(date: .abbreviated, time: .omitted) ?? "拍摄日期未知")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 6) {
                Button(selected ? "取消选择" : "选择", action: toggleSelection)
                Button("预览", action: openPreview)
            }
            .controlSize(.mini)
        }
        .frame(width: 164, alignment: .leading)
        .padding(6)
        .background(selected ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(selected ? Color.accentColor : .clear, lineWidth: 1.5)
        }
        .task(id: item.id) {
            image = nil
            guard let data = await model.thumbnailData(for: item.asset, maximumPixelSize: 256), !Task.isCancelled else { return }
            image = NSImage(data: data)
        }
        .accessibilityLabel("\(item.asset.filename)，\(item.dimensionsText)，\(item.fileSizeText)，\(item.ratingText)，\(item.flagText)，\(item.formatText)")
    }
}

private struct LibraryFilterPopover: View {
    @Binding var query: LibraryQuery
    @State private var dateScope: DateScope = .all

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("组合筛选")
                    .font(.headline)
                Spacer()
                Button("重置") { query = .all; dateScope = .all }
                    .buttonStyle(.borderless)
            }
            Picker("媒体类型", selection: mediaTypeBinding) {
                Text("全部").tag(MediaType?.none)
                Text("照片").tag(MediaType?.some(.photo))
                Text("视频").tag(MediaType?.some(.video))
            }
            Picker("最低评分", selection: ratingBinding) {
                Text("不限").tag(Int?.none)
                ForEach(1...5, id: \.self) { rating in
                    Text("\(rating) 星及以上").tag(Int?.some(rating))
                }
            }
            Picker("Flag", selection: flagBinding) {
                Text("不限").tag(AssetFlag?.none)
                Text("已选取").tag(AssetFlag?.some(.pick))
                Text("已拒绝").tag(AssetFlag?.some(.reject))
                Text("未标记").tag(AssetFlag?.some(.unflagged))
            }
            Picker("日期", selection: $dateScope) {
                ForEach(DateScope.allCases) { scope in Text(scope.title).tag(scope) }
            }
            .onChange(of: dateScope) { _, scope in
                let calendar = Calendar.current
                query.captureDateFrom = scope.startDate(using: calendar)
                query.captureDateTo = nil
            }
            TextField("相机", text: optionalBinding(\.camera))
            TextField("镜头", text: optionalBinding(\.lens))
        }
        .frame(width: 265)
    }

    private var mediaTypeBinding: Binding<MediaType?> {
        Binding(get: { query.mediaType }, set: { query.mediaType = $0 })
    }

    private var ratingBinding: Binding<Int?> {
        Binding(get: { query.minimumRating }, set: { query.minimumRating = $0 })
    }

    private var flagBinding: Binding<AssetFlag?> {
        Binding(get: { query.flag }, set: { query.flag = $0 })
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<LibraryQuery, String?>) -> Binding<String> {
        Binding(
            get: { query[keyPath: keyPath] ?? "" },
            set: { query[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }
}

private enum DateScope: String, CaseIterable, Identifiable {
    case all
    case week
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "不限"
        case .week: "最近 7 天"
        case .month: "最近 30 天"
        case .year: "最近一年"
        }
    }

    func startDate(using calendar: Calendar) -> Date? {
        switch self {
        case .all: nil
        case .week: calendar.date(byAdding: .day, value: -7, to: .now)
        case .month: calendar.date(byAdding: .day, value: -30, to: .now)
        case .year: calendar.date(byAdding: .year, value: -1, to: .now)
        }
    }
}

private struct AssetThumbnailCell: View {
    let asset: LibraryAssetRecord
    let selected: Bool
    let groupedRAWPair: Bool
    let displaySize: CGFloat
    let thumbnailPixelSize: Int
    @ObservedObject var model: ApplicationModel
    let select: () -> Void
    let preview: () -> Void
    @State private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color(nsColor: .windowBackgroundColor))
                            .overlay {
                                Image(systemName: asset.mediaType == .photo ? "photo" : "film")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .frame(height: max(92, min(displaySize * 0.72, 190)))
                .clipShape(RoundedRectangle(cornerRadius: 7))

                HStack(spacing: 4) {
                    if groupedRAWPair { Label("RAW+JPEG", systemImage: "rectangle.stack") }
                    if asset.mediaType == .video, let duration = asset.duration {
                        Text(videoDurationText(duration))
                    }
                    if asset.videoIsHDR == true { Text("HDR") }
                    if asset.flag == .pick { Image(systemName: "flag.fill") }
                    if asset.flag == .reject { Image(systemName: "flag.slash.fill") }
                    if asset.availability != .available { Image(systemName: "externaldrive.badge.xmark") }
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(5)
                .background(.black.opacity(0.5), in: Capsule())
                .padding(5)
            }
            HStack(spacing: 3) {
                Text(asset.filename)
                    .font(.caption)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if asset.rating > 0 {
                    Text(String(repeating: "★", count: asset.rating))
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
            }
        }
        .padding(5)
        .background(selected ? Color.accentColor.opacity(0.19) : .clear, in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(selected ? Color.accentColor : .clear, lineWidth: 2)
        }
        .contentShape(Rectangle())
        .onTapGesture { select() }
        .onTapGesture(count: 2) { preview() }
        .task(id: "\(asset.id.uuidString)-\(thumbnailPixelSize)") {
            image = nil
            guard let data = await model.thumbnailData(for: asset, maximumPixelSize: thumbnailPixelSize), !Task.isCancelled else { return }
            image = NSImage(data: data)
        }
        .accessibilityLabel(asset.filename)
        .accessibilityValue([selected ? "已选择" : nil, groupedRAWPair ? "RAW 与 JPEG 组合" : nil].compactMap { $0 }.joined(separator: "，"))
    }

    private func videoDurationText(_ duration: Double) -> String {
        let seconds = max(0, Int(duration.rounded(.down)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
