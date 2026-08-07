import SwiftUI

struct LibraryHomeView: View {
    @ObservedObject var model: ApplicationModel

    var body: some View {
        Group {
            switch model.startupState {
            case .starting:
                ProgressView("正在准备本地资料库…")
                    .frame(minWidth: 620, minHeight: 420)
            case .ready(let paths):
                libraryContent(paths: paths)
            case .failed(let message):
                ContentUnavailableView(
                    "无法初始化 Catalog",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
                .frame(minWidth: 620, minHeight: 420)
            }
        }
        .task(id: model.startupState) {
            while case .ready = model.startupState {
                try? await Task.sleep(for: .milliseconds(500))
                await model.refreshLibrary()
            }
        }
    }

    @ViewBuilder
    private func libraryContent(paths: CatalogPaths) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mac Photo Studio")
                        .font(.title2.weight(.semibold))
                    Text("Referenced Library — 原始媒体始终保留在原位置")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("添加文件夹…") {
                    model.presentAddFolderPanel()
                }
            }

            if let libraryError = model.libraryError {
                Label(libraryError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.footnote)
            }

            if model.mediaRoots.isEmpty {
                ContentUnavailableView(
                    "尚未添加媒体文件夹",
                    systemImage: "folder.badge.plus",
                    description: Text("从“文件 → 添加文件夹到资料库…”选择照片、视频、外置盘或 SD 卡目录。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.mediaRoots) { root in
                    MediaRootRow(
                        root: root,
                        scanStatus: model.scanStatuses.first(where: { $0.rootID == root.id }),
                        startScan: { Task { await model.startScan(for: root.id) } },
                        pause: { scanID in Task { await model.pause(scanID: scanID) } },
                        resume: { scanID in Task { await model.resume(scanID: scanID) } },
                        cancel: { scanID in Task { await model.cancel(scanID: scanID) } }
                    )
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }

            Text(paths.catalogDirectory.path(percentEncoded: false))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .padding(24)
        .frame(minWidth: 680, minHeight: 460)
    }
}

private struct MediaRootRow: View {
    let root: MediaRootRecord
    let scanStatus: ScanStatus?
    let startScan: () -> Void
    let pause: (UUID) -> Void
    let resume: (UUID) -> Void
    let cancel: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(root.displayName, systemImage: root.availability == .online ? "folder" : "externaldrive.badge.exclamationmark")
                    .font(.headline)
                availabilityLabel
                Spacer()
                controls
            }
            Text(root.lastKnownPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let scanStatus, !scanStatus.state.isTerminal {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text("已检查 \(scanStatus.progress.inspectedFiles) 个文件，发现 \(scanStatus.progress.discoveredMedia) 个媒体项目")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let scanStatus, scanStatus.state == .completed {
                Text("最近扫描：\(scanStatus.progress.indexedMedia) 个媒体项目；元数据读取失败 \(scanStatus.progress.metadataFailures) 个")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let errorMessage = scanStatus?.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    private var availabilityLabel: some View {
        Text(root.availability == .online ? "在线" : root.availability == .offline ? "离线" : "需要重新授权")
            .font(.caption.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(root.availability == .online ? Color.green.opacity(0.15) : Color.orange.opacity(0.18), in: Capsule())
    }

    @ViewBuilder
    private var controls: some View {
        if let scanStatus, scanStatus.state == .running {
            Button("暂停") { pause(scanStatus.id) }
            Button("取消", role: .cancel) { cancel(scanStatus.id) }
        } else if let scanStatus, scanStatus.state == .paused {
            Button("继续") { resume(scanStatus.id) }
            Button("取消", role: .cancel) { cancel(scanStatus.id) }
        } else {
            Button("重新扫描") { startScan() }
        }
    }
}
