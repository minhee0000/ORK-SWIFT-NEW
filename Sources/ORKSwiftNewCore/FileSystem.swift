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

func copySourceTree(from input: URL, to output: URL, pruning patterns: [String], fileManager: FileManager) throws {
    let inputPath = input.standardizedFileURL.path
    let outputPath = output.standardizedFileURL.path
    if inputPath == outputPath {
        throw ORKSwiftNewError.invalidConfiguration("--output must be different from --input")
    }
    if outputPath.hasPrefix(inputPath + "/") {
        throw ORKSwiftNewError.invalidConfiguration("--output must not be inside --input")
    }
    if fileManager.fileExists(atPath: output.path) {
        try fileManager.removeItem(at: output)
    }
    try ensureDirectory(output.deletingLastPathComponent(), fileManager: fileManager)
    try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
    try copyDirectoryContents(
        from: input,
        to: output,
        root: input,
        pruning: PathFilter(patterns: patterns),
        fileManager: fileManager
    )
}

private func copyDirectoryContents(
    from sourceDirectory: URL,
    to destinationDirectory: URL,
    root: URL,
    pruning filter: PathFilter,
    fileManager: FileManager
) throws {
    let items = try fileManager.contentsOfDirectory(
        at: sourceDirectory,
        includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
    )

    for item in items {
        let relative = relativePath(from: root, to: item)
        if filter.isExcluded(relativePath: relative) {
            continue
        }

        let destination = destinationDirectory.appendingPathComponent(item.lastPathComponent)
        let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        if values.isDirectory == true, values.isSymbolicLink != true {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            try copyDirectoryContents(
                from: item,
                to: destination,
                root: root,
                pruning: filter,
                fileManager: fileManager
            )
        } else {
            try fileManager.copyItem(at: item, to: destination)
        }
    }
}

func swiftFiles(in root: URL, excluding filter: PathFilter, fileManager: FileManager) -> [URL] {
    guard let enumerator = fileManager.enumerator(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }

    var result: [URL] = []
    for case let url as URL in enumerator {
        let relative = relativePath(from: root, to: url)
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        if values?.isDirectory == true {
            if filter.isExcluded(relativePath: relative) {
                enumerator.skipDescendants()
            }
            continue
        }
        if values?.isRegularFile == true && values?.isSymbolicLink != true && url.pathExtension == "swift" {
            if filter.isExcluded(relativePath: relative) {
                continue
            }
            result.append(url)
        }
    }

    return result.sorted { $0.path < $1.path }
}

func swiftSymlinkTargetPaths(in root: URL, excluding filter: PathFilter, fileManager: FileManager) -> Set<String> {
    guard let enumerator = fileManager.enumerator(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }

    var result = Set<String>()
    for case let url as URL in enumerator {
        let relative = relativePath(from: root, to: url)
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        if values?.isDirectory == true {
            if filter.isExcluded(relativePath: relative) {
                enumerator.skipDescendants()
            }
            continue
        }

        guard values?.isSymbolicLink == true, url.pathExtension == "swift" else {
            continue
        }
        guard !filter.isExcluded(relativePath: relative) else {
            continue
        }
        guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: url.path) else {
            continue
        }

        let destinationURL: URL
        if destination.hasPrefix("/") {
            destinationURL = URL(fileURLWithPath: destination)
        } else {
            destinationURL = url.deletingLastPathComponent().appendingPathComponent(destination)
        }

        let standardizedDestination = destinationURL.standardizedFileURL
        let rootPath = root.standardizedFileURL.path
        guard standardizedDestination.path.hasPrefix(rootPath + "/") else {
            continue
        }
        let destinationRelative = relativePath(from: root, to: standardizedDestination)
        guard destinationRelative.hasSuffix(".swift"), !filter.isExcluded(relativePath: destinationRelative) else {
            continue
        }
        result.insert(standardizedDestination.path)
    }

    return result
}
