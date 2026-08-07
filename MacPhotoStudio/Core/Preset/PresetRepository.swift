import Foundation

actor PresetRepository {
    private let catalogStore: CatalogStore

    init(catalogStore: CatalogStore) {
        self.catalogStore = catalogStore
    }

    func presets() async throws -> [PhotoPreset] {
        try await catalogStore.photoPresets()
    }

    func create(named name: String, content: PhotoPresetContent, now: Date = .now) async throws -> PhotoPreset {
        try await catalogStore.createPhotoPreset(named: name, content: content, now: now)
    }

    func rename(_ preset: PhotoPreset, to name: String, now: Date = .now) async throws {
        try await catalogStore.renamePhotoPreset(preset.id, to: name, now: now)
    }

    func setFavorite(_ isFavorite: Bool, for preset: PhotoPreset, now: Date = .now) async throws {
        try await catalogStore.setPhotoPresetFavorite(isFavorite, for: preset.id, now: now)
    }

    func delete(_ preset: PhotoPreset) async throws {
        try await catalogStore.deletePhotoPreset(preset.id)
    }

    func export(_ preset: PhotoPreset, to destinationURL: URL) throws {
        guard !FileManager.default.fileExists(atPath: destinationURL.path(percentEncoded: false)) else {
            throw StudioError.exportFailed(message: "目标文件已存在：\(destinationURL.lastPathComponent)")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(PhotoPresetExchange(preset: preset)).write(to: destinationURL, options: .atomic)
        } catch {
            throw StudioError.invalidPreset(message: "无法写入预设文件：\(error.localizedDescription)")
        }
    }

    func importPreset(from sourceURL: URL, now: Date = .now) async throws -> PhotoPreset {
        let exchange: PhotoPresetExchange
        do {
            exchange = try JSONDecoder().decode(PhotoPresetExchange.self, from: Data(contentsOf: sourceURL))
        } catch {
            throw StudioError.invalidPreset(message: "无法读取预设文件：\(error.localizedDescription)")
        }
        guard exchange.version == PhotoPresetExchange.currentVersion else {
            throw StudioError.invalidPreset(message: "不支持的预设版本：\(exchange.version)")
        }
        // The source JSON is read only. A fresh Catalog record avoids external IDs
        // replacing any existing local preset.
        let existingNames = try await catalogStore.photoPresets().map(\.name)
        return try await catalogStore.createPhotoPreset(
            named: uniqueImportedName(exchange.name, excluding: existingNames),
            content: exchange.content,
            isFavorite: exchange.isFavorite,
            now: now
        )
    }

    private func uniqueImportedName(_ proposedName: String, excluding names: [String]) -> String {
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "导入预设" : trimmed
        let existing = Set(names.map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) })
        guard existing.contains(base.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)) else {
            return base
        }
        var suffix = 2
        while existing.contains("\(base) (\(suffix))".folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)) {
            suffix += 1
        }
        return "\(base) (\(suffix))"
    }
}
