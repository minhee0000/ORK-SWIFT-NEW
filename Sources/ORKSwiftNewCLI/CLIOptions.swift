import Foundation
import ORKSwiftNewCore

let version = "0.2.0"

struct CLIOptions {
    var inputPath: String?
    var outputPath: String?
    var manifestPath: String?
    var seed = "ORK-SWIFT-NEW"
    var inPlace = false
    var dryRun = false
    var renameFiles = false
    var renamePrivateFunctions = false
    var renameTypes = false
    var useDefaultExcludes = true
    var excludePatterns: [String] = []
    var verbose = false
    var quiet = false

    func makeCoreOptions() -> ObfuscationOptions {
        ObfuscationOptions(
            inputPath: inputPath ?? "",
            outputPath: outputPath,
            manifestPath: manifestPath,
            seed: seed,
            inPlace: inPlace,
            dryRun: dryRun,
            renameFiles: renameFiles,
            renamePrivateFunctions: renamePrivateFunctions,
            renameTypes: renameTypes,
            useDefaultExcludes: useDefaultExcludes,
            excludePatterns: excludePatterns
        )
    }
}
