import AppKit

/// A restrained echo of Cue's blue icon, resolved only when appearance changes.
@MainActor
enum LauncherAppearance {
    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    static let selection = NSColor(name: nil) { appearance in
        isDark(appearance)
            ? NSColor(srgbRed: 0.30, green: 0.65, blue: 0.90, alpha: 0.22)
            : NSColor(srgbRed: 0.16, green: 0.47, blue: 0.72, alpha: 0.15)
    }
}

@MainActor
final class LauncherBackdrop: NSVisualEffectView {
    private let tint = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.borderWidth = 1
        tint.wantsLayer = true
        addSubview(tint)
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        tint.frame = bounds
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func updateColors() {
        let dark = LauncherAppearance.isDark(effectiveAppearance)
        tint.layer?.backgroundColor = NSColor(
            srgbRed: 0.18, green: 0.48, blue: 0.72, alpha: dark ? 0.12 : 0.065
        ).cgColor
        layer?.borderColor = NSColor(
            srgbRed: 0.42, green: 0.68, blue: 0.88, alpha: dark ? 0.22 : 0.18
        ).cgColor
    }
}
