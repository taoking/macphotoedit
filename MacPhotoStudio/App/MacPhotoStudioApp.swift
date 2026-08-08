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
            }
        }
    }
}
