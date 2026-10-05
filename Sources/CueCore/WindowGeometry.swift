import Foundation
import CoreGraphics

public enum WindowDirection: String, Codable, CaseIterable, Sendable {
    case left, right, up, down
}

/// All geometry uses desktop points and the AX top-left coordinate system.
public struct WindowScreen: Equatable, Sendable {
    public let id: UInt32
    public let frame: CGRect
    public let visibleFrame: CGRect

    public init(id: UInt32, frame: CGRect, visibleFrame: CGRect) {
        self.id = id; self.frame = frame; self.visibleFrame = visibleFrame
    }
}

public struct WindowPreset: Codable, Equatable, Sendable, Identifiable {
    public let slot: Int
    public let name: String
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public var id: Int { slot }

    public init(slot: Int, name: String, x: Double, y: Double, width: Double, height: Double) {
        self.slot = slot; self.name = name; self.x = x; self.y = y
        self.width = width; self.height = height
    }

    public var isValid: Bool {
        (1...9).contains(slot) && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && name.count <= 80 && !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            && [x, y, width, height].allSatisfy(\.isFinite)
            && x >= 0 && x <= 1 && y >= 0 && y <= 1 && width > 0 && width <= 1 && height > 0 && height <= 1
            && x + width <= 1.000_000_001 && y + height <= 1.000_000_001
    }
}

public enum WindowAction: Equatable, Sendable {
    case half(WindowDirection), move(WindowDirection), fill, center, restore, preset(WindowPreset)
}

public enum WindowGeometry {
    public static func isUsable(_ frame: CGRect) -> Bool {
        [frame.origin.x, frame.origin.y, frame.width, frame.height, frame.maxX, frame.maxY].allSatisfy(\.isFinite)
            && frame.width > 0 && frame.height > 0
    }

    /// primaryFrame is NSScreen.screens.first.frame, never NSScreen.main.
    public static func accessibilityFrame(fromAppKit frame: CGRect, primaryFrame: CGRect) -> CGRect {
        CGRect(x: frame.minX, y: primaryFrame.maxY - frame.maxY, width: frame.width, height: frame.height)
    }

    public static func screens(_ screens: [WindowScreen]) -> [WindowScreen] {
        // Mirrored outputs describe one work area. Stable IDs also settle every tie.
        var frames = Set<String>()
        return screens.sorted { $0.id < $1.id }.filter { screen in
            guard isUsable(screen.frame), isUsable(screen.visibleFrame) else { return false }
            let f = screen.frame
            return frames.insert("\(f.minX),\(f.minY),\(f.width),\(f.height)").inserted
        }
    }

    public static func currentScreen(for window: CGRect, screens candidates: [WindowScreen]) -> WindowScreen? {
        guard isUsable(window) else { return nil }
        let center = CGPoint(x: window.midX, y: window.midY)
        return screens(candidates).min { left, right in
            let la = intersectionArea(window, left.frame), ra = intersectionArea(window, right.frame)
            if la != ra { return la > ra }
            let lc = left.frame.contains(center), rc = right.frame.contains(center)
            if lc != rc { return lc }
            let ld = distanceSquared(center, to: left.frame), rd = distanceSquared(center, to: right.frame)
            return ld == rd ? left.id < right.id : ld < rd
        }
    }

    public static func adjacentScreen(from source: WindowScreen, direction: WindowDirection,
                                      screens candidates: [WindowScreen]) -> WindowScreen? {
        let horizontal = direction == .left || direction == .right
        let positive = direction == .right || direction == .down
        func rank(_ destination: WindowScreen) -> (Bool, CGFloat, CGFloat, UInt32) {
            let a = source.frame, b = destination.frame
            let overlap = horizontal ? min(a.maxY, b.maxY) - max(a.minY, b.minY)
                : min(a.maxX, b.maxX) - max(a.minX, b.minX)
            let distance = horizontal
                ? (positive ? max(0, b.minX - a.maxX) : max(0, a.minX - b.maxX))
                : (positive ? max(0, b.minY - a.maxY) : max(0, a.minY - b.maxY))
            let perpendicular = horizontal ? abs(b.midY - a.midY) : abs(b.midX - a.midX)
            return (overlap > 0, distance, perpendicular, destination.id)
        }
        return screens(candidates).filter { destination in
            guard destination.id != source.id, destination.frame != source.frame else { return false }
            let delta = horizontal ? destination.frame.midX - source.frame.midX : destination.frame.midY - source.frame.midY
            return positive ? delta > 1 : delta < -1
        }.min { left, right in
            let l = rank(left), r = rank(right)
            if l.0 != r.0 { return l.0 }
            if l.1 != r.1 { return l.1 < r.1 }
            if l.2 != r.2 { return l.2 < r.2 }
            return l.3 < r.3
        }
    }

