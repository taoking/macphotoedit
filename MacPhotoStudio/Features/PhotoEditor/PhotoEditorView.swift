import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class PhotoEditorViewModel: ObservableObject {
    @Published var state = PhotoEditState.identity
    @Published private(set) var editedImage: NSImage?
    @Published private(set) var originalImage: NSImage?
    @Published private(set) var histogram: PreviewHistogram = .empty
    @Published private(set) var luts: [CubeLUT] = []
    @Published private(set) var isRendering = false
    @Published private(set) var saveSucceeded = false

    let asset: LibraryAssetRecord
    private let applicationModel: ApplicationModel
    private var renderTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var renderGeneration = 0

    init(asset: LibraryAssetRecord, applicationModel: ApplicationModel) {
        self.asset = asset
        self.applicationModel = applicationModel
    }

    deinit {
        renderTask?.cancel()
        saveTask?.cancel()
    }

    func load() async {
        state = await applicationModel.photoEditState(for: asset.id) ?? .identity
        await reloadLUTs()
        await renderOriginal()
        scheduleRender(debounce: false)
    }

    func reloadLUTs() async {
        luts = await applicationModel.photoLUTLibrary()?.all ?? []
    }

    func stateDidChange() {
        saveSucceeded = false
        scheduleSave()
        scheduleRender(debounce: true)
    }

    func scheduleRender(debounce: Bool) {
        renderGeneration += 1
        let generation = renderGeneration
        renderTask?.cancel()
        isRendering = true
        let state = state
        renderTask = Task { [weak self] in
            if debounce {
                try? await Task.sleep(for: .milliseconds(90))
            }
            guard !Task.isCancelled, let self else { return }
            let result = await self.applicationModel.renderPhotoPreview(for: self.asset, state: state)
            guard !Task.isCancelled, generation == self.renderGeneration else { return }
            self.isRendering = false
            guard let result else { return }
            self.editedImage = NSImage(data: result.imageData)
            self.histogram = result.histogram ?? .empty
        }
    }

    func renderOriginal() async {
        guard let result = await applicationModel.renderPhotoPreview(for: asset, state: .identity) else { return }
        originalImage = NSImage(data: result.imageData)
    }

    func importLUT() {
        let panel = NSOpenPanel()
        panel.title = "导入 .cube LUT"
        panel.message = "导入会复制经过验证的 LUT 到应用数据目录，不会修改原始 .cube 文件。"
        panel.prompt = "导入 LUT"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "cube")!]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            guard let lut = await applicationModel.importLUT(from: url) else { return }
            await reloadLUTs()
            state.lut = LUTApplication(identifier: lut.id)
            stateDidChange()
        }
    }

    func renameSelectedLUT(to title: String) async {
        guard let identifier = state.lut?.identifier,
              await applicationModel.renameLUT(identifier: identifier, to: title) else { return }
        await reloadLUTs()
    }

    func deleteSelectedLUT() async {
        guard let identifier = state.lut?.identifier,
              await applicationModel.deleteLUT(identifier: identifier) else { return }
        state.lut = nil
        await reloadLUTs()
        stateDidChange()
    }

    func toggleFavorite(for lut: CubeLUT) async {
        guard await applicationModel.setLUTFavorite(!lut.isFavorite, identifier: lut.id) else { return }
        await reloadLUTs()
    }

    func addCurvePoint(channel: CurveChannel) {
        var points = state.curves[channel]
        let midpoint = points.indices.dropLast().map { (points[$0].x + points[$0 + 1].x) / 2 }.first ?? 0.5
        points.append(CurvePoint(x: midpoint, y: midpoint))
        state.curves[channel] = points
        stateDidChange()
    }

    func updateCurvePoint(_ point: CurvePoint, channel: CurveChannel, x: Double? = nil, y: Double? = nil) {
        var points = state.curves[channel]
        guard let index = points.firstIndex(where: { $0.id == point.id }) else { return }
        points[index].x = x ?? points[index].x
        points[index].y = y ?? points[index].y
        state.curves[channel] = points
        stateDidChange()
    }

    func deleteCurvePoint(_ point: CurvePoint, channel: CurveChannel) {
        var points = state.curves[channel]
        guard points.count > 2, let index = points.firstIndex(where: { $0.id == point.id }) else { return }
        points.remove(at: index)
        state.curves[channel] = points
        stateDidChange()
    }

    func resetCurve(_ channel: CurveChannel) {
        state.curves.reset(channel)
        stateDidChange()
    }

    func binding(_ keyPath: WritableKeyPath<PhotoEditState, Double>) -> Binding<Double> {
        Binding(get: { self.state[keyPath: keyPath] }, set: { self.state[keyPath: keyPath] = $0 })
    }

    func binding(_ keyPath: WritableKeyPath<PhotoEditState, Bool>) -> Binding<Bool> {
        Binding(get: { self.state[keyPath: keyPath] }, set: { self.state[keyPath: keyPath] = $0 })
    }

    func hslBinding(_ color: HSLColor, keyPath: WritableKeyPath<HSLAdjustment, Double>) -> Binding<Double> {
        Binding(
            get: { self.state.hsl[color][keyPath: keyPath] },
            set: {
                var adjustment = self.state.hsl[color]
                adjustment[keyPath: keyPath] = $0
                self.state.hsl[color] = adjustment
            }
        )
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let state = state
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled, let self else { return }
            self.saveSucceeded = await self.applicationModel.savePhotoEditState(state, for: self.asset.id)
        }
    }
}

