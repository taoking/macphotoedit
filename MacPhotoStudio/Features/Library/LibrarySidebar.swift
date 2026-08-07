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

            Section("文件夹") {
                ForEach(model.mediaRoots) { root in
                    HStack(spacing: 6) {
                        Button {
                            selectRoot(root.id)
                        } label: {
                            Label(root.displayName, systemImage: root.availability == .online ? "folder" : "externaldrive.badge.exclamationmark")
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(query.rootID == root.id ? Color.accentColor : Color.primary)
                        Spacer(minLength: 0)
                        if root.availability != .online {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.orange)
                                .help("根目录当前不可访问；已缓存的缩略图仍可浏览。")
                        }
                        Button {
                            rescanRoot(root.id)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("重新扫描")
                    }
                    .contextMenu {
                        Button("重新定位文件夹…") { relinkRoot(root) }
                    }
                }
                if model.mediaRoots.isEmpty {
                    Text("尚未添加文件夹")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
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
            } header: {
                HStack {
                    Text("相册")
                    Spacer()
                    Button(action: addAlbum) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("新建相册")
                }
            }

            Section {
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
            } header: {
                HStack {
                    Text("智能相册")
                    Spacer()
                    Button(action: addSmartAlbum) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("新建智能相册")
                }
            }

            Section("堆栈") {
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
            }

            Section("评分") {
                ForEach(Array((1...5).reversed()), id: \.self) { rating in
                    sidebarButton("\(rating) 星及以上", systemImage: "star.fill", selected: query.minimumRating == rating) {
                        selectMinimumRating(rating)
                    }
                }
            }

            Section("标记") {
                sidebarButton("已选取", systemImage: "flag.fill", selected: query.flag == .pick) {
                    selectFlag(.pick)
                }
                sidebarButton("已拒绝", systemImage: "flag.slash.fill", selected: query.flag == .reject) {
                    selectFlag(.reject)
                }
            }

            Section("RAW + JPEG") {
                Picker("显示方式", selection: $rawJPEGPairPreference) {
                    ForEach(RAWJPEGPairPreference.allCases, id: \.rawValue) { preference in
                        Text(preference.title).tag(preference.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }

            Section {
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
            } header: {
                HStack {
                    Text("标签")
                    Spacer()
                    Button(action: addTag) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("新建标签")
                }
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
}
