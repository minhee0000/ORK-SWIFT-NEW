import Foundation

struct SecurityStringObfuscator {
    private let fileManager: FileManager

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    func transform(
        in root: URL,
        seed: String,
        values: [String],
        filter: PathFilter,
        dryRun: Bool,
        manifest: inout ObfuscationManifest
    ) throws {
        let allowlist = Set(values.filter { !$0.isEmpty })
        guard !allowlist.isEmpty else { return }

        for file in swiftFiles(in: root, excluding: filter, fileManager: fileManager) {
            let relative = relativePath(from: root, to: file)
            let source = try String(contentsOf: file, encoding: .utf8)
            let result = obfuscateStrings(in: source, relativeFile: relative, seed: seed, allowlist: allowlist)

            manifest.securityStringObfuscations.append(contentsOf: result.manifestEntries)

            if result.source != source, !dryRun {
                try result.source.write(to: file, atomically: true, encoding: .utf8)
            }
        }
    }

    private func obfuscateStrings(
        in source: String,
        relativeFile: String,
        seed: String,
        allowlist: Set<String>
    ) -> (source: String, manifestEntries: [ObfuscationManifest.SecurityStringObfuscation]) {
        let tokens = tokenize(source)
        var replacements: [Replacement] = []
        var countsByDigest: [String: Int] = [:]

        for token in tokens where token.kind == .stringLiteral {
            guard let value = simpleStringLiteralContent(token.text),
                  allowlist.contains(value),
                  isSafeStringLiteralContext(tokens: tokens, token: token) else {
                continue
            }

            let expression = maskedStringExpression(value, seed: seed, line: token.line)
            replacements.append(.init(range: token.range, value: expression))
            let digest = hexName(prefix: "h_", key: "security-string|\(value)")
            countsByDigest[digest, default: 0] += 1
        }

        let entries = countsByDigest.keys.sorted().map {
            ObfuscationManifest.SecurityStringObfuscation(
                file: relativeFile,
                digest: $0,
                count: countsByDigest[$0] ?? 0
            )
        }

        return (applyReplacements(replacements, to: source), entries)
    }

    private func simpleStringLiteralContent(_ literal: String) -> String? {
        guard literal.hasPrefix("\""),
              literal.hasSuffix("\""),
              !literal.hasPrefix("\"\"\""),
              !literal.contains("\\"),
              !literal.contains("\n") else {
            return nil
        }

        return String(literal.dropFirst().dropLast())
    }

    private func isSafeStringLiteralContext(tokens: [Token], token: Token) -> Bool {
        guard let index = tokens.firstIndex(where: { $0.range == token.range }) else { return false }
        let previous = significantText(tokens, previousSignificantIndex(in: tokens, before: index))
        return previous != "@" && previous != "case"
    }

    private func maskedStringExpression(_ value: String, seed: String, line: Int) -> String {
        let bytes = Array(value.utf8)
        let spice = UInt8(truncatingIfNeeded: Int(fnv1a64("\(seed)|security-string|\(value)|\(line)") & 0xFF) + bytes.count)
        let encoded = encodeStageMasked(bytes, spice: spice)

        return "String(decoding: R0E.decode(masked: \(swiftByteArray(encoded.data)), maskA: \(swiftByteArray(encoded.maskA)), maskB: \(swiftByteArray(encoded.maskB)), spice: 0x\(String(format: "%02X", spice))), as: UTF8.self)"
    }

    private func encodeStageMasked(_ bytes: [UInt8], spice: UInt8) -> (maskA: [UInt8], maskB: [UInt8], data: [UInt8]) {
        let maskA = stableMask(label: "maskA", bytes: bytes, spice: spice, count: bytes.count)
        let maskB = stableMask(label: "maskB", bytes: bytes, spice: spice, count: bytes.count)
        var encoded: [UInt8] = []
        encoded.reserveCapacity(bytes.count)

        for (index, byte) in bytes.enumerated() {
            let a = UInt8(truncatingIfNeeded: Int(maskA[index]) + Int(spice) + index)
            let b = UInt8(truncatingIfNeeded: Int(maskB[bytes.count - 1 - index]) ^ Int(spice) ^ ((index * 17) & 0xFF))
            let stage1 = byte ^ rotateLeft(a, by: index + Int(spice))
            encoded.append(stage1 ^ rotateRight(b, by: (Int(spice) >> 3) + index))
        }

        return (maskA, maskB, encoded)
    }

    private func stableMask(label: String, bytes: [UInt8], spice: UInt8, count: Int) -> [UInt8] {
        var state = stableSeed(label: label, bytes: bytes, spice: spice)
        return (0..<count).map { _ in UInt8(truncatingIfNeeded: splitMix64(&state)) }
    }

    private func stableSeed(label: String, bytes: [UInt8], spice: UInt8) -> UInt64 {
        var hash: UInt64 = 0xCBF29CE484222325
        for byte in label.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001B3
        }
        hash = (hash ^ UInt64(spice)) &* 0x100000001B3
        for byte in bytes {
            hash = (hash ^ UInt64(byte)) &* 0x100000001B3
        }
        return hash
    }

    private func splitMix64(_ state: inout UInt64) -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }

    private func rotateLeft(_ value: UInt8, by shift: Int) -> UInt8 {
        let s = shift & 7
        return UInt8(truncatingIfNeeded: (Int(value) << s) | (Int(value) >> ((8 - s) & 7)))
    }

    private func rotateRight(_ value: UInt8, by shift: Int) -> UInt8 {
        let s = shift & 7
        return UInt8(truncatingIfNeeded: (Int(value) >> s) | (Int(value) << ((8 - s) & 7)))
    }

    private func swiftByteArray(_ bytes: [UInt8]) -> String {
        "[" + bytes.map { String(format: "0x%02X", $0) }.joined(separator: ", ") + "]"
    }
}
