import SwiftUI

struct LibraryHomeView: View {
    @ObservedObject var model: ApplicationModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Mac Photo Studio")
                .font(.title2.weight(.semibold))

            switch model.startupState {
            case .starting:
                ProgressView("正在准备本地目录…")
            case .ready(let paths):
                Text("Catalog 已就绪")
                    .font(.headline)
                Text(paths.catalogDirectory.path(percentEncoded: false))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            case .failed(let message):
                Text("无法初始化 Catalog")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text(message)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
        }
        .frame(minWidth: 620, minHeight: 420)
        .padding(40)
    }
}
