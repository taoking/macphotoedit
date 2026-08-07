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
            CommandGroup(replacing: .newItem) { }
        }
    }
}
