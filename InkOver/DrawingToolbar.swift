import SwiftUI

struct DrawingToolbar: View {
    @ObservedObject var session: AnnotationSession
    @ObservedObject var preferences: AppPreferences
    let dock: ToolbarDock
    let availableSize: CGSize
    let onBoard: () -> Void
    let onHide: () -> Void
    let onDone: () -> Void
    let onDrag: (Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: dock.isSide ? 24 : 31, style: .continuous)
    }
    private let outerPadding: CGFloat = 12
    private let selection = Color.primary.opacity(0.12)

    var body: some View {
        glassControls
            .padding(outerPadding)
            .fixedSize()
            .environment(\.colorScheme, session.isBoard ? .dark : colorScheme)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Drawing toolbar")
    }

    @ViewBuilder
    private var glassControls: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            controls.glassEffect(.regular.interactive(), in: shape)
        } else {
            frostedControls
        }
        #else
        frostedControls
        #endif
    }

    private var frostedControls: some View {
        controls
            .background(.regularMaterial, in: shape)
            .overlay {
                shape.strokeBorder(.primary.opacity(0.12))
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
    }

    @ViewBuilder
    private var controls: some View {
        if dock.isSide {
            sidebar
        } else {
            horizontalBar
        }
    }

    private var horizontalBar: some View {
        HStack(spacing: 6) {
            grip
            toolButton(.pointer)
            divider
            ViewThatFits(in: .horizontal) {
                toolStrip
                ScrollView(.horizontal) {
                    toolStrip
                }
                .scrollIndicators(.visible)
                .accessibilityLabel("Scrollable drawing tools")
            }
            hide
            done
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: max(1, availableSize.width - 2 * outerPadding))
        .foregroundStyle(.primary)
    }

    private var toolStrip: some View {
        HStack(spacing: 7) {
            tools
            divider
            colorControls
            divider
            sizeControls
            divider
            editControls
            divider
            presentationControls
        }
        .fixedSize()
    }

    private var sidebar: some View {
        VStack(spacing: 7) {
            HStack(spacing: 6) {
                grip.frame(width: 77)
                toolButton(.pointer)
            }
            sidebarDivider
            ViewThatFits(in: .vertical) {
                sidebarTools
                ScrollView(.vertical) {
                    sidebarTools
                }
                .scrollIndicators(.visible)
                .accessibilityLabel("Scrollable drawing tools")
            }
            sidebarDivider
            HStack(spacing: 6) {
                hide
                done
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxHeight: max(1, availableSize.height - 2 * outerPadding))
        .foregroundStyle(.primary)
    }

    private var sidebarTools: some View {
        VStack(spacing: 7) {
            let tools = drawingTools
            Grid(horizontalSpacing: 6, verticalSpacing: 3) {
                ForEach(Array(stride(from: 0, to: tools.count, by: 2)), id: \.self) { index in
                    GridRow {
                        ForEach(tools[index..<min(index + 2, tools.count)]) { tool in
                            toolButton(tool)
                        }
                    }
                }
            }
            sidebarDivider
            colorControls
            sizeControls
            sidebarDivider
            editControls
            presentationControls
        }
        .fixedSize()
    }

    private var sidebarDivider: some View {
        Rectangle().fill(.primary.opacity(0.13)).frame(width: 160, height: 1)
    }

    private var grip: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 29, height: 43)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in onDrag(false) }
                    .onEnded { _ in onDrag(true) }
            )
            .accessibilityLabel("Move toolbar")
            .help("Drag to move the toolbar")
    }

    private var drawingTools: [DrawingTool] {
        DrawingTool.allCases.filter { $0 != .pointer }
    }

    private var tools: some View {
        HStack(spacing: 2) {
            ForEach(drawingTools) { tool in
                toolButton(tool)
            }
        }
    }

    private func toolButton(_ tool: DrawingTool) -> some View {
        let selected = session.tool == tool
        return Button { session.selectTool(tool) } label: {
            VStack(spacing: 4) {
                Image(systemName: tool.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .scaleEffect(selected && !reduceMotion ? 1.08 : 1)
                Text(tool.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(width: dock.isSide ? 77 : 57, height: 47)
            .background(selected ? selection : .clear, in: RoundedRectangle(cornerRadius: 15))
            .contentShape(Rectangle())
            .animation(reduceMotion ? nil : .snappy(duration: 0.23), value: selected)
        }
        .buttonStyle(ToolbarButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(toolHelp(tool))
    }

    private func toolHelp(_ tool: DrawingTool) -> String {
        switch tool {
        case .pointer: "Use the app underneath while keeping your marks visible"
        case .text: "Click the canvas to add a label"
        default: tool.title
        }
    }

    private var colorControls: some View {
        HStack(spacing: 8) {
            Text("Color")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            InkSwatches(selection: $preferences.inkColor)
                .accessibilityLabel("Ink color")
        }
        .fixedSize()
    }

    private var sizeControls: some View {
        ZStack(alignment: .leading) {
            sizeRow("Text size") {
                ForEach(InkTextSize.allCases) { size in
                    option("\(size.rawValue)", selected: preferences.inkTextSize == size,
                           help: "\(size.title) text") {
                        preferences.inkTextSize = size
                    }
                }
            }
            .opacity(session.tool == .text ? 1 : 0)
            .allowsHitTesting(session.tool == .text)
            .accessibilityHidden(session.tool != .text)

            sizeRow("Width") {
                ForEach(InkWidth.allCases) { width in
                    option(width.title, selected: preferences.inkWidth == width,
                           help: "\(width.title) line width") {
                        preferences.inkWidth = width
                    }
                }
            }
            .opacity(session.tool == .text ? 0 : 1)
            .allowsHitTesting(session.tool != .text)
            .accessibilityHidden(session.tool == .text)
        }
        .fixedSize()
    }

    private func sizeRow<Options: View>(_ title: String, @ViewBuilder options: () -> Options) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 1, content: options)
        }
    }

    private func option(_ title: String, selected: Bool, help: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title)
                .fixedSize()
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 5)
                .frame(minWidth: 23, minHeight: 26)
                .background(selected ? selection : .clear, in: Capsule())
                .contentShape(Rectangle())
        }
        .buttonStyle(ToolbarButtonStyle())
        .accessibilityLabel(help)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(help)
    }

    private var editControls: some View {
        HStack(spacing: 1) {
            action("Undo", symbol: "arrow.uturn.backward", help: "Undo (⌘Z)", perform: session.undo)
                .disabled(!session.canUndo)
                .opacity(session.canUndo ? 1 : 0.35)
            action("Redo", symbol: "arrow.uturn.forward", help: "Redo (⇧⌘Z)", perform: session.redo)
                .disabled(!session.canRedo)
                .opacity(session.canRedo ? 1 : 0.35)
            action("Clear", symbol: "trash", help: "Clear this canvas", perform: session.clear)
                .disabled(session.markCount == 0)
                .opacity(session.markCount == 0 ? 0.35 : 1)
        }
    }

    private var presentationControls: some View {
        HStack(spacing: 1) {
            action("Board", symbol: "rectangle.on.rectangle", selected: session.isBoard,
                   help: session.isBoard ? "Return to the screen" : "Open the drawing board", perform: onBoard)
            boardOptions
            action("Ring", symbol: "cursorarrow.rays", selected: preferences.ringEnabled,
                   help: "Toggle the cursor ring") {
                preferences.ringEnabled.toggle()
            }
        }
    }

    private var boardOptions: some View {
        Menu {
            Picker("Orientation", selection: $preferences.boardOrientation) {
                ForEach(BoardOrientation.allCases) { orientation in
                    Text(orientation.title).tag(orientation)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Picker("Background", selection: $preferences.boardBackground) {
                ForEach(BoardBackground.allCases) { background in
                    Text(background.title).tag(background)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Options", systemImage: "slider.horizontal.3")
                .font(.system(size: 11, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Board options")
        .help("Board orientation and background")
    }

    private func action(
        _ title: String, symbol: String, selected: Bool = false, help: String,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            Label(title, systemImage: symbol)
                .fixedSize()
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 4)
                .frame(height: 29)
                .background(selected ? selection : .clear, in: Capsule())
                .contentShape(Rectangle())
        }
        .buttonStyle(ToolbarButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(help)
    }

    private var hide: some View {
        action("Hide", symbol: "eye.slash", help: "Hide toolbar. Show it from the InkOver menu.", perform: onHide)
    }

    private var done: some View {
        Button(action: onDone) {
            Label("Done", systemImage: "checkmark")
                .fixedSize()
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 9)
                .frame(height: 31)
                .background(selection, in: Capsule())
        }
        .buttonStyle(ToolbarButtonStyle())
        .help("Stop annotation (Esc)")
    }

    private var divider: some View {
        Rectangle().fill(.primary.opacity(0.13)).frame(width: 1, height: 18)
    }
}

private struct ToolbarButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.73 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: configuration.isPressed)
    }
}

struct InkSwatches: View {
    @Binding var selection: InkColor

    var body: some View {
        HStack(spacing: 1) {
            ForEach(InkColor.allCases) { swatch in
                let selected = selection == swatch
                Button { selection = swatch } label: {
                    Circle()
                        .fill(swatch.color)
                        .overlay {
                            Circle().strokeBorder(.black.opacity(0.22))
                        }
                        .frame(width: 13, height: 13)
                        .frame(width: 21, height: 25)
                        .background {
                            Circle()
                                .strokeBorder(.primary.opacity(selected ? 0.85 : 0), lineWidth: 1.5)
                                .frame(width: 20, height: 20)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(swatch.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .help(swatch.title)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
