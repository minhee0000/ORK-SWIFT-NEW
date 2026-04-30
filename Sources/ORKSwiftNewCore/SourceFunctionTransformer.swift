import Foundation

struct SourceFunctionTransformer {
    private let fileManager: FileManager

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    func transform(
        in root: URL,
        seed: String,
        filter: PathFilter,
        dryRun: Bool,
        manifest: inout ObfuscationManifest
    ) throws {
        for file in swiftFiles(in: root, excluding: filter, fileManager: fileManager) {
            let relative = relativePath(from: root, to: file)
            let original = try String(contentsOf: file, encoding: .utf8)
            let transformed = transformFunctions(
                source: original,
                relativeFile: relative,
                seed: seed,
                manifest: &manifest
            )
            if transformed != original, !dryRun {
                try transformed.write(to: file, atomically: true, encoding: .utf8)
            }
        }
    }
}
