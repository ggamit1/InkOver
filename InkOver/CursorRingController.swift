import AppKit
import Combine

@MainActor
final class CursorRingController {
    private var window: NSWindow?
    private var ring: RingView?
    private var timer: Timer?
    private var observers = Set<AnyCancellable>()
    private var diameter = 44.0
    private var color = InkColor.amber

    func observe(_ preferences: AppPreferences) {
        preferences.$ringDiameter.removeDuplicates().sink { [weak self] value in
            self?.diameter = value
            self?.updatePosition()
        }.store(in: &observers)

        preferences.$ringColor.removeDuplicates().sink { [weak self] color in
            self?.color = color
            self?.ring?.color = color
        }.store(in: &observers)

        preferences.$ringEnabled.removeDuplicates().sink { [weak self] enabled in
            if enabled {
                self?.start()
            } else {
                self?.stop()
            }
        }.store(in: &observers)
    }

    private func start() {
        guard window == nil else { return }
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        let ring = RingView()
        ring.color = color
        window.contentView = ring
        window.title = "InkOver Cursor Ring"
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isExcludedFromWindowsMenu = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.window = window
        self.ring = ring
        updatePosition()
        window.orderFrontRegardless()

        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePosition() }
        }
        timer.tolerance = 0.003
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updatePosition() {
        guard let window else { return }
        let pointer = NSEvent.mouseLocation
        let size = diameter + 8
        let frame = CGRect(x: pointer.x - size / 2, y: pointer.y - size / 2, width: size, height: size)
        if window.frame.size != frame.size {
            window.setFrame(frame, display: true)
        } else if window.frame.origin != frame.origin {
            window.setFrameOrigin(frame.origin)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        window?.close()
        window = nil
        ring = nil
    }
}

private final class RingView: NSView {
    var color = InkColor.amber {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let path = bounds.insetBy(dx: 4, dy: 4)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.7).cgColor)
        context.setLineWidth(5)
        context.strokeEllipse(in: path)
        context.setStrokeColor(color.nsColor.cgColor)
        context.setLineWidth(2.5)
        context.strokeEllipse(in: path)
    }
}
