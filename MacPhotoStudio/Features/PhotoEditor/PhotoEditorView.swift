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

    func importTechnicalLUT(metadata: TechnicalLUTMetadata) {
        let panel = NSOpenPanel()
        panel.title = "导入 Technical .cube LUT"
        panel.message = "必须声明 LUT 的输入与输出色彩空间；导入只复制已验证的 LUT，不会修改原始 .cube 文件。"
        panel.prompt = "导入 Technical LUT"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "cube")!]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            guard let lut = await applicationModel.importLUT(
                from: url,
                kind: .technical,
                technicalMetadata: metadata
            ) else { return }
            await reloadLUTs()
            state.technicalLUT = LUTApplication(identifier: lut.id)
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

    func deleteTechnicalLUT() async {
        guard let identifier = state.technicalLUT?.identifier,
              await applicationModel.deleteLUT(identifier: identifier) else { return }
        state.technicalLUT = nil
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

    func addLocalMask(kind: LocalMaskKind) -> UUID {
        let mask = LocalMask(kind: kind)
        state.localMasks.append(mask)
        stateDidChange()
        return mask.id
    }

    func deleteLocalMask(id: UUID) {
        state.localMasks.removeAll { $0.id == id }
        stateDidChange()
    }

    func localMask(id: UUID) -> LocalMask? {
        state.localMasks.first(where: { $0.id == id })
    }

    func localMaskBinding(_ id: UUID, keyPath: WritableKeyPath<LocalMask, Double>) -> Binding<Double> {
        Binding(
            get: { self.localMask(id: id)?[keyPath: keyPath] ?? 0 },
            set: { value in
                guard let index = self.state.localMasks.firstIndex(where: { $0.id == id }) else { return }
                self.state.localMasks[index][keyPath: keyPath] = value
            }
        )
    }

    func localMaskEnabledBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { self.localMask(id: id)?.isEnabled ?? false },
            set: { value in
                guard let index = self.state.localMasks.firstIndex(where: { $0.id == id }) else { return }
                self.state.localMasks[index].isEnabled = value
            }
        )
    }

    func localMaskAdjustmentBinding(
        _ id: UUID,
        keyPath: WritableKeyPath<LocalMaskAdjustments, Double>
    ) -> Binding<Double> {
        Binding(
            get: { self.localMask(id: id)?.adjustments[keyPath: keyPath] ?? 0 },
            set: { value in
                guard let index = self.state.localMasks.firstIndex(where: { $0.id == id }) else { return }
                self.state.localMasks[index].adjustments[keyPath: keyPath] = value
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
    @State private var technicalInputSpace: PhotoColorSpace = .sRGB
    @State private var technicalInputTransfer: PhotoTransferFunction = .sRGB
    @State private var technicalOutputSpace: PhotoColorSpace = .rec709
    @State private var technicalOutputTransfer: PhotoTransferFunction = .rec709
    @State private var selectedLocalMaskID: UUID?

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
        .task {
            await editor.load()
            selectedLocalMaskID = editor.state.localMasks.first?.id
        }
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
                ExtendedRangeImageView(
                    image: image,
                    enablesExtendedRange: editor.state.colorPipeline.dynamicRange == .hdr
                )
                .padding(14)
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
                localMasksSection
                transformSection
                hslSection
                curvesSection
                colorManagementSection
                technicalLUTSection
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

    private var localMasksSection: some View {
        adjustmentSection("局部蒙版") {
            HStack(spacing: 8) {
                Button("添加线性") {
                    selectedLocalMaskID = editor.addLocalMask(kind: .linearGradient)
                }
                Button("添加径向") {
                    selectedLocalMaskID = editor.addLocalMask(kind: .radialGradient)
                }
            }
            if editor.state.localMasks.isEmpty {
                Text("本地非破坏性渐变蒙版会同时用于预览和导出。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("当前蒙版", selection: $selectedLocalMaskID) {
                    ForEach(Array(editor.state.localMasks.enumerated()), id: \.element.id) { index, mask in
                        Text("\(index + 1). \(mask.kind.title)").tag(Optional(mask.id))
                    }
                }
                .pickerStyle(.menu)
                if let selectedLocalMaskID, let mask = editor.localMask(id: selectedLocalMaskID) {
                    Toggle("启用", isOn: editor.localMaskEnabledBinding(selectedLocalMaskID))
                    slider("不透明度", value: editor.localMaskBinding(selectedLocalMaskID, keyPath: \.opacity), range: 0...1)
                    switch mask.kind {
                    case .linearGradient:
                        slider("起点 X", value: editor.localMaskBinding(selectedLocalMaskID, keyPath: \.startX), range: 0...1)
                        slider("起点 Y", value: editor.localMaskBinding(selectedLocalMaskID, keyPath: \.startY), range: 0...1)
                        slider("终点 X", value: editor.localMaskBinding(selectedLocalMaskID, keyPath: \.endX), range: 0...1)
                        slider("终点 Y", value: editor.localMaskBinding(selectedLocalMaskID, keyPath: \.endY), range: 0...1)
                    case .radialGradient:
                        slider("中心 X", value: editor.localMaskBinding(selectedLocalMaskID, keyPath: \.centerX), range: 0...1)
                        slider("中心 Y", value: editor.localMaskBinding(selectedLocalMaskID, keyPath: \.centerY), range: 0...1)
                        slider("半径", value: editor.localMaskBinding(selectedLocalMaskID, keyPath: \.radius), range: 0.01...1)
                        slider("羽化", value: editor.localMaskBinding(selectedLocalMaskID, keyPath: \.feather), range: 0.001...1)
                    }
                    slider("局部曝光", value: editor.localMaskAdjustmentBinding(selectedLocalMaskID, keyPath: \.exposure), range: -3...3)
                    slider("局部对比度", value: editor.localMaskAdjustmentBinding(selectedLocalMaskID, keyPath: \.contrast), range: -1...1)
                    slider("局部饱和度", value: editor.localMaskAdjustmentBinding(selectedLocalMaskID, keyPath: \.saturation), range: -1...1)
                    Button(role: .destructive) {
                        editor.deleteLocalMask(id: selectedLocalMaskID)
                        self.selectedLocalMaskID = editor.state.localMasks.first?.id
                    } label: {
                        Label("删除当前蒙版", systemImage: "trash")
                    }
                }
            }
            Text("蒙版坐标按原图比例保存；旋转、裁剪和不同预览尺寸不会改变其作用位置。局部蒙版不包含在可复用 Preset 中。")
                .font(.caption)
                .foregroundStyle(.secondary)
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
        adjustmentSection("Creative LUT") {
            Picker("LUT", selection: Binding<UUID?>(get: { editor.state.lut?.identifier }, set: { identifier in
                editor.state.lut = identifier.map { LUTApplication(identifier: $0, strength: editor.state.lut?.strength ?? 1) }
            })) {
                Text("无").tag(UUID?.none)
                Divider()
                ForEach(editor.luts.filter { !$0.isImported && $0.kind == .creative }) { lut in
                    Text("内置 · \(lut.title)").tag(Optional(lut.id))
                }
                ForEach(editor.luts.filter { $0.isImported && $0.kind == .creative }) { lut in
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
            Text("创意 \(editor.luts.filter { $0.kind == .creative }.count) · Technical \(editor.luts.filter { $0.kind == .technical }.count) · 收藏 \(editor.luts.filter(\.isFavorite).count)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var colorManagementSection: some View {
        adjustmentSection("Color Management") {
            Picker("输出色彩空间", selection: $editor.state.colorPipeline.outputColorSpace) {
                ForEach(PhotoColorSpace.outputSpaces) { colorSpace in
                    Text(colorSpace.title).tag(colorSpace)
                }
            }
            .pickerStyle(.menu)
            Picker("预览动态范围", selection: $editor.state.colorPipeline.dynamicRange) {
                ForEach(PhotoDynamicRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.menu)
            Text(editor.state.colorPipeline.dynamicRange == .hdr
                ? "HDR 预览保留扩展范围；SDR 屏幕由系统色调映射。当前 ImageIO 导出仅允许真实 SDR，避免伪 HDR 文件。"
                : "SDR 输出由 ColorSync 转换到所选输出色彩空间。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var technicalLUTSection: some View {
        adjustmentSection("Technical Transform") {
            Picker("Technical LUT", selection: Binding<UUID?>(
                get: { editor.state.technicalLUT?.identifier },
                set: { identifier in
                    editor.state.technicalLUT = identifier.map {
                        LUTApplication(identifier: $0, strength: editor.state.technicalLUT?.strength ?? 1)
                    }
                }
            )) {
                Text("无").tag(UUID?.none)
                ForEach(editor.luts.filter { $0.kind == .technical }) { lut in
                    let contract = lut.technicalMetadata.map { "\($0.input.title) → \($0.output.title)" } ?? "缺少元数据"
                    Text("\(lut.title) · \(contract)").tag(Optional(lut.id))
                }
            }
            .pickerStyle(.menu)
            if editor.state.technicalLUT != nil {
                slider("Technical 强度", value: Binding(
                    get: { editor.state.technicalLUT?.strength ?? 1 },
                    set: { editor.state.technicalLUT?.strength = $0 }
                ), range: 0...1)
                if let selected = editor.luts.first(where: { $0.id == editor.state.technicalLUT?.identifier }) {
                    HStack {
                        Button { Task { await editor.toggleFavorite(for: selected) } } label: {
                            Image(systemName: selected.isFavorite ? "star.fill" : "star")
                        }
                        if selected.isImported {
                            Button(role: .destructive) { Task { await editor.deleteTechnicalLUT() } } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
            }
            Group {
                Picker("输入色彩空间", selection: $technicalInputSpace) {
                    ForEach(PhotoColorSpace.allCases) { Text($0.title).tag($0) }
                }
                Picker("输入传递函数", selection: $technicalInputTransfer) {
                    ForEach(PhotoTransferFunction.allCases) { Text($0.title).tag($0) }
                }
                Picker("输出色彩空间", selection: $technicalOutputSpace) {
                    ForEach(PhotoColorSpace.allCases) { Text($0.title).tag($0) }
                }
                Picker("输出传递函数", selection: $technicalOutputTransfer) {
                    ForEach(PhotoTransferFunction.allCases) { Text($0.title).tag($0) }
                }
            }
            .pickerStyle(.menu)
            Button("导入 Technical .cube") {
                editor.importTechnicalLUT(metadata: TechnicalLUTMetadata(
                    input: PhotoColorDescriptor(colorSpace: technicalInputSpace, transferFunction: technicalInputTransfer),
                    output: PhotoColorDescriptor(colorSpace: technicalOutputSpace, transferFunction: technicalOutputTransfer)
                ))
            }
            Text("Technical LUT 只会在源色彩空间和传递函数与其声明完全匹配时运行；不能作为 Creative LUT 使用。")
                .font(.caption)
                .foregroundStyle(.secondary)
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
