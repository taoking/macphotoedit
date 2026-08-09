import SwiftUI

struct LibrarySidebar: View {
    @ObservedObject var model: ApplicationModel
    @Binding var selection: LibraryLocation?
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

    var body: some View {
        List(selection: $selection) {
            Section("资料库") {
                navigationRow("所有媒体", systemImage: "rectangle.stack", location: .all)
                navigationRow("照片", systemImage: "photo", location: .photos)
                navigationRow("视频", systemImage: "film", location: .videos)
            }

            Section("来源") {
                ForEach(model.mediaRoots) { root in
                    HStack(spacing: 6) {
                        Label(root.displayName, systemImage: root.availability == .online ? "folder" : "externaldrive.badge.exclamationmark")
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if root.availability != .online {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.orange)
                                .help("根目录当前不可访问；已缓存的缩略图仍可浏览。")
                                .accessibilityLabel("来源当前不可访问")
                                .accessibilityHint(root.lastScanError ?? "已缓存的缩略图仍可浏览。")
                        }
                    }
                    .tag(LibraryLocation.root(root.id))
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
                    Label(album.name, systemImage: "rectangle.stack")
                        .tag(LibraryLocation.album(album.id))
                    .contextMenu {
                        Button("重命名") { editAlbum(album) }
                        Button("删除", role: .destructive) { deleteAlbum(album) }
                    }
                }

                organizationHeader("智能相册", systemImage: "gearshape.2", addAction: addSmartAlbum, help: "新建智能相册")
                ForEach(model.albums.filter { $0.kind == .smartAlbum }) { album in
                    Label(album.name, systemImage: "gearshape.2")
                        .tag(LibraryLocation.smartAlbum(album.id))
                    .contextMenu {
                        Button("编辑规则…") { editAlbum(album) }
                        Button("删除", role: .destructive) { deleteAlbum(album) }
                    }
                }

                organizationHeader("堆栈", systemImage: "square.stack.3d.up")
                ForEach(model.assetStacks) { stack in
                    Label("\(stack.title)（\(stack.assetCount)）", systemImage: "square.stack.3d.up")
                        .tag(LibraryLocation.stack(stack.id))
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
                    Label(tag.name, systemImage: "tag")
                        .tag(LibraryLocation.tag(tag.id))
                    .contextMenu {
                        Button("重命名") { editTag(tag) }
                        Button("删除", role: .destructive) { deleteTag(tag) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func navigationRow(
        _ title: String,
        systemImage: String,
        location: LibraryLocation
    ) -> some View {
        Label(title, systemImage: systemImage)
            .tag(location)
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
