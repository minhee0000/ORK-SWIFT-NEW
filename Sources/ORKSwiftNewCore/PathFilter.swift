import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct PathFilter {
    public let patterns: [String]

    public init(patterns: [String]) {
        self.patterns = patterns
    }

    public func isExcluded(relativePath: String) -> Bool {
        let path = normalize(relativePath)
        guard !path.isEmpty else { return false }
        let components = path.split(separator: "/").map(String.init)

        for pattern in patterns {
            let normalizedPattern = normalize(pattern)
            guard !normalizedPattern.isEmpty else { continue }

            if containsGlob(normalizedPattern) {
                if fnmatch(normalizedPattern, path, 0) == 0 {
                    return true
                }
                if let last = components.last, fnmatch(normalizedPattern, last, 0) == 0 {
                    return true
                }
                continue
            }

            if path == normalizedPattern || path.hasPrefix(normalizedPattern + "/") {
                return true
            }

            if !normalizedPattern.contains("/") && components.contains(normalizedPattern) {
                return true
            }
        }

        return false
    }

    private func normalize(_ value: String) -> String {
        var result = value.replacingOccurrences(of: "\\", with: "/")
        while result.hasPrefix("./") {
            result.removeFirst(2)
        }
        while result.hasPrefix("/") {
            result.removeFirst()
        }
        while result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }

    private func containsGlob(_ value: String) -> Bool {
        value.contains("*") || value.contains("?") || value.contains("[")
    }
}
