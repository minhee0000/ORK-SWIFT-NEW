import Foundation

struct CIMetalFileRenamer {
    private let fileManager: FileManager

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    func rename(
        in root: URL,
        seed: String,
        filter: PathFilter,
        dryRun: Bool,
        mergeIntoSingle: Bool,
        manifest: inout ObfuscationManifest
    ) throws {
        let files = ciMetalFiles(in: root, excluding: filter)
        guard !files.isEmpty else { return }

        var usedByDirectory: [String: Set<String>] = [:]
        var swiftStringReplacements: [(from: String, to: String)] = []
        var usedFunctionNames = Set<String>()
        var renamedFiles: [URL] = []
        var renamedLoaderNames: [String] = []

        for file in files {
            let relative = relativePath(from: root, to: file)
            let functionReplacements = try rewriteCIMetalFunctions(
                in: file,
                relativePath: relative,
                seed: seed,
                dryRun: dryRun,
                usedFunctionNames: &usedFunctionNames,
                manifest: &manifest
            )
            swiftStringReplacements.append(contentsOf: functionReplacements)

            let directory = file.deletingLastPathComponent()
            let directoryPath = directory.path
            var used = usedByDirectory[directoryPath] ?? existingNames(in: directory)

            var basename = hexName(prefix: "R_", key: "\(seed)|ci-metal|\(relative)") + ".ci.metal"
            var counter = 1
            while used.contains(basename) || fileManager.fileExists(atPath: directory.appendingPathComponent(basename).path) {
                basename = hexName(prefix: "R_", key: "\(seed)|ci-metal|\(relative)|\(counter)") + ".ci.metal"
                counter += 1
            }

            used.insert(basename)
            usedByDirectory[directoryPath] = used

            let destination = directory.appendingPathComponent(basename)
            let newRelative = relativePath(from: root, to: destination)
            manifest.ciMetalFileRenames.append(.init(from: relative, to: newRelative))

            let oldLoaderName = logicalName(fromCIMetalFilename: file.lastPathComponent)
            let newLoaderName = logicalName(fromCIMetalFilename: basename)
            swiftStringReplacements.append((from: oldLoaderName, to: newLoaderName))
            renamedFiles.append(destination)
            renamedLoaderNames.append(newLoaderName)

            if !dryRun {
                try fileManager.moveItem(at: file, to: destination)
            }
        }

        if mergeIntoSingle,
           let mergedName = try mergeCIMetalFiles(
            renamedFiles,
            in: root,
            seed: seed,
            dryRun: dryRun,
            manifest: &manifest
           ) {
            swiftStringReplacements.append(contentsOf: renamedLoaderNames.map { (from: $0, to: mergedName) })
        }

        if !dryRun {
            try rewriteSwiftStringLiterals(in: root, filter: filter, replacements: swiftStringReplacements)
        }
    }

    private func ciMetalFiles(in root: URL, excluding filter: PathFilter) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var result: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            let relative = relativePath(from: root, to: url)
            if filter.isExcluded(relativePath: relative) {
                continue
            }

            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values?.isRegularFile == true, values?.isSymbolicLink != true else {
                continue
            }

