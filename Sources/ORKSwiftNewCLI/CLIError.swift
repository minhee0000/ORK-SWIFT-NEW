import Foundation

enum CLIError: Error, CustomStringConvertible {
    case usage(String)
    case missingValue(String)

    var description: String {
        switch self {
        case .usage(let message), .missingValue(let message):
            return message
        }
    }
}
