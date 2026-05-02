import Foundation

struct EnumCaseSourceFile {
    let url: URL
    let relativePath: String
    let source: String
    let tokens: [Token]
}

struct EnumCaseCandidate {
    let file: String
    let enumName: String
    let caseName: String
    let declarationTokenIndex: Int
}

struct EnumCaseReferenceContext {
    let range: Range<Int>
    let enumName: String
}

struct SourceEnumCaseTransformer {
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
            return EnumCaseSourceFile(
                url: file,
                relativePath: relativePath(from: root, to: file),
                source: source,
                tokens: tokenize(source)
            )
        }

        let transformed = transformEnumCases(
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

func transformEnumCases(
    files: [EnumCaseSourceFile],
    seed: String,
    manifest: inout ObfuscationManifest
) -> [TransformedTypeSourceFile] {
    var candidates: [EnumCaseCandidate] = []
    var skipped: [ObfuscationManifest.SkippedEnumCase] = []

    for file in files {
        let result = findEnumCaseCandidates(in: file.tokens, relativeFile: file.relativePath)
        candidates.append(contentsOf: result.candidates)
        skipped.append(contentsOf: result.skipped)
    }

    let groupedByCaseName = Dictionary(grouping: candidates, by: \.caseName)
    let reservedCaseNames = Set(skipped.map(\.name))
    var eligible: [EnumCaseCandidate] = []

    for name in groupedByCaseName.keys.sorted() {
        guard let group = groupedByCaseName[name] else { continue }
        if reservedCaseNames.contains(name) {
            skipped.append(contentsOf: group.map {
                .init(
                    file: $0.file,
                    enumName: $0.enumName,
                    name: $0.caseName,
                    reason: "same case name is present in a skipped enum"
                )
            })
        } else if group.count == 1, let candidate = group.first {
            eligible.append(candidate)
        } else {
            skipped.append(contentsOf: group.map {
                .init(
                    file: $0.file,
                    enumName: $0.enumName,
                    name: $0.caseName,
                    reason: "same case name is declared in multiple selected enums"
                )
            })
        }
    }

    var existingWords = Set(files.flatMap { file in
        file.tokens.filter { $0.kind == .word }.map(\.text)
    })
    let preliminaryEligible = eligible
    let enumNames = Set(preliminaryEligible.map(\.enumName))
    let globalValueTypes = projectEnumValueTypes(files: files, enumNames: enumNames)
    let contextsByFile = Dictionary(uniqueKeysWithValues: files.map {
        ($0.relativePath, enumCaseReferenceContexts(
            in: $0.tokens,
            enumNames: enumNames,
            globalValueTypes: globalValueTypes
        ))
    })
    let unsafeKeys = unsafeEnumCaseKeys(
        files: files,
        candidates: preliminaryEligible,
        contextsByFile: contextsByFile
    )
    eligible.removeAll { candidate in
        let key = enumCaseKey(enumName: candidate.enumName, caseName: candidate.caseName)
        if unsafeKeys.contains(key) {
            skipped.append(.init(
                file: candidate.file,
                enumName: candidate.enumName,
                name: candidate.caseName,
                reason: "case has unqualified references without a provable enum type context"
            ))
            return true
        }
        return false
    }

    var mappingByEnum: [String: [String: String]] = [:]
    var declarationIndicesByFile: [String: [Int: String]] = [:]

    for candidate in eligible.sorted(by: { lhs, rhs in
        if lhs.file != rhs.file { return lhs.file < rhs.file }
        if lhs.enumName != rhs.enumName { return lhs.enumName < rhs.enumName }
        return lhs.caseName < rhs.caseName
    }) {
        var newName = hexName(prefix: "e_", key: "\(seed)|enum-case|\(candidate.enumName)|\(candidate.caseName)")
        var counter = 1
        while existingWords.contains(newName) {
            newName = hexName(prefix: "e_", key: "\(seed)|enum-case|\(candidate.enumName)|\(candidate.caseName)|\(counter)")
            counter += 1
        }
        existingWords.insert(newName)

        mappingByEnum[candidate.enumName, default: [:]][candidate.caseName] = newName
        declarationIndicesByFile[candidate.file, default: [:]][candidate.declarationTokenIndex] = newName
        manifest.enumCaseRenames.append(.init(
            file: candidate.file,
            enumName: candidate.enumName,
            from: candidate.caseName,
            to: newName
        ))
    }

    manifest.skippedEnumCases.append(contentsOf: skipped)

    return files.map { file in
        var replacements: [Replacement] = []

        for (index, newName) in declarationIndicesByFile[file.relativePath] ?? [:] {
            replacements.append(.init(range: file.tokens[index].range, value: newName))
        }

        replacements.append(contentsOf: enumCaseReferenceReplacements(
            in: file.tokens,
            mappingByEnum: mappingByEnum,
            contexts: contextsByFile[file.relativePath] ?? []
        ))

        return TransformedTypeSourceFile(
            url: file.url,
            originalSource: file.source,
            source: applyReplacements(replacements, to: file.source)
        )
    }
}

func findEnumCaseCandidates(
    in tokens: [Token],
    relativeFile: String
) -> (candidates: [EnumCaseCandidate], skipped: [ObfuscationManifest.SkippedEnumCase]) {
    var candidates: [EnumCaseCandidate] = []
    var skipped: [ObfuscationManifest.SkippedEnumCase] = []

    for enumIndex in tokens.indices where tokens[enumIndex].kind == .word && tokens[enumIndex].text == "enum" {
        guard let nameIndex = nextSignificantIndex(in: tokens, after: enumIndex),
              tokens[nameIndex].kind == .word,
              let openIndex = firstSignificantToken("{", in: tokens, after: nameIndex),
              let closeIndex = matchingDelimiterIndex(in: tokens, openIndex: openIndex, open: "{", close: "}") else {
            continue
        }

        let enumName = tokens[nameIndex].text
        let cases = enumCaseDeclarations(
            in: tokens,
            relativeFile: relativeFile,
            enumName: enumName,
            openIndex: openIndex,
            closeIndex: closeIndex
        )
        guard !cases.isEmpty else { continue }

        if let skipReason = enumCaseRenameSkipReason(
            tokens: tokens,
            enumIndex: enumIndex,
            nameIndex: nameIndex,
            openIndex: openIndex,
            enumName: enumName
        ) {
            skipped.append(contentsOf: cases.map {
                .init(
                    file: relativeFile,
                    enumName: enumName,
                    name: $0.caseName,
                    reason: skipReason
                )
            })
            continue
        }

        candidates.append(contentsOf: cases)
    }

    return (candidates, skipped)
}

private func enumCaseRenameSkipReason(
    tokens: [Token],
    enumIndex: Int,
    nameIndex: Int,
    openIndex: Int,
    enumName: String
) -> String? {
    if enumName.hasPrefix("`") {
        return "backticked enum names are skipped"
    }
    if enumName == "CodingKeys" {
        return "special Swift synthesized enum name"
    }
    if braceDepthBefore(tokens: tokens, index: enumIndex) != 0 {
        return "nested enum declarations are skipped"
    }

    let preamble = preambleTokens(in: tokens, before: enumIndex)
    let preambleTexts = Set(preamble.map(\.text))
    if preambleContainsAttribute(preamble, ["objc", "objcMembers", "NSManaged"]) {
        return "enum has a runtime-sensitive attribute"
    }
    if !preambleTexts.isDisjoint(with: ["open", "public"]) {
        return "enum has an exported access modifier"
    }

    let headerTexts = significantIndices(in: tokens, range: (nameIndex + 1)..<openIndex)
        .map { tokens[$0].text }
    let runtimeSensitiveConformances: Set<String> = [
        "Codable",
        "Decodable",
        "Encodable",
        "RawRepresentable"
    ]
    let rawValueTypes: Set<String> = [
        "String",
        "Character",
        "Bool",
        "Int",
        "Int8",
        "Int16",
        "Int32",
        "Int64",
        "UInt",
        "UInt8",
        "UInt16",
        "UInt32",
        "UInt64",
        "Float",
        "Double"
    ]

    if headerTexts.contains(":"),
       !Set(headerTexts).isDisjoint(with: runtimeSensitiveConformances.union(rawValueTypes)) {
        return "raw-value or Codable enums are skipped"
    }

    return nil
}

private func enumCaseDeclarations(
    in tokens: [Token],
    relativeFile: String,
    enumName: String,
    openIndex: Int,
    closeIndex: Int
) -> [EnumCaseCandidate] {
    var result: [EnumCaseCandidate] = []
    var braceDepth = 0
    var cursor = openIndex + 1

    while cursor < closeIndex {
        let token = tokens[cursor]
        if token.kind == .symbol {
            switch token.text {
            case "{":
                braceDepth += 1
            case "}":
                braceDepth = max(0, braceDepth - 1)
            default:
                break
            }
        }

        if braceDepth == 0, token.kind == .word, token.text == "case" {
            result.append(contentsOf: parseCaseDeclaration(
                in: tokens,
                relativeFile: relativeFile,
                enumName: enumName,
                caseIndex: cursor,
                closeIndex: closeIndex
            ))
        }

        cursor += 1
    }

    return result
}

private func parseCaseDeclaration(
    in tokens: [Token],
    relativeFile: String,
    enumName: String,
    caseIndex: Int,
    closeIndex: Int
) -> [EnumCaseCandidate] {
    var result: [EnumCaseCandidate] = []
    var cursor = nextSignificantIndex(in: tokens, after: caseIndex)

    while let nameIndex = cursor, nameIndex < closeIndex {
        let token = tokens[nameIndex]
        guard token.kind == .word, !token.text.hasPrefix("`") else { break }

        result.append(.init(
            file: relativeFile,
            enumName: enumName,
            caseName: token.text,
            declarationTokenIndex: nameIndex
        ))

        var next = nextSignificantIndex(in: tokens, after: nameIndex)
        if let open = next, tokens[open].text == "(" {
            guard let close = matchingDelimiterIndex(in: tokens, openIndex: open, open: "(", close: ")") else {
                break
            }
            next = nextSignificantIndex(in: tokens, after: close)
        }

        guard let separator = next,
              separator < closeIndex,
              tokens[separator].text == ",",
              tokens[separator].line == token.line else {
            break
        }
        cursor = nextSignificantIndex(in: tokens, after: separator)
    }

    return result
}

private func enumCaseReferenceReplacements(
    in tokens: [Token],
    mappingByEnum: [String: [String: String]],
    contexts: [EnumCaseReferenceContext]
) -> [Replacement] {
    tokens.indices.compactMap { index -> Replacement? in
        let token = tokens[index]
        guard token.kind == .word,
              let dotIndex = previousSignificantIndex(in: tokens, before: index),
              tokens[dotIndex].text == "." else {
            return nil
        }

        if let enumNameIndex = previousSignificantIndex(in: tokens, before: dotIndex),
           tokens[enumNameIndex].kind == .word,
           let newName = mappingByEnum[tokens[enumNameIndex].text]?[token.text] {
            return .init(range: token.range, value: newName)
        }

        if isPrefixEnumCaseDot(tokens: tokens, dotIndex: dotIndex),
           let contextEnum = enumNameForReference(index: index, contexts: contexts),
           let newName = mappingByEnum[contextEnum]?[token.text] {
            return .init(range: token.range, value: newName)
        }

        return nil
    }
}

private func isPrefixEnumCaseDot(tokens: [Token], dotIndex: Int) -> Bool {
    guard let previous = previousSignificantIndex(in: tokens, before: dotIndex) else {
        return true
    }

    let introducers: Set<String> = [
        "(",
        "[",
        "{",
        ",",
        ":",
        "=",
        "return",
        "case",
        "in",
        "if",
        "guard",
        "else"
    ]
    return introducers.contains(tokens[previous].text)
}

private func unsafeEnumCaseKeys(
    files: [EnumCaseSourceFile],
    candidates: [EnumCaseCandidate],
    contextsByFile: [String: [EnumCaseReferenceContext]]
) -> Set<String> {
    let candidateByCaseName = Dictionary(uniqueKeysWithValues: candidates.map {
        ($0.caseName, $0)
    })
    var unsafe = Set<String>()

    for file in files {
        let contexts = contextsByFile[file.relativePath] ?? []
        for index in file.tokens.indices {
            let token = file.tokens[index]
            guard token.kind == .word,
                  let candidate = candidateByCaseName[token.text],
                  let dotIndex = previousSignificantIndex(in: file.tokens, before: index),
                  file.tokens[dotIndex].text == "." else {
                continue
            }

            if let receiverIndex = previousSignificantIndex(in: file.tokens, before: dotIndex),
               file.tokens[receiverIndex].kind == .word {
                if file.tokens[receiverIndex].text == candidate.enumName {
                    continue
                }
                continue
            }

            guard isPrefixEnumCaseDot(tokens: file.tokens, dotIndex: dotIndex),
                  enumNameForReference(index: index, contexts: contexts) == candidate.enumName else {
                unsafe.insert(enumCaseKey(enumName: candidate.enumName, caseName: candidate.caseName))
                continue
            }
        }
    }

    return unsafe
}

private func enumCaseReferenceContexts(
    in tokens: [Token],
    enumNames: Set<String>,
    globalValueTypes: [String: String] = [:]
) -> [EnumCaseReferenceContext] {
    var contexts: [EnumCaseReferenceContext] = []
    var valueTypes: [String: String] = [:]
    var arrayElementTypes: [String: String] = [:]
    let enclosingTypes = enclosingTypeRanges(in: tokens, enumNames: enumNames)

    for index in tokens.indices where tokens[index].kind == .word {
        switch tokens[index].text {
        case "func", "init":
            collectFunctionParameterContexts(
                tokens: tokens,
                declarationIndex: index,
                enumNames: enumNames,
                valueTypes: &valueTypes,
                arrayElementTypes: &arrayElementTypes,
                contexts: &contexts
            )
            collectFunctionReturnContexts(
                tokens: tokens,
                declarationIndex: index,
                enumNames: enumNames,
                contexts: &contexts
            )
        case "let", "var":
            collectValueDeclarationContexts(
                tokens: tokens,
                declarationIndex: index,
                enumNames: enumNames,
                globalValueTypes: globalValueTypes,
                valueTypes: &valueTypes,
                arrayElementTypes: &arrayElementTypes,
                contexts: &contexts
            )
        default:
            break
        }
    }

    collectForLoopContexts(
        tokens: tokens,
        valueTypes: &valueTypes,
        arrayElementTypes: arrayElementTypes,
        contexts: &contexts
    )

    for index in tokens.indices where tokens[index].kind == .word && tokens[index].text == "switch" {
        guard let expressionIndex = nextSignificantIndex(in: tokens, after: index),
              let openIndex = firstSignificantToken("{", in: tokens, after: expressionIndex),
              let closeIndex = matchingDelimiterIndex(in: tokens, openIndex: openIndex, open: "{", close: "}") else {
            continue
        }

        if let enumName = enumNameForSwitchExpression(
            tokens: tokens,
            switchIndex: index,
            expressionIndex: expressionIndex,
            openIndex: openIndex,
            enclosingTypes: enclosingTypes,
            valueTypes: valueTypes,
            globalValueTypes: globalValueTypes
        ) {
            addSwitchCasePatternContexts(
                tokens: tokens,
                bodyRange: (openIndex + 1)..<closeIndex,
                enumName: enumName,
                contexts: &contexts
            )
        }
    }

    for index in tokens.indices where tokens[index].kind == .word {
        guard let elementEnum = arrayElementTypes[tokens[index].text],
              let dotIndex = nextSignificantIndex(in: tokens, after: index),
              tokens[dotIndex].text == ".",
              let appendIndex = nextSignificantIndex(in: tokens, after: dotIndex),
              tokens[appendIndex].text == "append",
              let openIndex = nextSignificantIndex(in: tokens, after: appendIndex),
              tokens[openIndex].text == "(",
              let closeIndex = matchingDelimiterIndex(in: tokens, openIndex: openIndex, open: "(", close: ")") else {
            continue
        }
        contexts.append(.init(range: (openIndex + 1)..<closeIndex, enumName: elementEnum))
    }

    return contexts
}

private func collectFunctionParameterContexts(
    tokens: [Token],
    declarationIndex: Int,
    enumNames: Set<String>,
    valueTypes: inout [String: String],
    arrayElementTypes: inout [String: String],
    contexts: inout [EnumCaseReferenceContext]
) {
    let nameIndex: Int
    if tokens[declarationIndex].text == "init" {
        nameIndex = declarationIndex
    } else {
        guard let foundNameIndex = nextSignificantIndex(in: tokens, after: declarationIndex) else { return }
        nameIndex = foundNameIndex
    }
    guard let bounds = functionParameterListBounds(in: tokens, afterNameIndex: nameIndex) else { return }

    for segment in topLevelSegments(in: tokens, from: bounds.open + 1, to: bounds.close) {
        let indices = significantIndices(in: tokens, range: segment)
        guard let colonPosition = indices.firstIndex(where: { tokens[$0].text == ":" }),
              colonPosition > 0 else {
            continue
        }

        let localNameIndex = indices[..<colonPosition].last { tokens[$0].kind == .word && tokens[$0].text != "_" }
        let parsedType = parseEnumType(in: tokens, indices: Array(indices[(colonPosition + 1)...]), enumNames: enumNames)

        if let localNameIndex, let enumName = parsedType.enumName {
            valueTypes[tokens[localNameIndex].text] = enumName
        }
        if let localNameIndex, let elementEnumName = parsedType.arrayElementEnumName {
            arrayElementTypes[tokens[localNameIndex].text] = elementEnumName
        }
        if let enumName = parsedType.enumName,
           let equalsIndex = indices.first(where: { tokens[$0].text == "=" }) {
            contexts.append(.init(range: (equalsIndex + 1)..<segment.upperBound, enumName: enumName))
        }
    }
}

private func collectFunctionReturnContexts(
    tokens: [Token],
    declarationIndex: Int,
    enumNames: Set<String>,
    contexts: inout [EnumCaseReferenceContext]
) {
    let nameIndex: Int
    if tokens[declarationIndex].text == "init" {
        return
    } else {
        guard let foundNameIndex = nextSignificantIndex(in: tokens, after: declarationIndex) else { return }
        nameIndex = foundNameIndex
    }
    guard let bounds = functionParameterListBounds(in: tokens, afterNameIndex: nameIndex) else { return }

    var cursor = nextSignificantIndex(in: tokens, after: bounds.close)
    var returnEnum: String?
    var returnArrayElementEnum: String?
    while let index = cursor {
        if tokens[index].text == "{" {
            guard let closeIndex = matchingDelimiterIndex(in: tokens, openIndex: index, open: "{", close: "}") else {
                return
            }
            addReturnContexts(
                tokens: tokens,
                bodyRange: (index + 1)..<closeIndex,
                returnEnum: returnEnum,
                returnArrayElementEnum: returnArrayElementEnum,
                contexts: &contexts
            )
            return
        }
        if tokens[index].text == "-", let next = nextSignificantIndex(in: tokens, after: index), tokens[next].text == ">" {
            var typeIndices: [Int] = []
            var scan = nextSignificantIndex(in: tokens, after: next)
            while let typeIndex = scan, tokens[typeIndex].text != "{" {
                typeIndices.append(typeIndex)
                scan = nextSignificantIndex(in: tokens, after: typeIndex)
            }
            let parsed = parseEnumType(in: tokens, indices: typeIndices, enumNames: enumNames)
            returnEnum = parsed.enumName
            returnArrayElementEnum = parsed.arrayElementEnumName
            cursor = scan
            continue
        }
        cursor = nextSignificantIndex(in: tokens, after: index)
    }
}

private func collectValueDeclarationContexts(
    tokens: [Token],
    declarationIndex: Int,
    enumNames: Set<String>,
    globalValueTypes: [String: String],
    valueTypes: inout [String: String],
    arrayElementTypes: inout [String: String],
    contexts: inout [EnumCaseReferenceContext]
) {
    guard let nameIndex = nextSignificantIndex(in: tokens, after: declarationIndex),
          tokens[nameIndex].kind == .word else {
        return
    }

    var cursor = nextSignificantIndex(in: tokens, after: nameIndex)
    guard let colonIndex = cursor, tokens[colonIndex].text == ":" else {
        guard let equalsIndex = cursor, tokens[equalsIndex].text == "=",
              let initializerIndex = nextSignificantIndex(in: tokens, after: equalsIndex),
              tokens[initializerIndex].kind == .word else {
            return
        }

        let initializerName = tokens[initializerIndex].text
        if let enumName = valueTypes[initializerName] {
            valueTypes[tokens[nameIndex].text] = enumName
        }
        if let elementEnumName = arrayElementTypes[initializerName] {
            arrayElementTypes[tokens[nameIndex].text] = elementEnumName
        }
        return
    }

    var typeIndices: [Int] = []
    cursor = nextSignificantIndex(in: tokens, after: colonIndex)
    while let index = cursor,
          tokens[index].text != "=",
          tokens[index].text != "{",
          tokens[index].text != "\n",
          tokens[index].line == tokens[nameIndex].line {
        typeIndices.append(index)
        cursor = nextSignificantIndex(in: tokens, after: index)
    }

    let parsedType = parseEnumType(in: tokens, indices: typeIndices, enumNames: enumNames)
    if let enumName = parsedType.enumName {
        valueTypes[tokens[nameIndex].text] = enumName
    }
    if let elementEnumName = parsedType.arrayElementEnumName {
        arrayElementTypes[tokens[nameIndex].text] = elementEnumName
    }

    guard let startIndex = cursor else { return }
    if tokens[startIndex].text == "=" {
        if let enumName = parsedType.enumName {
            let end = endOfLineIndex(in: tokens, after: startIndex)
            contexts.append(.init(range: (startIndex + 1)..<end, enumName: enumName))
        }
        if let elementEnumName = parsedType.arrayElementEnumName,
           let openIndex = nextSignificantIndex(in: tokens, after: startIndex),
           tokens[openIndex].text == "[",
           let closeIndex = matchingDelimiterIndex(in: tokens, openIndex: openIndex, open: "[", close: "]") {
            contexts.append(.init(range: (openIndex + 1)..<closeIndex, enumName: elementEnumName))
        }
    } else if tokens[startIndex].text == "{",
              let closeIndex = matchingDelimiterIndex(in: tokens, openIndex: startIndex, open: "{", close: "}") {
        if let enumName = parsedType.enumName {
            addReturnContexts(
                tokens: tokens,
                bodyRange: (startIndex + 1)..<closeIndex,
                returnEnum: enumName,
                returnArrayElementEnum: nil,
                contexts: &contexts
            )
            if !tokens[(startIndex + 1)..<closeIndex].contains(where: { $0.kind == .word && $0.text == "return" }) {
                contexts.append(.init(range: (startIndex + 1)..<closeIndex, enumName: enumName))
            }
        }
        if let elementEnumName = parsedType.arrayElementEnumName {
            addArrayLiteralContexts(
                tokens: tokens,
                bodyRange: (startIndex + 1)..<closeIndex,
                elementEnumName: elementEnumName,
                contexts: &contexts
            )
        }
    }
}

private func enumNameForSwitchExpression(
    tokens: [Token],
    switchIndex: Int,
    expressionIndex: Int,
    openIndex: Int,
    enclosingTypes: [(range: Range<Int>, enumName: String)],
    valueTypes: [String: String],
    globalValueTypes: [String: String]
) -> String? {
    let expression = tokens[expressionIndex].text
    if expression == "self" {
        return enclosingTypes.first(where: { $0.range.contains(switchIndex) })?.enumName
    }
    if let enumName = nearestEnumAliasType(
        tokens: tokens,
        variableName: expression,
        before: switchIndex,
        valueTypes: valueTypes,
        globalValueTypes: globalValueTypes
    ) {
        return enumName
    }
    if let enumName = valueTypes[expression] {
        return enumName
    }

    return enumNameForValueExpression(
        tokens: tokens,
        expressionRange: expressionIndex..<openIndex,
        valueTypes: valueTypes,
        globalValueTypes: globalValueTypes
    )
}

private func enumNameForValueExpression(
    tokens: [Token],
    expressionRange: Range<Int>,
    valueTypes: [String: String],
    globalValueTypes: [String: String] = [:]
) -> String? {
    let expressionIndices = significantIndices(in: tokens, range: expressionRange)
    if let firstIndex = expressionIndices.first,
       tokens[firstIndex].kind == .word,
       let enumName = valueTypes[tokens[firstIndex].text] ?? globalValueTypes[tokens[firstIndex].text] {
        return enumName
    }

    guard let dotPosition = expressionIndices.lastIndex(where: { tokens[$0].text == "." }),
          dotPosition + 1 < expressionIndices.count else {
        return nil
    }
    let memberIndex = expressionIndices[dotPosition + 1]
    guard tokens[memberIndex].kind == .word else {
        return nil
    }

    return valueTypes[tokens[memberIndex].text] ?? globalValueTypes[tokens[memberIndex].text]
}

private func nearestEnumAliasType(
    tokens: [Token],
    variableName: String,
    before index: Int,
    valueTypes: [String: String],
    globalValueTypes: [String: String]
) -> String? {
    var cursor = index - 1
    while cursor >= 0 {
        defer { cursor -= 1 }
        guard tokens[cursor].kind == .word,
              tokens[cursor].text == variableName,
              let keywordIndex = previousSignificantIndex(in: tokens, before: cursor),
              ["let", "var"].contains(tokens[keywordIndex].text),
              let equalsIndex = nextSignificantIndex(in: tokens, after: cursor),
              tokens[equalsIndex].text == "=",
              equalsIndex < index,
              let initializerIndex = nextSignificantIndex(in: tokens, after: equalsIndex) else {
            continue
        }

        return enumNameForValueExpression(
            tokens: tokens,
            expressionRange: initializerIndex..<endOfLineIndex(in: tokens, after: initializerIndex),
            valueTypes: valueTypes,
            globalValueTypes: globalValueTypes
        )
    }
    return nil
}

private func addSwitchCasePatternContexts(
    tokens: [Token],
    bodyRange: Range<Int>,
    enumName: String,
    contexts: inout [EnumCaseReferenceContext]
) {
    var cursor = bodyRange.lowerBound
    while cursor < bodyRange.upperBound {
        defer { cursor += 1 }
        guard tokens[cursor].kind == .word,
              tokens[cursor].text == "case",
              let end = switchCasePatternEnd(in: tokens, caseIndex: cursor, bodyEnd: bodyRange.upperBound),
              cursor + 1 < end else {
            continue
        }
        contexts.append(.init(range: (cursor + 1)..<end, enumName: enumName))
    }
}

private func switchCasePatternEnd(in tokens: [Token], caseIndex: Int, bodyEnd: Int) -> Int? {
    var parenDepth = 0
    var bracketDepth = 0
    var braceDepth = 0
    var cursor = caseIndex + 1

    while cursor < bodyEnd {
        let text = tokens[cursor].text
        switch text {
        case "(":
            parenDepth += 1
        case ")":
            parenDepth = max(0, parenDepth - 1)
        case "[":
            bracketDepth += 1
        case "]":
            bracketDepth = max(0, bracketDepth - 1)
        case "{":
            braceDepth += 1
        case "}":
            braceDepth = max(0, braceDepth - 1)
        case ":" where parenDepth == 0 && bracketDepth == 0 && braceDepth == 0:
            return cursor
        default:
            break
        }
        cursor += 1
    }

    return nil
}

private func collectForLoopContexts(
    tokens: [Token],
    valueTypes: inout [String: String],
    arrayElementTypes: [String: String],
    contexts: inout [EnumCaseReferenceContext]
) {
    for index in tokens.indices where tokens[index].kind == .word && tokens[index].text == "for" {
        guard let variableIndex = nextSignificantIndex(in: tokens, after: index),
              tokens[variableIndex].kind == .word,
              let inIndex = nextSignificantIndex(in: tokens, after: variableIndex),
              tokens[inIndex].text == "in",
              let collectionIndex = nextSignificantIndex(in: tokens, after: inIndex),
              tokens[collectionIndex].kind == .word,
              let elementEnumName = arrayElementTypes[tokens[collectionIndex].text] else {
            continue
        }

        valueTypes[tokens[variableIndex].text] = elementEnumName

        guard let openIndex = firstSignificantToken("{", in: tokens, after: collectionIndex),
              let closeIndex = matchingDelimiterIndex(in: tokens, openIndex: openIndex, open: "{", close: "}") else {
            continue
        }
        contexts.append(.init(range: (openIndex + 1)..<closeIndex, enumName: elementEnumName))
    }
}

private func addReturnContexts(
    tokens: [Token],
    bodyRange: Range<Int>,
    returnEnum: String?,
    returnArrayElementEnum: String?,
    contexts: inout [EnumCaseReferenceContext]
) {
    for index in bodyRange where tokens[index].kind == .word && tokens[index].text == "return" {
        if let returnEnum {
            let end = endOfLineIndex(in: tokens, after: index)
            contexts.append(.init(range: (index + 1)..<end, enumName: returnEnum))
        }
        if let returnArrayElementEnum,
           let openIndex = nextSignificantIndex(in: tokens, after: index),
           tokens[openIndex].text == "[",
           let closeIndex = matchingDelimiterIndex(in: tokens, openIndex: openIndex, open: "[", close: "]") {
            contexts.append(.init(range: (openIndex + 1)..<closeIndex, enumName: returnArrayElementEnum))
        }
    }
}

private func addArrayLiteralContexts(
    tokens: [Token],
    bodyRange: Range<Int>,
    elementEnumName: String,
    contexts: inout [EnumCaseReferenceContext]
) {
    for index in bodyRange where tokens[index].text == "[" {
        guard let closeIndex = matchingDelimiterIndex(in: tokens, openIndex: index, open: "[", close: "]"),
              bodyRange.contains(closeIndex) else {
            continue
        }
        contexts.append(.init(range: (index + 1)..<closeIndex, enumName: elementEnumName))
    }
}

private func parseEnumType(
    in tokens: [Token],
    indices: [Int],
    enumNames: Set<String>
) -> (enumName: String?, arrayElementEnumName: String?) {
    if let first = indices.first,
       tokens[first].text == "[",
       let second = indices.dropFirst().first,
       enumNames.contains(tokens[second].text) {
        return (nil, tokens[second].text)
    }

    if let firstWord = indices.first(where: { tokens[$0].kind == .word }),
       enumNames.contains(tokens[firstWord].text) {
        return (tokens[firstWord].text, nil)
    }

    return (nil, nil)
}

private func projectEnumValueTypes(files: [EnumCaseSourceFile], enumNames: Set<String>) -> [String: String] {
    var grouped: [String: Set<String>] = [:]

    for file in files {
        for index in file.tokens.indices where file.tokens[index].kind == .word && (file.tokens[index].text == "let" || file.tokens[index].text == "var") {
            guard let nameIndex = nextSignificantIndex(in: file.tokens, after: index),
                  file.tokens[nameIndex].kind == .word,
                  let colonIndex = nextSignificantIndex(in: file.tokens, after: nameIndex),
                  file.tokens[colonIndex].text == ":" else {
                continue
            }

            var typeIndices: [Int] = []
            var cursor = nextSignificantIndex(in: file.tokens, after: colonIndex)
            while let typeIndex = cursor,
                  file.tokens[typeIndex].text != "=",
                  file.tokens[typeIndex].text != "{",
                  file.tokens[typeIndex].line == file.tokens[nameIndex].line {
                typeIndices.append(typeIndex)
                cursor = nextSignificantIndex(in: file.tokens, after: typeIndex)
            }

            if let enumName = parseEnumType(in: file.tokens, indices: typeIndices, enumNames: enumNames).enumName {
                grouped[file.tokens[nameIndex].text, default: []].insert(enumName)
            }
        }
    }

    return grouped.compactMapValues { enumNames in
        enumNames.count == 1 ? enumNames.first : nil
    }
}

private func enclosingTypeRanges(in tokens: [Token], enumNames: Set<String>) -> [(range: Range<Int>, enumName: String)] {
    var result: [(Range<Int>, String)] = []
    for index in tokens.indices where tokens[index].kind == .word && (tokens[index].text == "enum" || tokens[index].text == "extension") {
        guard let nameIndex = nextSignificantIndex(in: tokens, after: index),
              tokens[nameIndex].kind == .word,
              enumNames.contains(tokens[nameIndex].text),
              let openIndex = firstSignificantToken("{", in: tokens, after: nameIndex),
              let closeIndex = matchingDelimiterIndex(in: tokens, openIndex: openIndex, open: "{", close: "}") else {
            continue
        }
        result.append(((openIndex + 1)..<closeIndex, tokens[nameIndex].text))
    }
    return result
}

private func enumNameForReference(index: Int, contexts: [EnumCaseReferenceContext]) -> String? {
    contexts.first(where: { $0.range.contains(index) })?.enumName
}

private func enumCaseKey(enumName: String, caseName: String) -> String {
    "\(enumName).\(caseName)"
}

private func endOfLineIndex(in tokens: [Token], after index: Int) -> Int {
    var cursor = index + 1
    while cursor < tokens.count, tokens[cursor].line == tokens[index].line {
        cursor += 1
    }
    return cursor
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
