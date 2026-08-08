import AppKit
import CoreGraphics
import SwiftUI

/// Maps the persistent, bottom-left-origin local-mask coordinates to the
/// aspect-fitted AppKit preview. Keeping this conversion separate from the
/// editor view makes direct manipulation deterministic at every window size.
enum LocalMaskCanvasGeometry {
    static func imageRect(container: CGSize, imageSize: CGSize) -> CGRect {
        guard container.width > 0, container.height > 0,
              imageSize.width > 0, imageSize.height > 0
        else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    static func viewPoint(x: Double, y: Double, in imageRect: CGRect) -> CGPoint {
        CGPoint(
            x: imageRect.minX + imageRect.width * CGFloat(clamp(x)),
            y: imageRect.minY + imageRect.height * CGFloat(1 - clamp(y))
        )
    }

    static func normalizedPoint(_ point: CGPoint, in imageRect: CGRect) -> CGPoint {
        guard imageRect.width > 0, imageRect.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(
            x: CGFloat(clamp(Double((point.x - imageRect.minX) / imageRect.width))),
            y: CGFloat(clamp(Double(1 - (point.y - imageRect.minY) / imageRect.height)))
        )
    }

    static func normalizedDistance(from center: CGPoint, to point: CGPoint, in imageRect: CGRect) -> Double {
        let scale = max(1, min(imageRect.width, imageRect.height))
        return Double(hypot(point.x - center.x, point.y - center.y) / scale)
    }

    static func translateLinearMask(_ mask: LocalMask, by delta: CGPoint) -> LocalMask {
        let startX = mask.clampedStartX
        let startY = mask.clampedStartY
        let endX = mask.clampedEndX
        let endY = mask.clampedEndY
        let dx = min(max(Double(delta.x), -min(startX, endX)), 1 - max(startX, endX))
        let dy = min(max(Double(delta.y), -min(startY, endY)), 1 - max(startY, endY))
        var translated = mask
        translated.startX = startX + dx
        translated.startY = startY + dy
        translated.endX = endX + dx
        translated.endY = endY + dy
        return translated
    }

    static func distanceToSegment(_ point: CGPoint, start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let projection = min(max(((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared, 0), 1)
        let nearest = CGPoint(x: start.x + projection * dx, y: start.y + projection * dy)
        return hypot(point.x - nearest.x, point.y - nearest.y)
    }

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
}

enum BrushMaskTool: String, CaseIterable, Identifiable, Equatable {
    case paint
    case erase

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paint: "绘制"
        case .erase: "擦除"
        }
    }
}

struct LocalMaskCanvas: View {
    let image: NSImage
    let enablesExtendedRange: Bool
    let mask: LocalMask
    let showsMaskOverlay: Bool
    let brushTool: BrushMaskTool
    let onMaskChange: (LocalMask) -> Void

    @State private var dragTarget: DragTarget?
    @State private var dragStartMask: LocalMask?
    @State private var activeBrushMask: LocalMask?
    @State private var activeBrushStrokeID: UUID?

