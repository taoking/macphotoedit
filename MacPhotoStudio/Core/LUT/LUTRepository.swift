import Foundation

struct LUTLibrary: Sendable, Equatable {
    var builtIn: [CubeLUT]
    var imported: [CubeLUT]

    var favorites: [CubeLUT] {
        (builtIn + imported).filter(\.isFavorite)
    }

    var all: [CubeLUT] { builtIn + imported }
}

private struct StoredLUT: Codable, Sendable {
    var id: UUID
    var title: String
    var kind: LUTKind
    var technicalMetadata: TechnicalLUTMetadata?
    var fileName: String
    var isFavorite: Bool
}

/// Manages only user-imported LUT copies under Application Support.  It never
/// touches the original `.cube` selected by the user, and media source files are
/// never part of this repository.
actor LUTRepository {
    private let directoryURL: URL
    private let indexURL: URL
    private let fileManager: FileManager

    init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.indexURL = directoryURL.appending(path: "lut-index.json")
        self.fileManager = fileManager
    }

    func library() throws -> LUTLibrary {
        try ensureDirectory()
        let stored = try readIndex()
        var builtIn = Self.builtInLUTs
        for index in builtIn.indices {
            if let metadata = stored.first(where: { $0.id == builtIn[index].id && $0.fileName.isEmpty }) {
                builtIn[index].isFavorite = metadata.isFavorite
            }
        }
        var imported: [CubeLUT] = []
        for entry in stored {
            guard !entry.fileName.isEmpty else { continue }
            let url = directoryURL.appending(path: entry.fileName)
            guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { continue }
            do {
                var lut = try CubeLUTParser.parse(url: url, identifier: entry.id, imported: true)
                lut.title = entry.title
                // Phase 3–6 stored imported LUTs as creative by default. A
                // legacy technical entry without an explicit colour contract is
                // deliberately downgraded to creative instead of being allowed
                // to masquerade as a safe technical conversion.
                lut.kind = entry.kind == .technical && entry.technicalMetadata != nil ? .technical : .creative
                lut.technicalMetadata = lut.kind == .technical ? entry.technicalMetadata : nil
                lut.isFavorite = entry.isFavorite
                imported.append(lut)
            } catch {
                AppLogger.app.error("Skipping invalid imported LUT \(entry.fileName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return LUTLibrary(builtIn: builtIn, imported: imported.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
    }

    func lut(identifier: UUID) throws -> CubeLUT? {
        try library().all.first(where: { $0.id == identifier })
    }

    func importLUT(
        from sourceURL: URL,
        kind: LUTKind = .creative,
        technicalMetadata: TechnicalLUTMetadata? = nil
    ) throws -> CubeLUT {
        try ensureDirectory()
        if kind == .technical, technicalMetadata == nil {
            throw StudioError.invalidLUT(message: "导入 Technical LUT 前必须声明输入色彩空间、输出色彩空间和传递函数。")
        }
        let id = UUID()
        var lut = try CubeLUTParser.parse(url: sourceURL, identifier: id, imported: true)
        lut.kind = kind
        lut.technicalMetadata = kind == .technical ? technicalMetadata : nil
        let destinationName = "\(id.uuidString).cube"
        let destinationURL = directoryURL.appending(path: destinationName)
        // Persist validated bytes only after parsing. The user-selected source is read,
        // never renamed, moved, edited, or deleted.
        try Data(contentsOf: sourceURL).write(to: destinationURL, options: .atomic)
        lut.sourceURL = destinationURL
        var entries = try readIndex()
        entries.append(StoredLUT(
            id: id,
            title: lut.title,
            kind: lut.kind,
            technicalMetadata: lut.technicalMetadata,
            fileName: destinationName,
            isFavorite: false
        ))
        try writeIndex(entries)
        return lut
    }

    func renameImportedLUT(identifier: UUID, to proposedTitle: String) throws {
        let title = proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw StudioError.invalidLUT(message: "LUT 名称不能为空。") }
        var entries = try readIndex()
        guard let index = entries.firstIndex(where: { $0.id == identifier }) else {
            throw StudioError.invalidLUT(message: "只能重命名已导入的 LUT。")
        }
        entries[index].title = title
        try writeIndex(entries)
    }

    func setFavorite(_ isFavorite: Bool, identifier: UUID) throws {
        var entries = try readIndex()
        if let index = entries.firstIndex(where: { $0.id == identifier }) {
            entries[index].isFavorite = isFavorite
            try writeIndex(entries)
            return
        }
        // Built-ins remain immutable in content but their favorite setting is stored
        // alongside imported metadata using an entry without a physical file.
        guard Self.builtInLUTs.contains(where: { $0.id == identifier }) else {
            throw StudioError.invalidLUT(message: "未找到 LUT。")
        }
        let builtin = Self.builtInLUTs.first(where: { $0.id == identifier })!
        entries.append(StoredLUT(
            id: builtin.id,
            title: builtin.title,
            kind: builtin.kind,
            technicalMetadata: builtin.technicalMetadata,
            fileName: "",
            isFavorite: isFavorite
        ))
        try writeIndex(entries)
    }

    func deleteImportedLUT(identifier: UUID) throws {
        var entries = try readIndex()
        guard let index = entries.firstIndex(where: { $0.id == identifier && !$0.fileName.isEmpty }) else {
            throw StudioError.invalidLUT(message: "只能删除已导入的 LUT。")
        }
        let entry = entries.remove(at: index)
        let fileURL = directoryURL.appending(path: entry.fileName)
        if fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) {
            try fileManager.removeItem(at: fileURL)
        }
        try writeIndex(entries)
    }

    private func ensureDirectory() throws {
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw StudioError.directoryCreationFailed(path: directoryURL.path(percentEncoded: false))
        }
    }

    private func readIndex() throws -> [StoredLUT] {
        guard fileManager.fileExists(atPath: indexURL.path(percentEncoded: false)) else { return [] }
        do {
            return try JSONDecoder().decode([StoredLUT].self, from: Data(contentsOf: indexURL))
        } catch {
            throw StudioError.invalidLUT(message: "LUT 索引无法读取：\(error.localizedDescription)")
        }
    }

    private func writeIndex(_ entries: [StoredLUT]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entries).write(to: indexURL, options: .atomic)
    }

    private static let builtInLUTs: [CubeLUT] = [
        identityLUT(
            identifier: UUID(uuidString: "C0A78A98-27B3-4B5F-9C1A-0DAE3E19B117")!,
            title: "Identity 17",
            dimension: 17
        ),
        identityLUT(
            identifier: UUID(uuidString: "8D2EAAC0-07AF-42D2-A8E0-3B2BFF8D7533")!,
            title: "Identity 33",
            dimension: 33
        )
    ]

    private static func identityLUT(identifier: UUID, title: String, dimension: Int) -> CubeLUT {
        var values: [SIMD3<Float>] = []
        values.reserveCapacity(dimension * dimension * dimension)
        for blue in 0..<dimension {
            for green in 0..<dimension {
                for red in 0..<dimension {
                    values.append(SIMD3<Float>(Float(red), Float(green), Float(blue)) / Float(dimension - 1))
                }
            }
        }
        return CubeLUT(
            id: identifier,
            title: title,
            kind: .creative,
            dimension: dimension,
            domainMinimum: SIMD3<Float>(repeating: 0),
            domainMaximum: SIMD3<Float>(repeating: 1),
            values: values,
            technicalMetadata: nil,
            sourceURL: nil,
            isImported: false,
            isFavorite: false
        )
    }
}
