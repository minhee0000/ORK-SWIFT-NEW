import Foundation

func matchingDelimiterIndex(
    in tokens: [Token],
    openIndex: Int,
    open: String,
    close: String
) -> Int? {
    var depth = 0
    var cursor = openIndex

    while cursor < tokens.count {
        let text = tokens[cursor].text
        if text == open {
            depth += 1
        } else if text == close {
            depth -= 1
            if depth == 0 {
                return cursor
            }
        }
        cursor += 1
    }

    return nil
}

func functionParameterListBounds(in tokens: [Token], afterNameIndex nameIndex: Int) -> (open: Int, close: Int)? {
    var cursor = nextSignificantIndex(in: tokens, after: nameIndex)

    while let index = cursor {
        let text = tokens[index].text
        if text == "(" {
            guard let close = matchingDelimiterIndex(in: tokens, openIndex: index, open: "(", close: ")") else {
                return nil
            }
            return (index, close)
        }
        if text == "{" || text == "=" {
            return nil
        }
        cursor = nextSignificantIndex(in: tokens, after: index)
    }

    return nil
}

func topLevelSegments(in tokens: [Token], from start: Int, to end: Int) -> [Range<Int>] {
    guard start <= end else { return [] }

    var segments: [Range<Int>] = []
    var segmentStart = start
    var parenDepth = 0
    var bracketDepth = 0
    var braceDepth = 0
    var angleDepth = 0
    var cursor = start

    while cursor < end {
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
        case "<":
            angleDepth += 1
        case ">":
            angleDepth = max(0, angleDepth - 1)
        case "," where parenDepth == 0 && bracketDepth == 0 && braceDepth == 0 && angleDepth == 0:
            segments.append(segmentStart..<cursor)
            segmentStart = cursor + 1
        default:
            break
        }
        cursor += 1
    }

    if segmentStart < end {
        segments.append(segmentStart..<end)
    }

    return segments
}

func significantIndices(in tokens: [Token], range: Range<Int>) -> [Int] {
    range.filter { tokens.indices.contains($0) && isSignificant(tokens[$0]) }
}

func declarationParameterLabels(in tokens: [Token], openIndex: Int, closeIndex: Int) -> [String] {
    let segments = topLevelSegments(in: tokens, from: openIndex + 1, to: closeIndex)
    let ignoredParameterWords: Set<String> = [
        "@",
        "autoclosure",
        "borrowing",
        "consuming",
        "escaping",
        "inout",
        "isolated",
        "nonisolated",
        "sending"
    ]

    return segments.compactMap { segment -> String? in
        let indices = significantIndices(in: tokens, range: segment)
        guard let labelIndex = indices.first(where: { !ignoredParameterWords.contains(tokens[$0].text) }) else {
            return nil
        }
        return tokens[labelIndex].text
    }
}

func callArgumentLabels(in tokens: [Token], openIndex: Int, closeIndex: Int) -> [String] {
    let segments = topLevelSegments(in: tokens, from: openIndex + 1, to: closeIndex)

    return segments.map { segment in
        let indices = significantIndices(in: tokens, range: segment)
        guard indices.count >= 2, tokens[indices[0]].kind == .word, tokens[indices[1]].text == ":" else {
            return "_"
        }
        return tokens[indices[0]].text
    }
}

func functionBodyRange(in tokens: [Token], afterParameterCloseIndex closeIndex: Int) -> Range<Int>? {
    var cursor = nextSignificantIndex(in: tokens, after: closeIndex)

    while let index = cursor {
        let text = tokens[index].text
        if text == "{" {
            guard let close = matchingDelimiterIndex(in: tokens, openIndex: index, open: "{", close: "}") else {
                return nil
            }
            return (index + 1)..<close
        }
        if text == ";" {
            return nil
        }
        cursor = nextSignificantIndex(in: tokens, after: index)
    }

    return nil
}