struct PhotoEditorView: View {
    let asset: LibraryAssetRecord
    @ObservedObject var applicationModel: ApplicationModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var editor: PhotoEditorViewModel
    @State private var selectedHSLColor: HSLColor = .red
    @State private var selectedCurveChannel: CurveChannel = .master
    @State private var showsOriginal = false
    @State private var sideBySide = false
    @State private var lutRename = ""

    init(asset: LibraryAssetRecord, model: ApplicationModel) {
        self.asset = asset
        applicationModel = model
        _editor = StateObject(wrappedValue: PhotoEditorViewModel(asset: asset, applicationModel: model))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                previewArea
                    .frame(minWidth: 600, idealWidth: 850, maxWidth: .infinity, maxHeight: .infinity)
                inspector
                    .frame(minWidth: 285, idealWidth: 335, maxWidth: 390, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 920, minHeight: 640)
        .task { await editor.load() }
        .onChange(of: editor.state) { _, _ in editor.stateDidChange() }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Label(asset.filename, systemImage: "slider.horizontal.3")
                .lineLimit(1)
            Spacer()
            if editor.isRendering { ProgressView().controlSize(.small) }
            if editor.saveSucceeded { Label("已保存", systemImage: "checkmark.circle").foregroundStyle(.secondary) }
            Toggle("并排", isOn: $sideBySide).toggleStyle(.button)
            Button("按住查看原图") {}
                .onLongPressGesture(minimumDuration: 0, pressing: { showsOriginal = $0 }, perform: {})
            Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    private var previewArea: some View {
        ZStack {
            Color.black.opacity(0.86)
            if sideBySide {
                HStack(spacing: 1) {
                    editorImage(editor.originalImage, label: "原图")
                    editorImage(editor.editedImage, label: "编辑后")
                }
            } else {
                editorImage(showsOriginal ? editor.originalImage : editor.editedImage, label: showsOriginal ? "原图" : "编辑后")
            }
        }
        .overlay(alignment: .bottomLeading) {
            Text(sideBySide ? "左：原图  ·  右：编辑后" : (showsOriginal ? "原图（松开恢复编辑后）" : "编辑后"))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .padding(8)
        }
    }

    private func editorImage(_ image: NSImage?, label: String) -> some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit().padding(14)
            } else {
                ContentUnavailableView("\(label)预览不可用", systemImage: "photo")
                    .foregroundStyle(.white)
            }
        }
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HistogramView(histogram: editor.histogram)
                adjustmentSection("光线") {
                    slider("曝光", value: editor.binding(\.light.exposure), range: -3...3)
                    slider("对比度", value: editor.binding(\.light.contrast), range: -1...1)
                    slider("高光", value: editor.binding(\.light.highlights), range: -1...1)
                    slider("阴影", value: editor.binding(\.light.shadows), range: -1...1)
                    slider("白色色阶", value: editor.binding(\.light.whites), range: -1...1)
                    slider("黑色色阶", value: editor.binding(\.light.blacks), range: -1...1)
                }
                adjustmentSection("颜色") {
                    slider("色温", value: editor.binding(\.color.temperature), range: -1...1)
                    slider("色调", value: editor.binding(\.color.tint), range: -1...1)
                    slider("饱和度", value: editor.binding(\.color.saturation), range: -1...1)
                    slider("自然饱和度", value: editor.binding(\.color.vibrance), range: -1...1)
                }
                adjustmentSection("细节与效果") {
                    slider("锐化", value: editor.binding(\.detail.sharpness), range: 0...2)
                    slider("降噪", value: editor.binding(\.detail.noiseReduction), range: 0...0.2)
                    slider("暗角", value: editor.binding(\.effects.vignette), range: -2...2)
                }
                transformSection
                hslSection
                curvesSection
                lutSection
            }
            .padding(14)
        }
        .background(.bar)
    }

    private var transformSection: some View {
        adjustmentSection("裁剪与变换") {
            slider("左边", value: Binding(get: { editor.state.transform.crop.x }, set: { editor.state.transform.crop.x = $0 }), range: 0...0.9)
            slider("下边", value: Binding(get: { editor.state.transform.crop.y }, set: { editor.state.transform.crop.y = $0 }), range: 0...0.9)
            slider("宽度", value: Binding(get: { editor.state.transform.crop.width }, set: { editor.state.transform.crop.width = $0 }), range: 0.1...1)
            slider("高度", value: Binding(get: { editor.state.transform.crop.height }, set: { editor.state.transform.crop.height = $0 }), range: 0.1...1)
            slider("旋转", value: editor.binding(\.transform.rotationDegrees), range: -180...180)
            slider("校正", value: editor.binding(\.transform.straightenDegrees), range: -15...15)
            Toggle("水平翻转", isOn: editor.binding(\.transform.flipHorizontal))
            Toggle("垂直翻转", isOn: editor.binding(\.transform.flipVertical))
        }
    }

    private var hslSection: some View {
        adjustmentSection("HSL") {
            Picker("颜色", selection: $selectedHSLColor) {
                ForEach(HSLColor.allCases) { color in Text(color.rawValue.capitalized).tag(color) }
            }
            .pickerStyle(.menu)
            slider("色相", value: editor.hslBinding(selectedHSLColor, keyPath: \.hue), range: -1...1)
            slider("饱和度", value: editor.hslBinding(selectedHSLColor, keyPath: \.saturation), range: -1...1)
            slider("明度", value: editor.hslBinding(selectedHSLColor, keyPath: \.luminance), range: -1...1)
        }
    }

    private var curvesSection: some View {
        adjustmentSection("曲线") {
            HStack {
                Picker("通道", selection: $selectedCurveChannel) {
                    ForEach(CurveChannel.allCases) { channel in Text(channel.rawValue.capitalized).tag(channel) }
                }.pickerStyle(.menu)
                Spacer()
                Button("重置") { editor.resetCurve(selectedCurveChannel) }
            }
            ForEach(editor.state.curves[selectedCurveChannel]) { point in
                HStack(spacing: 6) {
                    Text("点").font(.caption)
                    Slider(value: Binding(get: { point.x }, set: { editor.updateCurvePoint(point, channel: selectedCurveChannel, x: $0) }), in: 0...1)
                    Slider(value: Binding(get: { point.y }, set: { editor.updateCurvePoint(point, channel: selectedCurveChannel, y: $0) }), in: 0...1)
                    Button(role: .destructive) { editor.deleteCurvePoint(point, channel: selectedCurveChannel) } label: {
                        Image(systemName: "minus.circle")
                    }
                    .disabled(editor.state.curves[selectedCurveChannel].count <= 2)
                }
            }
            Button("添加控制点") { editor.addCurvePoint(channel: selectedCurveChannel) }
        }
    }

    private var lutSection: some View {
        adjustmentSection("LUT") {
            Picker("LUT", selection: Binding<UUID?>(get: { editor.state.lut?.identifier }, set: { identifier in
                editor.state.lut = identifier.map { LUTApplication(identifier: $0, strength: editor.state.lut?.strength ?? 1) }
            })) {
                Text("无").tag(UUID?.none)
                Divider()
                ForEach(editor.luts.filter { !$0.isImported }) { lut in
                    Text("内置 · \(lut.title)").tag(Optional(lut.id))
                }
                ForEach(editor.luts.filter(\.isImported)) { lut in
                    Text("导入 · \(lut.title)").tag(Optional(lut.id))
                }
            }
            .pickerStyle(.menu)
            if editor.state.lut != nil {
                slider("强度", value: Binding(get: { editor.state.lut?.strength ?? 1 }, set: { editor.state.lut?.strength = $0 }), range: 0...1)
            }
            HStack {
                Button("导入 .cube", action: editor.importLUT)
                if let selected = editor.luts.first(where: { $0.id == editor.state.lut?.identifier }) {
                    Button { Task { await editor.toggleFavorite(for: selected) } } label: {
                        Image(systemName: selected.isFavorite ? "star.fill" : "star")
                    }
                    if selected.isImported {
                        Button(role: .destructive) { Task { await editor.deleteSelectedLUT() } } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
            if let selected = editor.luts.first(where: { $0.id == editor.state.lut?.identifier }), selected.isImported {
                HStack {
                    TextField("重命名 LUT", text: $lutRename)
                        .onAppear { lutRename = selected.title }
                    Button("改名") { Task { await editor.renameSelectedLUT(to: lutRename) } }
                }
            }
            Text("内置 \(editor.luts.filter { !$0.isImported }.count) · 导入 \(editor.luts.filter(\.isImported).count) · 收藏 \(editor.luts.filter(\.isFavorite).count)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func adjustmentSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(title); Spacer(); Text(value.wrappedValue, format: .number.precision(.fractionLength(2))).foregroundStyle(.secondary) }
                .font(.caption)
            Slider(value: value, in: range)
        }
    }
}

private struct HistogramView: View {
    let histogram: PreviewHistogram

    var body: some View {
        Canvas { context, size in
            let maximum = max(1, (histogram.red + histogram.green + histogram.blue).max() ?? 1)
            for (bins, color) in [(histogram.red, Color.red), (histogram.green, Color.green), (histogram.blue, Color.blue), (histogram.luminance, Color.white.opacity(0.7))] {
                var path = Path()
                for index in bins.indices {
                    let x = size.width * CGFloat(index) / CGFloat(PreviewHistogram.binCount - 1)
                    let y = size.height * (1 - CGFloat(bins[index]) / CGFloat(maximum))
                    if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(path, with: .color(color), lineWidth: 1)
            }
        }
        .frame(height: 72)
        .background(.black, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel("预览 RGB 与亮度直方图")
    }
}
