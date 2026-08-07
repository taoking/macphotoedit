import AppKit
import AVKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class VideoEditorViewModel: ObservableObject {
    @Published var state = VideoEditState.identity
    @Published private(set) var session: VideoPlaybackSession?
    @Published private(set) var luts: [CubeLUT] = []
    @Published private(set) var isPreparingPreview = false
    @Published private(set) var saveSucceeded = false

    let asset: LibraryAssetRecord
    private let model: ApplicationModel
    private var previewTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var previewGeneration = 0

    init(asset: LibraryAssetRecord, model: ApplicationModel) {
        self.asset = asset
        self.model = model
    }

    deinit {
        previewTask?.cancel()
        saveTask?.cancel()
    }

    func load() async {
        state = await model.videoEditState(for: asset.id) ?? .identity
        luts = (await model.videoLUTLibrary()?.all ?? []).filter { $0.kind == .creative }
        session = await model.makeVideoPlaybackSession(for: asset)
        schedulePreview(debounce: false)
    }

    func stateDidChange() {
        saveSucceeded = false
        scheduleSave()
        schedulePreview(debounce: true)
    }

    func importLUT() {
        let panel = NSOpenPanel()
        panel.title = "导入 .cube 视频 LUT"
        panel.message = "只导入经验证的 Creative LUT 到应用数据目录；不会修改原始 .cube 或视频文件。"
        panel.prompt = "导入 LUT"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "cube")!]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            guard let lut = await model.importLUT(from: url) else { return }
            luts = (await model.videoLUTLibrary()?.all ?? []).filter { $0.kind == .creative }
            state.lut = LUTApplication(identifier: lut.id)
            stateDidChange()
        }
    }

    func close() {
        previewTask?.cancel()
        saveTask?.cancel()
        session?.close()
        session = nil
    }

    func doubleBinding(_ keyPath: WritableKeyPath<VideoEditState, Double>) -> Binding<Double> {
        Binding(
            get: { self.state[keyPath: keyPath] },
            set: { self.state[keyPath: keyPath] = $0 }
        )
    }

    func boolBinding(_ keyPath: WritableKeyPath<VideoEditState, Bool>) -> Binding<Bool> {
        Binding(
            get: { self.state[keyPath: keyPath] },
            set: { self.state[keyPath: keyPath] = $0 }
        )
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let state = state
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled, let self else { return }
            self.saveSucceeded = await self.model.saveVideoEditState(state, for: self.asset.id)
        }
    }

    private func schedulePreview(debounce: Bool) {
        guard let session else { return }
        previewGeneration += 1
        let generation = previewGeneration
        let state = state
        previewTask?.cancel()
        isPreparingPreview = true
        previewTask = Task { [weak self, weak session] in
            if debounce {
                try? await Task.sleep(for: .milliseconds(180))
            }
            guard !Task.isCancelled, let self, let session else { return }
            let payload = await self.model.videoPreviewPayload(for: session, state: state)
            guard !Task.isCancelled, generation == self.previewGeneration else { return }
            self.isPreparingPreview = false
            guard let payload else { return }
            session.replaceCurrentItem(with: payload.playerItem, duration: payload.duration)
        }
    }
}

struct VideoEditorView: View {
    let asset: LibraryAssetRecord
    @ObservedObject var model: ApplicationModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var editor: VideoEditorViewModel
    @State private var showsExport = false

