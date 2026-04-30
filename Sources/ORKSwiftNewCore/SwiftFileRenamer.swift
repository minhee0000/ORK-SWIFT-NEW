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
        var usedByDirectory: [String: Set<String>] = [:]

        for file in files {
            let relative = relativePath(from: root, to: file)
            if symlinkTargets.contains(file.standardizedFileURL.path) {
                continue
            }

            let directory = file.deletingLastPathComponent()
            let directoryPath = directory.path
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
}
