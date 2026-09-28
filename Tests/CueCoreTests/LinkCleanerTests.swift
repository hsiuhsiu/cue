import Foundation
import XCTest
import CueCore

final class LinkCleanerTests: XCTestCase {
    func testKnownTrackingParametersAreRemovedWithoutDroppingContentParameters() throws {
        let input = "https://example.com/product?id=42&utm_source=email&fbclid=a&gclid=b&dclid=c&msclkid=d&twclid=e&ttclid=f&mc_cid=g&mc_eid=h&page=2"
        let result = try LinkCleaner.clean(input)
        XCTAssertEqual(result.url, "https://example.com/product?id=42&page=2")
        XCTAssertEqual(result.removedParameterCount, 9)
        XCTAssertFalse(result.isProtected)
    }

    func testTrackingNamesMatchCaseInsensitivelyAfterExactlyOnePercentDecode() throws {
        let input = "https://example.com/?%75tm_Source=A&FBCLID=B&%67cLiD=C&%2575tm_source=keep&utm_=keep&utm=keep"
        let result = try LinkCleaner.clean(input)
        XCTAssertEqual(result.url, "https://example.com/?%2575tm_source=keep&utm_=keep&utm=keep")
        XCTAssertEqual(result.removedParameterCount, 3)
    }

    func testUTMNamespaceRequiresANonemptySuffixAndDoesNotMatchNearNames() throws {
        let input = "https://example.com/?utm_custom=value&utm_source=&utm_&xutm_source=a&utm-source=b&my_fbclid=c&fbclid_extra=d"
        let result = try LinkCleaner.clean(input)
        XCTAssertEqual(result.url, "https://example.com/?utm_&xutm_source=a&utm-source=b&my_fbclid=c&fbclid_extra=d")
        XCTAssertEqual(result.removedParameterCount, 2)
    }

    func testEmptyOrMissingTrackingValuesStillCountAsParameters() throws {
        let result = try LinkCleaner.clean("https://example.com/?utm_source&utm_source=&fbclid")
        XCTAssertEqual(result.url, "https://example.com/")
        XCTAssertEqual(result.removedParameterCount, 3)
    }

    func testRetainedEncodingOrderDuplicatesAndEmptyValuesRemainByteForByte() throws {
        let input = "HTTPS://ExAmPlE.com:443/A%2fb/%7Euser?b=hello+world&a=%20&a=%2f&a=%2F&flag&empty=&utm_source=x&url=https%3A%2F%2Fa.test%2F%3Fq%3D1%26v%3D2#Heading%20One"
        let expected = "HTTPS://ExAmPlE.com:443/A%2fb/%7Euser?b=hello+world&a=%20&a=%2f&a=%2F&flag&empty=&url=https%3A%2F%2Fa.test%2F%3Fq%3D1%26v%3D2#Heading%20One"
        let result = try LinkCleaner.clean(input)
        XCTAssertEqual(result.url.utf8.elementsEqual(expected.utf8), true)
        XCTAssertEqual(result.removedParameterCount, 1)
    }

    func testOnlyParameterNamesAreInspected() throws {
        let input = "https://example.com/?q=utm_source%3Dx%26fbclid%3Dy&next=https%3A%2F%2Fa.test%2F%3Fgclid%3Dz&name=signature&gclid=x"
        let result = try LinkCleaner.clean(input)
        XCTAssertEqual(result.url, "https://example.com/?q=utm_source%3Dx%26fbclid%3Dy&next=https%3A%2F%2Fa.test%2F%3Fgclid%3Dz&name=signature")
        XCTAssertEqual(result.removedParameterCount, 1)
        XCTAssertFalse(result.isProtected)
    }

    func testFunctionalAndUnverifiedParametersRemainUntouched() throws {
        let input = "https://www.youtube.com/watch?v=abc&list=xyz&t=42&index=3&si=keep&ref=keep&source=keep&igsh=keep&igshid=keep&q=C%2B%2B"
        let result = try LinkCleaner.clean(input)
        XCTAssertEqual(result.url, input)
        XCTAssertEqual(result.removedParameterCount, 0)
        XCTAssertFalse(result.isProtected)
    }

