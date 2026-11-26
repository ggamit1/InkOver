import AppKit
import Combine

final class DrawingCanvasView: NSView, NSTextFieldDelegate {
    private let session: AnnotationSession
    private let preferences: AppPreferences
    private let visibleArea: CGRect
    private var boardPreferencesObserver: AnyCancellable?
    private var boardLayout: (key: BoardLayoutKey, viewport: BoardViewport)?
    private var redrawObserver: AnyCancellable?
    private var toolObserver: AnyCancellable?
    private var textDraft: TextDraft?

    private struct BoardLayoutKey: Equatable {
        let area: CGRect
        let orientation: BoardOrientation
        let dock: ToolbarDock
    }

    private struct TextDraft {
        let field: NSTextField
        let point: CGPoint
        let color: InkColor
        let size: InkTextSize
    }

    var isEditingText: Bool { textDraft != nil }

    init(session: AnnotationSession, preferences: AppPreferences, visibleArea: CGRect) {
        self.session = session
        self.preferences = preferences
        self.visibleArea = visibleArea
        super.init(frame: .zero)
        redrawObserver = session.redraw.sink { [weak self] in self?.needsDisplay = true }
        toolObserver = session.$tool.removeDuplicates().dropFirst().sink { [weak self] _ in
            guard let self else { return }
            cancelText()
            window?.invalidateCursorRects(for: self)
        }
        boardPreferencesObserver = Publishers.CombineLatest4(
            preferences.$boardOrientation.removeDuplicates(),
            preferences.$boardBackground.removeDuplicates(),
            preferences.$toolbarDock.removeDuplicates(),
            session.$isBoard.removeDuplicates()
        )
        .dropFirst()
        .sink { [weak self] _, _, _, isBoard in
            guard let self else { return }
            if isBoard {
                cancelText()
                session.cancelGesture()
                needsDisplay = true
            }
            window?.invalidateCursorRects(for: self)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Annotation canvas")
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        guard session.tool != .pointer else { return }
        let cursor: NSCursor = session.tool == .text ? .iBeam : .crosshair
        addCursorRect(boardViewport()?.contentFrame ?? bounds, cursor: cursor)
    }

    override func mouseDown(with event: NSEvent) {
        let location = point(for: event)
        let viewport = boardViewport()
        let area = viewport?.contentFrame ?? bounds
        guard area.contains(location) else { return }
        let canvasPoint = viewport?.canvasPoint(for: location) ?? location
        if session.tool == .text {
            beginText(at: location, canvasPoint: canvasPoint, area: area, scale: viewport?.scale ?? 1)
        } else {
            session.begin(at: canvasPoint, color: preferences.inkColor, width: preferences.inkWidth,
                          bounds: viewport?.canvasBounds ?? bounds)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isEditingText else { return }
        let location = point(for: event)
        let viewport = boardViewport()
        session.drag(to: viewport?.canvasPoint(for: location) ?? location, bounds: viewport?.canvasBounds ?? bounds)
    }

    override func mouseUp(with event: NSEvent) {
        guard !isEditingText else { return }
        let location = point(for: event)
        let viewport = boardViewport()
        session.end(at: viewport?.canvasPoint(for: location) ?? location, bounds: viewport?.canvasBounds ?? bounds)
    }

    private func point(for event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    private func boardViewport() -> BoardViewport? {
        guard session.isBoard else { return nil }
        let area = visibleArea.intersection(bounds)
        guard !area.isEmpty else { return nil }
        let key = BoardLayoutKey(area: area, orientation: preferences.boardOrientation, dock: preferences.toolbarDock)
        if let boardLayout, boardLayout.key == key { return boardLayout.viewport }
        let viewport = BoardViewport(visibleArea: area, dock: key.dock, orientation: key.orientation,
                                     artwork: session.boardArtworkBounds)
        boardLayout = (key, viewport)
        return viewport
    }

    private func beginText(at point: CGPoint, canvasPoint: CGPoint, area: CGRect, scale: CGFloat) {
        cancelText()
        let field = NSTextField()
        let width = min(310, max(1, area.width - 16))
        let font = NSFont.systemFont(ofSize: max(12, CGFloat(preferences.inkTextSize.rawValue) * scale), weight: .semibold)
        field.font = font
        field.placeholderString = "Type a label…"
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.setAccessibilityLabel("Annotation text")
        field.delegate = self
        field.target = self
        field.action = #selector(commitText)
        let height = field.intrinsicContentSize.height
        field.frame = CGRect(x: min(max(point.x, area.minX + 8), max(area.minX, area.maxX - width - 8)),
                             y: min(max(point.y - height, area.minY + 8), max(area.minY, area.maxY - height - 8)),
                             width: width, height: height)
        textDraft = TextDraft(field: field, point: canvasPoint, color: preferences.inkColor, size: preferences.inkTextSize)
        addSubview(field)
        if window?.makeFirstResponder(field) != true { cancelText() }
    }

    @objc private func commitText() {
        guard let draft = textDraft else { return }
        let text = draft.field.stringValue
        cancelText()
        session.addText(text, at: draft.point, color: draft.color, size: draft.size)
    }

    @discardableResult
    func cancelText() -> Bool {
        guard let draft = textDraft else { return false }
        removeTextField(draft)
        window?.makeFirstResponder(self)
        return true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let draft = textDraft, let field = notification.object as? NSTextField, field === draft.field else { return }
        removeTextField(draft)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.insertNewline(_:)), !textView.hasMarkedText(),
              let draft = textDraft else { return false }
        let text = textView.string
        cancelText()
        session.addText(text, at: draft.point, color: draft.color, size: draft.size)
        return true
    }

    private func removeTextField(_ draft: TextDraft) {
        textDraft = nil
        draft.field.delegate = nil
        draft.field.removeFromSuperview()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let viewport = boardViewport()
        if let viewport {
            context.setFillColor(red: 0.065, green: 0.071, blue: 0.090, alpha: 1)
            context.fill(dirtyRect)
            drawPaper(viewport.paperFrame, in: context)
        } else {
            // Keep the screen overlay hit-testable even where there is no ink.
            context.setFillColor(gray: 0, alpha: 0.012)
            context.fill(dirtyRect)
        }

        context.saveGState()
        defer { context.restoreGState() }
        if let viewport {
            context.clip(to: viewport.contentFrame)
            context.concatenate(viewport.canvasToView)
        }
        let inkBounds = viewport?.canvasBounds ?? bounds
        for mark in session.marks {
            mark.draw(in: context, bounds: inkBounds)
        }
        session.pending?.draw(in: context, bounds: inkBounds)
        if let point = session.eraserPoint {
            let radius = AnnotationSession.eraserRadius
            let circle = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            context.setStrokeColor(NSColor.black.withAlphaComponent(0.7).cgColor)
            context.setLineWidth(4)
            context.strokeEllipse(in: circle)
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(1.5)
            context.strokeEllipse(in: circle)
        }
    }

    private func drawPaper(_ frame: CGRect, in context: CGContext) {
        let path = CGPath(roundedRect: frame, cornerWidth: 15, cornerHeight: 15, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -5), blur: 18,
                          color: NSColor.black.withAlphaComponent(0.40).cgColor)
        context.setFillColor(preferences.boardBackground.color.cgColor)
        context.addPath(path)
        context.fillPath()
        context.restoreGState()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.10).cgColor)
        context.setLineWidth(1)
        context.addPath(path)
        context.strokePath()
    }
}

