import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PresetNameSheet: View {
    let asset: LibraryAssetRecord
    @ObservedObject var model: ApplicationModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("创建照片预设").font(.headline)
            Text("预设会保存 Light、Color、HSL、Curves、Detail、Effects 和 LUT（含强度）；不会保存裁剪、旋转或翻转。")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("预设名称", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("创建", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 390)
    }

    private func create() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        Task {
            if await model.createPhotoPreset(named: trimmedName, from: asset.id) {
                dismiss()
            }
        }
    }
}

struct SelectivePasteSheet: View {
    @ObservedObject var model: ApplicationModel
    let assetIDs: [UUID]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedComponents = PhotoEditComponent.allPresetComponents

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择要粘贴的调整").font(.headline)
            Text("裁剪、旋转与翻转从不属于粘贴内容。")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(PhotoEditComponent.allCases) { component in
                Toggle(component.title, isOn: componentBinding(component))
            }
            HStack {
                Button("全选") { selectedComponents = PhotoEditComponent.allPresetComponents }
                Button("全不选") { selectedComponents.removeAll() }
                Spacer()
                Button("取消") { dismiss() }
                Button("粘贴") {
                    Task {
                        _ = await model.pastePhotoEdits(to: assetIDs, components: selectedComponents)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedComponents.isEmpty || assetIDs.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 330)
    }

    private func componentBinding(_ component: PhotoEditComponent) -> Binding<Bool> {
        Binding(
            get: { selectedComponents.contains(component) },
            set: { isSelected in
                if isSelected {
                    selectedComponents.insert(component)
                } else {
                    selectedComponents.remove(component)
                }
            }
        )
    }
}

struct PresetManagerSheet: View {
    @ObservedObject var model: ApplicationModel
    @Environment(\.dismiss) private var dismiss
    @State private var draftNames: [UUID: String] = [:]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("照片预设").font(.headline)
                Spacer()
                Button("导入…", action: importPreset)
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()
            if model.photoPresets.isEmpty {
                ContentUnavailableView("尚无预设", systemImage: "slider.horizontal.3", description: Text("在资料库中选择一张照片，然后从“编辑”菜单创建预设。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(model.photoPresets) { preset in
                        HStack(spacing: 10) {
                            Button {
                                Task { _ = await model.setPhotoPresetFavorite(!preset.isFavorite, preset: preset) }
                            } label: {
                                Image(systemName: preset.isFavorite ? "star.fill" : "star")
                                    .foregroundStyle(preset.isFavorite ? .yellow : .secondary)
                            }
                            .buttonStyle(.borderless)
                            TextField("预设名称", text: draftBinding(for: preset))
                                .onSubmit { rename(preset) }
                            Button("导出…") { export(preset) }
                                .buttonStyle(.borderless)
                            Button(role: .destructive) {
                                Task { _ = await model.deletePhotoPreset(preset) }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .frame(width: 540, height: 400)
        .task { await model.reloadPhotoPresets() }
    }

    private func draftBinding(for preset: PhotoPreset) -> Binding<String> {
        Binding(
            get: { draftNames[preset.id] ?? preset.name },
            set: { draftNames[preset.id] = $0 }
        )
    }

    private func rename(_ preset: PhotoPreset) {
        let name = (draftNames[preset.id] ?? preset.name).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != preset.name else { return }
        Task {
            if await model.renamePhotoPreset(preset, to: name) {
                draftNames[preset.id] = nil
            }
        }
    }

    private func importPreset() {
        let panel = NSOpenPanel()
        panel.title = "导入照片预设"
        panel.message = "预设将导入 Catalog；原始预设文件不会被修改。"
        panel.prompt = "导入"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "mpspreset") ?? .json, .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { _ = await model.importPhotoPreset(from: url) }
    }

    private func export(_ preset: PhotoPreset) {
        let panel = NSSavePanel()
        panel.title = "导出照片预设"
        panel.message = "将导出预设 JSON，不会修改 Catalog 或任何原始媒体。"
        panel.nameFieldStringValue = "\(preset.name).mpspreset"
        panel.allowedContentTypes = [UTType(filenameExtension: "mpspreset") ?? .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { _ = await model.exportPhotoPreset(preset, to: url) }
    }
}

struct BatchExportSheet: View {
    @ObservedObject var model: ApplicationModel
    let assets: [LibraryAssetRecord]
    @Environment(\.dismiss) private var dismiss
    @State private var outputDirectoryURL: URL?
    @State private var format: PhotoExportFormat = .jpeg
    @State private var useResize = false
    @State private var maximumPixelSize = 2_048
    @State private var quality = 0.92
    @State private var namingRule: PhotoExportNamingRule = .editedName
    @State private var keepsMetadata = true
    @State private var removesGPS = false
    @State private var collisionPolicy: ExportCollisionPolicy = .rename
    @State private var outputColorSpace: PhotoColorSpace = .sRGB

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("批量导出 \(assets.count) 张照片").font(.headline)
            Text("按顺序逐张渲染，以限制内存占用；源照片只读，不会被复制、移动或覆盖。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(outputDirectoryURL?.path(percentEncoded: false) ?? "尚未选择输出文件夹")
                    .lineLimit(1)
                    .foregroundStyle(outputDirectoryURL == nil ? .secondary : .primary)
                Spacer()
                Button("选择文件夹…", action: chooseOutputDirectory)
            }
            Form {
                Picker("格式", selection: $format) {
                    ForEach(PhotoExportFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                Picker("命名", selection: $namingRule) {
                    ForEach(PhotoExportNamingRule.allCases) { rule in
                        Text(rule.title).tag(rule)
                    }
                }
                Picker("重名", selection: $collisionPolicy) {
                    ForEach(ExportCollisionPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                Picker("输出色彩空间", selection: $outputColorSpace) {
                    ForEach(PhotoColorSpace.outputSpaces) { colorSpace in
                        Text(colorSpace.title).tag(colorSpace)
                    }
                }
                Toggle("调整尺寸", isOn: $useResize)
                if useResize {
                    Stepper("最长边：\(maximumPixelSize) px", value: $maximumPixelSize, in: 256...12_000, step: 128)
                }
                if format != .tiff {
                    HStack {
                        Text("质量")
                        Slider(value: $quality, in: 0.1...1, step: 0.01)
                        Text("\(Int(quality * 100))%")
                            .monospacedDigit()
                            .frame(width: 38, alignment: .trailing)
                    }
                }
                Toggle("保留元数据", isOn: $keepsMetadata)
                Toggle("移除 GPS 位置", isOn: $removesGPS)
                    .disabled(!keepsMetadata)
                if !HDRPhotoCapabilities.supportsHDRExport {
                    Text("此 macOS 的安全 ImageIO 路径不提供可靠 HDR gain-map 写入；批量导出会执行真实 SDR 色调映射，而不会伪标为 HDR。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("开始导出", action: start)
                    .keyboardShortcut(.defaultAction)
                    .disabled(outputDirectoryURL == nil || assets.isEmpty || !format.isSupported)
            }
        }
        .padding(20)
        .frame(width: 500)
    }

    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择照片导出文件夹"
        panel.message = "导出文件只会写入此文件夹；冲突默认自动重命名。"
        panel.prompt = "选择输出文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputDirectoryURL = url
    }

    private func start() {
        guard let outputDirectoryURL else { return }
        let options = PhotoExportOptions(
            format: format,
            resize: useResize ? .maximum(maximumPixelSize) : .original,
            quality: quality,
            namingRule: namingRule,
            keepsMetadata: keepsMetadata,
            removesGPS: keepsMetadata && removesGPS,
            collisionPolicy: collisionPolicy,
            outputColorSpace: outputColorSpace,
            dynamicRange: .sdr
        )
        Task {
            if await model.startBatchExport(assets: assets, outputDirectoryURL: outputDirectoryURL, options: options) != nil {
                dismiss()
            }
        }
    }
}

struct BatchTaskStatusSummary: View {
    @ObservedObject var model: ApplicationModel

    var body: some View {
        if let activeTask = model.batchTasks.last(where: { !$0.state.isTerminal }) {
            HStack(spacing: 5) {
                ProgressView(value: activeTask.progress).frame(width: 70)
                Text(activeTask.title).font(.caption).lineLimit(1)
                Button {
                    Task { await model.cancelBatchTask(activeTask.id) }
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .help("取消后台任务")
            }
        } else if let report = model.latestBatchExportReport {
            Text("最近导出：成功 \(report.succeeded)，跳过 \(report.skipped)，失败 \(report.failed)")
                .font(.caption)
                .foregroundStyle(report.failed == 0 ? Color.secondary : Color.orange)
        } else if let report = model.latestVideoExportReport {
            Text("最近视频导出：\(report.destinationURL.lastPathComponent)")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let report = model.latestBatchEditReport {
            Text("最近批量调整：成功 \(report.succeeded)，失败 \(report.failed)")
                .font(.caption)
                .foregroundStyle(report.failed == 0 ? Color.secondary : Color.orange)
        }
    }
}
