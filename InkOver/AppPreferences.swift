import AppKit
import SwiftUI

enum InkColor: String, CaseIterable, Identifiable {
    case coral, amber, mint, sky, lilac, white, black

    var id: Self { self }
    var title: String { rawValue.capitalized }

    var nsColor: NSColor {
        switch self {
        case .coral: NSColor(srgbRed: 1, green: 0.30, blue: 0.35, alpha: 1)
        case .amber: NSColor(srgbRed: 1, green: 0.77, blue: 0.31, alpha: 1)
        case .mint: NSColor(srgbRed: 0.34, green: 0.91, blue: 0.66, alpha: 1)
        case .sky: NSColor(srgbRed: 0.37, green: 0.74, blue: 1, alpha: 1)
        case .lilac: NSColor(srgbRed: 0.75, green: 0.63, blue: 1, alpha: 1)
        case .white: NSColor(srgbRed: 0.98, green: 0.98, blue: 1, alpha: 1)
        case .black: NSColor(srgbRed: 0.13, green: 0.14, blue: 0.17, alpha: 1)
        }
    }

    var color: Color { Color(nsColor: nsColor) }
}

enum InkWidth: Int, CaseIterable, Identifiable {
    case fine = 3
    case regular = 6
    case bold = 10

    var id: Self { self }
    var title: String {
        switch self {
        case .fine: "Fine"
        case .regular: "Regular"
        case .bold: "Bold"
        }
    }
}

enum InkTextSize: Int, CaseIterable, Identifiable {
    case small = 16
    case medium = 24
    case large = 36

    var id: Self { self }
    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }
}

enum ToolbarDock: String, CaseIterable, Identifiable {
    case top, bottom, left, right

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var isSide: Bool { self == .left || self == .right }
}

struct ToolbarPlacement {
    let displayID: CGDirectDisplayID
    let position: CGPoint
}

enum AutoClearDelay: Int, CaseIterable, Identifiable {
    case fiveSeconds = 5
    case tenSeconds = 10
    case thirtySeconds = 30
    case oneMinute = 60

    var id: Self { self }
    var title: String { "\(rawValue) seconds" }
}

enum BoardOrientation: String, CaseIterable, Identifiable {
    case horizontal, vertical

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var size: CGSize {
        switch self {
        case .horizontal: CGSize(width: 960, height: 600)
        case .vertical: CGSize(width: 600, height: 960)
        }
    }
}

enum BoardBackground: String, CaseIterable, Identifiable {
    case dark, white

    var id: Self { self }
    var title: String { rawValue.capitalized }

    var color: NSColor {
        switch self {
        case .dark: NSColor(srgbRed: 0.13, green: 0.14, blue: 0.17, alpha: 1)
        case .white: .white
        }
    }
}

@MainActor
final class AppPreferences: ObservableObject {
    private enum Key {
        static let inkColor = "inkColor"
        static let inkWidth = "inkWidth"
        static let inkTextSize = "inkTextSize"
        static let toolbarDock = "toolbarDock"
        static let toolbarPlacement = "toolbarPlacement"
        static let autoClearEnabled = "autoClearEnabled"
        static let autoClearDelay = "autoClearDelay"
        static let boardOrientation = "boardOrientation"
        static let boardBackground = "boardBackground"
        static let ringEnabled = "ringEnabled"
        static let ringColor = "ringColor"
        static let ringDiameter = "ringDiameter"
    }

    static let ringDiameterRange = 28.0...88.0

    private let defaults: UserDefaults

    @Published var inkColor: InkColor {
        didSet { defaults.set(inkColor.rawValue, forKey: Key.inkColor) }
    }

    @Published var inkWidth: InkWidth {
        didSet { defaults.set(inkWidth.rawValue, forKey: Key.inkWidth) }
    }

    @Published var inkTextSize: InkTextSize {
        didSet { defaults.set(inkTextSize.rawValue, forKey: Key.inkTextSize) }
    }

    @Published var toolbarDock: ToolbarDock {
        didSet { defaults.set(toolbarDock.rawValue, forKey: Key.toolbarDock) }
    }

    var toolbarPlacement: ToolbarPlacement? {
        get {
            guard let saved = defaults.dictionary(forKey: Key.toolbarPlacement),
                  let display = saved["display"] as? UInt32,
                  let x = saved["x"] as? Double, (0...1).contains(x),
                  let y = saved["y"] as? Double, (0...1).contains(y) else { return nil }
            return ToolbarPlacement(displayID: display, position: CGPoint(x: x, y: y))
        }
        set {
            if let newValue {
                defaults.set([
                    "display": newValue.displayID,
                    "x": newValue.position.x,
                    "y": newValue.position.y
                ] as [String: Any], forKey: Key.toolbarPlacement)
            } else {
                defaults.removeObject(forKey: Key.toolbarPlacement)
            }
        }
    }

    @Published var autoClearEnabled: Bool {
        didSet { defaults.set(autoClearEnabled, forKey: Key.autoClearEnabled) }
    }

    @Published var autoClearDelay: AutoClearDelay {
        didSet { defaults.set(autoClearDelay.rawValue, forKey: Key.autoClearDelay) }
    }

    @Published var boardOrientation: BoardOrientation {
        didSet { defaults.set(boardOrientation.rawValue, forKey: Key.boardOrientation) }
    }

    @Published var boardBackground: BoardBackground {
        didSet { defaults.set(boardBackground.rawValue, forKey: Key.boardBackground) }
    }

    @Published var ringEnabled: Bool {
        didSet { defaults.set(ringEnabled, forKey: Key.ringEnabled) }
    }

    @Published var ringColor: InkColor {
        didSet { defaults.set(ringColor.rawValue, forKey: Key.ringColor) }
    }

    @Published private(set) var ringDiameter: Double {
        didSet { defaults.set(ringDiameter, forKey: Key.ringDiameter) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        inkColor = InkColor(rawValue: defaults.string(forKey: Key.inkColor) ?? "") ?? .coral
        inkWidth = InkWidth(rawValue: defaults.integer(forKey: Key.inkWidth)) ?? .regular
        inkTextSize = InkTextSize(rawValue: defaults.integer(forKey: Key.inkTextSize)) ?? .medium
        toolbarDock = ToolbarDock(rawValue: defaults.string(forKey: Key.toolbarDock) ?? "") ?? .right
        autoClearEnabled = defaults.bool(forKey: Key.autoClearEnabled)
        autoClearDelay = AutoClearDelay(rawValue: defaults.integer(forKey: Key.autoClearDelay)) ?? .tenSeconds
        boardOrientation = BoardOrientation(rawValue: defaults.string(forKey: Key.boardOrientation) ?? "") ?? .horizontal
        boardBackground = BoardBackground(rawValue: defaults.string(forKey: Key.boardBackground) ?? "") ?? .dark
        ringEnabled = defaults.bool(forKey: Key.ringEnabled)
        ringColor = InkColor(rawValue: defaults.string(forKey: Key.ringColor) ?? "") ?? .amber
        let savedDiameter = defaults.double(forKey: Key.ringDiameter)
        ringDiameter = Self.ringDiameterRange.contains(savedDiameter) ? savedDiameter : 44
    }

    func setRingDiameter(_ value: Double) {
        guard value.isFinite else { return }
        ringDiameter = min(max(value, Self.ringDiameterRange.lowerBound), Self.ringDiameterRange.upperBound)
    }
}
