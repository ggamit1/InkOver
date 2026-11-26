import SwiftUI

struct PreferencesView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var session: AnnotationSession

    var body: some View {
        Form {
            Section("Annotation") {
                LabeledContent("Ink color") {
                    InkSwatches(selection: $preferences.inkColor)
                }
                Picker("Line width", selection: $preferences.inkWidth) {
                    ForEach(InkWidth.allCases) { width in
                        Text(width.title).tag(width)
                    }
                }
                .pickerStyle(.segmented)
                Picker("Toolbar position", selection: $preferences.toolbarDock) {
                    ForEach(ToolbarDock.allCases) { dock in
                        Text(dock.title).tag(dock)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Auto-clear ink", isOn: $preferences.autoClearEnabled)
                Picker("Auto-clear delay", selection: $preferences.autoClearDelay) {
                    ForEach(AutoClearDelay.allCases) { delay in
                        Text(delay.title).tag(delay)
                    }
                }
                .disabled(!preferences.autoClearEnabled)
                LabeledContent("Toggle annotation") {
                    if session.shortcutError != nil {
                        Text("Shortcut unavailable")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(ShortcutController.displayName)
                            .monospaced()
                            .accessibilityLabel("Control Option Command I")
                    }
                }
            }

            Section("Board") {
                Picker("Orientation", selection: $preferences.boardOrientation) {
                    ForEach(BoardOrientation.allCases) { orientation in
                        Text(orientation.title).tag(orientation)
                    }
                }
                .pickerStyle(.segmented)
                Picker("Background", selection: $preferences.boardBackground) {
                    ForEach(BoardBackground.allCases) { background in
                        Text(background.title).tag(background)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Cursor ring") {
                Toggle("Show cursor ring", isOn: $preferences.ringEnabled)
                LabeledContent("Ring color") {
                    InkSwatches(selection: $preferences.ringColor)
                }
                LabeledContent("Diameter") {
                    HStack(spacing: 10) {
                        Slider(
                            value: Binding(
                                get: { preferences.ringDiameter },
                                set: preferences.setRingDiameter
                            ),
                            in: AppPreferences.ringDiameterRange, step: 1
                        )
                        .accessibilityLabel("Ring diameter")
                        Text("\(Int(preferences.ringDiameter)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                HStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .strokeBorder(.black.opacity(0.65), lineWidth: 5)
                        Circle()
                            .strokeBorder(preferences.ringColor.color, lineWidth: 2.5)
                    }
                    .frame(width: preferences.ringDiameter, height: preferences.ringDiameter)
                    .frame(width: 100, height: 100)
                    .accessibilityHidden(true)
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 435, height: 600)
    }
}
