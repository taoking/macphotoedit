import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
private final class RAWEditorModel: ObservableObject {
    @Published var rawState = RAWEditState.identity
    @Published var photoState = PhotoEditState.identity
    @Published var image: NSImage?
    @Published var capabilities = RAWCapabilities()
    @Published var luts: [CubeLUT] = []
    @Published var isRendering = false
    @Published var isExporting = false
    @Published var exportMessage: String?
    private let asset: LibraryAssetRecord
    private let app: ApplicationModel
    private var task: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var generation = 0

    init(asset: LibraryAssetRecord, app: ApplicationModel) { self.asset = asset; self.app = app }
    deinit { task?.cancel(); saveTask?.cancel() }

    func load() async {
        rawState = await app.rawEditState(for: asset.id) ?? .identity
        photoState = await app.photoEditState(for: asset.id) ?? .identity
        await reloadLUTs()
        requestRender(debounce: false)
    }

    func changed() { requestRender(debounce: true); save() }

    func reloadLUTs() async {
        luts = await app.photoLUTLibrary()?.all ?? []
    }

    func importLUT() {
        let panel = NSOpenPanel()
        panel.title = "导入 .cube LUT"
        panel.message = "导入会复制经过验证的 LUT 到应用数据目录，不会修改原始 .cube 或 RAW 文件。"
        panel.prompt = "导入 LUT"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "cube")!]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            guard let lut = await app.importLUT(from: url) else { return }
            await reloadLUTs()
            photoState.lut = LUTApplication(identifier: lut.id)
            changed()
        }
    }

    func export(_ format: RAWExportFormat) {
        let panel = NSSavePanel()
        panel.title = "导出 RAW 编辑结果"
        panel.message = "导出会创建新文件，不会覆盖或修改原始 RAW 文件。"
        panel.prompt = "导出 \(format.title)"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [format.contentType]
        let baseName = URL(filePath: asset.filename).deletingPathExtension().lastPathComponent
        panel.nameFieldStringValue = "\(baseName).\(format.filenameExtension)"
        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }
        let raw = rawState
        let photo = photoState
        Task {
            isExporting = true
            defer { isExporting = false }
            if await app.exportRAW(
                for: asset,
                rawState: raw,
                photoState: photo,
                destinationURL: destinationURL,
                format: format
            ) {
                exportMessage = "已导出 \(destinationURL.lastPathComponent)"
            }
        }
    }

    func binding(_ keyPath: WritableKeyPath<RAWEditState, Double>) -> Binding<Double> {
        Binding(get: { self.rawState[keyPath: keyPath] }, set: { self.rawState[keyPath: keyPath] = $0 })
    }
    func optionalBinding(_ keyPath: WritableKeyPath<RAWEditState, Double?>, default value: Double) -> Binding<Double> {
        Binding(get: { self.rawState[keyPath: keyPath] ?? value }, set: { self.rawState[keyPath: keyPath] = $0 })
    }
    func optionalBoolBinding(_ keyPath: WritableKeyPath<RAWEditState, Bool?>) -> Binding<Bool> {
        Binding(get: { self.rawState[keyPath: keyPath] ?? false }, set: { self.rawState[keyPath: keyPath] = $0 })
    }
    private func requestRender(debounce: Bool) {
        generation += 1; let token = generation; task?.cancel(); isRendering = true
        let raw = rawState; let photo = photoState
        task = Task { [weak self] in
            if debounce { try? await Task.sleep(for: .milliseconds(100)) }
            guard !Task.isCancelled, let self else { return }
            let result = await self.app.renderRAWPreview(for: self.asset, rawState: raw, photoState: photo)
            guard !Task.isCancelled, token == self.generation else { return }
            self.isRendering = false
            guard let result else { return }
            self.image = NSImage(data: result.render.imageData)
            self.capabilities = result.capabilities
        }
    }
    private func save() {
        saveTask?.cancel(); let raw = rawState; let photo = photoState
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300)); guard !Task.isCancelled, let self else { return }
            _ = await self.app.saveRAWEditState(raw, for: self.asset.id)
            _ = await self.app.savePhotoEditState(photo, for: self.asset.id)
        }
    }
}

struct RAWPhotoEditorView: View {
    let asset: LibraryAssetRecord
    @ObservedObject var applicationModel: ApplicationModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var editor: RAWEditorModel

