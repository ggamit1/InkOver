import AppKit
import SwiftUI

@main
struct AnnotationApp: App {
    @NSApplicationDelegateAdaptor(ScreenInkletDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            StatusMenu(delegate: delegate, session: delegate.session, preferences: delegate.preferences)
        } label: {
            StatusLabel(session: delegate.session)
        }

        Settings {
            PreferencesView(preferences: delegate.preferences, session: delegate.session)
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
final class ScreenInkletDelegate: NSObject, NSApplicationDelegate {
    let session: AnnotationSession
    let preferences: AppPreferences
    private let ring = CursorRingController()
    private let shortcut = ShortcutController()
    lazy var overlay = OverlayWindowController(session: session, preferences: preferences)

    override init() {
        let preferences = AppPreferences()
        self.preferences = preferences
        session = AnnotationSession(preferences: preferences)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ring.observe(preferences)
        session.shortcutError = shortcut.register { [weak self] in self?.overlay.toggle() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlay.stop()
        ring.stop()
        shortcut.stop()
    }
}

private struct StatusLabel: View {
    @ObservedObject var session: AnnotationSession

    var body: some View {
        Image(systemName: session.isAnnotating ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
            .accessibilityLabel(session.isAnnotating ? "ScreenInklet, annotating" : "ScreenInklet")
    }
}

private struct StatusMenu: View {
    let delegate: ScreenInkletDelegate
    @ObservedObject var session: AnnotationSession
    @ObservedObject var preferences: AppPreferences
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if session.isAnnotating {
            Button("Stop Annotation", action: delegate.overlay.stop)
        } else {
            Button("Start Annotation", action: delegate.overlay.start)
        }

        if let error = session.shortcutError {
            Text("Shortcut unavailable (\(error))")
        } else {
            Text("Toggle with \(ShortcutController.displayName)")
        }

        Divider()
        Button(session.isToolbarVisible ? "Hide Toolbar" : "Show Toolbar", action: delegate.overlay.toggleToolbar)
        Menu("Toolbar Position") {
            Picker("Toolbar Position", selection: $preferences.toolbarDock) {
                ForEach(ToolbarDock.allCases) { dock in
                    Text(dock.title).tag(dock)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Reset to Selected Edge", action: delegate.overlay.resetToolbarPosition)
        }

        Divider()
        Toggle("Cursor Ring", isOn: $preferences.ringEnabled)
        Button("Settings…") {
            delegate.overlay.stop()
            openSettings()
            NSApp.activate()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()
        Button("Quit ScreenInklet") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
