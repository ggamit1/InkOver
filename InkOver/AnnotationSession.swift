import AppKit
import Combine

@MainActor
final class AnnotationSession: ObservableObject {
    @Published private(set) var tool: DrawingTool = .pen
    @Published private(set) var isAnnotating = false
    @Published var isToolbarVisible = false
    @Published private(set) var isBoard = false
    @Published private(set) var markCount = 0
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published var shortcutError: OSStatus?

    let redraw = PassthroughSubject<Void, Never>()
    private(set) var pending: DrawingMark?
    private(set) var eraserPoint: CGPoint?
    private var erasedIndices: Set<Int> = []
    private var previousDrawingTool: DrawingTool = .pen
    private var displayID: CGDirectDisplayID?
    private var canvases: [Surface: Canvas] = [:]
    private var autoClearDelay: AutoClearDelay?
    private var autoClearObserver: AnyCancellable?
    private var autoClearTasks: [Surface: Task<Void, Never>] = [:]

    static let eraserRadius: CGFloat = 12

    init(preferences: AppPreferences) {
        autoClearObserver = preferences.$autoClearEnabled.combineLatest(preferences.$autoClearDelay)
            .map { enabled, delay in enabled ? delay : nil }
            .removeDuplicates()
            .sink { [weak self] delay in self?.updateAutoClear(delay) }
    }

    private struct Surface: Hashable {
        let displayID: CGDirectDisplayID
        let isBoard: Bool
    }

    private var surface: Surface? {
        displayID.map { Surface(displayID: $0, isBoard: isBoard) }
    }

    var marks: [DrawingMark] {
        guard let surface, let canvas = canvases[surface] else { return [] }
        guard !erasedIndices.isEmpty else { return canvas.marks }
        return canvas.marks.enumerated().compactMap { erasedIndices.contains($0.offset) ? nil : $0.element }
    }

    var boardArtworkBounds: CGRect {
        guard isBoard, let surface, let canvas = canvases[surface] else { return .null }
        var bounds = CGRect.null
        // Each insertion represents an original mark, including marks that Undo or Redo can restore.
        for history in [canvas.undoHistory, canvas.redoHistory] {
            for case .insert(let entries) in history {
                for entry in entries {
                    bounds = bounds.union(entry.mark.artworkBounds)
                }
            }
        }
        return bounds
    }

    func cancelGesture() {
        guard pending != nil || eraserPoint != nil else { return }
        refresh()
    }

    func activate(displayID: CGDirectDisplayID) {
        self.displayID = displayID
        if tool == .pointer { tool = previousDrawingTool }
        isAnnotating = true
        refresh()
    }

    func deactivate() {
        displayID = nil
        isAnnotating = false
        refresh()
    }

    func selectTool(_ tool: DrawingTool) {
        guard self.tool != tool else { return }
        if tool == .pointer {
            isBoard = false
        } else {
            previousDrawingTool = tool
        }
        self.tool = tool
        refresh()
    }

    func toggleBoard() {
        guard isAnnotating else { return }
        if tool == .pointer { tool = previousDrawingTool }
        isBoard.toggle()
        refresh()
    }

    func retainDisplays(_ displayIDs: Set<CGDirectDisplayID>) {
        canvases = canvases.filter { displayIDs.contains($0.key.displayID) }
        for surface in Array(autoClearTasks.keys) where !displayIDs.contains(surface.displayID) {
            autoClearTasks.removeValue(forKey: surface)?.cancel()
        }
    }

    func begin(at point: CGPoint, color: InkColor, width: InkWidth, bounds: CGRect) {
        guard surface != nil else { return }
        switch tool {
        case .eraser:
            eraserPoint = point
            erase(to: point, bounds: bounds)
        case .pointer, .text:
            return
        default:
            pending = DrawingMark(tool: tool, color: color, width: width, start: point)
        }
        redraw.send()
    }

    func drag(to point: CGPoint, bounds: CGRect) {
        if eraserPoint != nil {
            erase(to: point, bounds: bounds)
        } else {
            pending?.update(to: point)
        }
        redraw.send()
    }

    func end(at point: CGPoint, bounds: CGRect) {
        guard let surface else { return }
        if eraserPoint != nil {
            erase(to: point, bounds: bounds)
            if let canvas = canvases[surface], !erasedIndices.isEmpty {
                let removed = erasedIndices.sorted().map { IndexedMark(index: $0, mark: canvas.marks[$0]) }
                canvases[surface]?.record(.remove(removed))
            }
            scheduleAutoClear(on: surface)
        } else if var mark = pending {
            mark.update(to: point)
            if mark.canCommit { append(mark, to: surface) }
            scheduleAutoClear(on: surface)
        }
        refresh()
    }

