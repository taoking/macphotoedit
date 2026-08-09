import SwiftUI

struct LibrarySidebar: View {
    @ObservedObject var model: ApplicationModel
    let query: LibraryQuery
    let selectAll: () -> Void
    let selectRoot: (UUID?) -> Void
    let selectMediaType: (MediaType?) -> Void
    let selectMinimumRating: (Int?) -> Void
    let selectFlag: (AssetFlag?) -> Void
    let selectTag: (UUID?) -> Void
    let selectAlbum: (AlbumRecord) -> Void
    let selectStack: (AssetStackRecord) -> Void
    let addTag: () -> Void
    let editTag: (TagRecord) -> Void
    let deleteTag: (TagRecord) -> Void
    let addAlbum: () -> Void
    let addSmartAlbum: () -> Void
    let editAlbum: (AlbumRecord) -> Void
    let deleteAlbum: (AlbumRecord) -> Void
    let deleteStack: (AssetStackRecord) -> Void
    let rescanRoot: (UUID) -> Void
    let relinkRoot: (MediaRootRecord) -> Void
    @Binding var rawJPEGPairPreference: String

    var body: some View {
        List {
            Section("资料库") {
                sidebarButton("所有媒体", systemImage: "rectangle.stack", selected: isAllSelected) {
                    selectAll()
                }
                sidebarButton("照片", systemImage: "photo", selected: query.mediaType == .photo) {
                    selectMediaType(.photo)
                }
                sidebarButton("视频", systemImage: "film", selected: query.mediaType == .video) {
                    selectMediaType(.video)
                }
            }

            Section("来源") {
                ForEach(model.mediaRoots) { root in
                    Button {
                        selectRoot(root.id)
                    } label: {
                        HStack(spacing: 6) {
                            Label(root.displayName, systemImage: root.availability == .online ? "folder" : "externaldrive.badge.exclamationmark")
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if root.availability != .online {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(.orange)
                                    .help("根目录当前不可访问；已缓存的缩略图仍可浏览。")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(query.rootID == root.id ? Color.accentColor : Color.primary)
                    .contextMenu {
                        Button("重新扫描") { rescanRoot(root.id) }
                        Button("重新定位文件夹…") { relinkRoot(root) }
                    }
                }
                if model.mediaRoots.isEmpty {
                    Label("尚未添加来源", systemImage: "folder.badge.plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("使用工具栏中的“添加媒体文件夹”建立引用式资料库。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("整理") {
                organizationHeader("相册", systemImage: "rectangle.stack", addAction: addAlbum, help: "新建相册")
                ForEach(model.albums.filter { $0.kind == .album }) { album in
                    Button {
                        selectAlbum(album)
                    } label: {
                        Label(album.name, systemImage: "rectangle.stack")
                            .foregroundStyle(query.albumID == album.id ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("重命名") { editAlbum(album) }
                        Button("删除", role: .destructive) { deleteAlbum(album) }
                    }
                }

                organizationHeader("智能相册", systemImage: "gearshape.2", addAction: addSmartAlbum, help: "新建智能相册")
                ForEach(model.albums.filter { $0.kind == .smartAlbum }) { album in
                    Button {
                        selectAlbum(album)
                    } label: {
                        Label(album.name, systemImage: "gearshape.2")
                            .foregroundStyle(query.smartAlbumCriteria == album.criteria ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("编辑规则…") { editAlbum(album) }
                        Button("删除", role: .destructive) { deleteAlbum(album) }
                    }
                }

                organizationHeader("堆栈", systemImage: "square.stack.3d.up")
                ForEach(model.assetStacks) { stack in
                    Button {
                        selectStack(stack)
                    } label: {
                        Label("\(stack.title)（\(stack.assetCount)）", systemImage: "square.stack.3d.up")
                            .foregroundStyle(query.stackID == stack.id ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("删除堆栈", role: .destructive) { deleteStack(stack) }
                    }
                }
                if model.assetStacks.isEmpty {
                    Text("选择至少两项后，可从“整理”创建堆栈")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                organizationHeader("标签", systemImage: "tag", addAction: addTag, help: "新建标签")
                ForEach(model.tags) { tag in
                    Button {
                        selectTag(tag.id)
                    } label: {
                        Label(tag.name, systemImage: "tag")
                            .foregroundStyle(query.tagID == tag.id ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("重命名") { editTag(tag) }
                        Button("删除", role: .destructive) { deleteTag(tag) }
                    }
                }
            }

            Section("筛选") {
                Menu {
                    Button("不限") { selectMinimumRating(nil) }
                    ForEach(Array((1...5).reversed()), id: \.self) { rating in
                        Button("\(rating) 星及以上") { selectMinimumRating(rating) }
                    }
                } label: {
                    Label(minimumRatingTitle, systemImage: "star")
                }

                Menu {
                    Button("不限") { selectFlag(nil) }
                    Button("已选取") { selectFlag(.pick) }
                    Button("已拒绝") { selectFlag(.reject) }
                } label: {
                    Label(flagTitle, systemImage: query.flag == .reject ? "flag.slash" : "flag")
                }

                Picker("RAW + JPEG", selection: $rawJPEGPairPreference) {
                    ForEach(RAWJPEGPairPreference.allCases, id: \.rawValue) { preference in
                        Text(preference.title).tag(preference.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .listStyle(.sidebar)
    }

    private var isAllSelected: Bool {
        query == .all
    }

    private func sidebarButton(
        _ title: String,
        systemImage: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private var minimumRatingTitle: String {
        guard let rating = query.minimumRating else { return "评分不限" }
        return "\(rating) 星及以上"
    }

    private var flagTitle: String {
        switch query.flag {
        case .pick: "已选取"
        case .reject: "已拒绝"
        default: "标记不限"
        }
    }

    private func organizationHeader(
        _ title: String,
        systemImage: String,
        addAction: (() -> Void)? = nil,
        help: String? = nil
    ) -> some View {
        HStack(spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if let addAction {
                Button(action: addAction) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help(help ?? "新建\(title)")
                .accessibilityLabel(help ?? "新建\(title)")
            }
        }
        .padding(.top, 3)
    }
}
