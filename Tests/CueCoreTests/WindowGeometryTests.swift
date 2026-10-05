import Foundation
import CoreGraphics
import XCTest
import CueCore

final class WindowGeometryTests: XCTestCase {
    private let main = WindowScreen(id: 1, frame: CGRect(x: 0, y: 0, width: 1513, height: 982),
                                    visibleFrame: CGRect(x: 0, y: 25, width: 1513, height: 903))

    func testAppKitConversionUsesPrimaryScreenEvenOnUpperAndLeftDisplays() {
        let primary = CGRect(x: 0, y: 0, width: 1512, height: 982)
        XCTAssertEqual(WindowGeometry.accessibilityFrame(fromAppKit: CGRect(x: -1920, y: 982, width: 1920, height: 1080), primaryFrame: primary),
                       CGRect(x: -1920, y: -1080, width: 1920, height: 1080))
        XCTAssertEqual(WindowGeometry.accessibilityFrame(fromAppKit: CGRect(x: 0, y: 54, width: 1512, height: 903), primaryFrame: primary),
                       CGRect(x: 0, y: 25, width: 1512, height: 903))
    }

    func testOddHalfSizesHaveExactlySharedEdgesAndCoverVisibleArea() {
        let left = WindowGeometry.half(.left, on: main), right = WindowGeometry.half(.right, on: main)
        let up = WindowGeometry.half(.up, on: main), down = WindowGeometry.half(.down, on: main)
        XCTAssertEqual(left.maxX, right.minX)
        XCTAssertEqual(up.maxY, down.minY)
        XCTAssertEqual(left.union(right), main.visibleFrame)
        XCTAssertEqual(up.union(down), main.visibleFrame)
        XCTAssertEqual(left.width, 756)
        XCTAssertEqual(right.width, 757)
        XCTAssertEqual(up.minY, 25)
        XCTAssertEqual(down.maxY, 928)
    }

    func testCurrentScreenUsesIntersectionThenStableIdentityAndNearestOffscreen() {
        let left = screen(2, x: -1200, y: 0, width: 1200, height: 900)
        XCTAssertEqual(WindowGeometry.currentScreen(for: CGRect(x: -400, y: 50, width: 500, height: 700), screens: [main, left])?.id, 2)
        XCTAssertEqual(WindowGeometry.currentScreen(for: CGRect(x: -100, y: 50, width: 500, height: 700), screens: [left, main])?.id, 1)
        XCTAssertEqual(WindowGeometry.currentScreen(for: CGRect(x: -2000, y: -500, width: 200, height: 200), screens: [main, left])?.id, 2)
        XCTAssertNil(WindowGeometry.currentScreen(for: .zero, screens: [main]))
        XCTAssertNil(WindowGeometry.currentScreen(for: main.frame, screens: []))
    }

    func testDirectionalNeighborsHonorGeometricArrangementAndDoNotWrap() {
        let left = screen(2, x: -1400, y: 0), right = screen(3, x: 1800, y: 100)
        let above = screen(4, x: 100, y: -1000), below = screen(5, x: 100, y: 1200)
        let diagonal = screen(6, x: 1520, y: -2000)
        let screens = [diagonal, below, above, right, left, main]
        XCTAssertEqual(WindowGeometry.adjacentScreen(from: main, direction: .left, screens: screens)?.id, 2)
        XCTAssertEqual(WindowGeometry.adjacentScreen(from: main, direction: .right, screens: screens)?.id, 3)
        XCTAssertEqual(WindowGeometry.adjacentScreen(from: main, direction: .up, screens: screens)?.id, 4)
        XCTAssertEqual(WindowGeometry.adjacentScreen(from: main, direction: .down, screens: screens)?.id, 5)
        XCTAssertNil(WindowGeometry.adjacentScreen(from: left, direction: .left, screens: screens))
        XCTAssertNil(WindowGeometry.adjacentScreen(from: main, direction: .left, screens: [main]))
    }

