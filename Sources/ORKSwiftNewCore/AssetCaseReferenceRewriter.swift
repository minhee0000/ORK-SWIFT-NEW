import Foundation

struct AssetCaseReferenceRewriter {
    private let fileManager: FileManager

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    func rewrite(
        in root: URL,
        seed: String,
        enumRelativePath: String,
        enumName: String,
        receiverName: String,
        methodNames: Set<String>,
        filter: PathFilter,
        dryRun: Bool,
        manifest: inout ObfuscationManifest
    ) throws {
        let enumURL = root.appendingPathComponent(enumRelativePath)
        guard fileManager.fileExists(atPath: enumURL.path) else {
            throw ORKSwiftNewError.invalidInput("Asset case enum source does not exist: \(enumRelativePath)")
        }

        let enumSource = try String(contentsOf: enumURL, encoding: .utf8)
        let caseNames = assetCaseNames(in: enumSource, enumName: enumName)
        guard !caseNames.isEmpty else { return }

        let mapping = opaqueCaseMapping(for: caseNames, seed: seed)
        manifest.assetCaseRenames.append(contentsOf: caseNames.map {
            .init(file: enumRelativePath, enumName: enumName, from: $0, to: mapping[$0] ?? $0)
        })

        var files = swiftFiles(in: root, excluding: filter, fileManager: fileManager)
        if !files.contains(where: { $0.standardizedFileURL.path == enumURL.standardizedFileURL.path }) {
            files.append(enumURL)
        }
        files.sort { $0.path < $1.path }

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let relative = relativePath(from: root, to: file)
            let transformed = rewriteAssetCaseReferences(
                in: source,
                mapping: mapping,
                receiverName: receiverName,
                methodNames: methodNames,
                rewriteDeclarations: relative == enumRelativePath
            )
            if transformed != source, !dryRun {
                try transformed.write(to: file, atomically: true, encoding: .utf8)
            }
        }
    }

    private func assetCaseNames(in source: String, enumName: String) -> [String] {
        let tokens = tokenize(source)
        guard let enumIndex = tokens.indices.first(where: { tokens[$0].kind == .word && tokens[$0].text == "enum" }),
              let nameIndex = nextSignificantIndex(in: tokens, after: enumIndex),
              tokens[nameIndex].text == enumName,
              let openIndex = firstSignificantToken("{", in: tokens, after: nameIndex),
              let closeIndex = matchingDelimiterIndex(in: tokens, openIndex: openIndex, open: "{", close: "}") else {
            return []
        }

        var names: [String] = []
        var cursor = openIndex + 1
        while cursor < closeIndex {
            if tokens[cursor].kind == .word,
               tokens[cursor].text == "case",
               let nameIndex = nextSignificantIndex(in: tokens, after: cursor),
               nameIndex < closeIndex,
               tokens[nameIndex].kind == .word {
                names.append(tokens[nameIndex].text)
            }
            cursor += 1
        }
        return names
    }

    private func firstSignificantToken(_ text: String, in tokens: [Token], after index: Int) -> Int? {
        var cursor = nextSignificantIndex(in: tokens, after: index)
        while let current = cursor {
            if tokens[current].text == text {
                return current
            }
            cursor = nextSignificantIndex(in: tokens, after: current)
        }
        return nil
    }

    private func opaqueCaseMapping(for caseNames: [String], seed: String) -> [String: String] {
        var used = Set<String>()
        var mapping: [String: String] = [:]

        for name in caseNames {
            var newName = hexName(prefix: "c_", key: "\(seed)|asset-case|\(name)")
            var counter = 2
            while used.contains(newName) {
                newName = hexName(prefix: "c_", key: "\(seed)|asset-case|\(name)|\(counter)")
                counter += 1
            }
            used.insert(newName)
            mapping[name] = newName
        }

        return mapping
    }

    private func rewriteAssetCaseReferences(
        in source: String,
        mapping: [String: String],
        receiverName: String,
        methodNames: Set<String>,
        rewriteDeclarations: Bool
    ) -> String {
        let tokens = tokenize(source)
        let assetReferenceRanges = rewriteDeclarations ? [] : protectedAssetCallArgumentRanges(
            in: tokens,
            receiverName: receiverName,
            methodNames: methodNames
        )
        let replacements = tokens.indices.compactMap { index -> Replacement? in
            let token = tokens[index]
            guard token.kind == .word, let newName = mapping[token.text] else { return nil }

            let previous = significantText(tokens, previousSignificantIndex(in: tokens, before: index))
            if rewriteDeclarations && (previous == "." || previous == "case") {
                return Replacement(range: token.range, value: newName)
            }

            if previous == ".", assetReferenceRanges.contains(where: { $0.contains(index) }) {
                return Replacement(range: token.range, value: newName)
            }

            return nil
        }

        return applyReplacements(replacements, to: source)
    }

    private func protectedAssetCallArgumentRanges(
        in tokens: [Token],
        receiverName: String,
        methodNames: Set<String>
    ) -> [Range<Int>] {
        tokens.indices.compactMap { index -> Range<Int>? in
            guard tokens[index].text == "(",
                  isProtectedAssetCallOpenParen(
                    tokens: tokens,
                    openIndex: index,
                    receiverName: receiverName,
                    methodNames: methodNames
                  ),
                  let closeIndex = matchingDelimiterIndex(in: tokens, openIndex: index, open: "(", close: ")"),
                  index + 1 < closeIndex else {
                return nil
            }
            return (index + 1)..<closeIndex
        }
    }

    private func isProtectedAssetCallOpenParen(
        tokens: [Token],
        openIndex: Int,
        receiverName: String,
        methodNames: Set<String>
    ) -> Bool {
        guard let methodIndex = previousSignificantIndex(in: tokens, before: openIndex),
              tokens[methodIndex].kind == .word,
              methodNames.contains(tokens[methodIndex].text),
              let dotIndex = previousSignificantIndex(in: tokens, before: methodIndex),
              tokens[dotIndex].text == ".",
              let receiverIndex = previousSignificantIndex(in: tokens, before: dotIndex),
              tokens[receiverIndex].kind == .word,
              tokens[receiverIndex].text == receiverName else {
            return false
        }
        return true
    }
}
