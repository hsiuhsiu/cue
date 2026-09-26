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
    public static func scan(
        roots: [URL] = defaultRoots,
        excludingBundleIdentifier: String? = "com.yyhsiu.cue"
    ) -> [IndexedApplication] {
        let fileManager = FileManager()
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
                    name: displayName(for: bundle, at: canonicalURL),
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

    private static func displayName(for bundle: Bundle?, at url: URL) -> String {
        let localizedInfo = bundle?.localizedInfoDictionary
        let info = bundle?.infoDictionary
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let name = nonemptyString(localizedInfo?[key] as? String)
                ?? nonemptyString(info?[key] as? String) {
                return name
            }
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private static func nonemptyString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
