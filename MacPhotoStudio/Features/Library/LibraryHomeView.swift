import AppKit
import SwiftUI

struct LibraryHomeView: View {
    @ObservedObject var model: ApplicationModel

    @AppStorage("library.showsInspector") private var showsInspector = true
    @AppStorage("library.rawJPEGPairPreference") private var rawJPEGPairPreferenceRaw = RAWJPEGPairPreference.showBoth.rawValue
    @State private var query = LibraryQuery.all
    @State private var selectedAssetIDs: Set<UUID> = []
    @State private var selectionAnchor: UUID?
    @State private var previewAsset: LibraryAssetRecord?
    @State private var thumbnailSize: CGFloat = 180
    @State private var tagEditor: TagEditorContext?
    @State private var albumEditor: AlbumEditorContext?
    @FocusState private var gridIsFocused: Bool

    var body: some View {
        Group {
            switch model.startupState {
            case .starting:
                ProgressView("正在准备本地资料库…")
                    .frame(minWidth: 860, minHeight: 560)
            case .ready:
                libraryContent
            case .failed(let message):
                ContentUnavailableView(
                    "无法初始化 Catalog",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
                .frame(minWidth: 860, minHeight: 560)
            }
        }
        .task(id: model.startupState) {
            while case .ready = model.startupState {
                try? await Task.sleep(for: .milliseconds(500))
                await model.refreshLibrary()
            }
        }
        .onChange(of: query) { _, newQuery in
            selectedAssetIDs.removeAll()
            selectionAnchor = nil
            Task { await model.reloadLibraryAssets(query: newQuery) }
        }
        .onChange(of: model.libraryAssets.map(\.id)) { _, availableIDs in
            selectedAssetIDs.formIntersection(Set(availableIDs))
            if selectedAssetIDs.count != 1 {
                Task { await model.loadTags(for: nil) }
            } else {
                Task { await model.loadTags(for: selectedAssetIDs.first) }
            }
        }
        .onChange(of: rawJPEGPairPreferenceRaw) { _, _ in
            selectedAssetIDs.formIntersection(Set(visibleLibraryAssets.map(\.id)))
            if selectedAssetIDs.count != 1 {
                Task { await model.loadTags(for: nil) }
            }
        }
        .sheet(item: $tagEditor) { context in
            TagEditorSheet(context: context, model: model)
        }
        .sheet(item: $albumEditor) { context in
            AlbumEditorSheet(context: context, model: model)
        }
        .sheet(item: $previewAsset) { asset in
            if asset.mediaType == .video {
                VideoPreviewSheet(asset: asset, applicationModel: model)
            } else {
                AssetPreviewSheet(asset: asset, model: model)
            }
        }
    }

    private var libraryContent: some View {
        HSplitView {
            LibrarySidebar(
                model: model,
                query: query,
                selectAll: { updateQuery { $0 = .all } },
                selectRoot: { rootID in updateQuery { $0.rootID = rootID } },
                selectMediaType: { mediaType in updateQuery { $0.mediaType = mediaType } },
                selectMinimumRating: { rating in updateQuery { $0.minimumRating = rating } },
                selectFlag: { flag in updateQuery { $0.flag = flag } },
                selectTag: { tagID in updateQuery { $0.tagID = tagID } },
                selectAlbum: selectAlbum,
                selectStack: { stack in updateQuery { $0 = LibraryQuery(stackID: stack.id) } },
                addTag: { tagEditor = TagEditorContext(tag: nil) },
                editTag: { tagEditor = TagEditorContext(tag: $0) },
                deleteTag: { tag in Task { await model.deleteTag(tag) } },
                addAlbum: { albumEditor = AlbumEditorContext(album: nil, kind: .album) },
                addSmartAlbum: { albumEditor = AlbumEditorContext(album: nil, kind: .smartAlbum) },
                editAlbum: { albumEditor = AlbumEditorContext(album: $0, kind: $0.kind) },
                deleteAlbum: { album in Task { await model.deleteAlbum(album) } },
                deleteStack: { stack in Task { await model.deleteStack(stack) } },
                rescanRoot: { rootID in Task { await model.startScan(for: rootID) } },
                relinkRoot: model.presentRelinkPanel,
                rawJPEGPairPreference: $rawJPEGPairPreferenceRaw
            )
            .frame(minWidth: 185, idealWidth: 230, maxWidth: 300)

            AssetBrowserView(
                model: model,
                assets: visibleLibraryAssets,
                groupedRAWAssetIDs: rawJPEGPairPreference == .groupPairs ? RAWJPEGPairing.pairedRAWAssetIDs(in: model.libraryAssets) : [],
                query: $query,
                selectedAssetIDs: $selectedAssetIDs,
                selectionAnchor: $selectionAnchor,
                previewAsset: $previewAsset,
                thumbnailSize: $thumbnailSize,
                showsInspector: $showsInspector,
                gridIsFocused: $gridIsFocused,
                addFolder: model.presentAddFolderPanel,
                setRating: setRating,
                setFlag: setFlag,
                addTag: addTagToSelection,
                addToAlbum: { album in
                    Task { await model.addAssets(Array(selectedAssetIDs), toAlbum: album) }
                },
                removeFromCurrentAlbum: removeSelectionFromCurrentAlbum,
                createStack: { kind, title in
                    Task { _ = await model.createStack(kind: kind, title: title, assets: selectedAssets) }
                },
                removeFromCurrentStack: removeSelectionFromCurrentStack,
                scanDuplicates: { Task { _ = await model.startExactDuplicateScan() } },
                moveToTrash: { assets in Task { _ = await model.moveAssetsToTrash(assets) } },
                select: select,
                moveSelection: moveSelection
            )
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)

            if showsInspector {
                LibraryInspectorView(
                    asset: selectedAsset,
                    tags: model.selectedAssetTags,
                    allTags: model.tags,
                    close: { showsInspector = false },
                    setRating: setRating,
                    setFlag: setFlag,
                    addTag: addTagToSelection,
                    removeTag: { tag in
                        guard let assetID = selectedAsset?.id else { return }
                        Task { await model.removeTag(tag, from: [assetID]) }
                    }
                )
                .frame(minWidth: 230, idealWidth: 285, maxWidth: 360)
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .overlay(alignment: .top) {
            if let error = model.libraryError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
    }

    private var selectedAsset: LibraryAssetRecord? {
        guard selectedAssetIDs.count == 1, let assetID = selectedAssetIDs.first else { return nil }
        return model.libraryAssets.first(where: { $0.id == assetID })
    }

    private var selectedAssets: [LibraryAssetRecord] {
        visibleLibraryAssets.filter { selectedAssetIDs.contains($0.id) }
    }

    private var rawJPEGPairPreference: RAWJPEGPairPreference {
        RAWJPEGPairPreference(rawValue: rawJPEGPairPreferenceRaw) ?? .showBoth
    }

    private var visibleLibraryAssets: [LibraryAssetRecord] {
        RAWJPEGPairing.visibleAssets(from: model.libraryAssets, preference: rawJPEGPairPreference)
    }

    private func updateQuery(_ change: (inout LibraryQuery) -> Void) {
        var updated = query
        change(&updated)
        query = updated
    }

    private func select(_ assetID: UUID, modifiers: NSEvent.ModifierFlags) {
        let normalizedModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
        let assets = visibleLibraryAssets
        guard let selectedIndex = assets.firstIndex(where: { $0.id == assetID }) else { return }

        if normalizedModifiers.contains(.shift), let selectionAnchor,
           let anchorIndex = assets.firstIndex(where: { $0.id == selectionAnchor }) {
            let lower = min(anchorIndex, selectedIndex)
            let upper = max(anchorIndex, selectedIndex)
            selectedAssetIDs = Set(assets[lower...upper].map(\.id))
        } else if normalizedModifiers.contains(.command) {
            if selectedAssetIDs.contains(assetID) {
                selectedAssetIDs.remove(assetID)
            } else {
                selectedAssetIDs.insert(assetID)
            }
            selectionAnchor = assetID
        } else {
            selectedAssetIDs = [assetID]
            selectionAnchor = assetID
        }
        gridIsFocused = true
        Task { await model.loadTags(for: selectedAssetIDs.count == 1 ? selectedAssetIDs.first : nil) }
    }

    private func moveSelection(by offset: Int) {
        let assets = visibleLibraryAssets
        guard !assets.isEmpty else { return }
        let currentIndex = selectionAnchor.flatMap { id in assets.firstIndex(where: { $0.id == id }) } ?? 0
        let nextIndex = min(max(0, currentIndex + offset), assets.count - 1)
        let nextID = assets[nextIndex].id
        selectedAssetIDs = [nextID]
        selectionAnchor = nextID
        Task { await model.loadTags(for: nextID) }
    }

    private func setRating(_ rating: Int) {
        guard !selectedAssetIDs.isEmpty else { return }
        Task { await model.setRating(rating, for: Array(selectedAssetIDs)) }
    }

    private func setFlag(_ flag: AssetFlag) {
        guard !selectedAssetIDs.isEmpty else { return }
        Task { await model.setFlag(flag, for: Array(selectedAssetIDs)) }
    }

    private func addTagToSelection(_ tag: TagRecord) {
        guard !selectedAssetIDs.isEmpty else { return }
        Task { await model.addTag(tag, to: Array(selectedAssetIDs)) }
    }

    private func selectAlbum(_ album: AlbumRecord) {
        switch album.kind {
        case .album:
            updateQuery { $0 = LibraryQuery(albumID: album.id) }
        case .smartAlbum:
            updateQuery { $0 = LibraryQuery(smartAlbumCriteria: album.criteria ?? .all) }
        }
    }

    private func removeSelectionFromCurrentAlbum() {
        guard let albumID = query.albumID,
              let album = model.albums.first(where: { $0.id == albumID }),
              !selectedAssetIDs.isEmpty
        else { return }
        Task { await model.removeAssets(Array(selectedAssetIDs), fromAlbum: album) }
    }

    private func removeSelectionFromCurrentStack() {
        guard let stackID = query.stackID,
              let stack = model.assetStacks.first(where: { $0.id == stackID }),
              !selectedAssetIDs.isEmpty
        else { return }
        Task { await model.removeAssets(Array(selectedAssetIDs), fromStack: stack) }
    }
}

private struct TagEditorContext: Identifiable {
    let id = UUID()
    let tag: TagRecord?
}

private struct AlbumEditorContext: Identifiable {
    let id = UUID()
    let album: AlbumRecord?
    let kind: AlbumKind
}

private struct TagEditorSheet: View {
    let context: TagEditorContext
    @ObservedObject var model: ApplicationModel
    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(context: TagEditorContext, model: ApplicationModel) {
        self.context = context
        self.model = model
        _name = State(initialValue: context.tag?.name ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(context.tag == nil ? "新建标签" : "重命名标签")
                .font(.headline)
            TextField("标签名称", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func save() {
        let proposedName = name
        Task {
            if let tag = context.tag {
                await model.renameTag(tag, to: proposedName)
            } else {
                _ = await model.createTag(named: proposedName)
            }
            dismiss()
        }
    }
}

private struct AlbumEditorSheet: View {
    let context: AlbumEditorContext
    @ObservedObject var model: ApplicationModel
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var minimumRating: Int
    @State private var useCaptureDate: Bool
    @State private var captureDateFrom: Date
    @State private var captureDateTo: Date
    @State private var camera: String
    @State private var lens: String
    @State private var selectedTagID: UUID?
    @State private var mediaType: MediaType?
    @State private var editedFilter = -1
    @State private var rawFilter = -1

    init(context: AlbumEditorContext, model: ApplicationModel) {
        self.context = context
        self.model = model
        let criteria = context.album?.criteria ?? .all
        _name = State(initialValue: context.album?.name ?? "")
        _minimumRating = State(initialValue: criteria.minimumRating ?? 0)
        _useCaptureDate = State(initialValue: criteria.captureDateFrom != nil || criteria.captureDateTo != nil)
        _captureDateFrom = State(initialValue: criteria.captureDateFrom ?? Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .now)
        _captureDateTo = State(initialValue: criteria.captureDateTo ?? .now)
        _camera = State(initialValue: criteria.camera ?? "")
        _lens = State(initialValue: criteria.lens ?? "")
        _selectedTagID = State(initialValue: criteria.tagID)
        _mediaType = State(initialValue: criteria.mediaType)
        _editedFilter = State(initialValue: criteria.isEdited.map { $0 ? 1 : 0 } ?? -1)
        _rawFilter = State(initialValue: criteria.isRAW.map { $0 ? 1 : 0 } ?? -1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(context.album == nil ? (context.kind == .album ? "新建相册" : "新建智能相册") : "编辑\(context.kind == .album ? "相册" : "智能相册")")
                .font(.headline)
            TextField("名称", text: $name)
                .textFieldStyle(.roundedBorder)
            if context.kind == .smartAlbum {
                Form {
                    Picker("最低评分", selection: $minimumRating) {
                        Text("不限").tag(0)
                        ForEach(1...5, id: \.self) { rating in Text("\(rating) 星及以上").tag(rating) }
                    }
                    Toggle("按拍摄日期筛选", isOn: $useCaptureDate)
                    if useCaptureDate {
                        DatePicker("开始", selection: $captureDateFrom, displayedComponents: .date)
                        DatePicker("结束", selection: $captureDateTo, in: captureDateFrom..., displayedComponents: .date)
                    }
                    TextField("相机包含", text: $camera)
                    TextField("镜头包含", text: $lens)
                    Picker("标签", selection: $selectedTagID) {
                        Text("不限").tag(UUID?.none)
                        ForEach(model.tags) { tag in Text(tag.name).tag(UUID?.some(tag.id)) }
                    }
                    Picker("媒体类型", selection: $mediaType) {
                        Text("不限").tag(MediaType?.none)
                        Text("照片").tag(MediaType?.some(.photo))
                        Text("视频").tag(MediaType?.some(.video))
                    }
                    Picker("是否已编辑", selection: $editedFilter) {
                        Text("不限").tag(-1)
                        Text("已编辑").tag(1)
                        Text("未编辑").tag(0)
                    }
                    Picker("是否 RAW", selection: $rawFilter) {
                        Text("不限").tag(-1)
                        Text("RAW").tag(1)
                        Text("非 RAW").tag(0)
                    }
                }
                .formStyle(.grouped)
            } else {
                Text("相册仅保存 Catalog 中的虚拟引用，不会移动或复制原始媒体文件。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: context.kind == .smartAlbum ? 460 : 360)
    }

    private func save() {
        let proposedName = name
        let criteria = SmartAlbumCriteria(
            minimumRating: minimumRating == 0 ? nil : minimumRating,
            captureDateFrom: useCaptureDate ? captureDateFrom : nil,
            captureDateTo: useCaptureDate ? Calendar.current.date(byAdding: .day, value: 1, to: captureDateTo) : nil,
            camera: camera.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : camera,
            lens: lens.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : lens,
            tagID: selectedTagID,
            mediaType: mediaType,
            isEdited: editedFilter == -1 ? nil : editedFilter == 1,
            isRAW: rawFilter == -1 ? nil : rawFilter == 1
        )
        Task {
            if let album = context.album {
                await model.renameAlbum(album, to: proposedName)
                if context.kind == .smartAlbum {
                    await model.updateSmartAlbum(album, criteria: criteria)
                }
            } else if context.kind == .smartAlbum {
                _ = await model.createSmartAlbum(named: proposedName, criteria: criteria)
            } else {
                _ = await model.createAlbum(named: proposedName)
            }
            dismiss()
        }
    }
}

private struct AssetPreviewSheet: View {
    let asset: LibraryAssetRecord
    @ObservedObject var model: ApplicationModel
    @Environment(\.dismiss) private var dismiss
    @State private var image: NSImage?
    @State private var editorAsset: LibraryAssetRecord?
    @State private var rawEditorAsset: LibraryAssetRecord?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label(asset.filename, systemImage: asset.mediaType == .photo ? "photo" : "film")
                    .lineLimit(1)
                Spacer()
                if asset.mediaType == .photo {
                    Button("编辑") {
                        if RAWFormat.isRAW(asset.fileExtension) { rawEditorAsset = asset } else { editorAsset = asset }
                    }
                }
                Button("完成") { dismiss() }
            }
            .padding(.horizontal)
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ContentUnavailableView(
                        "预览不可用",
                        systemImage: asset.availability == .offline ? "externaldrive.badge.xmark" : "photo",
                        description: Text("原文件不可访问且没有可用的本地缩略图。")
                    )
                }
            }
            .frame(minWidth: 520, minHeight: 360)
            .padding(.horizontal)
        }
        .padding(.vertical)
        .task(id: asset.id) {
            guard let data = await model.thumbnailData(for: asset, maximumPixelSize: 512), !Task.isCancelled else { return }
            image = NSImage(data: data)
        }
        .sheet(item: $editorAsset) { editorAsset in
            PhotoEditorView(asset: editorAsset, model: model)
        }
        .sheet(item: $rawEditorAsset) { rawEditorAsset in
            RAWPhotoEditorView(asset: rawEditorAsset, model: model)
        }
    }
}
