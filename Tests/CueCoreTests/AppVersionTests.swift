import Foundation
import XCTest
import CueCore

final class AppVersionTests: XCTestCase {
    func testStableLabelOmitsInternalBuildNumber() {
        let version = AppVersion(baseVersion: "0.9.1", buildNumber: "11", channel: "stable")
        XCTAssertEqual(version.displayVersion, "0.9.1")
        XCTAssertEqual(version.baseVersion, "0.9.1")
        XCTAssertEqual(version.buildNumber, "11")
        XCTAssertEqual(version.channel, .stable)
    }

    func testLegacyMissingChannelIsStable() {
        let version = AppVersion(baseVersion: "0.9.1", buildNumber: "11")
        XCTAssertEqual(version.displayVersion, "0.9.1")
        XCTAssertEqual(version.channel, .stable)
    }

    func testPrereleaseLabelsDistinguishBetaAndDevelopmentBuilds() {
        for channel in ["beta", "dev"] {
            let version = AppVersion(
                baseVersion: "0.10.0", buildNumber: "12", channel: channel, prereleaseNumber: "1"
            )
            XCTAssertEqual(version.displayVersion, "0.10.0-\(channel).1")
            XCTAssertEqual(version.prereleaseNumber, "1")
            XCTAssertEqual(version.buildNumber, "12")
        }
    }

    func testPrereleasesRequireCanonicalPositiveSequence() {
        let invalid: [String?] = [nil, "", "0", "01", "-1", "+1", "1.2", "1 ", " 1", "１", "1b"]
        for channel in ["beta", "dev"] {
            for number in invalid {
                let version = AppVersion(baseVersion: "0.10.0", channel: channel, prereleaseNumber: number)
                XCTAssertNil(version.displayVersion, "\(channel): \(String(describing: number))")
                XCTAssertNil(version.prereleaseNumber)
            }
        }
    }

    func testUnknownOrEmptyChannelDoesNotLookLikeAStableRelease() {
        for channel in ["", "release", "preview", "Beta", "DEV", "stable "] {
            let version = AppVersion(baseVersion: "0.10.0", channel: channel, prereleaseNumber: "1")
            XCTAssertNil(version.displayVersion, channel)
            XCTAssertNil(version.channel, channel)
        }
    }

    func testStableOrLegacyBundleCannotAlsoClaimAPrereleaseNumber() {
        let channels: [String?] = [nil, "stable"]
        for channel in channels {
            for number in ["1", "0", "", "beta"] {
                XCTAssertNil(AppVersion(
                    baseVersion: "0.10.0", channel: channel, prereleaseNumber: number
                ).displayVersion)
            }
        }
    }

    func testBaseRequiresThreeCanonicalASCIINumericComponents() {
        let invalid: [String?] = [
            nil, "", "1", "1.2", "1.2.3.4", ".1.2", "1..2", "1.2.", "01.2.3", "1.02.3", "1.2.03",
            "-1.2.3", "+1.2.3", "1.2.3-beta.1", "1.2.3 (12)", "1.2.3 ", " 1.2.3", "１.2.3", "a.2.3"
        ]
        for base in invalid {
            let version = AppVersion(baseVersion: base, buildNumber: "12", channel: "stable")
            XCTAssertNil(version.baseVersion, String(describing: base))
            XCTAssertNil(version.displayVersion, String(describing: base))
        }
        for base in ["0.0.0", "0.10.0", "1.0.12", "123.456.789"] {
            XCTAssertEqual(AppVersion(baseVersion: base).displayVersion, base)
        }
    }

    func testInvalidDiagnosticBuildNumberDoesNotChangeValidPresentationVersion() {
        let invalid: [String?] = [nil, "", "0", "01", "-1", "1.2", "12b", "１２", " 12"]
        for build in invalid {
            let version = AppVersion(baseVersion: "0.10.0", buildNumber: build, channel: "stable")
            XCTAssertNil(version.buildNumber, String(describing: build))
            XCTAssertEqual(version.displayVersion, "0.10.0")
        }
    }

