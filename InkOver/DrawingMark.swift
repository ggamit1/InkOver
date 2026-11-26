import AppKit

enum DrawingTool: String, CaseIterable, Identifiable {
    case pointer, pen, highlighter, line, arrow, rectangle, oval, text, eraser

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var samplesFreehand: Bool { self == .pen || self == .highlighter }

    var symbol: String {
        switch self {
        case .pointer: "cursorarrow"
        case .pen: "pencil.tip"
        case .highlighter: "highlighter"
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .oval: "oval"
        case .text: "textformat"
        case .eraser: "eraser"
        }
    }
}

struct DrawingMark {
    let tool: DrawingTool
    let color: InkColor
    let width: InkWidth
    let start: CGPoint
    private(set) var end: CGPoint
    private var points: [CGPoint]
    private let text: String
    private let textSize: InkTextSize

    init(
        tool: DrawingTool, color: InkColor, width: InkWidth, start: CGPoint,
        text: String = "", textSize: InkTextSize = .medium
    ) {
        self.tool = tool
        self.color = color
        self.width = width
        self.start = start
        self.text = text
        self.textSize = textSize
        end = start
        points = tool.samplesFreehand ? [start] : []
    }

    mutating func update(to point: CGPoint) {
        guard point != end else { return }
        end = point
        if tool.samplesFreehand {
            points.append(point)
        }
    }

    var canCommit: Bool {
        switch tool {
        case .pen, .highlighter: true
        case .line, .arrow: distance >= 4
        case .rectangle, .oval: rectangle.width >= 4 && rectangle.height >= 4
        case .text: !text.isEmpty
        case .pointer, .eraser: false
        }
    }

    private var lineWidth: CGFloat {
        CGFloat(width.rawValue) * (tool == .highlighter ? 3 : 1)
    }

    private var distance: CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    private var rectangle: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    private var outline: CGPath {
        let path = CGMutablePath()
        switch tool {
        case .pen, .highlighter:
            path.addLines(between: points)
        case .line, .arrow:
            path.addLines(between: [start, end])
            if tool == .arrow, distance > 0 {
                let angle = atan2(end.y - start.y, end.x - start.x)
                let length = min(max(12, lineWidth * 3), distance * 0.52)
                let spread = CGFloat.pi / 6
                let left = CGPoint(x: end.x - length * cos(angle + spread), y: end.y - length * sin(angle + spread))
                let right = CGPoint(x: end.x - length * cos(angle - spread), y: end.y - length * sin(angle - spread))
                path.addLines(between: [left, end, right])
            }
        case .rectangle: path.addRect(rectangle)
        case .oval: path.addEllipse(in: rectangle)
        case .pointer, .text, .eraser: break
        }
        return path
    }

    func draw(in context: CGContext, bounds: CGRect) {
        context.saveGState()
        defer { context.restoreGState() }

        if tool == .text {
            let layout = textLayout(in: bounds)
            let background = CGPath(roundedRect: layout.frame, cornerWidth: 7, cornerHeight: 7, transform: nil)
            context.setFillColor(gray: color == .black ? 0.96 : 0.07, alpha: 0.92)
            context.addPath(background)
            context.fillPath()
            layout.content.draw(with: layout.frame.insetBy(dx: 8, dy: 4),
                                options: [.usesLineFragmentOrigin, .usesFontLeading])
            return
        }

        let ink = color.nsColor.withAlphaComponent(tool == .highlighter ? 0.38 : 1).cgColor
        if points.count == 1 {
            context.setFillColor(ink)
            context.fillEllipse(in: CGRect(x: start.x - lineWidth / 2, y: start.y - lineWidth / 2,
                                           width: lineWidth, height: lineWidth))
        } else {
            context.setStrokeColor(ink)
            context.setLineWidth(lineWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.addPath(outline)
            context.strokePath()
        }
    }

    func hitTest(from origin: CGPoint, to point: CGPoint, radius: CGFloat, bounds: CGRect) -> Bool {
        let steps = max(1, Int(ceil(hypot(point.x - origin.x, point.y - origin.y) / radius)))
        let locations = (0...steps).lazy.map { index in
            let fraction = CGFloat(index) / CGFloat(steps)
            return CGPoint(x: origin.x + (point.x - origin.x) * fraction,
                           y: origin.y + (point.y - origin.y) * fraction)
        }
        if tool == .text {
            let frame = textLayout(in: bounds).frame.insetBy(dx: -radius, dy: -radius)
            return locations.contains { frame.contains($0) }
        }
        if points.count == 1 {
            return locations.contains { hypot($0.x - start.x, $0.y - start.y) <= radius + lineWidth / 2 }
        }
        let path = outline
        let sweep = CGRect(x: min(origin.x, point.x), y: min(origin.y, point.y),
                           width: abs(point.x - origin.x), height: abs(point.y - origin.y))
            .insetBy(dx: -(radius + lineWidth), dy: -(radius + lineWidth))
        guard sweep.intersects(path.boundingBoxOfPath.insetBy(dx: -1, dy: -1)) else { return false }
        let stroke = path.copy(strokingWithWidth: lineWidth + 2 * radius, lineCap: .round,
                               lineJoin: .round, miterLimit: 2)
        return locations.contains { stroke.contains($0) }
    }

    var artworkBounds: CGRect {
        if tool == .text {
            let size = measuredText(maxWidth: 400).size
            return CGRect(x: start.x, y: start.y - size.height, width: size.width, height: size.height)
        }
        let geometry = points.count == 1 ? CGRect(origin: start, size: .zero) : outline.boundingBoxOfPath
        return geometry.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
    }

    private func textLayout(in bounds: CGRect) -> (content: NSAttributedString, frame: CGRect) {
        let (content, size) = measuredText(maxWidth: max(1, min(400, bounds.width - 28)))
        let height = min(max(1, bounds.height - 12), size.height)
        let x = min(max(start.x, bounds.minX + 6), max(bounds.minX, bounds.maxX - size.width - 6))
        let y = min(max(start.y - height, bounds.minY + 6), max(bounds.minY, bounds.maxY - height - 6))
        return (content, CGRect(x: x, y: y, width: size.width, height: height))
    }

    private func measuredText(maxWidth: CGFloat) -> (content: NSAttributedString, size: CGSize) {
        let content = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: CGFloat(textSize.rawValue), weight: .semibold),
            .foregroundColor: color.nsColor,
        ])
        let measured = content.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                                            options: [.usesLineFragmentOrigin, .usesFontLeading])
        return (content, CGSize(width: min(maxWidth, ceil(measured.width)) + 16, height: ceil(measured.height) + 8))
    }
}
