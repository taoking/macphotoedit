import AppKit
import SwiftUI

struct AssetBrowserView: View {
    @ObservedObject var model: ApplicationModel
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
    let select: (UUID, NSEvent.ModifierFlags) -> Void
    let moveSelection: (Int) -> Void
    @State private var showingFilters = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if model.libraryAssets.isEmpty, !model.isLoadingLibraryAssets {
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
                Text("\(model.libraryAssets.count) 个已加载项目")
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
                    Text("已选择 \(selectedAssetIDs.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                ForEach(model.libraryAssets) { asset in
                    AssetThumbnailCell(
                        asset: asset,
                        selected: selectedAssetIDs.contains(asset.id),
                        displaySize: thumbnailSize,
                        thumbnailPixelSize: thumbnailSize <= 180 ? 256 : 512,
                        model: model,
                        select: { select(asset.id, NSEvent.modifierFlags) },
                        preview: { previewAsset = asset }
                    )
                    .onAppear {
                        if asset.id == model.libraryAssets.last?.id {
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
        query.searchText != nil || query.rootID != nil || query.mediaType != nil || query.minimumRating != nil || query.flag != nil || query.tagID != nil || query.captureDateFrom != nil || query.camera != nil || query.lens != nil
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
                previewAsset = model.libraryAssets.first(where: { $0.id == selectedID })
                return .handled
            }
            return .ignored
        default:
            return .ignored
        }
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
        .accessibilityValue(selected ? "已选择" : "")
    }
}
