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
    let addTag: () -> Void
    let editTag: (TagRecord) -> Void
    let deleteTag: (TagRecord) -> Void
    let rescanRoot: (UUID) -> Void
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
                }
                if model.mediaRoots.isEmpty {
                    Text("尚未添加文件夹")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("智能相册") {
                sidebarButton("全部照片", systemImage: "rectangle.stack.badge.play", selected: query.mediaType == .photo) {
                    selectMediaType(.photo)
                }
                sidebarButton("全部视频", systemImage: "rectangle.stack.badge.person.crop", selected: query.mediaType == .video) {
                    selectMediaType(.video)
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
        query.rootID == nil && query.mediaType == nil && query.minimumRating == nil && query.flag == nil && query.tagID == nil
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
