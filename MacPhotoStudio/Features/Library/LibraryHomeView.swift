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
        .sheet(item: $previewAsset) { asset in
            AssetPreviewSheet(asset: asset, model: model)
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
                addTag: { tagEditor = TagEditorContext(tag: nil) },
                editTag: { tagEditor = TagEditorContext(tag: $0) },
                deleteTag: { tag in Task { await model.deleteTag(tag) } },
                rescanRoot: { rootID in Task { await model.startScan(for: rootID) } },
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
}

private struct TagEditorContext: Identifiable {
    let id = UUID()
    let tag: TagRecord?
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
