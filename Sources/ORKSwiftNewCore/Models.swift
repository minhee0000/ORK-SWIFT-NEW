import Foundation

public let defaultExcludePatterns = [
    ".build",
    ".git",
    "build",
    "DerivedData",
    "Pods",
    "tmp",
    "*.generated.swift"
]

public enum ORKSwiftNewError: Error, CustomStringConvertible {
    case invalidConfiguration(String)
    case invalidInput(String)

    public var description: String {
        switch self {
        case .invalidConfiguration(let message), .invalidInput(let message):
            return message
        }
    }
}

public struct ObfuscationOptions {
    public var inputPath: String
    public var outputPath: String?
    public var manifestPath: String?
    public var seed: String
    public var inPlace: Bool
    public var dryRun: Bool
    public var renameFiles: Bool
    public var renamePrivateFunctions: Bool
    public var useDefaultExcludes: Bool
    public var excludePatterns: [String]

    public init(
        inputPath: String,
        outputPath: String? = nil,
        manifestPath: String? = nil,
        seed: String = "ORK-SWIFT-NEW",
        inPlace: Bool = false,
        dryRun: Bool = false,
        renameFiles: Bool = false,
        renamePrivateFunctions: Bool = false,
        useDefaultExcludes: Bool = true,
        excludePatterns: [String] = []
    ) {
        self.inputPath = inputPath
        self.outputPath = outputPath
        self.manifestPath = manifestPath
        self.seed = seed
        self.inPlace = inPlace
        self.dryRun = dryRun
        self.renameFiles = renameFiles
        self.renamePrivateFunctions = renamePrivateFunctions
        self.useDefaultExcludes = useDefaultExcludes
        self.excludePatterns = excludePatterns
    }
}

public struct ObfuscationManifest: Codable, Equatable {
    public struct FileRename: Codable, Equatable {
        public let from: String
        public let to: String

        public init(from: String, to: String) {
            self.from = from
            self.to = to
        }
    }

    public struct FunctionRename: Codable, Equatable {
        public let file: String
        public let from: String
        public let to: String

        public init(file: String, from: String, to: String) {
            self.file = file
            self.from = from
            self.to = to
        }
    }

    public struct SkippedFunction: Codable, Equatable {
        public let file: String
        public let name: String
        public let reason: String

        public init(file: String, name: String, reason: String) {
            self.file = file
            self.name = name
            self.reason = reason
        }
    }

    public let generatedAt: String
    public let seed: String
    public let input: String
    public let output: String
    public let excludedPatterns: [String]
    public var fileRenames: [FileRename]
    public var functionRenames: [FunctionRename]
    public var skippedFunctions: [SkippedFunction]

    public init(
        generatedAt: String,
        seed: String,
        input: String,
        output: String,
        excludedPatterns: [String],
        fileRenames: [FileRename] = [],
        functionRenames: [FunctionRename] = [],
        skippedFunctions: [SkippedFunction] = []
    ) {
        self.generatedAt = generatedAt
        self.seed = seed
        self.input = input
        self.output = output
        self.excludedPatterns = excludedPatterns
        self.fileRenames = fileRenames
        self.functionRenames = functionRenames
        self.skippedFunctions = skippedFunctions
    }
}

public struct ObfuscationSummary: Equatable {
    public let swiftFiles: Int
    public let fileRenames: Int
    public let functionRenames: Int
    public let skippedFunctions: Int
    public let output: String
    public let excludedPatterns: [String]

    public init(
        swiftFiles: Int,
        fileRenames: Int,
        functionRenames: Int,
        skippedFunctions: Int,
        output: String,
        excludedPatterns: [String]
    ) {
        self.swiftFiles = swiftFiles
        self.fileRenames = fileRenames
        self.functionRenames = functionRenames
        self.skippedFunctions = skippedFunctions
        self.output = output
        self.excludedPatterns = excludedPatterns
    }
}

public struct ObfuscationResult: Equatable {
    public let manifest: ObfuscationManifest
    public let summary: ObfuscationSummary

    public init(manifest: ObfuscationManifest, summary: ObfuscationSummary) {
        self.manifest = manifest
        self.summary = summary
    }
}
