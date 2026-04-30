import Foundation
import ORKSwiftNewCore

struct ConsoleReporter {
    func printResult(_ result: ObfuscationResult, options: CLIOptions) {
        if !options.quiet {
            printSummary(result, manifestPath: options.manifestPath)
        }

        if options.verbose {
            for skipped in result.manifest.skippedFunctions {
                writeLine(
                    "[ORK-SWIFT-NEW] skipped \(skipped.file):\(skipped.name) - \(skipped.reason)",
                    manifestPath: options.manifestPath
                )
            }
            for skipped in result.manifest.skippedTypes {
                writeLine(
                    "[ORK-SWIFT-NEW] skipped type \(skipped.file):\(skipped.name) - \(skipped.reason)",
                    manifestPath: options.manifestPath
                )
            }
        }
    }

    private func printSummary(_ result: ObfuscationResult, manifestPath: String?) {
        let prefix = "[ORK-SWIFT-NEW]"
        writeLine("\(prefix) swift files: \(result.summary.swiftFiles)", manifestPath: manifestPath)
        writeLine("\(prefix) file renames: \(result.summary.fileRenames)", manifestPath: manifestPath)
        writeLine("\(prefix) directory renames: \(result.summary.directoryRenames)", manifestPath: manifestPath)
        writeLine("\(prefix) type renames: \(result.summary.typeRenames)", manifestPath: manifestPath)
        writeLine("\(prefix) function renames: \(result.summary.functionRenames)", manifestPath: manifestPath)
        writeLine("\(prefix) skipped types: \(result.summary.skippedTypes)", manifestPath: manifestPath)
        writeLine("\(prefix) skipped functions: \(result.summary.skippedFunctions)", manifestPath: manifestPath)
        writeLine(
            "\(prefix) excludes: \(result.summary.excludedPatterns.isEmpty ? "(none)" : result.summary.excludedPatterns.joined(separator: ", "))",
            manifestPath: manifestPath
        )
        writeLine("\(prefix) output: \(result.summary.output)", manifestPath: manifestPath)
    }

    private func writeLine(_ line: String, manifestPath: String?) {
        if manifestPath == "-" {
            fputs(line + "\n", stderr)
        } else {
            print(line)
        }
    }
}
