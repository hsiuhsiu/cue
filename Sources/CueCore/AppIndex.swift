import Foundation

/// Discovers launchable application bundles without searching inside their contents.
public enum AppIndex {
    public static let defaultRoots: [URL] = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Library/CoreServices/Applications", isDirectory: true),
    ]

    /// Run this filesystem work away from the main actor. Earlier roots win when
    /// multiple copies of an application share a bundle identifier.
    /// Application names follow the system language, independently of Cue's UI language.
    public static func scan(
        roots: [URL] = defaultRoots,
        excludingBundleIdentifier: String? = "com.yyhsiu.cue",
        preferredLanguages: [String]? = nil
    ) -> [IndexedApplication] {
        let fileManager = FileManager()
        // Cue's interface language must not rename other apps in search results.
        // Locale.preferredLanguages and localizedInfoDictionary honor per-app overrides,
        // so read the system preference once and resolve bundle resources explicitly.
        let requestedLanguages = preferredLanguages
            ?? (UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String])
            ?? []
        let preferredLanguages = requestedLanguages.isEmpty ? ["en"] : requestedLanguages
        var applications: [IndexedApplication] = []
        var seenPaths = Set<String>()
        var seenBundleIdentifiers = Set<String>()

        for root in roots {
            for url in applicationURLs(in: root, fileManager: fileManager) {
                let canonicalURL = url.resolvingSymlinksInPath().standardizedFileURL
                guard !seenPaths.contains(canonicalURL.path) else { continue }

                let bundle = Bundle(url: canonicalURL)
                let bundleIdentifier = nonemptyString(bundle?.bundleIdentifier)
                let normalizedIdentifier = bundleIdentifier?.lowercased()

                if let normalizedIdentifier {
                    guard normalizedIdentifier != excludingBundleIdentifier?.lowercased(),
                          !seenBundleIdentifiers.contains(normalizedIdentifier) else { continue }
                    seenBundleIdentifiers.insert(normalizedIdentifier)
                }

                seenPaths.insert(canonicalURL.path)
                applications.append(IndexedApplication(
                    id: canonicalURL.path,
                    name: displayName(for: bundle, at: canonicalURL, preferredLanguages: preferredLanguages),
                    url: canonicalURL,
                    bundleIdentifier: bundleIdentifier
                ))
            }
        }

        return applications
    }

    private static func applicationURLs(in root: URL, fileManager: FileManager) -> [URL] {
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isHiddenKey, .isSymbolicLinkKey]
        guard let rootValues = try? root.resourceValues(forKeys: Set(keys)),
              rootValues.isDirectory == true,
              rootValues.isHidden != true else { return [] }

        if root.pathExtension.lowercased() == "app" { return [root] }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            guard !url.lastPathComponent.hasPrefix("."),
                  let values = try? url.resourceValues(forKeys: Set(keys)) else {
                enumerator.skipDescendants()
                continue
            }

            if url.pathExtension.lowercased() == "app" {
                // macOS marks the Safari symlink in /Applications as hidden,
                // although the application in the Cryptex is visible.
                guard values.isHidden != true || values.isSymbolicLink == true else {
                    enumerator.skipDescendants()
                    continue
                }
                let destination = url.resolvingSymlinksInPath()
                if let destinationValues = try? destination.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey]),
                   destinationValues.isDirectory == true,
                   destinationValues.isHidden != true {
                    urls.append(url)
                }
                enumerator.skipDescendants()
                continue
            }

            if values.isHidden == true || values.isPackage == true {
                enumerator.skipDescendants()
            }
        }

        // Directory enumeration order varies by filesystem. Sorting before
        // deduplication makes the selected copy predictable within each root.
        return urls.sorted { $0.path < $1.path }
    }

    private static func displayName(for bundle: Bundle?, at url: URL, preferredLanguages: [String]) -> String {
        let localizedInfo = bundle.flatMap { Self.localizedInfo(for: $0, preferredLanguages: preferredLanguages) }
        let info = bundle?.infoDictionary
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let name = nonemptyString(localizedInfo?[key] as? String)
                ?? nonemptyString(info?[key] as? String) {
                return name
            }
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private static func localizedInfo(for bundle: Bundle, preferredLanguages: [String]) -> [String: Any]? {
        guard let localization = Bundle.preferredLocalizations(
            from: bundle.localizations, forPreferences: preferredLanguages
        ).first,
              let url = bundle.url(
                forResource: "InfoPlist", withExtension: "strings", subdirectory: nil,
                localization: localization
              ),
              let data = try? Data(contentsOf: url),
              let info = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        else { return nil }
        return info as? [String: Any]
    }

    private static func nonemptyString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