    public static func half(_ direction: WindowDirection, on screen: WindowScreen) -> CGRect {
        let f = screen.visibleFrame
        let x = f.minX + (f.width / 2).rounded(.down)
        let y = f.minY + (f.height / 2).rounded(.down)
        switch direction {
        case .left: return CGRect(x: f.minX, y: f.minY, width: x - f.minX, height: f.height)
        case .right: return CGRect(x: x, y: f.minY, width: f.maxX - x, height: f.height)
        case .up: return CGRect(x: f.minX, y: f.minY, width: f.width, height: y - f.minY)
        case .down: return CGRect(x: f.minX, y: y, width: f.width, height: f.maxY - y)
        }
    }

    public static func centered(_ window: CGRect, on screen: WindowScreen) -> CGRect {
        let area = screen.visibleFrame
        // Fixed-size windows can still be centered. Keep their title bar reachable.
        return CGRect(x: area.midX - window.width / 2,
                      y: max(area.minY, area.midY - window.height / 2),
                      width: window.width, height: window.height)
    }

    public static func constrained(_ window: CGRect, to screen: WindowScreen, resize: Bool = true) -> CGRect {
        let area = screen.visibleFrame
        let width = resize ? min(window.width, area.width) : window.width
        let height = resize ? min(window.height, area.height) : window.height
        return CGRect(x: max(area.minX, min(window.minX, area.maxX - width)),
                      y: max(area.minY, min(window.minY, area.maxY - height)), width: width, height: height)
    }

    public static func moved(_ window: CGRect, from source: WindowScreen, to destination: WindowScreen,
                             resize: Bool = true) -> CGRect {
        let a = source.visibleFrame, b = destination.visibleFrame
        let x = max(0, min(1, (window.midX - a.minX) / a.width))
        let y = max(0, min(1, (window.midY - a.minY) / a.height))
        let width = resize ? min(window.width, b.width) : window.width
        let height = resize ? min(window.height, b.height) : window.height
        let result = CGRect(x: b.minX + x * b.width - width / 2,
                            y: b.minY + y * b.height - height / 2, width: width, height: height)
        return constrained(result, to: destination, resize: resize)
    }

    public static func frame(for preset: WindowPreset, on screen: WindowScreen) -> CGRect? {
        guard preset.isValid, isUsable(screen.visibleFrame) else { return nil }
        let f = screen.visibleFrame
        // Shared edges are rounded, instead of separately rounding widths.
        let x = (f.minX + preset.x * f.width).rounded(), y = (f.minY + preset.y * f.height).rounded()
        let right = (f.minX + (preset.x + preset.width) * f.width).rounded()
        let bottom = (f.minY + (preset.y + preset.height) * f.height).rounded()
        let result = CGRect(x: x, y: y, width: right - x, height: bottom - y)
        return isUsable(result) ? result : nil
    }

    public static func preset(from window: CGRect, on screen: WindowScreen, slot: Int, name: String) -> WindowPreset? {
        guard isUsable(window), isUsable(screen.visibleFrame) else { return nil }
        let f = screen.visibleFrame
        guard window.minX >= f.minX - 1, window.minY >= f.minY - 1,
              window.maxX <= f.maxX + 1, window.maxY <= f.maxY + 1 else { return nil }
        let bounded = window.intersection(f)
        let result = WindowPreset(slot: slot, name: name, x: (bounded.minX - f.minX) / f.width,
                                  y: (bounded.minY - f.minY) / f.height,
                                  width: bounded.width / f.width, height: bounded.height / f.height)
        return result.isValid ? result : nil
    }

    public static func approximatelyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    private static func intersectionArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let f = a.intersection(b)
        return f.isNull ? 0 : f.width * f.height
    }

    private static func distanceSquared(_ point: CGPoint, to frame: CGRect) -> CGFloat {
        let x = max(frame.minX - point.x, 0, point.x - frame.maxX)
        let y = max(frame.minY - point.y, 0, point.y - frame.maxY)
        return x * x + y * y
    }
}
