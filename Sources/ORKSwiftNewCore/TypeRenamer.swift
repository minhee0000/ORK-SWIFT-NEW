import Foundation

struct TypeSourceFile {
    let url: URL
    let relativePath: String
    let source: String
    let tokens: [Token]
}

struct TransformedTypeSourceFile {
    let url: URL
    let originalSource: String
    let source: String
}

struct TypeCandidate {
    let file: String
    let kind: String
    let name: String
    let declarationTokenIndex: Int
}

func findTypeCandidates(in tokens: [Token]) -> ([TypeCandidate], [ObfuscationManifest.SkippedType]) {
    let typeKeywords: Set<String> = ["actor", "class", "enum", "struct"]
    let prohibitedAttributes: Set<String> = [
        "IBDesignable",
        "NSApplicationMain",
        "UIApplicationMain",
        "main",
        "objc",
        "objcMembers"
    ]
    let prohibitedModifiers: Set<String> = [
        "open",
        "public"
    ]

    var candidates: [TypeCandidate] = []
    var skipped: [ObfuscationManifest.SkippedType] = []

    for index in tokens.indices where tokens[index].kind == .word && typeKeywords.contains(tokens[index].text) {
        guard let nameIndex = nextSignificantIndex(in: tokens, after: index) else { continue }
        let nameToken = tokens[nameIndex]
        guard nameToken.kind == .word else { continue }

        let name = nameToken.text
        guard !name.hasPrefix("`") else {
            skipped.append(.init(file: "", name: name, reason: "backticked type names are skipped"))
            continue
        }
        guard name != "CodingKeys" else {
            skipped.append(.init(file: "", name: name, reason: "special Swift synthesized type name"))
            continue
        }
        guard isUpperCamelTypeName(name) else {
            skipped.append(.init(file: "", name: name, reason: "type name is not UpperCamelCase"))
            continue
        }
        guard braceDepthBefore(tokens: tokens, index: index) == 0 else {
            skipped.append(.init(file: "", name: name, reason: "nested type declarations are skipped"))
            continue
        }

        let preamble = preambleTokens(in: tokens, before: index)
        let preambleTexts = Set(preamble.map(\.text))

        if preambleContainsAttribute(preamble, prohibitedAttributes) {
            skipped.append(.init(file: "", name: name, reason: "type has a runtime-sensitive attribute"))
            continue
        }

        if !preambleTexts.isDisjoint(with: prohibitedModifiers) {
            skipped.append(.init(file: "", name: name, reason: "type has an exported access modifier"))
            continue
        }

        candidates.append(TypeCandidate(
            file: "",
            kind: tokens[index].text,
            name: name,
            declarationTokenIndex: nameIndex
        ))
    }

    return (candidates, skipped)
}

func typeDeclarationNameIndices(in tokens: [Token]) -> [String: Set<Int>] {
    let declarationKeywords: Set<String> = ["actor", "class", "enum", "protocol", "struct"]
    var result: [String: Set<Int>] = [:]

    for index in tokens.indices where tokens[index].kind == .word && declarationKeywords.contains(tokens[index].text) {
        guard let nameIndex = nextSignificantIndex(in: tokens, after: index) else { continue }
        let nameToken = tokens[nameIndex]
        guard nameToken.kind == .word else { continue }
        result[nameToken.text, default: []].insert(nameIndex)
    }

    return result
}

func isUpperCamelTypeName(_ name: String) -> Bool {
    guard let scalar = name.unicodeScalars.first else { return false }
    return (65...90).contains(Int(scalar.value))
}

func braceDepthBefore(tokens: [Token], index: Int) -> Int {
    var depth = 0
    for cursor in tokens.indices where cursor < index && tokens[cursor].kind == .symbol {
        if tokens[cursor].text == "{" {
            depth += 1
        } else if tokens[cursor].text == "}" {
            depth = max(0, depth - 1)
        }
    }
    return depth
}

func appearsInAnyStringLiteral(_ name: String, files: [TypeSourceFile]) -> Bool {
    files.contains { file in
        appearsInStringLiteral(name, tokens: file.tokens)
    }
}

