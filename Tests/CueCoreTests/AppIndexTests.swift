import Foundation
import XCTest
import CueCore

final class AppIndexTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueAppIndexTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testFindsApplicationsInsideNestedFoldersButNotApplicationContents() throws {
        let outer = try makeApplication("Utilities/Outer.app", identifier: "test.outer")
        _ = try makeApplication("Utilities/Outer.app/Contents/Helpers/Hidden.app", identifier: "test.helper")
        let nested = try makeApplication("Tools/Developer/Nested.app", identifier: "test.nested")

        let applications = AppIndex.scan(roots: [temporaryDirectory])

        XCTAssertEqual(Set(applications.map(\.url.path)), Set([outer.path, nested.path]))
    }

    func testSkipsHiddenFoldersAndOtherPackages() throws {
        _ = try makeApplication(".Hidden/Secret.app", identifier: "test.hidden")
        _ = try makeApplication(".Hidden.app", identifier: "test.hidden-app")
        _ = try makeApplication("Resources.bundle/Nested.app", identifier: "test.bundled")
        let hiddenApp = try makeApplication("FinderHidden.app", identifier: "test.finder-hidden")
        try markHidden(hiddenApp)
        _ = try makeApplication("FinderHiddenFolder/Nested.app", identifier: "test.hidden-folder")
        try markHidden(temporaryDirectory.appendingPathComponent("FinderHiddenFolder"))
        _ = try makeApplication("Visible.app", identifier: "test.visible")

        XCTAssertEqual(AppIndex.scan(roots: [temporaryDirectory]).map(\.name), ["Visible"])
    }

    func testFindsHiddenApplicationSymlinkWhenDestinationIsVisible() throws {
        let application = try makeApplication("Cryptex/Safari.app", identifier: "test.safari")
        let root = temporaryDirectory.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("Safari.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: application)
        try markHidden(link)

        let applications = AppIndex.scan(roots: [root])

        XCTAssertEqual(applications.count, 1)
        XCTAssertEqual(applications.first?.name, "Safari")
        XCTAssertEqual(applications.first?.url, application)
    }

    func testUsesDisplayNameThenBundleNameThenFilename() throws {
        _ = try makeApplication("A.app", displayName: "Display name", name: "Bundle name")
        _ = try makeApplication("B.app", name: "Bundle name")
        _ = try makeApplication("Fallback.app", displayName: "  ", name: "")

        XCTAssertEqual(AppIndex.scan(roots: [temporaryDirectory]).map(\.name), [
            "Display name", "Bundle name", "Fallback",
        ])
    }

    func testDeduplicatesBundleIdentifiersGivingEarlierRootsPriority() throws {
        let preferred = try makeApplication("First/Z.app", identifier: "test.same", name: "Preferred")
        _ = try makeApplication("Second/A.app", identifier: "test.same", name: "Other copy")
        let applications = AppIndex.scan(roots: [
            temporaryDirectory.appendingPathComponent("First"),
            temporaryDirectory.appendingPathComponent("Second"),
        ])

        XCTAssertEqual(applications.count, 1)
        XCTAssertEqual(applications.first?.url, preferred)
        XCTAssertEqual(applications.first?.name, "Preferred")
    }

    func testDeduplicatesCanonicalPathsAcrossRepeatedAndSymlinkedRoots() throws {
        let application = try makeApplication("Original/Example.app")
        let originalRoot = temporaryDirectory.appendingPathComponent("Original")
        let linkedRoot = temporaryDirectory.appendingPathComponent("Linked")
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: originalRoot)

        XCTAssertEqual(AppIndex.scan(roots: [linkedRoot]).first?.url, application)

        let applications = AppIndex.scan(roots: [originalRoot, originalRoot, linkedRoot])

        XCTAssertEqual(applications.count, 1)
        XCTAssertEqual(applications.first?.id, application.path)
    }

    func testMissingAndNondirectoryRootsAreIgnored() throws {
        let plainFile = temporaryDirectory.appendingPathComponent("file")
        try Data().write(to: plainFile)
        XCTAssertTrue(AppIndex.scan(roots: [
            temporaryDirectory.appendingPathComponent("missing"), plainFile,
        ]).isEmpty)
    }

    func testExcludesCueAndAllowsOverridingExclusion() throws {
        _ = try makeApplication("Cue.app", identifier: "com.yyhsiu.cue")
        _ = try makeApplication("Other.app", identifier: "test.other")

        XCTAssertEqual(AppIndex.scan(roots: [temporaryDirectory]).map(\.name), ["Other"])
        XCTAssertEqual(AppIndex.scan(roots: [temporaryDirectory], excludingBundleIdentifier: nil).count, 2)
        XCTAssertEqual(
            AppIndex.scan(roots: [temporaryDirectory], excludingBundleIdentifier: "test.other").map(\.name),
            ["Cue"]
        )
    }

    @discardableResult
    private func makeApplication(
        _ relativePath: String,
        identifier: String? = nil,
        displayName: String? = nil,
        name: String? = nil
    ) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(relativePath, isDirectory: true)
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundlePackageType": "APPL", "CFBundleVersion": "1"]
        info["CFBundleIdentifier"] = identifier
        info["CFBundleDisplayName"] = displayName
        info["CFBundleName"] = name
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return url.resolvingSymlinksInPath().standardizedFileURL
    }

    private func markHidden(_ url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isHidden = true
        try url.setResourceValues(values)
    }
}
