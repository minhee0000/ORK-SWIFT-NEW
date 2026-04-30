import Foundation

struct SwiftDirectoryRenamer {
    private let fileManager: FileManager

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    func rename(
        in root: URL,
        seed: String,
        filter: PathFilter,
        dryRun: Bool,
        manifest: inout ObfuscationManifest
    ) throws {
        let candidates = swiftOnlyDirectories(in: root, excluding: filter)
            .sorted { lhs, rhs in
                pathDepth(lhs) < pathDepth(rhs)
            }

        var mappings: [(from: String, to: String)] = []
        var usedByParent: [String: Set<String>] = [:]

        for originalRelative in candidates {
            let currentRelative = applyingDirectoryMappings(to: originalRelative, mappings: mappings)
            let currentURL = root.appendingPathComponent(currentRelative)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: currentURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }

            let parentURL = currentURL.deletingLastPathComponent()
            let parentRelative = parentURL.standardizedFileURL.path == root.standardizedFileURL.path
                ? "."
                : relativePath(from: root, to: parentURL)
            let parentKey = parentURL.path
            var used = usedByParent[parentKey] ?? existingDirectoryNames(in: parentURL)
            var basename = hexName(prefix: "D_", key: "\(seed)|directory|\(originalRelative)")
            var counter = 1
            while used.contains(basename) {
                basename = hexName(prefix: "D_", key: "\(seed)|directory|\(originalRelative)|\(counter)")
                counter += 1
            }
            used.insert(basename)
            usedByParent[parentKey] = used

            let destination = parentURL.appendingPathComponent(basename)
            let newRelative = parentRelative == "."
                ? basename
                : parentRelative + "/" + basename

            manifest.directoryRenames.append(.init(from: originalRelative, to: newRelative))
            mappings.append((from: originalRelative, to: newRelative))

            if !dryRun {
                try fileManager.moveItem(at: currentURL, to: destination)
            }
        }
    }

    private func swiftOnlyDirectories(in root: URL, excluding filter: PathFilter) -> [String] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var infos: [String: DirectoryInfo] = [:]

        for case let url as URL in enumerator {
            let relative = relativePath(from: root, to: url)
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])

            if values?.isDirectory == true {
                if filter.isExcluded(relativePath: relative) {
                    markAncestors(of: relative, in: &infos, excluded: true)
                    enumerator.skipDescendants()
                    continue
                }
                _ = info(for: relative, in: &infos)
                continue
            }

            guard values?.isRegularFile == true, values?.isSymbolicLink != true else {
                markAncestors(of: relative, in: &infos, nonSwift: true)
                continue
            }

            if filter.isExcluded(relativePath: relative) {
                markAncestors(of: relative, in: &infos, excluded: true)
            } else if url.pathExtension == "swift" {
                markAncestors(of: relative, in: &infos, swift: true)
            } else {
                markAncestors(of: relative, in: &infos, nonSwift: true)
            }
        }

        return infos
            .filter { key, value in
                key != "." && value.containsSwift && !value.containsNonSwift && !value.containsExcluded
            }
            .map(\.key)
    }

    private func info(for relative: String, in infos: inout [String: DirectoryInfo]) -> DirectoryInfo {
        if let existing = infos[relative] {
            return existing
        }
        let created = DirectoryInfo()
        infos[relative] = created
        return created
    }

    private func markAncestors(
        of relative: String,
        in infos: inout [String: DirectoryInfo],
        swift: Bool = false,
        nonSwift: Bool = false,
        excluded: Bool = false
    ) {
        let directory = directoryPart(of: relative)
        guard directory != "." else { return }

        let parts = directory.split(separator: "/").map(String.init)
        var current = ""
        for part in parts {
            current = current.isEmpty ? part : current + "/" + part
            var value = info(for: current, in: &infos)
            value.containsSwift = value.containsSwift || swift
            value.containsNonSwift = value.containsNonSwift || nonSwift
            value.containsExcluded = value.containsExcluded || excluded
            infos[current] = value
        }
    }

    private func directoryPart(of relative: String) -> String {
        guard let slash = relative.lastIndex(of: "/") else {
            return "."
        }
        return String(relative[..<slash])
    }

    private func existingDirectoryNames(in directory: URL) -> Set<String> {
        guard let items = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return []
        }

        return Set(items.compactMap { item in
            let values = try? item.resourceValues(forKeys: [.isDirectoryKey])
            return values?.isDirectory == true ? item.lastPathComponent : nil
        })
    }

    private func applyingDirectoryMappings(
        to relative: String,
        mappings: [(from: String, to: String)]
    ) -> String {
        guard let mapping = mappings
            .filter({ relative == $0.from || relative.hasPrefix($0.from + "/") })
            .max(by: { pathDepth($0.from) < pathDepth($1.from) })
        else {
            return relative
        }

        if relative == mapping.from {
            return mapping.to
        }

        return mapping.to + String(relative.dropFirst(mapping.from.count))
    }

    private func pathDepth(_ path: String) -> Int {
        path.split(separator: "/").count
    }
}

private struct DirectoryInfo {
    var containsSwift = false
    var containsNonSwift = false
    var containsExcluded = false
}
