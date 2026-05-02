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
    var renameDirectories = false
    var renamePrivateFunctions = false
    var renameTypes = false
    var renameEnumCases = false
    var obfuscateAssetCases = false
    var assetCaseEnumPath: String?
    var assetCaseEnumName: String?
    var assetCaseReceiverName: String?
    var assetCaseMethods: [String] = []
    var renameCIMetalFiles = false
    var mergeCIMetalFiles = false
    var securityStrings: [String] = []
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
            renameDirectories: renameDirectories,
            renamePrivateFunctions: renamePrivateFunctions,
            renameTypes: renameTypes,
            renameEnumCases: renameEnumCases,
            obfuscateAssetCases: obfuscateAssetCases,
            assetCaseEnumPath: assetCaseEnumPath,
            assetCaseEnumName: assetCaseEnumName,
            assetCaseReceiverName: assetCaseReceiverName,
            assetCaseMethods: assetCaseMethods,
            renameCIMetalFiles: renameCIMetalFiles,
            mergeCIMetalFiles: mergeCIMetalFiles,
            securityStrings: securityStrings,
            useDefaultExcludes: useDefaultExcludes,
            excludePatterns: excludePatterns
        )
    }
}