    init(asset: LibraryAssetRecord, model: ApplicationModel) {
        self.asset = asset; applicationModel = model
        _editor = StateObject(wrappedValue: RAWEditorModel(asset: asset, app: model))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(asset.filename, systemImage: "camera.aperture")
                Spacer()
                if editor.isRendering || editor.isExporting { ProgressView().controlSize(.small) }
                Menu("导出") {
                    ForEach(RAWExportFormat.allCases) { format in
                        Button(format.title) { editor.export(format) }
                            .disabled(!format.isSupported)
                    }
                }
                .disabled(editor.isExporting)
                Button("完成") { dismiss() }
            }
            .padding(12)
            Divider()
            HSplitView {
                ZStack { Color.black; if let image = editor.image { Image(nsImage: image).resizable().scaledToFit().padding() } else { ContentUnavailableView("RAW 预览不可用", systemImage: "camera.aperture") } }
                    .frame(minWidth: 560, minHeight: 520)
                ScrollView { VStack(alignment: .leading, spacing: 12) {
                    Text("RAW 解码参数").font(.headline)
                    control("曝光", editor.binding(\.exposure), -3...3)
                    control("色温", editor.optionalBinding(\.temperature, default: 6500), 2000...50000)
                    control("色调", editor.optionalBinding(\.tint, default: 0), -150...150)
                    control("阴影偏移", editor.binding(\.shadowBias), -1...1)
                    if editor.capabilities.luminanceNoiseReduction { control("亮度降噪", editor.optionalBinding(\.luminanceNoiseReduction, default: 0), 0...1) }
                    if editor.capabilities.colorNoiseReduction { control("色彩降噪", editor.optionalBinding(\.colorNoiseReduction, default: 0), 0...1) }
                    if editor.capabilities.sharpness { control("RAW 锐化", editor.optionalBinding(\.sharpness, default: 0), 0...1) }
                    if editor.capabilities.localContrast { control("局部对比", editor.optionalBinding(\.localContrast, default: 0), 0...1) }
                    if editor.capabilities.detail { control("细节", editor.optionalBinding(\.detail, default: 0), 0...3) }
                    if editor.capabilities.localToneMap { control("局部色调", editor.optionalBinding(\.localToneMap, default: 0), 0...1) }
                    if editor.capabilities.lensCorrection { Toggle("镜头校正", isOn: editor.optionalBoolBinding(\.lensCorrectionEnabled)) }
                    if editor.capabilities.highlightRecovery { Toggle("高光恢复", isOn: editor.optionalBoolBinding(\.highlightRecoveryEnabled)) }
                    creativeLUTSection
                    if let message = editor.exportMessage {
                        Label(message, systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("系统不支持的 RAW 参数不会显示或写入。标准照片编辑与 LUT 将在此 RAW 解码之后应用。").font(.caption).foregroundStyle(.secondary)
                }.padding() }.frame(minWidth: 285, maxWidth: 360)
            }
        }.frame(minWidth: 880, minHeight: 620).task { await editor.load() }
            .onChange(of: editor.rawState) { _, _ in editor.changed() }
            .onChange(of: editor.photoState) { _, _ in editor.changed() }
    }

    private var creativeLUTSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("创意 LUT").font(.headline)
            Picker("LUT", selection: Binding<UUID?>(
                get: { editor.photoState.lut?.identifier },
                set: { identifier in
                    editor.photoState.lut = identifier.map {
                        LUTApplication(identifier: $0, strength: editor.photoState.lut?.strength ?? 1)
                    }
                }
            )) {
                Text("无").tag(UUID?.none)
                ForEach(editor.luts.filter { !$0.isImported }) { lut in
                    Text("内置 · \(lut.title)").tag(Optional(lut.id))
                }
                ForEach(editor.luts.filter(\.isImported)) { lut in
                    Text("导入 · \(lut.title)").tag(Optional(lut.id))
                }
            }
            .pickerStyle(.menu)
            if editor.photoState.lut != nil {
                control("LUT 强度", Binding(
                    get: { editor.photoState.lut?.strength ?? 1 },
                    set: { editor.photoState.lut?.strength = $0 }
                ), 0...1)
            }
            Button("导入 .cube", action: editor.importLUT)
                .buttonStyle(.borderless)
        }
    }
    private func control(_ title: String, _ binding: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) { HStack { Text(title); Spacer(); Text(binding.wrappedValue, format: .number.precision(.fractionLength(2))).foregroundStyle(.secondary) }.font(.caption); Slider(value: binding, in: range) }
    }
}
