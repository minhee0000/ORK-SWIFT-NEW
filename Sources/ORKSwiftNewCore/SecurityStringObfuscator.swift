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
        let context = fnv1a64("\(seed)|security-string|\(value)|\(line)")
        let spice = UInt8(truncatingIfNeeded: Int(context & 0xFF) + bytes.count)
        let variant = Int((context >> 8) % 4)
        let encoded = encodeStageMasked(bytes, spice: spice, variant: variant)

        return inlineDecoderExpression(encoded: encoded, spice: spice, variant: variant)
    }

    private func encodeStageMasked(_ bytes: [UInt8], spice: UInt8, variant: Int) -> (maskA: [UInt8], maskB: [UInt8], data: [UInt8]) {
        let maskA = stableMask(label: "maskA-\(variant)", bytes: bytes, spice: spice, count: bytes.count)
        let maskB = stableMask(label: "maskB-\(variant)", bytes: bytes, spice: spice, count: bytes.count)
        var encoded: [UInt8] = []
        encoded.reserveCapacity(bytes.count)

        for (index, byte) in bytes.enumerated() {
            encoded.append(byte ^ securityMaskByte(
                variant: variant,
                index: index,
                count: bytes.count,
                spice: spice,
                maskA: maskA,
                maskB: maskB
            ))
        }

        return (maskA, maskB, encoded)
    }

    private func securityMaskByte(
        variant: Int,
        index: Int,
        count: Int,
        spice: UInt8,
        maskA: [UInt8],
        maskB: [UInt8]
    ) -> UInt8 {
        switch variant {
        case 0:
            let a = UInt8(truncatingIfNeeded: Int(maskA[index]) + Int(spice) + index)
            let b = UInt8(truncatingIfNeeded: Int(maskB[count - 1 - index]) ^ Int(spice) ^ ((index * 17) & 0xFF))
            return rotateLeft(a, by: index + Int(spice)) ^ rotateRight(b, by: (Int(spice) >> 3) + index)
        case 1:
            let ai = (index + Int(spice & 0x0F)) % count
            let bi = count - 1 - ((index * 3 + Int(spice >> 4)) % count)
            let a = UInt8(truncatingIfNeeded: Int(maskA[ai]) ^ ((index * 31 + Int(spice)) & 0xFF))
            let b = UInt8(truncatingIfNeeded: Int(maskB[bi]) + Int(spice) + (index * 13))
            let mixed = UInt8(truncatingIfNeeded: Int(rotateLeft(b, by: (index * 3) + Int(spice >> 2))) + ((index + Int(spice)) & 0xFF))
            return rotateRight(a, by: index + Int(spice & 0x1F)) ^ mixed
        case 2:
            let ai = (index * 5 + 1) % count
            let bi = (index + Int(spice)) % count
            let ci = count - 1 - index
            let a = UInt8(truncatingIfNeeded: Int(maskA[ai]) + Int(maskB[bi]) + Int(spice) + index)
            let b = UInt8(truncatingIfNeeded: Int(maskA[ci]) ^ ((index * 29 + Int(spice)) & 0xFF))
            let c = UInt8(truncatingIfNeeded: Int(maskB[ci]) + index)
            return rotateLeft(a ^ b, by: Int((spice &+ UInt8(truncatingIfNeeded: index * 7)) & 7)) ^ c
        default:
            let ai = count - 1 - index
            let bi = (index * 7 + Int(spice & 0x03)) % count
            let a = (maskB[ai] &- UInt8(truncatingIfNeeded: index)) ^ spice
            let b = maskA[bi] &+ UInt8(truncatingIfNeeded: (index * 11) ^ Int(spice))
            return rotateRight(a, by: Int(spice) + index) ^ rotateLeft(b, by: index + 3)
        }
    }

    private func inlineDecoderExpression(
        encoded: (maskA: [UInt8], maskB: [UInt8], data: [UInt8]),
        spice: UInt8,
        variant: Int
    ) -> String {
        """
        String(decoding: { () -> [UInt8] in
            let d: [UInt8] = \(swiftByteArray(encoded.data))
            let a: [UInt8] = \(swiftByteArray(encoded.maskA))
            let b: [UInt8] = \(swiftByteArray(encoded.maskB))
            let s: UInt8 = 0x\(String(format: "%02X", spice))
            let n = d.count
            var o = [UInt8](repeating: 0, count: n)
            guard n > 0 else { return o }
            for i in 0..<n {
        \(inlineDecoderLoopBody(for: variant))
            }
            return o
        }(), as: UTF8.self)
        """
    }

    private func inlineDecoderLoopBody(for variant: Int) -> String {
        switch variant {
        case 0:
            return """
                let x = UInt8(truncatingIfNeeded: Int(a[i]) + Int(s) + i)
                let y = UInt8(truncatingIfNeeded: Int(b[n - 1 - i]) ^ Int(s) ^ ((i * 17) & 0xFF))
                let lx = Int((UInt8(truncatingIfNeeded: i) &+ s) & 7)
                let ly = Int(((s >> 3) &+ UInt8(truncatingIfNeeded: i)) & 7)
                let kx = UInt8(truncatingIfNeeded: (Int(x) << lx) | (Int(x) >> ((8 - lx) & 7)))
                let ky = UInt8(truncatingIfNeeded: (Int(y) >> ly) | (Int(y) << ((8 - ly) & 7)))
                o[i] = d[i] ^ kx ^ ky
            """
        case 1:
            return """
                let ai = (i + Int(s & 0x0F)) % n
                let bi = n - 1 - ((i * 3 + Int(s >> 4)) % n)
                let x = UInt8(truncatingIfNeeded: Int(a[ai]) ^ ((i * 31 + Int(s)) & 0xFF))
                let y = UInt8(truncatingIfNeeded: Int(b[bi]) + Int(s) + (i * 13))
                let lx = Int((UInt8(truncatingIfNeeded: i) &+ (s & 0x1F)) & 7)
                let ly = Int((UInt8(truncatingIfNeeded: i * 3) &+ (s >> 2)) & 7)
                let kx = UInt8(truncatingIfNeeded: (Int(x) >> lx) | (Int(x) << ((8 - lx) & 7)))
                let ky = UInt8(truncatingIfNeeded: (Int(y) << ly) | (Int(y) >> ((8 - ly) & 7)))
                let mix = UInt8(truncatingIfNeeded: Int(ky) + ((i + Int(s)) & 0xFF))
                o[i] = d[i] ^ kx ^ mix
            """
        case 2:
            return """
                let ai = (i * 5 + 1) % n
                let bi = (i + Int(s)) % n
                let ci = n - 1 - i
                let x = UInt8(truncatingIfNeeded: Int(a[ai]) + Int(b[bi]) + Int(s) + i)
                let y = UInt8(truncatingIfNeeded: Int(a[ci]) ^ ((i * 29 + Int(s)) & 0xFF))
                let z = x ^ y
                let lz = Int((s &+ UInt8(truncatingIfNeeded: i * 7)) & 7)
                let kz = UInt8(truncatingIfNeeded: (Int(z) << lz) | (Int(z) >> ((8 - lz) & 7)))
                let mix = UInt8(truncatingIfNeeded: Int(b[ci]) + i)
                o[i] = d[i] ^ kz ^ mix
            """
        default:
            return """
                let ai = n - 1 - i
                let bi = (i * 7 + Int(s & 0x03)) % n
                let x = (b[ai] &- UInt8(truncatingIfNeeded: i)) ^ s
                let y = a[bi] &+ UInt8(truncatingIfNeeded: (i * 11) ^ Int(s))
                let lx = Int((UInt8(truncatingIfNeeded: i) &+ s) & 7)
                let ly = Int((UInt8(truncatingIfNeeded: i) &+ 3) & 7)
                let kx = UInt8(truncatingIfNeeded: (Int(x) >> lx) | (Int(x) << ((8 - lx) & 7)))
                let ky = UInt8(truncatingIfNeeded: (Int(y) << ly) | (Int(y) >> ((8 - ly) & 7)))
                o[i] = d[i] ^ kx ^ ky
            """
        }
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
