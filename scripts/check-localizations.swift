import Foundation

// Validate the shipped resources as well as the source tables. No UI or preference writes.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = root.appendingPathComponent("Sources/Cue/Resources")
let tables = ["Localizable", "Settings", "Launcher", "Menu", "Clipboard", "ChineseConversion"]
let languages = ["en", "zh-Hant"]
let placeholder = try NSRegularExpression(pattern: #"%(?:([1-9][0-9]*)\$)?(ld|d|@)"#)
var checked = 0

func readTable(_ directory: URL, _ language: String, _ table: String) throws -> [String: String] {
    let url = directory.appendingPathComponent("\(language).lproj/\(table).strings")
    let data = try Data(contentsOf: url)
    guard let values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] else {
        throw NSError(domain: "CueLocalizationCheck", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Invalid string table: \(url.path)"])
    }
    return values
}

func arguments(_ format: String) -> [Int: String] {
    let text = format as NSString
    let matches = placeholder.matches(in: format, range: NSRange(location: 0, length: text.length))
    var result: [Int: String] = [:]
    for (index, match) in matches.enumerated() {
        let position = match.range(at: 1)
        let slot = position.location == NSNotFound ? index + 1 : Int(text.substring(with: position))!
        let type = text.substring(with: match.range(at: 2))
        precondition(result[slot] == nil || result[slot] == type, "Conflicting format argument types")
        result[slot] = type
    }
    return result
}

for table in tables {
    let english = try readTable(source, "en", table)
    let chinese = try readTable(source, "zh-Hant", table)
    precondition(Set(english.keys) == Set(chinese.keys), "Missing translation in \(table)")
    for (key, value) in english {
        let translation = chinese[key]!
        precondition(!value.isEmpty && !translation.isEmpty, "Empty translation: \(key)")
        precondition(arguments(value) == arguments(translation), "Mismatched format arguments: \(key)")
        checked += 1
    }
}

let supported = languages
for preferred in ["zh-Hant-US", "zh-TW", "zh-HK"] {
    precondition(Bundle.preferredLocalizations(from: supported, forPreferences: [preferred]).first == "zh-Hant",
                 "Traditional Chinese locale should resolve: \(preferred)")
}
precondition(Bundle.preferredLocalizations(from: supported, forPreferences: ["en-US"]).first == "en")
precondition(Bundle.preferredLocalizations(from: supported, forPreferences: ["fr-FR"]).first == "en")

if let path = CommandLine.arguments.dropFirst().first {
    let appURL = URL(fileURLWithPath: path)
    guard let bundle = Bundle(url: appURL), let resources = bundle.resourceURL else {
        fatalError("Cannot load built app bundle: \(path)")
    }
    for language in languages {
        precondition(bundle.localizations.contains(language), "App does not declare \(language)")
        let localized = Bundle(url: resources.appendingPathComponent("\(language).lproj"))!
        for table in tables {
            let original = try readTable(source, language, table)
            let bundled = try readTable(resources, language, table)
            precondition(bundled == original,
                         "Bundled \(language)/\(table) differs from source")
            for (key, value) in original {
                precondition(localized.localizedString(forKey: key, value: "MISSING", table: table) == value,
                             "Bundle cannot resolve \(language)/\(table)/\(key)")
            }
        }
    }
    let english = try readTable(resources, "en", "Launcher")
    let chinese = try readTable(resources, "zh-Hant", "Launcher")
    precondition(String(format: english["index.updated"]!, 12) == "Index updated · 12 applications")
    precondition(String(format: chinese["index.updated"]!, 12) == "索引已更新 · 12 個應用程式")
    let menu = try readTable(resources, "zh-Hant", "Menu")
    let conflict = String(format: menu["menu.shortcutConflict"]!, "⌥空白鍵", Int32(-9878))
    precondition(conflict.contains("⌥空白鍵") && conflict.contains("-9878"))
    print("Built app localization passed: both languages, all tables, Bundle resolution, and formatted messages.")
}

print("Localization passed: \(checked) English/Traditional Chinese pairs, format arguments, locale matching, and fallback.")
