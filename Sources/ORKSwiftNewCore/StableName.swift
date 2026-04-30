import Foundation

func fnv1a64(_ string: String) -> UInt64 {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in string.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x100000001b3
    }
    return hash
}

func hexName(prefix: String, key: String, length: Int = 12) -> String {
    let hex = String(format: "%016llx", fnv1a64(key))
    return prefix + String(hex.prefix(length))
}
