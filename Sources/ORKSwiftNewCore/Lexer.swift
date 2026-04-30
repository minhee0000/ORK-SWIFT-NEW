import Foundation

enum TokenKind {
    case word
    case symbol
    case trivia
    case comment
    case stringLiteral
}

struct Token {
    let kind: TokenKind
    let text: String
    let range: Range<String.Index>
    let line: Int
}

struct Replacement {
    let range: Range<String.Index>
    let value: String
}

func asciiValue(_ character: Character) -> UInt32? {
    guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
        return nil
    }
    return scalar.value
}

func isIdentifierHead(_ character: Character) -> Bool {
    guard let value = asciiValue(character) else { return false }
    return value == 95 || (65...90).contains(value) || (97...122).contains(value)
}

func isIdentifierBody(_ character: Character) -> Bool {
    guard let value = asciiValue(character) else { return false }
    return isIdentifierHead(character) || (48...57).contains(value)
}

func isWhitespaceButNotNewline(_ character: Character) -> Bool {
    character == " " || character == "\t" || character == "\r"
}

func hasPrefix(_ source: String, at index: String.Index, _ prefix: String) -> Bool {
    source[index...].hasPrefix(prefix)
}

func parseStringLiteralEnd(in source: String, from start: String.Index) -> String.Index? {
    var hashCount = 0
    var quoteIndex = start
    while quoteIndex < source.endIndex && source[quoteIndex] == "#" {
        hashCount += 1
        quoteIndex = source.index(after: quoteIndex)
    }

    guard quoteIndex < source.endIndex, source[quoteIndex] == "\"" else {
        return nil
    }

    let isMultiline = hasPrefix(source, at: quoteIndex, "\"\"\"")
    let closingQuote = isMultiline ? "\"\"\"" : "\""
    let closing = closingQuote + String(repeating: "#", count: hashCount)
    var index = source.index(quoteIndex, offsetBy: isMultiline ? 3 : 1)

    while index < source.endIndex {
        if hashCount == 0 && !isMultiline && source[index] == "\\" {
            index = source.index(after: index)
            if index < source.endIndex {
                index = source.index(after: index)
            }
            continue
        }
        if hasPrefix(source, at: index, closing) {
            return source.index(index, offsetBy: closing.count)
        }
        index = source.index(after: index)
    }

    return source.endIndex
}

func tokenize(_ source: String) -> [Token] {
    var tokens: [Token] = []
    var index = source.startIndex
    var line = 1

    func append(_ kind: TokenKind, _ start: String.Index, _ end: String.Index, _ line: Int) {
        tokens.append(Token(kind: kind, text: String(source[start..<end]), range: start..<end, line: line))
    }

    while index < source.endIndex {
        let start = index
        let tokenLine = line
        let character = source[index]

        if character == "\n" {
            index = source.index(after: index)
            line += 1
            append(.trivia, start, index, tokenLine)
            continue
        }

        if isWhitespaceButNotNewline(character) {
            index = source.index(after: index)
            while index < source.endIndex && isWhitespaceButNotNewline(source[index]) {
                index = source.index(after: index)
            }
            append(.trivia, start, index, tokenLine)
            continue
        }

        if hasPrefix(source, at: index, "//") {
            index = source.index(index, offsetBy: 2)
            while index < source.endIndex && source[index] != "\n" {
                index = source.index(after: index)
            }
            append(.comment, start, index, tokenLine)
            continue
        }

        if hasPrefix(source, at: index, "/*") {
            index = source.index(index, offsetBy: 2)
            var depth = 1
            while index < source.endIndex && depth > 0 {
                if hasPrefix(source, at: index, "/*") {
                    depth += 1
                    index = source.index(index, offsetBy: 2)
                    continue
                }
                if hasPrefix(source, at: index, "*/") {
                    depth -= 1
                    index = source.index(index, offsetBy: 2)
                    continue
                }
                if source[index] == "\n" {
                    line += 1
                }
                index = source.index(after: index)
            }
            append(.comment, start, index, tokenLine)
            continue
        }

        if character == "\"" || character == "#" {
            if let end = parseStringLiteralEnd(in: source, from: index) {
                var scan = index
                while scan < end {
                    if source[scan] == "\n" {
                        line += 1
                    }
                    scan = source.index(after: scan)
                }
                index = end
                append(.stringLiteral, start, index, tokenLine)
                continue
            }
        }

        if character == "`" {
            index = source.index(after: index)
            while index < source.endIndex && source[index] != "`" {
                if source[index] == "\n" {
                    line += 1
                }
                index = source.index(after: index)
            }
            if index < source.endIndex {
                index = source.index(after: index)
            }
            append(.word, start, index, tokenLine)
            continue
        }

        if isIdentifierHead(character) {
            index = source.index(after: index)
            while index < source.endIndex && isIdentifierBody(source[index]) {
                index = source.index(after: index)
            }
            append(.word, start, index, tokenLine)
            continue
        }

        index = source.index(after: index)
        append(.symbol, start, index, tokenLine)
    }

    return tokens
}

func applyReplacements(_ replacements: [Replacement], to source: String) -> String {
    var output = source
    for replacement in replacements.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
        output.replaceSubrange(replacement.range, with: replacement.value)
    }
    return output
}
