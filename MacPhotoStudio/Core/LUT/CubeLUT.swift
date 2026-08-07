import CoreImage
import Foundation
import simd

enum LUTKind: String, Codable, Sendable, CaseIterable {
    case creative
    case technical
}

struct CubeLUT: Identifiable, Sendable, Equatable {
    let id: UUID
    var title: String
    var kind: LUTKind
    var dimension: Int
    var domainMinimum: SIMD3<Float>
    var domainMaximum: SIMD3<Float>
    var values: [SIMD3<Float>]
    var technicalMetadata: TechnicalLUTMetadata?
    var sourceURL: URL?
    var isImported: Bool
    var isFavorite: Bool

    var isIdentity: Bool {
        guard values.count == dimension * dimension * dimension else { return false }
        for blue in 0..<dimension {
            for green in 0..<dimension {
                for red in 0..<dimension {
                    let index = blue * dimension * dimension + green * dimension + red
                    let expected = SIMD3<Float>(Float(red), Float(green), Float(blue)) / Float(dimension - 1)
                    if simd_distance(values[index], expected) > 0.0001 { return false }
                }
            }
        }
        return true
    }
}

enum CubeLUTParser {
    static func parse(data: Data, identifier: UUID = UUID(), sourceURL: URL? = nil, imported: Bool = true) throws -> CubeLUT {
        guard let content = String(data: data, encoding: .utf8) else {
            throw StudioError.invalidLUT(message: "LUT 不是 UTF-8 文本。")
        }

        var title = sourceURL?.deletingPathExtension().lastPathComponent ?? "Untitled LUT"
        var dimension: Int?
        var domainMinimum = SIMD3<Float>(repeating: 0)
        var domainMaximum = SIMD3<Float>(repeating: 1)
        var values: [SIMD3<Float>] = []

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.split(separator: "#", maxSplits: 1).first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !line.isEmpty else { continue }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard let keyword = parts.first else { continue }
            switch keyword.uppercased() {
            case "TITLE":
                let name = line.dropFirst(keyword.count).trimmingCharacters(in: .whitespacesAndNewlines)
                title = name.trimmingCharacters(in: CharacterSet(charactersIn: "\"")).isEmpty ? title : name.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            case "LUT_3D_SIZE":
                guard parts.count == 2, let parsed = Int(parts[1]), [17, 33, 65].contains(parsed) else {
                    throw StudioError.invalidLUT(message: "仅支持 17、33 或 65 维的 LUT_3D_SIZE。")
                }
                dimension = parsed
            case "DOMAIN_MIN":
                domainMinimum = try vector(parts, directive: keyword)
            case "DOMAIN_MAX":
                domainMaximum = try vector(parts, directive: keyword)
            case "LUT_1D_SIZE":
                throw StudioError.invalidLUT(message: "当前只支持 3D .cube LUT。")
            default:
                guard parts.count == 3, let red = Float(parts[0]), let green = Float(parts[1]), let blue = Float(parts[2]) else {
                    throw StudioError.invalidLUT(message: "无法解析行：\(line)")
                }
                values.append(SIMD3<Float>(red, green, blue))
            }
        }

        guard let dimension else {
            throw StudioError.invalidLUT(message: "缺少 LUT_3D_SIZE。")
        }
        guard domainMaximum.x > domainMinimum.x,
              domainMaximum.y > domainMinimum.y,
              domainMaximum.z > domainMinimum.z else {
            throw StudioError.invalidLUT(message: "DOMAIN_MAX 必须大于 DOMAIN_MIN。")
        }
        let expectedCount = dimension * dimension * dimension
        guard values.count == expectedCount else {
            throw StudioError.invalidLUT(message: "LUT 数据数量为 \(values.count)，预期 \(expectedCount)。")
        }
        return CubeLUT(
            id: identifier,
            title: title,
            kind: .creative,
            dimension: dimension,
            domainMinimum: domainMinimum,
            domainMaximum: domainMaximum,
            values: values,
            technicalMetadata: nil,
            sourceURL: sourceURL,
            isImported: imported,
            isFavorite: false
        )
    }

    static func parse(url: URL, identifier: UUID = UUID(), imported: Bool = true) throws -> CubeLUT {
        try parse(data: Data(contentsOf: url), identifier: identifier, sourceURL: url, imported: imported)
    }

    private static func vector(_ parts: [String], directive: String) throws -> SIMD3<Float> {
        guard parts.count == 4, let red = Float(parts[1]), let green = Float(parts[2]), let blue = Float(parts[3]) else {
            throw StudioError.invalidLUT(message: "\(directive) 需要三个数值。")
        }
        return SIMD3<Float>(red, green, blue)
    }
}

enum LUTProcessor {
    static func apply(_ lut: CubeLUT, to image: CIImage, strength: Double) -> CIImage {
        let normalizedStrength = min(max(strength, 0), 1)
        guard normalizedStrength > 0 else { return image }
        let normalized = normalizeDomain(of: image, minimum: lut.domainMinimum, maximum: lut.domainMaximum)
        guard let cube = CIFilter(name: "CIColorCube") else { return image }
        cube.setValue(normalized, forKey: kCIInputImageKey)
        cube.setValue(lut.dimension, forKey: "inputCubeDimension")
        cube.setValue(cubeData(for: lut), forKey: "inputCubeData")
        let transformed = cube.outputImage ?? image
        guard normalizedStrength < 1 else { return transformed }
        return transformed.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: image,
            kCIInputMaskImageKey: CIImage(color: CIColor(red: CGFloat(normalizedStrength), green: CGFloat(normalizedStrength), blue: CGFloat(normalizedStrength), alpha: 1)).cropped(to: image.extent)
        ])
    }

    static func cubeData(for lut: CubeLUT) -> Data {
        var rgba: [Float] = []
        rgba.reserveCapacity(lut.values.count * 4)
        for value in lut.values {
            rgba.append(contentsOf: [value.x, value.y, value.z, 1])
        }
        return rgba.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func normalizeDomain(of image: CIImage, minimum: SIMD3<Float>, maximum: SIMD3<Float>) -> CIImage {
        let range = maximum - minimum
        guard minimum != SIMD3<Float>(repeating: 0) || maximum != SIMD3<Float>(repeating: 1) else { return image }
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(1 / range.x), y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: CGFloat(1 / range.y), z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(1 / range.z), w: 0),
            "inputBiasVector": CIVector(x: CGFloat(-minimum.x / range.x), y: CGFloat(-minimum.y / range.y), z: CGFloat(-minimum.z / range.z), w: 0)
        ])
    }
}
