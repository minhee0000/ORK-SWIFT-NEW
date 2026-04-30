import Foundation

struct ManifestWriter {
    private let fileManager: FileManager

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    func write(_ manifest: ObfuscationManifest, to path: String?) throws {
        guard let path else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)

        if path == "-" {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }

        let url = makeURL(path)
        try ensureDirectory(url.deletingLastPathComponent(), fileManager: fileManager)
        try data.write(to: url, options: .atomic)
    }
}
