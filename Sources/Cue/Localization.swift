import CueCore
import Foundation

/// Resolve interface text once in each screen's cached strings, never per keystroke.
enum L10n {
    private static let bundle: Bundle = {
        // The install script stages the same main-bundle layout as Xcode.
        #if SWIFT_PACKAGE && !CUE_APP_BUNDLE
        return .module
        #else
        return .main
        #endif
    }()

    static func string(_ key: String, table: String = "Localizable", value: String) -> String {
        bundle.localizedString(forKey: key, value: value, table: table)
    }

    static func format(_ format: String, _ arguments: CVarArg...) -> String {
        String(format: format, locale: Locale.current, arguments: arguments)
    }

    private static let keyNames: [UInt32: String] = [
        36: string("key.return", value: "Return"),
        48: string("key.tab", value: "Tab"),
        49: string("key.space", value: "Space"),
        76: string("key.enter", value: "Enter"),
        114: string("key.help", value: "Help"),
        115: string("key.home", value: "Home"),
        116: string("key.page_up", value: "Page Up"),
        119: string("key.end", value: "End"),
        121: string("key.page_down", value: "Page Down"),
    ]

    static func keyName(for shortcut: LauncherShortcut) -> String {
        keyNames[shortcut.keyCode] ?? shortcut.key
    }
}

extension LauncherShortcut {
    /// Localize presentation only; saved shortcuts and hot-key registration remain language-independent.
    var localizedDisplayName: String {
        var displayed = self
        displayed.key = L10n.keyName(for: self)
        return displayed.displayName
    }
}