    init(asset: LibraryAssetRecord, model: ApplicationModel) {
        self.asset = asset
        self.model = model
        _editor = StateObject(wrappedValue: VideoEditorViewModel(asset: asset, model: model))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                preview
                    .frame(minWidth: 620, idealWidth: 860, maxWidth: .infinity, maxHeight: .infinity)
                inspector
                    .frame(minWidth: 300, idealWidth: 345, maxWidth: 410, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 980, minHeight: 660)
        .task { await editor.load() }
        .onChange(of: editor.state) { _, _ in editor.stateDidChange() }
        .onDisappear { editor.close() }
        .sheet(isPresented: $showsExport) {
            VideoExportSheet(asset: asset, state: editor.state, model: model)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Label(asset.filename, systemImage: "film.stack")
                .lineLimit(1)
            Spacer()
            if editor.isPreparingPreview { ProgressView().controlSize(.small) }
            if editor.saveSucceeded {
                Label("已保存", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
            Button("导出…") { showsExport = true }
                .disabled(editor.session == nil)
            Button("完成") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    @ViewBuilder
    private var preview: some View {
        ZStack {
            Color.black.opacity(0.88)
            if let session = editor.session {
                VStack(spacing: 12) {
                    VideoPlayer(player: session.player)
                        .background(.black, in: RoundedRectangle(cornerRadius: 8))
                    VideoEditorPlaybackControls(session: session)
                }
                .padding(14)
            } else {
                ProgressView("正在准备视频编辑…")
                    .foregroundStyle(.white)
            }
        }
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                trimSection
                adjustmentSection("颜色") {
                    slider("曝光", value: Binding(get: { editor.state.adjustments.exposure }, set: { editor.state.adjustments.exposure = $0 }), range: -3...3)
                    slider("对比度", value: Binding(get: { editor.state.adjustments.contrast }, set: { editor.state.adjustments.contrast = $0 }), range: -1...1)
                    slider("饱和度", value: Binding(get: { editor.state.adjustments.saturation }, set: { editor.state.adjustments.saturation = $0 }), range: -1...1)
                    slider("色温", value: Binding(get: { editor.state.adjustments.temperature }, set: { editor.state.adjustments.temperature = $0 }), range: -1...1)
                    slider("色调", value: Binding(get: { editor.state.adjustments.tint }, set: { editor.state.adjustments.tint = $0 }), range: -1...1)
                }
                transformSection
                lutSection
                audioSection
            }
            .padding(14)
        }
        .background(.bar)
    }

    private var trimSection: some View {
        adjustmentSection("剪辑与速度") {
            let duration = max(editor.session?.duration ?? asset.duration ?? 0, 0.01)
            slider("开始", value: Binding(
                get: { min(max(0, editor.state.trimStart), max(0, duration - 0.01)) },
                set: { editor.state.trimStart = min($0, max(0, effectiveTrimEnd(duration) - 0.01)) }
            ), range: 0...max(0.01, duration - 0.01))
            slider("结束", value: Binding(
                get: { min(max(effectiveTrimEnd(duration), 0.01), duration) },
                set: { editor.state.trimEnd = max($0, editor.state.trimStart + 0.01) }
            ), range: min(duration, editor.state.trimStart + 0.01)...duration)
            Picker("速度", selection: Binding(
                get: { editor.state.clampedSpeed },
                set: { editor.state.speed = $0 }
            )) {
                ForEach([0.25, 0.5, 1.0, 2.0, 4.0], id: \.self) { speed in
                    Text("\(speed.formatted(.number.precision(.fractionLength(2))))×").tag(speed)
                }
            }
            .pickerStyle(.menu)
            Text("导出时剪辑范围会与音轨同步按速度缩放。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var transformSection: some View {
        adjustmentSection("裁剪与变换") {
            slider("左边", value: Binding(get: { editor.state.transform.crop.x }, set: { editor.state.transform.crop.x = $0 }), range: 0...0.9)
            slider("下边", value: Binding(get: { editor.state.transform.crop.y }, set: { editor.state.transform.crop.y = $0 }), range: 0...0.9)
            slider("宽度", value: Binding(get: { editor.state.transform.crop.width }, set: { editor.state.transform.crop.width = $0 }), range: 0.1...1)
            slider("高度", value: Binding(get: { editor.state.transform.crop.height }, set: { editor.state.transform.crop.height = $0 }), range: 0.1...1)
            Picker("旋转", selection: Binding(
                get: { editor.state.transform.normalizedRotationDegrees },
                set: { editor.state.transform.rotationDegrees = $0 }
            )) {
                Text("0°").tag(0)
                Text("90°").tag(90)
                Text("180°").tag(180)
                Text("270°").tag(270)
            }
            .pickerStyle(.menu)
            Toggle("水平翻转", isOn: Binding(get: { editor.state.transform.flipHorizontal }, set: { editor.state.transform.flipHorizontal = $0 }))
            Toggle("垂直翻转", isOn: Binding(get: { editor.state.transform.flipVertical }, set: { editor.state.transform.flipVertical = $0 }))
        }
    }

    private var lutSection: some View {
        adjustmentSection("Creative LUT") {
            Picker("LUT", selection: Binding<UUID?>(
                get: { editor.state.lut?.identifier },
                set: { identifier in
                    editor.state.lut = identifier.map { LUTApplication(identifier: $0, strength: editor.state.lut?.strength ?? 1) }
                }
            )) {
                Text("无").tag(UUID?.none)
                ForEach(editor.luts) { lut in
                    Text(lut.isImported ? "导入 · \(lut.title)" : "内置 · \(lut.title)")
                        .tag(Optional(lut.id))
                }
            }
            .pickerStyle(.menu)
            if editor.state.lut != nil {
                slider("强度", value: Binding(get: { editor.state.lut?.strength ?? 1 }, set: { editor.state.lut?.strength = $0 }), range: 0...1)
            }
            Button("导入 .cube LUT", action: editor.importLUT)
        }
    }

    private var audioSection: some View {
        adjustmentSection("音频") {
            Toggle("静音", isOn: editor.boolBinding(\.isMuted))
            slider("增益", value: editor.doubleBinding(\.audioGain), range: -60...12, suffix: " dB")
        }
    }

    private func effectiveTrimEnd(_ duration: Double) -> Double {
        editor.state.trimEnd ?? duration
    }

    private func adjustmentSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.headline)
            content()
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String = "") -> some View {
        HStack(spacing: 8) {
            Text(title).frame(width: 58, alignment: .leading)
            Slider(value: value, in: range)
            Text("\(value.wrappedValue.formatted(.number.precision(.fractionLength(2))))\(suffix)")
                .font(.caption.monospacedDigit())
                .frame(width: suffix.isEmpty ? 42 : 64, alignment: .trailing)
        }
    }
}

private struct VideoEditorPlaybackControls: View {
    @ObservedObject var session: VideoPlaybackSession

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(timeText(session.currentTime)).font(.caption.monospacedDigit()).frame(width: 54, alignment: .leading)
                Slider(value: Binding(get: { session.currentTime }, set: { session.seek(to: $0) }), in: 0...max(0.01, session.duration))
                Text(timeText(session.duration)).font(.caption.monospacedDigit()).frame(width: 54, alignment: .trailing)
            }
            HStack(spacing: 12) {
                Button { session.step(frames: -1) } label: { Image(systemName: "backward.frame.fill") }
                Button { session.togglePlayback() } label: { Image(systemName: session.isPlaying ? "pause.fill" : "play.fill") }
                Button { session.step(frames: 1) } label: { Image(systemName: "forward.frame.fill") }
                Spacer()
                Button { session.toggleMute() } label: { Image(systemName: session.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") }
                Slider(value: Binding(get: { session.volume }, set: { session.setVolume($0) }), in: 0...1)
                    .frame(width: 90)
            }
        }
    }

    private func timeText(_ seconds: Double) -> String {
        let rounded = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", rounded / 60, rounded % 60)
    }
}

private struct VideoExportSheet: View {
    let asset: LibraryAssetRecord
    let state: VideoEditState
    @ObservedObject var model: ApplicationModel
    @Environment(\.dismiss) private var dismiss
    @State private var outputDirectoryURL: URL?
    @State private var format: VideoExportFormat = .h264
    @State private var quality: VideoExportQuality = .high
    @State private var resizeMaximumPixelSize: Int?
    @State private var namingRule: VideoExportNamingRule = .editedName
    @State private var collisionPolicy: ExportCollisionPolicy = .rename

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("导出视频").font(.headline)
            Text("将创建新的 MP4 文件。原视频只读，绝不会被覆盖。")
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
                Picker("编码", selection: $format) {
                    ForEach(VideoExportFormat.allCases) { format in Text(format.title).tag(format) }
                }
                Picker("质量", selection: $quality) {
                    ForEach(VideoExportQuality.allCases) { quality in Text(quality.title).tag(quality) }
                }
                Picker("尺寸", selection: $resizeMaximumPixelSize) {
                    Text("保留原始分辨率").tag(Int?.none)
                    Text("最长边 3840 px").tag(Optional(3_840))
                    Text("最长边 1920 px").tag(Optional(1_920))
                    Text("最长边 1280 px").tag(Optional(1_280))
                }
                Picker("命名", selection: $namingRule) {
                    ForEach(VideoExportNamingRule.allCases) { rule in Text(rule.title).tag(rule) }
                }
                Picker("重名", selection: $collisionPolicy) {
                    ForEach(ExportCollisionPolicy.allCases) { policy in Text(policy.title).tag(policy) }
                }
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("开始导出", action: start)
                    .keyboardShortcut(.defaultAction)
                    .disabled(outputDirectoryURL == nil)
            }
        }
        .padding(20)
        .frame(width: 500)
    }

    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择视频导出文件夹"
        panel.message = "视频导出会写入此文件夹；重名默认自动重命名。"
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
        let options = VideoExportOptions(
            format: format,
            quality: quality,
            resize: resizeMaximumPixelSize.map(VideoExportResize.maximum) ?? .original,
            namingRule: namingRule,
            collisionPolicy: collisionPolicy
        )
        Task {
            if await model.startVideoExport(asset: asset, state: state, outputDirectoryURL: outputDirectoryURL, options: options) != nil {
                dismiss()
            }
        }
    }
}
