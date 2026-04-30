import Foundation

struct SwiftFileRenamer {
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
        let files = swiftFiles(in: root, excluding: filter, fileManager: fileManager)
        let symlinkTargets = swiftSymlinkTargetPaths(in: root, excluding: filter, fileManager: fileManager)
        let importSensitiveDirectories = accessControlledImportDirectories(in: files)
        var usedByDirectory: [String: Set<String>] = [:]

        for file in files {
            let relative = relativePath(from: root, to: file)
            if symlinkTargets.contains(file.standardizedFileURL.path) {
                continue
            }

            let directory = file.deletingLastPathComponent()
            let directoryPath = directory.path
            if importSensitiveDirectories.contains(directoryPath) {
                continue
            }

            var used = usedByDirectory[directoryPath] ?? Set<String>()
            var basename = hexName(prefix: "S_", key: "\(seed)|file|\(relative)") + ".swift"
            var counter = 1
            while used.contains(basename) || fileManager.fileExists(atPath: directory.appendingPathComponent(basename).path) {
                basename = hexName(prefix: "S_", key: "\(seed)|file|\(relative)|\(counter)") + ".swift"
                counter += 1
            }
            used.insert(basename)
            usedByDirectory[directoryPath] = used

            let destination = directory.appendingPathComponent(basename)
            let newRelative = relativePath(from: root, to: destination)
            manifest.fileRenames.append(.init(from: relative, to: newRelative))

            if !dryRun {
                try fileManager.moveItem(at: file, to: destination)
            }
        }
    }

    private func accessControlledImportDirectories(in files: [URL]) -> Set<String> {
        Set(files.compactMap { file in
            guard fileHasAccessControlledImport(file) else { return nil }
            return file.deletingLastPathComponent().path
        })
    }

    private func fileHasAccessControlledImport(_ file: URL) -> Bool {
        guard let source = try? String(contentsOf: file, encoding: .utf8) else {
            return false
        }

        let importQualifiers = [
            "public",
            "internal",
            "package",
            "fileprivate",
            "private",
            "_exported",
            "_implementationOnly"
        ]
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") {
                continue
            }

            let words = tokenize(String(trimmed))
                .filter { $0.kind == .word }
                .map(\.text)

            guard words.contains("import") else {
                continue
            }

            if !Set(words).isDisjoint(with: importQualifiers) {
                return true
            }
        }

        return false
    }
}