private struct BoardViewport {
    let paperFrame: CGRect
    let contentFrame: CGRect
    let canvasBounds: CGRect
    let canvasToView: CGAffineTransform
    let scale: CGFloat

    init(visibleArea: CGRect, dock: ToolbarDock, orientation: BoardOrientation, artwork: CGRect) {
        var room = visibleArea.insetBy(dx: min(24, visibleArea.width * 0.08),
                                      dy: min(20, visibleArea.height * 0.08))
        let sideClearance = min(260, room.width * 0.32)
        let rowClearance = min(92, room.height * 0.22)
        switch dock {
        case .left:
            room.origin.x += sideClearance
            room.size.width -= sideClearance
        case .right:
            room.size.width -= sideClearance
        case .top:
            room.size.height -= rowClearance
        case .bottom:
            room.origin.y += rowClearance
            room.size.height -= rowClearance
        }

        let size = orientation.size
        let pageScale = min(room.width / size.width, room.height / size.height)
        let pageWidth = size.width * pageScale
        let pageHeight = size.height * pageScale
        let paper = CGRect(x: room.midX - pageWidth / 2, y: room.midY - pageHeight / 2,
                           width: pageWidth, height: pageHeight)
        paperFrame = paper
        let content = paper.insetBy(dx: min(12, paper.width * 0.10), dy: min(12, paper.height * 0.10))
        contentFrame = content

        let nominalCanvas = CGRect(x: -size.width / 2, y: -size.height / 2,
                                   width: size.width, height: size.height)
        let fittedCanvas = artwork.isNull ? nominalCanvas : nominalCanvas.union(artwork.insetBy(dx: -6, dy: -6))
        let fit = min(content.width / fittedCanvas.width, content.height / fittedCanvas.height)
        let transform = CGAffineTransform(a: fit, b: 0, c: 0, d: fit,
                                          tx: content.midX - fittedCanvas.midX * fit,
                                          ty: content.midY - fittedCanvas.midY * fit)
        scale = fit
        canvasToView = transform
        canvasBounds = content.applying(transform.inverted())
    }

    func canvasPoint(for location: CGPoint) -> CGPoint {
        let clamped = CGPoint(x: min(max(location.x, contentFrame.minX), contentFrame.maxX),
                              y: min(max(location.y, contentFrame.minY), contentFrame.maxY))
        return clamped.applying(canvasToView.inverted())
    }
}
