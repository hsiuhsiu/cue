import AppKit
import Foundation
import Sparkle

/// Runs in a disposable copy with a test bundle identifier. No application
/// delegate, preferences, hotkeys, clipboard, credentials or network services.
@main struct CheckSourceApp {
    static func main() throws {
        let app = Bundle.main
        precondition(app.bundleIdentifier == "com.yyhsiu.cue.tests.source-app")
        let expected = app.bundleURL.appendingPathComponent("Contents/Frameworks/Sparkle.framework")
        precondition(Bundle(for: SPUUpdater.self).bundleURL.resolvingSymlinksInPath() == expected.resolvingSymlinksInPath(),
                     "Sparkle must load from the relocated app, not the build machine")

        func resource(_ name: String, _ extensionName: String) -> URL {
            guard let url = app.url(forResource: name, withExtension: extensionName),
                  url.path.hasPrefix(app.bundleURL.path + "/") else {
                fatalError("Missing embedded resource: \(name).\(extensionName)")
            }
            return url
        }
        for name in ["AppIcon", "MenuBarIconTemplate", "MenuBarIconTemplate@2x",
                     "MenuBarIconUpdateTemplate", "MenuBarIconUpdateTemplate@2x"] {
            let url = resource(name, name == "AppIcon" ? "icns" : "png")
            precondition(NSImage(contentsOf: url)?.isValid == true, "Icon must decode: \(name)")
        }
        for name in ["Cue-LICENSE", "Sparkle-LICENSE", "OpenCC-LICENSE", "OpenCC-NOTICE",
                     "Unicode-LICENSE", "Emoji-NOTICE"] {
            let data = try Data(contentsOf: resource(name, "txt"))
            precondition(!data.isEmpty)
        }
        let converter = try ChineseConverter(resourceURL: resource("ChineseConversion", "cuecc"))
        let traditional = try converter.convert("软件和鼠标", to: .traditionalTaiwan)
        precondition(traditional == "軟體和滑鼠", "Shipped Taiwan vocabulary must work offline")
        let simplified = try converter.convert(traditional, to: .simplifiedChina)
        precondition(simplified == "软件和鼠标", "Shipped China vocabulary must work offline")

        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: resource("EmojiCatalog", "json")))
        let entries = (catalog as? [String: Any])?["entries"] as? [[String: Any]]
        precondition((entries?.count ?? 0) > 1_000, "The complete emoji catalog must be embedded")

        let translated = app.preferredLocalizations.first == "zh-Hant"
        precondition(app.localizedString(forKey: "menu.settings", value: "MISSING", table: "Menu")
                     == (translated ? "設定…" : "Settings…"), "Main-bundle language resolution must work")
        print("Relocated app probe passed: \(app.preferredLocalizations), Sparkle, icons, licenses, emoji and Chinese conversion.")
    }
}
