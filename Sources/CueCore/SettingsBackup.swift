import Foundation

public enum SettingsBackupError: Error, Equatable, Sendable {
    case invalidFile, unsupportedVersion, tooLarge, invalidSettings
    case passwordRequired, invalidPassword, encryptionRequired, authenticationFailed, cryptographyFailure
}

public enum SettingsBackupSection: String, CaseIterable, Hashable, Sendable {
    case general, appAliases, conversionAliases, browsers, gpt, clipboard, windows
}

/// Only explicitly portable fields exist in this schema. Machine permissions,
/// feature enablement, activity/history, paths, and credentials cannot be encoded.
public struct SettingsBackupDocument: Codable, Equatable, Sendable {
    public var format: String
    public var schemaVersion: Int
    public var exportedByVersion: String
    public var sections: SettingsBackupSections

    public init(exportedByVersion: String, sections: SettingsBackupSections,
                format: String = "cue-settings", schemaVersion: Int = 1) {
        self.format = format; self.schemaVersion = schemaVersion
        self.exportedByVersion = exportedByVersion; self.sections = sections
    }

    @discardableResult public func validated() throws -> Self {
        guard format == "cue-settings" else { throw SettingsBackupError.invalidFile }
        guard schemaVersion == 1 else { throw SettingsBackupError.unsupportedVersion }
        guard Self.safeText(exportedByVersion, maximumBytes: 64),
              exportedByVersion.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0)
                  || (97...122).contains($0) || [43, 45, 46].contains($0) }) else { throw SettingsBackupError.invalidSettings }
        if let general = sections.general {
            guard ["system", "en", "zh-Hant"].contains(general.language),
                  general.shortcut.isValid, Self.safeText(general.shortcut.key, maximumBytes: 96) else {
                throw SettingsBackupError.invalidSettings
            }
        }
        var aliases = Set<String>()
        if let apps = sections.appAliases {
            guard apps.count <= 256 else { throw SettingsBackupError.invalidSettings }
            var identifiers = Set<String>()
            for app in apps {
                let alias = SearchEngine.normalize(app.alias)
                guard Self.validBundleIdentifier(app.bundleIdentifier),
                      identifiers.insert(app.bundleIdentifier.lowercased()).inserted,
                      Self.safeText(app.alias, maximumBytes: 128), app.alias.count <= 32,
                      alias.count <= 32, alias.first?.isLetter == true,
                      alias.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }),
                      aliases.insert(alias).inserted else { throw SettingsBackupError.invalidSettings }
            }
        }
        if let conversion = sections.conversionAliases {
            guard let checked = try? ChineseConversionAliases(traditional: conversion.traditional, simplified: conversion.simplified),
                  checked.traditional == conversion.traditional, checked.simplified == conversion.simplified else {
                throw SettingsBackupError.invalidSettings
            }
            for alias in [checked.traditional, checked.simplified] where !alias.isEmpty {
                guard !aliases.contains(SearchEngine.normalize(alias)) else { throw SettingsBackupError.invalidSettings }
            }
        }
        if let browsers = sections.browsers {
            guard browsers.count <= 8 else { throw SettingsBackupError.invalidSettings }
            var identifiers = Set<String>()
            for browser in browsers {
                guard Self.validBundleIdentifier(browser.bundleIdentifier),
                      Self.safeText(browser.name, maximumBytes: 256),
                      identifiers.insert(browser.bundleIdentifier.lowercased()).inserted else { throw SettingsBackupError.invalidSettings }
            }
        }
        if let gpt = sections.gpt {
            guard GPTConfiguration.isValidModelID(gpt.model), GPTTranslationTarget(rawValue: gpt.translationTarget) != nil else {
                throw SettingsBackupError.invalidSettings
            }
        }
        if let windows = sections.windows {
            guard windows.shortcut.isValid, Self.safeText(windows.shortcut.key, maximumBytes: 96),
                  !(windows.shortcut.modifiers == .option && (123...126).contains(windows.shortcut.keyCode)),
                  windows.presets.count <= 9, windows.presets.allSatisfy(\.isValid),
                  Set(windows.presets.map(\.slot)).count == windows.presets.count else { throw SettingsBackupError.invalidSettings }
            // Whether both global shortcuts are registered depends on this Mac's
            // enablement choice, which intentionally is not portable. The apply
            // coordinator validates that runtime conflict before committing.
        }
        return self
    }

    static func validBundleIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 255
            && value.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0)
                || (97...122).contains($0) || $0 == 45 || $0 == 46 })
    }

    static func safeText(_ value: String, maximumBytes: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= maximumBytes
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
}

