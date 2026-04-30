import Foundation

func makeURL(_ path: String) -> URL {
    URL(fileURLWithPath: path).standardizedFileURL
}

func relativePath(from root: URL, to file: URL) -> String {
    let rootPath = root.standardizedFileURL.path
    let filePath = file.standardizedFileURL.path
    guard filePath.hasPrefix(rootPath + "/") else { return file.lastPathComponent }
    return String(filePath.dropFirst(rootPath.count + 1))
}

func ensureDirectory(_ url: URL, fileManager: FileManager) throws {
    try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
}

func copySourceTree(from input: URL, to output: URL, fileManager: FileManager) throws {
    if input.standardizedFileURL.path == output.standardizedFileURL.path {
        throw ORKSwiftNewError.invalidConfiguration("--output must be different from --input")
    }
    if fileManager.fileExists(atPath: output.path) {
        try fileManager.removeItem(at: output)
    }
    try ensureDirectory(output.deletingLastPathComponent(), fileManager: fileManager)
    try fileManager.copyItem(at: input, to: output)
}

func swiftFiles(in root: URL, excluding filter: PathFilter, fileManager: FileManager) -> [URL] {
    guard let enumerator = fileManager.enumerator(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }

    var result: [URL] = []
    for case let url as URL in enumerator {
        let relative = relativePath(from: root, to: url)
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        if values?.isDirectory == true {
            if filter.isExcluded(relativePath: relative) {
                enumerator.skipDescendants()
            }
            continue
        }
        if values?.isRegularFile == true && url.pathExtension == "swift" {
            if filter.isExcluded(relativePath: relative) {
                continue
            }
            result.append(url)
        }
    }

    return result.sorted { $0.path < $1.path }
}
