import Foundation
import XCTest
import CueCore

final class WebSearchTests: XCTestCase {
    func testEmptyAndWhitespaceOnlyQueriesHaveNoDestination() {
        for query in ["", " ", "\r\n\t ", "\u{00A0}\u{2003}\u{3000}"] {
            XCTAssertNil(WebSearch.googleURL(for: query), query.debugDescription)
        }
    }

    func testSearchRetainsOriginalTextAndOnlyTrimsItsEdges() throws {
        let query = "  \nCafé  ＡＢＣ\t正體中文\nC++ 🧑‍💻\r\n "
        let url = try XCTUnwrap(WebSearch.googleURL(for: query))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "q", value: "Café  ＡＢＣ\t正體中文\nC++ 🧑‍💻")])
    }

    func testLiteralPlusesAreEncodedForGoogleFormDecoding() throws {
        let url = try XCTUnwrap(WebSearch.googleURL(for: "C++ & C# 100%"))
        XCTAssertEqual(url.absoluteString, "https://www.google.com/search?q=C%2B%2B%20%26%20C%23%20100%25")
    }

    func testArbitraryQueriesCannotChangeTheDestinationOrInjectParameters() throws {
        let queries = [
            "a+b&c=d#fragment%20?x=y",
            "https://example.com/search?q=one+two&redirect=https://other.example/",
            "javascript:alert('hello')",
            "//other.example/?q=hello",
            "https://user:password@other.example:8443/#fragment",
            "日本語 正體中文 😀 + %2B %26 %23",
        ]
        for query in queries {
            let url = try XCTUnwrap(WebSearch.googleURL(for: query))
            let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            XCTAssertEqual(components.scheme, "https", query)
            XCTAssertEqual(components.host, "www.google.com", query)
            XCTAssertEqual(components.path, "/search", query)
            XCTAssertNil(components.user, query)
            XCTAssertNil(components.password, query)
            XCTAssertNil(components.port, query)
            XCTAssertNil(components.fragment, query)
            XCTAssertEqual(components.queryItems, [URLQueryItem(name: "q", value: query)], query)

            let encodedQuery = try XCTUnwrap(components.percentEncodedQuery)
            XCTAssertTrue(encodedQuery.hasPrefix("q="), query)
            let formDecodedQuery = String(encodedQuery.dropFirst(2))
                .replacingOccurrences(of: "+", with: " ")
                .removingPercentEncoding
            XCTAssertEqual(formDecodedQuery, query, query)
        }
    }

    func testFallbackUsesOriginalTextRatherThanLocalSearchNormalization() throws {
        let query = "  Why Café  ＡＢＣ + 正體中文?  "
        XCTAssertEqual(LauncherResult.search([], query: query, includeGoogleFallback: true), [.googleSearch])
        let url = try XCTUnwrap(WebSearch.googleURL(for: query))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first?.value, "Why Café  ＡＢＣ + 正體中文?")
    }

    func testBrowserChoiceRoundTripsWithoutAMachineSpecificAppPath() throws {
        let browsers = [
            WebSearchBrowser(bundleIdentifier: "com.example.browser", name: "Example Browser"),
            WebSearchBrowser(bundleIdentifier: "org.example.browser-beta", name: "瀏覽器 Beta"),
        ]
        let data = try JSONEncoder().encode(browsers)
        XCTAssertEqual(try JSONDecoder().decode([WebSearchBrowser].self, from: data), browsers)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        for browser in encoded {
            XCTAssertEqual(Set(browser.keys), ["bundleIdentifier", "name"])
        }
    }

    func testBrowserIdentitySurvivesDisplayNameChangesAndSupportsBoundedFallbacks() {
        let browser = WebSearchBrowser(bundleIdentifier: "com.example.browser", name: "Example")
        let renamed = WebSearchBrowser(bundleIdentifier: browser.bundleIdentifier, name: "Example Updated")
        XCTAssertEqual(browser.id, browser.bundleIdentifier)
        XCTAssertEqual(browser.id, renamed.id)
        XCTAssertEqual(Set([browser, browser]).count, 1)
        XCTAssertNotEqual(browser, renamed, "A changed label must remain visible to model/view equality checks")
        XCTAssertEqual(WebSearchBrowser.maximumAddedBrowsers, 8,
                       "One default-browser action plus added browsers must fit the launcher's nine rows")
    }
}