func unsafeTypeOccurrenceReason(tokens: [Token], index: Int, declarationIndices: Set<Int>) -> String? {
    if declarationIndices.contains(index) {
        return nil
    }

    let previous = significantText(tokens, previousSignificantIndex(in: tokens, before: index))
    let next = significantText(tokens, nextSignificantIndex(in: tokens, after: index))
    let valueDeclarationKeywords: Set<String> = [
        "associatedtype",
        "case",
        "func",
        "import",
        "let",
        "typealias",
        "var"
    ]

    if let previous, valueDeclarationKeywords.contains(previous) {
        return "identifier is declared or imported as \(previous)"
    }

    if previous == "." {
        return "identifier appears in a qualified member or external type reference"
    }

    if next == ":" {
        return "identifier appears before ':' and may be a value or parameter name"
    }

    return nil
}

func transformTypes(
    files: [TypeSourceFile],
    seed: String,
    manifest: inout ObfuscationManifest
) -> [TransformedTypeSourceFile] {
    var candidates: [TypeCandidate] = []
    var skipped: [ObfuscationManifest.SkippedType] = []
    var declarationIndicesByName: [String: [(file: String, index: Int)]] = [:]

    for file in files {
        let (fileCandidates, fileSkipped) = findTypeCandidates(in: file.tokens)
        candidates.append(contentsOf: fileCandidates.map {
            TypeCandidate(
                file: file.relativePath,
                kind: $0.kind,
                name: $0.name,
                declarationTokenIndex: $0.declarationTokenIndex
            )
        })
        skipped.append(contentsOf: fileSkipped.map {
            .init(file: file.relativePath, name: $0.name, reason: $0.reason)
        })

        for (name, indices) in typeDeclarationNameIndices(in: file.tokens) {
            for index in indices {
                declarationIndicesByName[name, default: []].append((file.relativePath, index))
            }
        }
    }

    manifest.skippedTypes.append(contentsOf: skipped)

    let grouped = Dictionary(grouping: candidates, by: \.name)
    var replacementsByFile: [String: [Replacement]] = [:]
    var existingWords = Set(files.flatMap { file in
        file.tokens.filter { $0.kind == .word }.map(\.text)
    })

    for name in grouped.keys.sorted() {
        guard let nameCandidates = grouped[name] else { continue }
        let allDeclarations = declarationIndicesByName[name] ?? []

        guard allDeclarations.count == 1, nameCandidates.count == 1, let candidate = nameCandidates.first else {
            manifest.skippedTypes.append(.init(
                file: nameCandidates.first?.file ?? "",
                name: name,
                reason: "same type name is declared more than once"
            ))
            continue
        }

        if appearsInAnyStringLiteral(name, files: files) {
            manifest.skippedTypes.append(.init(
                file: candidate.file,
                name: name,
                reason: "identifier appears inside a string literal or interpolation"
            ))
            continue
        }

        let declarationIndices = Set(allDeclarations.map(\.index))
        var unsafeReason: String?
        for file in files {
            for index in file.tokens.indices where file.tokens[index].kind == .word && file.tokens[index].text == name {
                if let reason = unsafeTypeOccurrenceReason(
                    tokens: file.tokens,
                    index: index,
                    declarationIndices: file.relativePath == candidate.file ? declarationIndices : []
                ) {
                    unsafeReason = "\(file.relativePath): \(reason)"
                    break
                }
            }
            if unsafeReason != nil { break }
        }

        if let unsafeReason {
            manifest.skippedTypes.append(.init(file: candidate.file, name: name, reason: unsafeReason))
            continue
        }

        var newName = hexName(prefix: "T_", key: "\(seed)|type|\(name)")
        var counter = 1
        while existingWords.contains(newName) {
            newName = hexName(prefix: "T_", key: "\(seed)|type|\(name)|\(counter)")
            counter += 1
        }
        existingWords.insert(newName)

        for file in files {
            let replacements = file.tokens
                .filter { $0.kind == .word && $0.text == name }
                .map { Replacement(range: $0.range, value: newName) }
            if !replacements.isEmpty {
                replacementsByFile[file.relativePath, default: []].append(contentsOf: replacements)
            }
        }

        manifest.typeRenames.append(.init(
            file: candidate.file,
            kind: candidate.kind,
            from: candidate.name,
            to: newName
        ))
    }

    return files.map { file in
        TransformedTypeSourceFile(
            url: file.url,
            originalSource: file.source,
            source: applyReplacements(replacementsByFile[file.relativePath] ?? [], to: file.source)
        )
    }
}
