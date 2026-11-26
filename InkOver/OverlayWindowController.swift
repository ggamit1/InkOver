import AppKit
import Carbon.HIToolbox
import Combine
import QuartzCore
import ScreenCaptureKit
import SwiftUI

@MainActor
final class OverlayWindowController: NSObject, NSWindowDelegate, ObservableObject {
    @Published private(set) var screenshotStatus: ScreenshotStatus = .ready

    private let session: AnnotationSession
    private let preferences: AppPreferences
    private var panel: AnnotationPanel?
    private var toolbarPanel: FloatingPanel?
    private weak var canvas: DrawingCanvasView?
    private var toolObserver: AnyCancellable?
    private var dockObserver: AnyCancellable?
    private var toolbarArea = CGRect.zero
    private var dragStart: (pointer: CGPoint, origin: CGPoint)?
    private var screenshotTask: Task<Void, Never>?

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
        let window = AnnotationPanel(frame: screen.frame, title: "ScreenInklet Annotation", level: menuLevel - 2)
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

    private func showToolbar(dock: ToolbarDock, animated: Bool = true) {
        guard toolbarPanel == nil, let canvas, let annotationScreen = panel?.screen else { return }
        let placement = preferences.toolbarPlacement
        let floatingScreen = placement.flatMap { placement in
            NSScreen.screens.first { $0.displayID == placement.displayID }
        }
        toolbarArea = (floatingScreen ?? annotationScreen).visibleFrame
        let toolbar = ToolbarHostingView(rootView: DrawingToolbar(
            session: session, preferences: preferences, overlay: self, dock: dock, availableSize: toolbarArea.size,
            onBoard: { [weak canvas, weak session] in
                canvas?.cancelText()
                session?.toggleBoard()
            }
        ))
        toolbar.sizingOptions = .intrinsicContentSize
        let size = toolbar.fittingSize
        let origin = toolbarOrigin(for: size, dock: dock, position: floatingScreen == nil ? nil : placement?.position)
        let frame = CGRect(origin: origin, size: size)
        let toolbarPanel = FloatingPanel(frame: frame, title: "ScreenInklet Toolbar",
                                         level: NSWindow.Level.mainMenu.rawValue - 1)
        toolbarPanel.contentView = toolbar
        self.toolbarPanel = toolbarPanel
        session.isToolbarVisible = true
        if animated { revealToolbar(toolbarPanel) } else { toolbarPanel.orderFrontRegardless() }
    }

    func resetToolbarPosition() {
        updateToolbarDock(preferences.toolbarDock)
    }

    private func updateToolbarDock(_ dock: ToolbarDock) {
        preferences.toolbarPlacement = nil
        rebuildToolbar(dock: dock)
    }

    private func rebuildToolbar(dock: ToolbarDock) {
        dragStart = nil
        guard let toolbarPanel else { return }
        self.toolbarPanel = nil
        toolbarPanel.close()
        showToolbar(dock: dock, animated: false)
    }

    private func toolbarOrigin(for size: CGSize, dock: ToolbarDock, position: CGPoint?) -> CGPoint {
        if let position {
            return CGPoint(x: toolbarArea.minX + position.x * max(0, toolbarArea.width - size.width),
                           y: toolbarArea.minY + position.y * max(0, toolbarArea.height - size.height))
        }
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
        screenshotTask?.cancel()
        screenshotTask = nil
        screenshotStatus = .ready
        toolObserver = nil
        canvas?.cancelText()
        panel.delegate = nil
        panel.ignoresMouseEvents = true
        panel.orderOut(nil)
        panel.close()
        session.deactivate()

        hideToolbar()
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

    func hideToolbar() {
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

    func moveToolbar(with event: NSEvent) {
        guard let toolbarPanel else { return }
        if event.type == .leftMouseDown {
            let pointer = toolbarPanel.convertPoint(toScreen: event.locationInWindow)
            dragStart = (pointer, toolbarPanel.frame.origin)
            return
        }
        guard let start = dragStart else { return }
        let pointer = NSEvent.mouseLocation
        let proposed = CGPoint(x: start.origin.x + pointer.x - start.pointer.x,
                               y: start.origin.y + pointer.y - start.pointer.y)
        if event.type == .leftMouseDragged {
            toolbarPanel.setFrameOrigin(proposed)
            return
        }
        dragStart = nil
        guard pointer != start.pointer || toolbarPanel.frame.origin != start.origin,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? toolbarPanel.screen,
              let displayID = screen.displayID else { return }

        let previousSize = toolbarArea.size
        toolbarArea = screen.visibleFrame
        let origin = clampedToolbarOrigin(proposed, size: toolbarPanel.frame.size)
        let travelX = max(0, toolbarArea.width - toolbarPanel.frame.width)
        let travelY = max(0, toolbarArea.height - toolbarPanel.frame.height)
        let position = CGPoint(x: travelX > 0 ? (origin.x - toolbarArea.minX) / travelX : 0.5,
                               y: travelY > 0 ? (origin.y - toolbarArea.minY) / travelY : 0.5)
        preferences.toolbarPlacement = ToolbarPlacement(displayID: displayID, position: position)
        if previousSize == toolbarArea.size {
            toolbarPanel.setFrameOrigin(origin)
        } else {
            rebuildToolbar(dock: preferences.toolbarDock)
        }
    }

    private func clampedToolbarOrigin(_ origin: CGPoint, size: CGSize) -> CGPoint {
        let x = min(max(origin.x, toolbarArea.minX), max(toolbarArea.minX, toolbarArea.maxX - size.width))
        let y = min(max(origin.y, toolbarArea.minY), max(toolbarArea.minY, toolbarArea.maxY - size.height))
        return CGPoint(x: x, y: y)
    }

    func takeScreenshot() {
        guard screenshotStatus != .capturing else { return }
        screenshotTask?.cancel()
        screenshotStatus = .capturing
        screenshotTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await copyScreenshot()
                guard !Task.isCancelled else { return }
                screenshotStatus = .copied
            } catch {
                guard !Task.isCancelled else { return }
                screenshotStatus = .failed(error.localizedDescription)
            }
            AccessibilityNotification.Announcement(screenshotStatus.help).post()
            if screenshotStatus == .copied {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                screenshotStatus = .ready
            }
            screenshotTask = nil
        }
    }

    private func copyScreenshot() async throws {
        try Task.checkCancellation()
        guard let panel, let displayID = panel.screen?.displayID else { throw ScreenshotError.unavailable }
        canvas?.displayIfNeeded()
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            if !CGPreflightScreenCaptureAccess() { throw ScreenshotError.permission }
            throw error
        }
        guard panel === self.panel, let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenshotError.unavailable
        }
        let excluded = content.windows.filter { $0.windowID == CGWindowID(toolbarPanel?.windowNumber ?? 0) }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        configuration.width = Int((filter.contentRect.width * scale).rounded())
        configuration.height = Int((filter.contentRect.height * scale).rounded())
        configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        try Task.checkCancellation()
        guard panel === self.panel else { throw ScreenshotError.unavailable }
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw ScreenshotError.clipboard
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setData(png, forType: .png) else { throw ScreenshotError.clipboard }
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

private enum ScreenshotError: LocalizedError {
    case permission, unavailable, clipboard

    var errorDescription: String? {
        switch self {
        case .permission: "Allow ScreenInklet to record the screen in System Settings, then try again."
        case .unavailable: "The annotation display is unavailable."
        case .clipboard: "The screenshot could not be copied to the clipboard."
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