    func testFragmentRoutesAndTextFragmentsAreNeverParsedAsQueryParameters() throws {
        let inputs = [
            "https://example.com/#/page?utm_source=x&fbclid=y",
            "https://example.com/#:~:text=hello%20world",
            "https://example.com/#utm_source=x?gclid=y",
        ]
        for input in inputs {
            XCTAssertEqual(try LinkCleaner.clean(input).url, input)
        }
        let result = try LinkCleaner.clean("https://example.com/?utm_source=x#/page?utm_source=keep&fbclid=keep")
        XCTAssertEqual(result.url, "https://example.com/#/page?utm_source=keep&fbclid=keep")
        XCTAssertEqual(result.removedParameterCount, 1)
    }

    func testExistingQueryAndFragmentDelimitersSurviveWhenNoChangeIsNeeded() throws {
        for input in [
            "https://example.com", "https://example.com/", "https://example.com?", "https://example.com?#",
            "https://example.com/?&&flag&&x=&", "http://localhost:8080/test#", "https://[::1]:8443/path?x=1",
        ] {
            let result = try LinkCleaner.clean(input)
            XCTAssertEqual(result.url, input)
            XCTAssertEqual(result.removedParameterCount, 0)
        }
    }

    func testEmptyRetainedQueryFieldsDoNotGetNormalized() throws {
        let result = try LinkCleaner.clean("https://example.com/?&&utm_source=x&&flag&")
        XCTAssertEqual(result.url, "https://example.com/?&&&flag&")
        XCTAssertEqual(result.removedParameterCount, 1)
    }

    func testAmbiguousSemicolonFieldsRetainTheirFunctionalValues() throws {
        let input = "https://example.com/?utm_source=email;product=42&gclid=remove&filter=one;two"
        let result = try LinkCleaner.clean(input)
        XCTAssertEqual(result.url, "https://example.com/?utm_source=email;product=42&filter=one;two")
        XCTAssertEqual(result.removedParameterCount, 1)
        XCTAssertFalse(result.isProtected)
        XCTAssertEqual(try LinkCleaner.clean("https://example.com/?utm_source=email;product=42").removedParameterCount, 0)
    }

    func testSignaturesAfterSemicolonSeparatorsProtectTheWholeURL() throws {
        for query in ["utm_source=email;sig=abc&fbclid=keep", "gclid=keep&data=x;%73ignature=abc"] {
            let input = "https://example.com/?\(query)"
            let result = try LinkCleaner.clean(input)
            XCTAssertEqual(result.url, input)
            XCTAssertEqual(result.removedParameterCount, 0)
            XCTAssertTrue(result.isProtected)
        }
    }

    func testUnicodePathsAndQueryValuesAreNotReencoded() throws {
        let input = "https://例子.台灣/正體中文/😀?q=咖啡&utm_source=電子報#章節二"
        let result = try LinkCleaner.clean(input)
        XCTAssertEqual(result.url, "https://例子.台灣/正體中文/😀?q=咖啡#章節二")
        XCTAssertEqual(result.removedParameterCount, 1)
    }

    func testIPv6HostsAndZoneIdentifiersAreValidatedWithoutNetworkLookups() throws {
        for authority in ["[::1]", "[2001:db8::1]:8443", "[::ffff:192.0.2.1]", "[fe80::1%25en0]"] {
            let result = try LinkCleaner.clean("https://\(authority)/?utm_source=x")
            XCTAssertEqual(result.url, "https://\(authority)/")
            XCTAssertEqual(result.removedParameterCount, 1)
        }
        for authority in ["[not-ipv6]", "[:::1]", "[12345::1]", "example.com:65536", "exa%20mple.com", "exa%00mple.com"] {
            assertInvalid("https://\(authority)/?utm_source=x")
        }
    }

    func testOuterWhitespaceIsTrimmedButRetainedURLBytesAreNotNormalized() throws {
        let result = try LinkCleaner.clean(" \r\n\tHTTPS://Example.com/%2f?q=two%20words&utm_source=a#Keep\u{3000}")
        XCTAssertEqual(result.url, "HTTPS://Example.com/%2f?q=two%20words#Keep")
        XCTAssertEqual(result.removedParameterCount, 1)
    }

    func testKnownSignatureMarkersProtectTheEntireURLRegardlessOfPositionOrValue() throws {
        for name in ["X-Amz-Signature", "X-Goog-Signature", "Signature", "sig", "oauth_signature", "HMAC", "%73ig"] {
            for query in ["utm_source=keep&\(name)=abc&fbclid=keep", "\(name)&utm_source=keep"] {
                let input = "https://example.com/private?\(query)#keep"
                let result = try LinkCleaner.clean("  \(input)  ")
                XCTAssertEqual(result.url, input, name)
                XCTAssertEqual(result.removedParameterCount, 0, name)
                XCTAssertTrue(result.isProtected, name)
            }
        }
    }

