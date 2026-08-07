import Foundation

/// Controls how catalogued RAW/JPEG sidecar pairs are presented in the library.
/// Pairing changes presentation only; both catalog records and both source files
/// remain intact.
enum RAWJPEGPairPreference: String, CaseIterable, Sendable {
    case showBoth
    case groupPairs
    case preferRAW

    var title: String {
        switch self {
        case .showBoth: "同时显示 RAW 和 JPEG"
        case .groupPairs: "组合显示 RAW + JPEG"
        case .preferRAW: "优先显示 RAW"
        }
    }
}

enum RAWJPEGPairing {
    private static let jpegExtensions: Set<String> = ["jpg", "jpeg"]

    /// Returns catalog records in their original order, with JPEG companions
    /// hidden only when the selected presentation mode requires it.
    static func visibleAssets(
        from assets: [LibraryAssetRecord],
        preference: RAWJPEGPairPreference
    ) -> [LibraryAssetRecord] {
        guard preference != .showBoth else { return assets }
        let pairedJPEGIDs = pairedJPEGAssetIDs(in: assets)
        return assets.filter { !pairedJPEGIDs.contains($0.id) }
    }

    /// RAW identifiers which have a JPEG companion. The library uses this to
    /// mark group-pair cards without storing pair state in the catalog.
    static func pairedRAWAssetIDs(in assets: [LibraryAssetRecord]) -> Set<UUID> {
        pairGroups(in: assets).values.reduce(into: Set<UUID>()) { result, group in
            guard !group.jpegIDs.isEmpty else { return }
            result.formUnion(group.rawIDs)
        }
    }

    static func pairedJPEGAssetIDs(in assets: [LibraryAssetRecord]) -> Set<UUID> {
        pairGroups(in: assets).values.reduce(into: Set<UUID>()) { result, group in
            guard !group.rawIDs.isEmpty else { return }
            result.formUnion(group.jpegIDs)
        }
    }

    private static func pairGroups(in assets: [LibraryAssetRecord]) -> [PairKey: PairGroup] {
        assets.reduce(into: [PairKey: PairGroup]()) { groups, asset in
            guard asset.mediaType == .photo, let key = pairKey(for: asset) else { return }
            var group = groups[key, default: PairGroup()]
            if RAWFormat.isRAW(asset.fileExtension) {
                group.rawIDs.insert(asset.id)
            } else if jpegExtensions.contains(asset.fileExtension.lowercased()) {
                group.jpegIDs.insert(asset.id)
            }
            groups[key] = group
        }
    }

    private static func pairKey(for asset: LibraryAssetRecord) -> PairKey? {
        guard RAWFormat.isRAW(asset.fileExtension) || jpegExtensions.contains(asset.fileExtension.lowercased()) else {
            return nil
        }
        let path = URL(filePath: asset.relativePath)
        let filenameStem = path.deletingPathExtension().lastPathComponent
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard !filenameStem.isEmpty else { return nil }
        return PairKey(
            rootID: asset.rootID,
            directory: path.deletingLastPathComponent().path(percentEncoded: false),
            filenameStem: filenameStem
        )
    }
}

private struct PairKey: Hashable {
    let rootID: UUID
    let directory: String
    let filenameStem: String
}

private struct PairGroup {
    var rawIDs = Set<UUID>()
    var jpegIDs = Set<UUID>()
}