    func testMirrorsAndInvalidScreensAreExcludedDeterministically() {
        let mirror = WindowScreen(id: 99, frame: main.frame, visibleFrame: main.visibleFrame)
        let invalid = WindowScreen(id: 0, frame: .zero, visibleFrame: .zero)
        XCTAssertEqual(WindowGeometry.screens([mirror, invalid, main]).map(\.id), [1])
        XCTAssertNil(WindowGeometry.adjacentScreen(from: main, direction: .right, screens: [mirror, main]))
        XCTAssertFalse(WindowGeometry.isUsable(CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10)))
    }

    func testCrossDisplayMovePreservesPointSizeAndRelativeCenterWithoutScaling() {
        let source = screen(1, x: 0, y: 0, width: 1000, height: 800)
        let destination = screen(2, x: -1800, y: -1000, width: 1800, height: 1200)
        let window = CGRect(x: 250, y: 200, width: 500, height: 400)
        XCTAssertEqual(WindowGeometry.moved(window, from: source, to: destination), CGRect(x: -1150, y: -600, width: 500, height: 400))
        let small = screen(3, x: 1800, y: 0, width: 300, height: 250)
        XCTAssertEqual(WindowGeometry.moved(window, from: source, to: small), small.frame)
        let fixed = WindowGeometry.moved(window, from: source, to: small, resize: false)
        XCTAssertEqual(fixed.size, window.size)
        XCTAssertEqual(fixed.origin, small.frame.origin)
    }

    func testCenterKeepsSizeAndOversizedWindowTitleBarReachable() {
        let normal = WindowGeometry.centered(CGRect(x: -200, y: -200, width: 600, height: 400), on: main)
        XCTAssertEqual(normal.midX, main.visibleFrame.midX)
        XCTAssertEqual(normal.midY, main.visibleFrame.midY)
        let oversized = WindowGeometry.centered(CGRect(x: 0, y: 0, width: 2000, height: 1800), on: main)
        XCTAssertEqual(oversized.size, CGSize(width: 2000, height: 1800))
        XCTAssertEqual(oversized.minY, main.visibleFrame.minY)
        XCTAssertEqual(oversized.midX, main.visibleFrame.midX)
    }

    func testPresetsValidateUntrustedImportedFields() throws {
        XCTAssertTrue(preset().isValid)
        XCTAssertFalse(preset(slot: 0).isValid)
        XCTAssertFalse(preset(slot: 10).isValid)
        XCTAssertFalse(preset(name: "\n").isValid)
        XCTAssertFalse(preset(name: "a\0b").isValid)
        XCTAssertFalse(preset(name: String(repeating: "a", count: 81)).isValid)
        XCTAssertFalse(preset(x: -.infinity).isValid)
        XCTAssertFalse(preset(width: .nan).isValid)
        XCTAssertFalse(preset(x: -0.01).isValid)
        XCTAssertFalse(preset(width: 0).isValid)
        XCTAssertFalse(preset(x: 0.5, width: 0.6).isValid)
        XCTAssertFalse(preset(y: 0.5, height: 0.6).isValid)
        let encoded = try JSONEncoder().encode(preset())
        XCTAssertEqual(try JSONDecoder().decode(WindowPreset.self, from: encoded), preset())
    }

    func testPresetScalingAndCaptureRoundTripAtNegativeDesktopCoordinates() throws {
        let target = screen(8, x: -1600, y: -1000, width: 1600, height: 1000)
        let choice = preset(x: 0.4, width: 0.6)
        let actual = try XCTUnwrap(WindowGeometry.frame(for: choice, on: target))
        XCTAssertEqual(actual, CGRect(x: -960, y: -1000, width: 960, height: 1000))
        let restored = try XCTUnwrap(WindowGeometry.preset(from: actual, on: target, slot: 1, name: "Window"))
        XCTAssertEqual(restored, choice)
        XCTAssertNil(WindowGeometry.preset(from: CGRect(x: -2000, y: -1000, width: 1000, height: 500), on: target, slot: 1, name: "Window"))
        XCTAssertNil(WindowGeometry.frame(for: preset(width: 2), on: target))
    }

    private func preset(slot: Int = 1, name: String = "Window", x: Double = 0, y: Double = 0,
                        width: Double = 1, height: Double = 1) -> WindowPreset {
        WindowPreset(slot: slot, name: name, x: x, y: y, width: width, height: height)
    }

    private func screen(_ id: UInt32, x: CGFloat, y: CGFloat, width: CGFloat = 1200, height: CGFloat = 900) -> WindowScreen {
        let frame = CGRect(x: x, y: y, width: width, height: height)
        return WindowScreen(id: id, frame: frame, visibleFrame: frame)
    }
}