    func testSignatureNamesInValuesPathsAndFragmentsDoNotProtectOrdinaryQueries() throws {
        let result = try LinkCleaner.clean("https://example.com/signature?key=sig&note=X-Amz-Signature&utm_source=x#sig=abc")
        XCTAssertEqual(result.url, "https://example.com/signature?key=sig&note=X-Amz-Signature#sig=abc")
        XCTAssertFalse(result.isProtected)
        XCTAssertEqual(result.removedParameterCount, 1)
    }

    func testOpaqueEscapedBytesArePreservedWithoutRepeatedDecoding() throws {
        let result = try LinkCleaner.clean("https://example.com/%FF?%FF=keep&%2573ig=keep&x=%00%0a%FF&utm_source=remove")
        XCTAssertEqual(result.url, "https://example.com/%FF?%FF=keep&%2573ig=keep&x=%00%0a%FF")
        XCTAssertEqual(result.removedParameterCount, 1)
        XCTAssertFalse(result.isProtected)
    }

    func testCleaningIsIdempotent() throws {
        for input in [
            "https://example.com/?utm_source=a&fbclid=b&q=two+words#keep",
            "https://example.com/?utm_medium=a",
            "https://example.com/?sig=abc&utm_source=protected",
            "https://example.com/?utm_source=a&",
        ] {
            let first = try LinkCleaner.clean(input)
            let second = try LinkCleaner.clean(first.url)
            XCTAssertEqual(second.url, first.url)
            XCTAssertEqual(second.removedParameterCount, 0)
            XCTAssertEqual(second.isProtected, first.isProtected)
        }
    }

    func testRejectsNonHTTPURLsMissingHostsAndNonURLText() {
        for input in [
            "", " \t\n ", "example.com?utm_source=x", "/path?utm_source=x", "//example.com/path",
            "mailto:person@example.com", "file:///tmp/test", "javascript:alert(1)", "data:text/plain,hello",
            "https:", "https:///path", "https://", "https://?utm_source=x", "https://#fragment",
            "https://example.com:invalid/path", "https://[not-ipv6]/path", "Read https://example.com/",
        ] {
            assertInvalid(input)
        }
    }

    func testRejectsEmbeddedWhitespaceControlsMultilineAndBackslashes() {
        for input in [
            "https://example.com/a b", "https://example.com/?q=two words", "https://exa mple.com/",
            "https://example.com/\nhttps://second.example/", "https://example.com/\r?q=x",
            "https://example.com/\tpath", "https://example.com/a\u{0000}b", "https://example.com/a\u{007f}b",
            "https://example.com/\u{3000}path", "https://example.com/\u{2028}path",
            "https://example.com\\@other.example/?utm_source=a",
        ] {
            assertInvalid(input)
        }
    }

    func testRejectsMalformedPercentEscapesAnywhereIncludingProtectedURLs() {
        for input in [
            "https://exa%mple.com/", "https://example.com/%", "https://example.com/%2",
            "https://example.com/%GG", "https://example.com/?bad%=a", "https://example.com/?q=%0z",
            "https://example.com/#bad%", "https://example.com/?sig=valid&utm_source=%Q1",
        ] {
            assertInvalid(input)
        }
    }

    func testInputLimitUsesUTF8BytesAndIncludesOuterWhitespace() throws {
        XCTAssertEqual(LinkCleaner.maximumInputBytes, 65_536)
        let prefix = "https://example.com/?q="
        let atLimit = prefix + String(repeating: "a", count: LinkCleaner.maximumInputBytes - prefix.utf8.count)
        XCTAssertEqual(try LinkCleaner.clean(atLimit).url, atLimit)
        for input in [atLimit + "a", " " + atLimit, prefix + String(repeating: "正", count: 22_000)] {
            XCTAssertThrowsError(try LinkCleaner.clean(input)) {
                XCTAssertEqual($0 as? LinkCleaner.Error, .inputTooLarge)
            }
        }
    }

    private func assertInvalid(_ input: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try LinkCleaner.clean(input), input.debugDescription, file: file, line: line) {
            XCTAssertEqual($0 as? LinkCleaner.Error, .invalidURL, file: file, line: line)
        }
    }
}