    var body: some View {
        GeometryReader { proxy in
            let imageRect = LocalMaskCanvasGeometry.imageRect(container: proxy.size, imageSize: image.size)
            ZStack(alignment: .topLeading) {
                ExtendedRangeImageView(image: image, enablesExtendedRange: enablesExtendedRange)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                if !imageRect.isEmpty {
                    if showsMaskOverlay {
                        overlay(in: imageRect)
                            .allowsHitTesting(false)
                    }
                    controls(in: imageRect)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(interactionGesture(in: imageRect))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("局部蒙版画布")
            .accessibilityHint(accessibilityHint)
        }
    }

    private var accessibilityHint: String {
        switch mask.kind {
        case .linearGradient:
            "拖动线性蒙版的起点、终点或中线。"
        case .radialGradient:
            "拖动径向蒙版的中心、半径或羽化环。"
        case .brush:
            "在图像上拖动以\(brushTool.title)画笔蒙版。"
        case .subject:
            "主体蒙版由本机 Apple Vision 根据显著前景生成。"
        }
    }

    @ViewBuilder
    private func overlay(in imageRect: CGRect) -> some View {
        let alpha = 0.46 * max(0.2, mask.clampedOpacity)
        switch mask.kind {
        case .linearGradient:
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.red.opacity(alpha), Color.red.opacity(0.01)],
                        startPoint: UnitPoint(x: mask.clampedStartX, y: 1 - mask.clampedStartY),
                        endPoint: UnitPoint(x: mask.clampedEndX, y: 1 - mask.clampedEndY)
                    )
                )
                .frame(width: imageRect.width, height: imageRect.height)
                .position(x: imageRect.midX, y: imageRect.midY)
        case .radialGradient:
            let radius = CGFloat(mask.clampedRadius) * min(imageRect.width, imageRect.height)
            let outerRadius = CGFloat(mask.clampedRadius + mask.clampedFeather) * min(imageRect.width, imageRect.height)
            Rectangle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: .red.opacity(alpha), location: 0),
                            .init(color: .red.opacity(alpha), location: min(1, radius / max(outerRadius, 1))),
                            .init(color: .red.opacity(0.01), location: 1)
                        ]),
                        center: UnitPoint(x: mask.clampedCenterX, y: 1 - mask.clampedCenterY),
                        startRadius: 0,
                        endRadius: outerRadius
                    )
                )
                .frame(width: imageRect.width, height: imageRect.height)
                .position(x: imageRect.midX, y: imageRect.midY)
        case .brush:
            brushOverlay(in: imageRect)
        case .subject:
            EmptyView()
        }
    }

    @ViewBuilder
    private func controls(in imageRect: CGRect) -> some View {
        switch mask.kind {
        case .linearGradient:
            let start = LocalMaskCanvasGeometry.viewPoint(x: mask.clampedStartX, y: mask.clampedStartY, in: imageRect)
            let end = LocalMaskCanvasGeometry.viewPoint(x: mask.clampedEndX, y: mask.clampedEndY, in: imageRect)
            Path { path in
                path.move(to: start)
                path.addLine(to: end)
            }
            .stroke(.orange, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            canvasHandle(at: start, color: .white, label: "线性蒙版起点")
            canvasHandle(at: end, color: .orange, label: "线性蒙版终点")
            Text("拖动端点旋转，拖动中线移动")
                .font(.caption2)
                .foregroundStyle(.white)
                .padding(4)
                .background(.black.opacity(0.55), in: Capsule())
                .position(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 - 15)
        case .radialGradient:
            let center = LocalMaskCanvasGeometry.viewPoint(x: mask.clampedCenterX, y: mask.clampedCenterY, in: imageRect)
            let scale = min(imageRect.width, imageRect.height)
            let radius = CGFloat(mask.clampedRadius) * scale
            let feather = CGFloat(mask.clampedFeather) * scale
            Circle()
                .stroke(.orange, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .frame(width: radius * 2, height: radius * 2)
                .position(center)
            Circle()
                .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                .frame(width: (radius + feather) * 2, height: (radius + feather) * 2)
                .position(center)
            canvasHandle(at: center, color: .orange, label: "径向蒙版中心")
            canvasHandle(
                at: CGPoint(x: center.x + radius, y: center.y),
                color: .orange,
                label: "径向蒙版半径"
            )
            canvasHandle(
                at: CGPoint(x: center.x + radius + feather, y: center.y),
                color: .white,
                label: "径向蒙版羽化"
            )
        case .brush:
            Text("\(brushTool.title)画笔：在图像上拖动")
                .font(.caption2)
                .foregroundStyle(.white)
                .padding(4)
                .background(.black.opacity(0.55), in: Capsule())
                .position(x: imageRect.midX, y: imageRect.minY + 16)
        case .subject:
            Text("主体蒙版：本机 Vision 前景选择")
                .font(.caption2)
                .foregroundStyle(.white)
                .padding(4)
                .background(.black.opacity(0.55), in: Capsule())
                .position(x: imageRect.midX, y: imageRect.minY + 16)
        }
    }

    private func brushOverlay(in imageRect: CGRect) -> some View {
        ZStack {
            ForEach(mask.brushStrokes) { stroke in
                brushStrokeOverlay(stroke, in: imageRect)
            }
        }
        .frame(width: imageRect.width, height: imageRect.height)
        .position(x: imageRect.midX, y: imageRect.midY)
    }

    @ViewBuilder
    private func brushStrokeOverlay(_ stroke: BrushStroke, in imageRect: CGRect) -> some View {
        let points = stroke.points.map {
            let point = LocalMaskCanvasGeometry.viewPoint(x: $0.clamped.x, y: $0.clamped.y, in: imageRect)
            return CGPoint(x: point.x - imageRect.minX, y: point.y - imageRect.minY)
        }
        let color = stroke.erase ? Color.cyan : Color.red
        let width = max(1, CGFloat(stroke.clampedRadius) * min(imageRect.width, imageRect.height) * 2)
        if let point = points.first, points.count == 1 {
            Circle()
                .stroke(color.opacity(0.75), lineWidth: 1.5)
                .frame(width: width, height: width)
                .position(point)
        } else if !points.isEmpty {
            Path { path in
                path.move(to: points[0])
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(
                color.opacity(max(0.2, stroke.clampedOpacity * 0.75)),
                style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func canvasHandle(at point: CGPoint, color: Color, label: String) -> some View {
        Circle()
            .fill(color)
            .overlay(Circle().stroke(.black.opacity(0.7), lineWidth: 1))
            .frame(width: 12, height: 12)
            .position(point)
            .accessibilityLabel(label)
    }

    private func interactionGesture(in imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !imageRect.isEmpty else { return }
                if case .brush = mask.kind {
                    updateBrush(with: value, in: imageRect)
                    return
                }
                if dragTarget == nil {
                    dragTarget = target(at: value.startLocation, in: imageRect)
                    dragStartMask = mask
                }
                guard let dragTarget, let original = dragStartMask else { return }
                onMaskChange(updatedMask(
                    original,
                    target: dragTarget,
                    start: value.startLocation,
                    current: value.location,
                    imageRect: imageRect
                ))
            }
            .onEnded { _ in
                dragTarget = nil
                dragStartMask = nil
                activeBrushMask = nil
                activeBrushStrokeID = nil
            }
    }

    private func updateBrush(with value: DragGesture.Value, in imageRect: CGRect) {
        if activeBrushMask == nil {
            guard imageRect.contains(value.startLocation) else { return }
            let point = LocalMaskCanvasGeometry.normalizedPoint(value.location, in: imageRect)
            let stroke = BrushStroke(
                points: [BrushPoint(x: point.x, y: point.y)],
                radius: mask.clampedBrushSize,
                hardness: 1 - mask.clampedBrushFeather,
                opacity: mask.clampedBrushFlow,
                erase: brushTool == .erase
            )
            var updated = mask
            updated.brushStrokes.append(stroke)
            activeBrushMask = updated
            activeBrushStrokeID = stroke.id
            onMaskChange(updated)
            return
        }

        guard var updated = activeBrushMask,
              let activeBrushStrokeID,
              let index = updated.brushStrokes.firstIndex(where: { $0.id == activeBrushStrokeID })
        else { return }
        let point = LocalMaskCanvasGeometry.normalizedPoint(value.location, in: imageRect)
        updated.brushStrokes[index].append(BrushPoint(x: point.x, y: point.y))
        activeBrushMask = updated
        onMaskChange(updated)
    }

    private func target(at point: CGPoint, in imageRect: CGRect) -> DragTarget? {
        switch mask.kind {
        case .linearGradient:
            let start = LocalMaskCanvasGeometry.viewPoint(x: mask.clampedStartX, y: mask.clampedStartY, in: imageRect)
            let end = LocalMaskCanvasGeometry.viewPoint(x: mask.clampedEndX, y: mask.clampedEndY, in: imageRect)
            if Self.distance(point, start) < 14 { return .linearStart }
            if Self.distance(point, end) < 14 { return .linearEnd }
            if LocalMaskCanvasGeometry.distanceToSegment(point, start: start, end: end) < 12 { return .linearPosition }
        case .radialGradient:
            let center = LocalMaskCanvasGeometry.viewPoint(x: mask.clampedCenterX, y: mask.clampedCenterY, in: imageRect)
            let distance = LocalMaskCanvasGeometry.normalizedDistance(from: center, to: point, in: imageRect)
            if Self.distance(point, center) < 12 { return .radialCenter }
            if abs(distance - mask.clampedRadius) < 0.035 { return .radialRadius }
            if abs(distance - (mask.clampedRadius + mask.clampedFeather)) < 0.035 { return .radialFeather }
        case .brush:
            return nil
        case .subject:
            return nil
        }
        return nil
    }

    private func updatedMask(
        _ original: LocalMask,
        target: DragTarget,
        start: CGPoint,
        current: CGPoint,
        imageRect: CGRect
    ) -> LocalMask {
        var updated = original
        let point = LocalMaskCanvasGeometry.normalizedPoint(current, in: imageRect)
        switch target {
        case .linearStart:
            updated.startX = point.x
            updated.startY = point.y
        case .linearEnd:
            updated.endX = point.x
            updated.endY = point.y
        case .linearPosition:
            let initial = LocalMaskCanvasGeometry.normalizedPoint(start, in: imageRect)
            updated = LocalMaskCanvasGeometry.translateLinearMask(
                original,
                by: CGPoint(x: point.x - initial.x, y: point.y - initial.y)
            )
        case .radialCenter:
            updated.centerX = point.x
            updated.centerY = point.y
        case .radialRadius, .radialFeather:
            let center = LocalMaskCanvasGeometry.viewPoint(
                x: original.clampedCenterX,
                y: original.clampedCenterY,
                in: imageRect
            )
            let distance = LocalMaskCanvasGeometry.normalizedDistance(from: center, to: current, in: imageRect)
            if target == .radialRadius {
                updated.radius = min(max(distance, 0.01), 1)
            } else {
                updated.feather = min(max(distance - original.clampedRadius, 0.001), 1)
            }
        }
        return updated
    }

    private static func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private enum DragTarget: Equatable {
        case linearStart
        case linearEnd
        case linearPosition
        case radialCenter
        case radialRadius
        case radialFeather
    }
}
