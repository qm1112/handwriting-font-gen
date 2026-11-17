import Foundation
import PencilKit
import CoreGraphics

struct ConvertedDrawing {
    let strokesJson: [[StrokePointData]]
    let mergedSvgPath: String
}

enum StrokeConverter {
    static let targetSize: CGFloat = 1000.0

    static func convert(drawing: PKDrawing, canvasSize: CGSize) -> ConvertedDrawing {
        let width = max(canvasSize.width, 1)
        let height = max(canvasSize.height, 1)
        let scaleX = targetSize / width
        let scaleY = targetSize / height
        let scaleW = targetSize / min(width, height)

        var allStrokesJson: [[StrokePointData]] = []
        var pathSegments: [String] = []

        for stroke in drawing.strokes {
            let sampled = stroke.path.interpolatedPoints(by: .distance(4.0))
            var points: [StrokePointData] = []
            for pt in sampled {
                let nx = clamp(Double(pt.location.x * scaleX), min: 0, max: Double(targetSize))
                let ny = clamp(Double(pt.location.y * scaleY), min: 0, max: Double(targetSize))
                let nw = max(1.0, Double(pt.size.width * scaleW))
                points.append(StrokePointData(
                    x: round2(nx),
                    y: round2(ny),
                    w: round2(nw)
                ))
            }

            if points.isEmpty, let first = stroke.path.first {
                let nx = clamp(Double(first.location.x * scaleX), min: 0, max: Double(targetSize))
                let ny = clamp(Double(first.location.y * scaleY), min: 0, max: Double(targetSize))
                let nw = max(1.0, Double(first.size.width * scaleW))
                points.append(StrokePointData(x: round2(nx), y: round2(ny), w: round2(nw)))
            }

            guard !points.isEmpty else { continue }
            allStrokesJson.append(points)

            if let svgSubpath = buildClosedOutline(for: points) {
                pathSegments.append(svgSubpath)
            }
        }

        return ConvertedDrawing(
            strokesJson: allStrokesJson,
            mergedSvgPath: pathSegments.joined(separator: " ")
        )
    }

    private static func buildClosedOutline(for points: [StrokePointData]) -> String? {
        if points.count == 1 {
            let p = points[0]
            let r = max(2.0, p.w * 0.5)
            return String(
                format: "M %.2f %.2f m -%.2f 0 a %.2f %.2f 0 1 0 %.2f 0 a %.2f %.2f 0 1 0 -%.2f 0 Z",
                p.x, p.y, r, r, r, r * 2, r, r, r * 2
            )
        }

        var leftSide: [CGPoint] = []
        var rightSide: [CGPoint] = []
        leftSide.reserveCapacity(points.count)
        rightSide.reserveCapacity(points.count)

        for i in 0..<points.count {
            let curr = points[i]
            let prev = points[max(0, i - 1)]
            let next = points[min(points.count - 1, i + 1)]

            var dx = next.x - prev.x
            var dy = next.y - prev.y
            let len = hypot(dx, dy)
            if len < 1e-5 {
                dx = 1
                dy = 0
            } else {
                dx /= len
                dy /= len
            }

            let nx = -dy
            let ny = dx
            let halfW = max(1.5, curr.w * 0.5)

            leftSide.append(CGPoint(x: curr.x + nx * halfW, y: curr.y + ny * halfW))
            rightSide.append(CGPoint(x: curr.x - nx * halfW, y: curr.y - ny * halfW))
        }

        var cmds: [String] = []
        cmds.reserveCapacity(leftSide.count + rightSide.count + 2)

        if let first = leftSide.first {
            cmds.append(String(format: "M %.2f %.2f", first.x, first.y))
        }
        for pt in leftSide.dropFirst() {
            cmds.append(String(format: "L %.2f %.2f", pt.x, pt.y))
        }
        for pt in rightSide.reversed() {
            cmds.append(String(format: "L %.2f %.2f", pt.x, pt.y))
        }
        cmds.append("Z")

        return cmds.joined(separator: " ")
    }

    private static func clamp(_ value: Double, min minVal: Double, max maxVal: Double) -> Double {
        Swift.max(minVal, Swift.min(maxVal, value))
    }

    private static func round2(_ value: Double) -> Double {
        (value * 100.0).rounded() / 100.0
    }
}
