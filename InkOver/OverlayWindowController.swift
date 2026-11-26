import AppKit
import Carbon.HIToolbox
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class OverlayWindowController: NSObject, NSWindowDelegate {
    private let session: AnnotationSession
    private let preferences: AppPreferences
    private var panel: AnnotationPanel?
    private var toolbarPanel: FloatingPanel?
    private weak var canvas: DrawingCanvasView?
    private var toolObserver: AnyCancellable?
    private var dockObserver: AnyCancellable?
    private var toolbarArea = CGRect.zero
    private var draggedToolbarOrigin: CGPoint?
    private var dragStart: (pointer: CGPoint, origin: CGPoint)?

    init(session: AnnotationSession, preferences: AppPreferences) {
        self.session = session
        self.preferences = preferences
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensDidChange),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(stop), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil
        )
        dockObserver = preferences.$toolbarDock.removeDuplicates().dropFirst().sink { [weak self] dock in
            self?.updateToolbarDock(dock)
        }
    }

    func toggle() {
        if session.isAnnotating {
            stop()
        } else {
            start()
        }
    }

    func start() {
        guard panel == nil else { return }
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main,
              let displayID = screen.displayID else { return }

        let menuLevel = NSWindow.Level.mainMenu.rawValue
        let window = AnnotationPanel(frame: screen.frame, title: "InkOver Annotation", level: menuLevel - 2)
        let visibleArea = screen.visibleFrame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        let canvas = DrawingCanvasView(session: session, preferences: preferences, visibleArea: visibleArea)
        window.contentView = canvas
        window.delegate = self
        window.initialFirstResponder = canvas
        window.onExit = { [weak self, weak canvas] in
            if canvas?.cancelText() != true { self?.stop() }
        }
        window.onHistory = { [weak canvas, weak session] redo in
            guard canvas?.isEditingText == false else { return false }
            if redo { session?.redo() } else { session?.undo() }
            return true
        }
        panel = window
        self.canvas = canvas

        session.activate(displayID: displayID)
        window.makeFirstResponder(canvas)
        window.orderFrontRegardless()
        window.makeKey()

        toolObserver = session.$tool.removeDuplicates().dropFirst().sink { [weak self] tool in
            self?.updateInput(for: tool)
        }

        toolbarArea = screen.visibleFrame
        showToolbar(dock: preferences.toolbarDock)
    }

    func toggleToolbar() {
        if panel == nil {
            start()
        } else if toolbarPanel == nil {
            showToolbar(dock: preferences.toolbarDock)
        } else {
            hideToolbar()
        }
    }

    private func showToolbar(dock: ToolbarDock) {
        guard toolbarPanel == nil, let canvas else { return }
        let toolbar = ToolbarHostingView(rootView: DrawingToolbar(
            session: session, preferences: preferences, dock: dock, availableSize: toolbarArea.size,
            onBoard: { [weak canvas, weak session] in
                canvas?.cancelText()
                session?.toggleBoard()
            },
            onHide: { [weak self] in self?.hideToolbar() },
            onDone: { [weak self] in self?.stop() },
            onDrag: { [weak self] ended in self?.moveToolbar(ended: ended) }
        ))
        toolbar.sizingOptions = .intrinsicContentSize
        let size = toolbar.fittingSize
        let origin = toolbarOrigin(for: size, dock: dock)
        let frame = CGRect(origin: origin, size: size)
        let toolbarPanel = FloatingPanel(frame: frame, title: "InkOver Toolbar",
                                         level: NSWindow.Level.mainMenu.rawValue - 1)
        toolbarPanel.contentView = toolbar
        self.toolbarPanel = toolbarPanel
        session.isToolbarVisible = true
        revealToolbar(toolbarPanel)
    }

    private func updateToolbarDock(_ dock: ToolbarDock) {
        dragStart = nil
        draggedToolbarOrigin = nil
        guard let toolbarPanel else { return }
        self.toolbarPanel = nil
        toolbarPanel.close()
        showToolbar(dock: dock)
    }

    private func toolbarOrigin(for size: CGSize, dock: ToolbarDock) -> CGPoint {
        if let draggedToolbarOrigin { return clampedToolbarOrigin(draggedToolbarOrigin, size: size) }
        let centerX = toolbarArea.midX - size.width / 2
        let inset: CGFloat = 10
        let origin: CGPoint
        switch dock {
        case .top:
            origin = CGPoint(x: centerX, y: toolbarArea.maxY - size.height - inset)
        case .bottom:
            origin = CGPoint(x: centerX, y: toolbarArea.minY + inset)
        case .left:
            origin = CGPoint(x: toolbarArea.minX + inset, y: toolbarArea.midY - size.height / 2)
        case .right:
            origin = CGPoint(x: toolbarArea.maxX - size.width - inset, y: toolbarArea.midY - size.height / 2)
        }
        return clampedToolbarOrigin(origin, size: size)
    }

    @objc func stop() {
        guard let panel else { return }
        self.panel = nil
        toolObserver = nil
        canvas?.cancelText()
        panel.delegate = nil
        panel.ignoresMouseEvents = true
        panel.orderOut(nil)
        panel.close()
        session.deactivate()

        hideToolbar()
        draggedToolbarOrigin = nil
    }

    private func updateInput(for tool: DrawingTool) {
        guard let panel, let canvas else { return }
        let isPointer = tool == .pointer
        guard panel.ignoresMouseEvents != isPointer else { return }
        panel.ignoresMouseEvents = isPointer
        if isPointer {
            canvas.cancelText()
            panel.disableCursorRects()
            // Ordering out relinquishes the nonactivating panel's key focus.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        } else {
            panel.enableCursorRects()
            panel.makeFirstResponder(canvas)
            panel.makeKey()
        }
    }

    private func revealToolbar(_ toolbar: NSWindow) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            toolbar.orderFrontRegardless()
            return
        }

        toolbar.alphaValue = 0
        toolbar.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.20
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            toolbar.animator().alphaValue = 1
        }
    }

    private func hideToolbar() {
        guard let toolbar = toolbarPanel else { return }
        toolbarPanel = nil
        dragStart = nil
        session.isToolbarVisible = false
        toolbar.ignoresMouseEvents = true
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            toolbar.close()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.13
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            toolbar.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in toolbar.close() }
        }
    }

    private func moveToolbar(ended: Bool) {
        guard let toolbarPanel else { return }
        let pointer = NSEvent.mouseLocation
        guard let start = dragStart else {
            if !ended { dragStart = (pointer, toolbarPanel.frame.origin) }
            return
        }
        if ended { dragStart = nil }
        let proposed = CGPoint(x: start.origin.x + pointer.x - start.pointer.x,
                               y: start.origin.y + pointer.y - start.pointer.y)
        let origin = clampedToolbarOrigin(proposed, size: toolbarPanel.frame.size)
        draggedToolbarOrigin = origin
        toolbarPanel.setFrameOrigin(origin)
    }

    private func clampedToolbarOrigin(_ origin: CGPoint, size: CGSize) -> CGPoint {
        let x = min(max(origin.x, toolbarArea.minX), max(toolbarArea.minX, toolbarArea.maxX - size.width))
        let y = min(max(origin.y, toolbarArea.minY), max(toolbarArea.minY, toolbarArea.maxY - size.height))
        return CGPoint(x: x, y: y)
    }

    @objc private func screensDidChange() {
        stop()
        session.retainDisplays(Set(NSScreen.screens.compactMap(\.displayID)))
    }

    func windowDidResignKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === panel, !window.ignoresMouseEvents {
            stop()
        }
    }
}

private class FloatingPanel: NSPanel {
    init(frame: CGRect, title: String, level: Int) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        setFrame(frame, display: false)
        self.title = title
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isMovable = false
        isExcludedFromWindowsMenu = true
        self.level = NSWindow.Level(rawValue: level)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    required init?(coder: NSCoder) { nil }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class ToolbarHostingView: NSHostingView<DrawingToolbar> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class AnnotationPanel: FloatingPanel {
    var onExit: (() -> Void)?
    var onHistory: ((Bool) -> Bool)?

    override var canBecomeKey: Bool { !ignoresMouseEvents }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if event.keyCode == UInt16(kVK_Escape), modifiers.isEmpty {
                onExit?()
                return
            }
            let historyShortcut = modifiers == .command || modifiers == [.command, .shift]
            if historyShortcut, event.charactersIgnoringModifiers?.lowercased() == "z",
               !event.isARepeat, onHistory?(modifiers.contains(.shift)) == true {
                return
            }
        }
        super.sendEvent(event)
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
