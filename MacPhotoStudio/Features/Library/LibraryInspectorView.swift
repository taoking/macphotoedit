import SwiftUI

struct LibraryInspectorView: View {
    let asset: LibraryAssetRecord?
    let tags: [TagRecord]
    let allTags: [TagRecord]
    let close: () -> Void
    let setRating: (Int) -> Void
    let setFlag: (AssetFlag) -> Void
    let addTag: (TagRecord) -> Void
    let removeTag: (TagRecord) -> Void

    var body: some View {
        Group {
            if let asset {
                inspector(asset)
            } else {
                ContentUnavailableView(
                    "检查器",
                    systemImage: "sidebar.right",
                    description: Text("选择一个媒体项目以查看元数据、评分、标记和标签。")
                )
            }
        }
        .background(.bar)
    }

    private func inspector(_ asset: LibraryAssetRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("检查器")
                        .font(.headline)
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help("隐藏检查器")
                }

                VStack(alignment: .leading, spacing: 5) {
                    Label(asset.filename, systemImage: asset.mediaType == .photo ? "photo" : "film")
                        .font(.headline)
                        .lineLimit(2)
                    availabilityLabel(asset.availability)
                }

                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("管理")
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 2) {
                        ForEach(0...5, id: \.self) { rating in
                            Button {
                                setRating(rating)
                            } label: {
                                Image(systemName: rating == 0 ? "star.slash" : (rating <= asset.rating ? "star.fill" : "star"))
                                    .foregroundStyle(rating == 0 || rating > asset.rating ? Color.secondary : Color.yellow)
                            }
                            .buttonStyle(.borderless)
                            .help(rating == 0 ? "清除评分" : "设置为 \(rating) 星")
                        }
                    }
                    Picker("Flag", selection: Binding(
                        get: { asset.flag },
                        set: { value in setFlag(value) }
                    )) {
                        Text("未标记").tag(AssetFlag.unflagged)
                        Text("选取").tag(AssetFlag.pick)
                        Text("拒绝").tag(AssetFlag.reject)
                    }
                    .pickerStyle(.segmented)
                }

                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("标签")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Menu {
                            ForEach(allTags.filter { candidate in !tags.contains(where: { $0.id == candidate.id }) }) { tag in
                                Button(tag.name) { addTag(tag) }
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .menuStyle(.borderlessButton)
                        .disabled(allTags.isEmpty)
                    }
                    if tags.isEmpty {
                        Text("尚未添加标签")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(tags) { tag in
                                Button {
                                    removeTag(tag)
                                } label: {
                                    Label(tag.name, systemImage: "xmark")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .help("移除标签 \(tag.name)")
                            }
                        }
                    }
                }

                Divider()
                metadata(asset)
            }
            .padding(14)
        }
    }

    private func availabilityLabel(_ availability: MediaAssetAvailability) -> some View {
        Text(availability == .available ? "可用" : availability == .missing ? "文件缺失" : "离线")
            .font(.caption.weight(.medium))
            .foregroundStyle(availability == .available ? .green : .orange)
    }

    private func metadata(_ asset: LibraryAssetRecord) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("元数据")
                .font(.subheadline.weight(.semibold))
            InspectorRow("文件", asset.filename)
            InspectorRow("文件夹", asset.rootPath + "/" + asset.folderPath)
            InspectorRow("类型", asset.mediaType == .photo ? "照片" : "视频")
            InspectorRow("大小", ByteCountFormatter.string(fromByteCount: asset.fileSize, countStyle: .file))
            if let dimensions = dimensions(asset) { InspectorRow("尺寸", dimensions) }
            if let date = asset.displayDate { InspectorRow("日期", date.formatted(date: .abbreviated, time: .shortened)) }
            let camera = [asset.cameraMake, asset.cameraModel].compactMap { $0 }.joined(separator: " ")
            if !camera.isEmpty {
                InspectorRow("相机", camera)
            }
            if let lens = asset.lensModel { InspectorRow("镜头", lens) }
            if let iso = asset.iso { InspectorRow("ISO", "\(iso)") }
            if let aperture = asset.aperture { InspectorRow("光圈", String(format: "f/%.1f", aperture)) }
            if let shutter = asset.shutterSpeed { InspectorRow("快门", shutterText(shutter)) }
            if let focalLength = asset.focalLength { InspectorRow("焦距", String(format: "%.0f mm", focalLength)) }
            if let orientation = asset.orientation { InspectorRow("方向", "\(orientation)") }
            if let colorProfile = asset.colorProfile { InspectorRow("颜色配置", colorProfile) }
            if let latitude = asset.gpsLatitude, let longitude = asset.gpsLongitude {
                InspectorRow("GPS", String(format: "%.5f, %.5f", latitude, longitude))
            }
            if let duration = asset.duration { InspectorRow("时长", duration.formatted(.number.precision(.fractionLength(1))) + " 秒") }
            if let frameRate = asset.frameRate { InspectorRow("帧率", frameRate.formatted(.number.precision(.fractionLength(2))) + " fps") }
            if let codec = asset.codec { InspectorRow("Codec", codec) }
        }
    }

    private func dimensions(_ asset: LibraryAssetRecord) -> String? {
        guard let width = asset.width, let height = asset.height else { return nil }
        return "\(width) × \(height)"
    }

    private func shutterText(_ shutter: Double) -> String {
        guard shutter > 0 else { return "—" }
        return shutter < 1 ? "1/\(Int((1 / shutter).rounded())) 秒" : String(format: "%.1f 秒", shutter)
    }
}

private struct InspectorRow: View {
    let title: String
    let value: String

    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    init(spacing: CGFloat) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var position = CGPoint.zero
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if position.x + size.width > maxWidth, position.x > 0 {
                position.x = 0
                position.y += rowHeight + spacing
                rowHeight = 0
            }
            position.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: position.y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var position = bounds.origin
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if position.x + size.width > bounds.maxX, position.x > bounds.minX {
                position.x = bounds.minX
                position.y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: position, proposal: ProposedViewSize(size))
            position.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