            if url.lastPathComponent.hasSuffix(".ci.metal") {
                result.append(url)
            }
        }

        return result.sorted { $0.path < $1.path }
    }

    private func existingNames(in directory: URL) -> Set<String> {
        guard let items = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return Set(items.map(\.lastPathComponent))
    }

    private func logicalName(fromCIMetalFilename filename: String) -> String {
        String(filename.dropLast(".ci.metal".count))
    }

    private func mergeCIMetalFiles(
        _ files: [URL],
        in root: URL,
        seed: String,
        dryRun: Bool,
        manifest: inout ObfuscationManifest
    ) throws -> String? {
        let files = files.sorted { $0.path < $1.path }
        guard files.count > 1 else { return nil }

        var basename = hexName(prefix: "R_", key: "\(seed)|ci-metal-merged") + ".ci.metal"
        var counter = 1
        let rootNames = existingNames(in: root)
        while rootNames.contains(basename) || fileManager.fileExists(atPath: root.appendingPathComponent(basename).path) {
            basename = hexName(prefix: "R_", key: "\(seed)|ci-metal-merged|\(counter)") + ".ci.metal"
            counter += 1
        }

        let destination = root.appendingPathComponent(basename)
        let mergedRelative = relativePath(from: root, to: destination)
        manifest.ciMetalMergedFile = mergedRelative

        if dryRun {
            return logicalName(fromCIMetalFilename: basename)
        }

        var combined = """
        // AUTO-GENERATED BY ORK-SWIFT-NEW.
        // Core Image Metal kernels are merged for Release packaging.

        """

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            combined += "\n// MARK: \(file.lastPathComponent)\n"
            combined += source
            combined += "\n"
        }

        try combined.write(to: destination, atomically: true, encoding: .utf8)

        for file in files where file.path != destination.path {
            if fileManager.fileExists(atPath: file.path) {
                try fileManager.removeItem(at: file)
            }
        }

        return logicalName(fromCIMetalFilename: basename)
    }

    private func rewriteCIMetalFunctions(
        in file: URL,
        relativePath: String,
        seed: String,
        dryRun: Bool,
        usedFunctionNames: inout Set<String>,
        manifest: inout ObfuscationManifest
    ) throws -> [(from: String, to: String)] {
        let source = try String(contentsOf: file, encoding: .utf8)
        let functionNames = ciKernelFunctionNames(in: source)
        guard !functionNames.isEmpty else { return [] }

        var replacements: [(from: String, to: String)] = []
        for functionName in functionNames {
            var newName = hexName(prefix: "r_", key: "\(seed)|ci-metal-function|\(relativePath)|\(functionName)")
            var counter = 1
            while usedFunctionNames.contains(newName) || functionNames.contains(newName) {
                newName = hexName(prefix: "r_", key: "\(seed)|ci-metal-function|\(relativePath)|\(functionName)|\(counter)")
                counter += 1
            }

            usedFunctionNames.insert(newName)
            replacements.append((from: functionName, to: newName))
            manifest.ciMetalFunctionRenames.append(.init(file: relativePath, from: functionName, to: newName))
        }

        if !dryRun {
            let rewritten = replaceIdentifiers(in: source, replacements: Dictionary(uniqueKeysWithValues: replacements))
            if rewritten != source {
                try rewritten.write(to: file, atomically: true, encoding: .utf8)
            }
        }

        return replacements
    }

    private func ciKernelFunctionNames(in source: String) -> [String] {
        let pattern = #"(?m)^\s*(?!(?:static|inline)\b)(?:kernel\s+)?(?:float|half|void|int|uint|bool|sample_t)(?:[234])?\s+([A-Za-z][A-Za-z0-9_]*)\s*\("#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        var result: [String] = []
        var seen = Set<String>()

        for match in regex.matches(in: source, range: range) {
            guard match.numberOfRanges > 1,
                  let matchRange = Range(match.range(at: 1), in: source) else {
                continue
            }

            let name = String(source[matchRange])
            if seen.insert(name).inserted {
                result.append(name)
            }
        }

        return result
    }

    private func replaceIdentifiers(in source: String, replacements: [String: String]) -> String {
        guard !replacements.isEmpty else { return source }

        var result = ""
        result.reserveCapacity(source.count)
        var index = source.startIndex

        while index < source.endIndex {
            let character = source[index]
            if isIdentifierStart(character) {
                let start = index
                source.formIndex(after: &index)
                while index < source.endIndex, isIdentifierContinuation(source[index]) {
                    source.formIndex(after: &index)
                }

                let token = String(source[start..<index])
                result += replacements[token] ?? token
            } else {
                result.append(character)
                source.formIndex(after: &index)
            }
        }

        return result
    }

    private func isIdentifierStart(_ character: Character) -> Bool {
        character == "_" || character.isLetter
    }

    private func isIdentifierContinuation(_ character: Character) -> Bool {
        character == "_" || character.isLetter || character.isNumber
    }

    private func rewriteSwiftStringLiterals(
        in root: URL,
        filter: PathFilter,
        replacements: [(from: String, to: String)]
    ) throws {
        guard !replacements.isEmpty else { return }

        for file in swiftFiles(in: root, excluding: filter, fileManager: fileManager) {
            var source = try String(contentsOf: file, encoding: .utf8)
            let original = source

            for replacement in replacements {
                source = source.replacingOccurrences(
                    of: "\"\(replacement.from)\"",
                    with: "\"\(replacement.to)\""
                )
            }

            if source != original {
                try source.write(to: file, atomically: true, encoding: .utf8)
            }
        }
    }
}
