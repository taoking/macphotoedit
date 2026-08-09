import SwiftUI

@main
struct MacPhotoStudioApp: App {
    @StateObject private var applicationModel = ApplicationModel()

    var body: some Scene {
        WindowGroup {
            LibraryHomeView(model: applicationModel)
                .task {
                    await applicationModel.bootstrapIfNeeded()
                }
        }
        .defaultSize(width: 1_180, height: 720)
        .commands {
            CommandGroup(after: .newItem) {
                Button("添加文件夹到资料库…") {
                    applicationModel.presentAddFolderPanel()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("运行 RAW 诊断…") {
                    applicationModel.presentRAWDiagnosticPanel()
                }
                Button("运行静态图像色彩验证…") {
                    applicationModel.presentStillImageColorDiagnosticPanels()
                }
                Button("运行媒体根目录可用性诊断") {
                    Task { await applicationModel.runMediaRootAvailabilityDiagnostics() }
                }
                Button("运行相似照片基准（开发者）") {
                    Task { await applicationModel.runSimilarPhotoBenchmark() }
                }
            }
        }
    }
}
