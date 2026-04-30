import Foundation

struct FunctionCandidate {
    let name: String
    let declarationTokenIndex: Int
}

func isSignificant(_ token: Token) -> Bool {
    token.kind == .word || token.kind == .symbol
}

func nextSignificantIndex(in tokens: [Token], after index: Int) -> Int? {
    var cursor = index + 1
    while cursor < tokens.count {
        if isSignificant(tokens[cursor]) {
            return cursor
        }
        cursor += 1
    }
    return nil
}

func previousSignificantIndex(in tokens: [Token], before index: Int) -> Int? {
    var cursor = index - 1
    while cursor >= 0 {
        if isSignificant(tokens[cursor]) {
            return cursor
        }
        cursor -= 1
    }
    return nil
}

func significantText(_ tokens: [Token], _ index: Int?) -> String? {
    guard let index else { return nil }
    return tokens[index].text
}

func preambleTokens(in tokens: [Token], before funcIndex: Int) -> [Token] {
    let funcLine = tokens[funcIndex].line
    let declarationWords: Set<String> = [
        "actor",
        "class",
        "enum",
        "func",
        "init",
        "let",
        "protocol",
        "struct",
        "subscript",
        "typealias",
        "var"
    ]
    var result: [Token] = []
    var cursor = previousSignificantIndex(in: tokens, before: funcIndex)

    while let index = cursor {
        let token = tokens[index]
        guard token.line == funcLine else {
            break
        }
        if token.text == "{" || token.text == "}" || token.text == ";" {
            break
        }
        result.append(token)
        cursor = previousSignificantIndex(in: tokens, before: index)
    }

    var attributeLine = funcLine - 1
    while attributeLine > 0 {
        let lineTokens = tokens
            .filter { $0.line == attributeLine && isSignificant($0) }

        guard !lineTokens.isEmpty else {
            break
        }

        if lineTokens.first?.text == "@", lineTokens.map(\.text).allSatisfy({ !declarationWords.contains($0) }) {
            result.append(contentsOf: lineTokens.reversed())
            attributeLine -= 1
            continue
        }

        break
    }

    return result.reversed()
}

func preambleContainsAttribute(_ preamble: [Token], _ names: Set<String>) -> Bool {
    guard preamble.count > 1 else { return false }
    for index in 0..<(preamble.count - 1) where preamble[index].text == "@" {
        if names.contains(preamble[index + 1].text) {
            return true
        }
    }
    return false
}

func findFunctionCandidates(in tokens: [Token]) -> ([FunctionCandidate], [ObfuscationManifest.SkippedFunction]) {
    let prohibitedAttributes: Set<String> = [
        "objc",
        "IBAction",
        "NSManaged",
        "GKInspectable",
        "_cdecl",
        "_silgen_name",
        "_dynamicReplacement"
    ]
    let prohibitedModifiers: Set<String> = [
        "override",
        "dynamic",
        "public",
        "open"
    ]

    var candidates: [FunctionCandidate] = []
    var skipped: [ObfuscationManifest.SkippedFunction] = []

    for index in tokens.indices where tokens[index].kind == .word && tokens[index].text == "func" {
        guard let nameIndex = nextSignificantIndex(in: tokens, after: index) else { continue }
        let nameToken = tokens[nameIndex]
        guard nameToken.kind == .word else {
            continue
        }
        let name = nameToken.text
        guard !name.hasPrefix("`") else {
            skipped.append(.init(file: "", name: name, reason: "backticked function names are skipped"))
            continue
        }

        let preamble = preambleTokens(in: tokens, before: index)
        let preambleTexts = Set(preamble.map(\.text))
        guard preambleTexts.contains("private") || preambleTexts.contains("fileprivate") else {
            continue
        }

        if preambleContainsAttribute(preamble, prohibitedAttributes) {
            skipped.append(.init(file: "", name: name, reason: "function has an Objective-C/runtime-sensitive attribute"))
            continue
        }

        if !preambleTexts.isDisjoint(with: prohibitedModifiers) {
            skipped.append(.init(file: "", name: name, reason: "function has a runtime-sensitive modifier"))
            continue
        }

        if name == "init" || name == "deinit" || name == "subscript" {
            skipped.append(.init(file: "", name: name, reason: "special Swift entry point"))
            continue
        }

        candidates.append(FunctionCandidate(name: name, declarationTokenIndex: nameIndex))
    }

    return (candidates, skipped)
}