    func addText(_ text: String, at point: CGPoint, color: InkColor, size: InkTextSize) {
        guard let surface else { return }
        let cleaned = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !cleaned.isEmpty else { return }
        append(DrawingMark(tool: .text, color: color, width: .regular,
                           start: point, text: cleaned, textSize: size), to: surface)
        scheduleAutoClear(on: surface)
        refresh()
    }

    func undo() {
        guard let surface else { return }
        canvases[surface]?.undo()
        scheduleAutoClear(on: surface)
        refresh()
    }

    func redo() {
        guard let surface else { return }
        canvases[surface]?.redo()
        scheduleAutoClear(on: surface)
        refresh()
    }

    func clear() {
        guard let surface else { return }
        clear(on: surface)
    }

    private func clear(on surface: Surface) {
        guard let canvas = canvases[surface], !canvas.marks.isEmpty else { return }
        let removed = canvas.marks.enumerated().map { IndexedMark(index: $0.offset, mark: $0.element) }
        canvases[surface]?.record(.remove(removed))
        autoClearTasks.removeValue(forKey: surface)?.cancel()
        if surface == self.surface { refresh() }
    }

    private func updateAutoClear(_ delay: AutoClearDelay?) {
        autoClearDelay = delay
        for task in autoClearTasks.values { task.cancel() }
        autoClearTasks.removeAll()
        for surface in canvases.keys { scheduleAutoClear(on: surface) }
    }

    private func scheduleAutoClear(on surface: Surface) {
        autoClearTasks.removeValue(forKey: surface)?.cancel()
        guard let autoClearDelay, let canvas = canvases[surface], !canvas.marks.isEmpty else { return }
        autoClearTasks[surface] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(autoClearDelay.rawValue))
            guard !Task.isCancelled, let self else { return }
            autoClearTasks.removeValue(forKey: surface)
            if surface == self.surface, pending != nil || eraserPoint != nil {
                // Keep the mark indices stable until the active gesture finishes.
                scheduleAutoClear(on: surface)
            } else {
                clear(on: surface)
            }
        }
    }

    private func erase(to point: CGPoint, bounds: CGRect) {
        guard let eraserPoint, let surface else { return }
        let marks = canvases[surface]?.marks ?? []
        for (index, mark) in marks.enumerated() where !erasedIndices.contains(index) {
            if mark.hitTest(from: eraserPoint, to: point, radius: Self.eraserRadius, bounds: bounds) {
                erasedIndices.insert(index)
            }
        }
        self.eraserPoint = point
    }

    private func append(_ mark: DrawingMark, to surface: Surface) {
        let index = canvases[surface]?.marks.count ?? 0
        canvases[surface, default: Canvas()].record(.insert([IndexedMark(index: index, mark: mark)]))
    }

    private func refresh() {
        pending = nil
        eraserPoint = nil
        erasedIndices.removeAll()
        let canvas = surface.flatMap { canvases[$0] }
        markCount = canvas?.marks.count ?? 0
        canUndo = !(canvas?.undoHistory.isEmpty ?? true)
        canRedo = !(canvas?.redoHistory.isEmpty ?? true)
        redraw.send()
    }
}

private struct IndexedMark {
    let index: Int
    let mark: DrawingMark
}

private enum CanvasEdit {
    case insert([IndexedMark])
    case remove([IndexedMark])

    var inverse: Self {
        switch self {
        case .insert(let marks): .remove(marks)
        case .remove(let marks): .insert(marks)
        }
    }
}

private struct Canvas {
    var marks: [DrawingMark] = []
    var undoHistory: [CanvasEdit] = []
    var redoHistory: [CanvasEdit] = []

    mutating func record(_ edit: CanvasEdit) {
        apply(edit)
        undoHistory.append(edit)
        redoHistory.removeAll()
    }

    mutating func undo() {
        guard let edit = undoHistory.popLast() else { return }
        apply(edit.inverse)
        redoHistory.append(edit)
    }

    mutating func redo() {
        guard let edit = redoHistory.popLast() else { return }
        apply(edit)
        undoHistory.append(edit)
    }

    private mutating func apply(_ edit: CanvasEdit) {
        switch edit {
        case .insert(let entries):
            for entry in entries { marks.insert(entry.mark, at: entry.index) }
        case .remove(let entries):
            for entry in entries.reversed() { marks.remove(at: entry.index) }
        }
    }
}
