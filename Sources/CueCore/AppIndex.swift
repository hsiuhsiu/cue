import Foundation

/// Discovers launchable application bundles without searching inside their contents.
public enum AppIndex {
    public static let defaultRoots: [URL] = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Library/CoreServices/Applications", isDirectory: true),
        // Finder lives beside Applications. Index this bundle directly so
        // CoreServices' background helpers do not become launcher results.
        URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app", isDirectory: true),
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
                // Read the selected localization only once. Keep all declared
                // names searchable without changing the system display name.
                let localizedInfo = bundle.flatMap { Self.localizedInfo(for: $0, preferredLanguages: preferredLanguages) }
                let info = bundle?.infoDictionary
                let searchNames = ["CFBundleDisplayName", "CFBundleName"].flatMap { key in
                    [nonemptyString(localizedInfo?[key] as? String), nonemptyString(info?[key] as? String)]
                        .compactMap { $0 }
                } + [canonicalURL.deletingPathExtension().lastPathComponent]
                applications.append(IndexedApplication(
                    id: canonicalURL.path,
                    name: displayName(localizedInfo: localizedInfo, info: info, at: canonicalURL),
                    url: canonicalURL,
                    bundleIdentifier: bundleIdentifier,
                    searchNames: searchNames
                ))
            }
        }

        return applications
    }

    private static func applicationURLs(in root: URL, fileManager: FileManager) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isHiddenKey, .isSymbolicLinkKey]
        let keySet = Set(keys)
        var pending = [root]
        var visitedDirectories = Set<String>()
        var urls: [URL] = []
        while let candidate = pending.popLast() {
            let directory = candidate.resolvingSymlinksInPath().standardizedFileURL
            guard visitedDirectories.insert(directory.path).inserted,
                  let values = try? directory.resourceValues(forKeys: keySet),
                  values.isDirectory == true, values.isHidden != true,
                  !directory.lastPathComponent.hasPrefix(".") else { continue }

            if directory.pathExtension.lowercased() == "app" {
                urls.append(directory)
                continue
            }
            // Localized application folders (for example Chrome Apps.localized)
            // are containers even when Finder gives them a package flag. Actual
            // bundles remain opaque so their helpers never become results.
            guard values.isPackage != true || directory.pathExtension.lowercased() == "localized",
                  let children = try? fileManager.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: keys
                  ) else { continue }
            for child in children {
                guard !child.lastPathComponent.hasPrefix("."),
                      let childValues = try? child.resourceValues(forKeys: keySet) else { continue }
                // macOS marks the Safari symlink as hidden, while its destination
                // is visible. Keep this exception limited to application links.
                let isApplicationLink = child.pathExtension.lowercased() == "app"
                    && childValues.isSymbolicLink == true
                guard childValues.isHidden != true || isApplicationLink else { continue }
                if childValues.isDirectory == true || childValues.isSymbolicLink == true {
                    // Follow visible directory links as well as application links.
                    // Canonical paths above stop loops and repeated subtrees.
                    pending.append(child)
                }
            }
        }

        // Directory enumeration order varies by filesystem. Sorting before
        // deduplication makes the selected copy predictable within each root.
        return urls.sorted { $0.path < $1.path }
    }

    private static func displayName(localizedInfo: [String: Any]?, info: [String: Any]?, at url: URL) -> String {
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
