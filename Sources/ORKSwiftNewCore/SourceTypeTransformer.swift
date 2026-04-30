import Foundation

struct SourceTypeTransformer {
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
        let files = try swiftFiles(in: root, excluding: filter, fileManager: fileManager).map { file in
            let source = try String(contentsOf: file, encoding: .utf8)
            return TypeSourceFile(
                url: file,
                relativePath: relativePath(from: root, to: file),
                source: source,
                tokens: tokenize(source)
            )
        }

        let transformed = transformTypes(
            files: files,
            seed: seed,
            manifest: &manifest
        )

        guard !dryRun else { return }

        for file in transformed where file.source != file.originalSource {
            try file.source.write(to: file.url, atomically: true, encoding: .utf8)
        }
    }
}