func functionDeclarationNameIndices(in tokens: [Token]) -> [String: Set<Int>] {
    var result: [String: Set<Int>] = [:]

    for index in tokens.indices where tokens[index].kind == .word && tokens[index].text == "func" {
        guard let nameIndex = nextSignificantIndex(in: tokens, after: index) else { continue }
        let nameToken = tokens[nameIndex]
        guard nameToken.kind == .word else { continue }
        result[nameToken.text, default: []].insert(nameIndex)
    }

    return result
}

func appearsInStringLiteral(_ name: String, tokens: [Token]) -> Bool {
    tokens.contains { token in
        token.kind == .stringLiteral && token.text.contains(name)
    }
}

func isSafeFunctionOccurrence(tokens: [Token], index: Int, declarationIndices: Set<Int>) -> Bool {
    if declarationIndices.contains(index) {
        return true
    }

    let next = nextSignificantIndex(in: tokens, after: index)
    guard significantText(tokens, next) == "(" else {
        return false
    }

    let previous = previousSignificantIndex(in: tokens, before: index)
    if significantText(tokens, previous) == "." {
        let receiver = previous.flatMap { previousSignificantIndex(in: tokens, before: $0) }
        let receiverText = significantText(tokens, receiver)
        return receiverText == "self" || receiverText == "Self"
    }

    return true
}

func transformFunctions(
    source: String,
    relativeFile: String,
    seed: String,
    manifest: inout ObfuscationManifest
) -> String {
    let tokens = tokenize(source)
    let (allCandidates, skippedFromDeclaration) = findFunctionCandidates(in: tokens)
    manifest.skippedFunctions.append(contentsOf: skippedFromDeclaration.map {
        .init(file: relativeFile, name: $0.name, reason: $0.reason)
    })

    let allDeclarationIndices = functionDeclarationNameIndices(in: tokens)
    let grouped = Dictionary(grouping: allCandidates, by: \.name)
    var replacements: [Replacement] = []
    var existingWords = Set(tokens.filter { $0.kind == .word }.map(\.text))

    for name in grouped.keys.sorted() {
        guard let candidates = grouped[name] else { continue }
        let declarationIndices = Set(candidates.map(\.declarationTokenIndex))

        let nonCandidateDeclarations = (allDeclarationIndices[name] ?? []).subtracting(declarationIndices)
        if !nonCandidateDeclarations.isEmpty {
            manifest.skippedFunctions.append(.init(
                file: relativeFile,
                name: name,
                reason: "same base name is also declared by a non-private or unsafe overload"
            ))
            continue
        }

        if appearsInStringLiteral(name, tokens: tokens) {
            manifest.skippedFunctions.append(.init(
                file: relativeFile,
                name: name,
                reason: "identifier appears inside a string literal or interpolation"
            ))
            continue
        }

        let occurrenceIndices = tokens.indices.filter { tokens[$0].kind == .word && tokens[$0].text == name }
        let unsafe = occurrenceIndices.first { !isSafeFunctionOccurrence(tokens: tokens, index: $0, declarationIndices: declarationIndices) }

        if let unsafe {
            let nextText = significantText(tokens, nextSignificantIndex(in: tokens, after: unsafe)) ?? "<end>"
            manifest.skippedFunctions.append(.init(
                file: relativeFile,
                name: name,
                reason: "identifier occurrence is not a normal direct call; next token: \(nextText)"
            ))
            continue
        }

        var newName = hexName(prefix: "f_", key: "\(seed)|func|\(relativeFile)|\(name)")
        var counter = 1
        while existingWords.contains(newName) {
            newName = hexName(prefix: "f_", key: "\(seed)|func|\(relativeFile)|\(name)|\(counter)")
            counter += 1
        }
        existingWords.insert(newName)

        for index in occurrenceIndices {
            replacements.append(Replacement(range: tokens[index].range, value: newName))
        }
        manifest.functionRenames.append(.init(file: relativeFile, from: name, to: newName))
    }

    return applyReplacements(replacements, to: source)
}