    func testVersionNumbersUseTheSameIntegerRangeAsReleaseValidation() {
        let maximum = "2147483647"
        XCTAssertEqual(AppVersion(baseVersion: "\(maximum).0.0").displayVersion, "\(maximum).0.0")
        let version = AppVersion(
            baseVersion: "0.10.0", buildNumber: maximum, channel: "beta", prereleaseNumber: maximum
        )
        XCTAssertEqual(version.displayVersion, "0.10.0-beta.\(maximum)")
        XCTAssertEqual(version.buildNumber, maximum)
        for invalid in ["2147483648", "9999999999", "10000000000"] {
            XCTAssertNil(AppVersion(baseVersion: "\(invalid).0.0").displayVersion)
            XCTAssertNil(AppVersion(baseVersion: "0.10.0", buildNumber: invalid).buildNumber)
            XCTAssertNil(AppVersion(
                baseVersion: "0.10.0", channel: "beta", prereleaseNumber: invalid
            ).displayVersion)
        }
    }

    func testBundleReadsPresentationAndDiagnosticMetadata() throws {
        try withBundle([
            "CFBundleShortVersionString": "0.10.0",
            "CFBundleVersion": "12",
            "CueBuildChannel": "beta",
            "CuePrereleaseNumber": "2"
        ]) { bundle in
            let version = AppVersion(bundle: bundle)
            XCTAssertEqual(version.displayVersion, "0.10.0-beta.2")
            XCTAssertEqual(version.buildNumber, "12")
        }
    }

    func testBundleAcceptsIntegerPrereleaseMetadata() throws {
        try withBundle([
            "CFBundleShortVersionString": "0.10.0",
            "CueBuildChannel": "dev",
            "CuePrereleaseNumber": 3
        ]) { bundle in
            XCTAssertEqual(AppVersion(bundle: bundle).displayVersion, "0.10.0-dev.3")
        }
    }

    func testBundleRejectsBooleanFractionalAndMalformedPrereleaseMetadata() throws {
        let invalidValues: [Any] = [true, false, 1.5, -1, 0, [1], ["number": 1]]
        for value in invalidValues {
            for channel in ["beta", "dev", "stable"] {
                try withBundle([
                    "CFBundleShortVersionString": "0.10.0",
                    "CueBuildChannel": channel,
                    "CuePrereleaseNumber": value
                ]) { bundle in
                    XCTAssertNil(AppVersion(bundle: bundle).displayVersion)
                }
            }
        }
    }

    func testBundleWithMissingVersionMetadataNeedsLocalizedFallback() throws {
        try withBundle([:]) { bundle in
            let version = AppVersion(bundle: bundle)
            XCTAssertNil(version.displayVersion)
            XCTAssertNil(version.baseVersion)
            XCTAssertNil(version.buildNumber)
        }
    }

    func testBundleOnlyTreatsAbsentChannelAsLegacy() throws {
        try withBundle(["CFBundleShortVersionString": "0.9.1", "CFBundleVersion": "11"]) { bundle in
            XCTAssertEqual(AppVersion(bundle: bundle).displayVersion, "0.9.1")
        }
        let invalidChannels: [Any] = [1, true, ["stable"]]
        for invalidChannel in invalidChannels {
            try withBundle([
                "CFBundleShortVersionString": "0.10.0",
                "CueBuildChannel": invalidChannel
            ]) { bundle in
                XCTAssertNil(AppVersion(bundle: bundle).displayVersion)
                XCTAssertNil(AppVersion(bundle: bundle).channel)
            }
        }
    }

    private func withBundle(_ metadata: [String: Any], check: (Bundle) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueAppVersion-\(UUID().uuidString).bundle", isDirectory: true)
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        var info = metadata
        info["CFBundleIdentifier"] = "app.cue.version-test.\(UUID().uuidString)"
        info["CFBundlePackageType"] = "BNDL"
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        try check(XCTUnwrap(Bundle(url: url)))
    }
}