public struct SettingsBackupSections: Codable, Equatable, Sendable {
    public var general: SettingsBackupGeneral?
    public var appAliases: [SettingsBackupAppAlias]?
    public var conversionAliases: SettingsBackupConversion?
    public var browsers: [SettingsBackupBrowser]?
    public var gpt: SettingsBackupGPT?
    public var clipboard: SettingsBackupClipboard?
    public var windows: SettingsBackupWindows?

    public init(general: SettingsBackupGeneral? = nil, appAliases: [SettingsBackupAppAlias]? = nil,
                conversionAliases: SettingsBackupConversion? = nil, browsers: [SettingsBackupBrowser]? = nil,
                gpt: SettingsBackupGPT? = nil, clipboard: SettingsBackupClipboard? = nil,
                windows: SettingsBackupWindows? = nil) {
        self.general = general; self.appAliases = appAliases; self.conversionAliases = conversionAliases
        self.browsers = browsers; self.gpt = gpt; self.clipboard = clipboard; self.windows = windows
    }

    public var available: Set<SettingsBackupSection> {
        var value = Set<SettingsBackupSection>()
        if general != nil { value.insert(.general) }; if appAliases != nil { value.insert(.appAliases) }
        if conversionAliases != nil { value.insert(.conversionAliases) }; if browsers != nil { value.insert(.browsers) }
        if gpt != nil { value.insert(.gpt) }; if clipboard != nil { value.insert(.clipboard) }
        if windows != nil { value.insert(.windows) }
        return value
    }
}

public struct SettingsBackupGeneral: Codable, Equatable, Sendable {
    public var language: String
    public var shortcut: LauncherShortcut
    public var display: LauncherPreferences.Display
    public var dismissOnFocusLoss: Bool
    public init(language: String, shortcut: LauncherShortcut, display: LauncherPreferences.Display, dismissOnFocusLoss: Bool) {
        self.language = language; self.shortcut = shortcut; self.display = display; self.dismissOnFocusLoss = dismissOnFocusLoss
    }
}

public struct SettingsBackupAppAlias: Codable, Equatable, Sendable {
    public var bundleIdentifier: String
    public var alias: String
    public init(bundleIdentifier: String, alias: String) { self.bundleIdentifier = bundleIdentifier; self.alias = alias }
}

public struct SettingsBackupConversion: Codable, Equatable, Sendable {
    public var traditional: String
    public var simplified: String
    public init(traditional: String, simplified: String) { self.traditional = traditional; self.simplified = simplified }
}

public struct SettingsBackupBrowser: Codable, Equatable, Sendable {
    public var bundleIdentifier: String
    public var name: String
    public init(bundleIdentifier: String, name: String) { self.bundleIdentifier = bundleIdentifier; self.name = name }
}

public struct SettingsBackupGPT: Codable, Equatable, Sendable {
    public var model: String
    public var translationTarget: String
    public init(model: String, translationTarget: String) { self.model = model; self.translationTarget = translationTarget }
}

public struct SettingsBackupClipboard: Codable, Equatable, Sendable {
    public var retention: ClipboardRetention
    public init(retention: ClipboardRetention) { self.retention = retention }
}

public struct SettingsBackupWindows: Codable, Equatable, Sendable {
    public var shortcut: LauncherShortcut
    public var keepModeOpen: Bool
    public var presets: [WindowPreset]
    public init(shortcut: LauncherShortcut, keepModeOpen: Bool, presets: [WindowPreset]) {
        self.shortcut = shortcut; self.keepModeOpen = keepModeOpen; self.presets = presets
    }
}

public struct SettingsBackupDecoded: Sendable {
    public let document: SettingsBackupDocument
    public let apiKey: String?
    public let isEncrypted: Bool
    /// Ignored field paths only, never their potentially sensitive values.
    public let warnings: [String]
    public init(document: SettingsBackupDocument, apiKey: String?, isEncrypted: Bool, warnings: [String] = []) {
        self.document = document; self.apiKey = apiKey; self.isEncrypted = isEncrypted; self.warnings = warnings
    }
}
