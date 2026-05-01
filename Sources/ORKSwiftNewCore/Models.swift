import Foundation

public let defaultExcludePatterns = [
    ".build",
    ".git",
    "build",
    "DerivedData",
    "Pods",
    "Package.swift",
    "Package@swift-*.swift",
    "main.swift",
    "LinuxMain.swift",
    "tmp",
    "*.generated.swift"
]

let defaultCopyPrunePatterns = [
    ".build",
    ".git",
    "build",
    "DerivedData",
    "tmp"
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
    public var renameDirectories: Bool
    public var renamePrivateFunctions: Bool
    public var renameTypes: Bool
    public var renameCIMetalFiles: Bool
    public var mergeCIMetalFiles: Bool
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
        renameDirectories: Bool = false,
        renamePrivateFunctions: Bool = false,
        renameTypes: Bool = false,
        renameCIMetalFiles: Bool = false,
        mergeCIMetalFiles: Bool = false,
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
        self.renameDirectories = renameDirectories
        self.renamePrivateFunctions = renamePrivateFunctions
        self.renameTypes = renameTypes
        self.renameCIMetalFiles = renameCIMetalFiles
        self.mergeCIMetalFiles = mergeCIMetalFiles
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

    public struct DirectoryRename: Codable, Equatable {
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

    public struct TypeRename: Codable, Equatable {
        public let file: String
        public let kind: String
        public let from: String
        public let to: String

        public init(file: String, kind: String, from: String, to: String) {
            self.file = file
            self.kind = kind
            self.from = from
            self.to = to
        }
    }

    public struct SkippedType: Codable, Equatable {
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
    public var directoryRenames: [DirectoryRename]
    public var functionRenames: [FunctionRename]
    public var skippedFunctions: [SkippedFunction]
    public var typeRenames: [TypeRename]
    public var skippedTypes: [SkippedType]
    public var ciMetalFileRenames: [FileRename]
    public var ciMetalFunctionRenames: [FunctionRename]
    public var ciMetalMergedFile: String?

    public init(
        generatedAt: String,
        seed: String,
        input: String,
        output: String,
        excludedPatterns: [String],
        fileRenames: [FileRename] = [],
        directoryRenames: [DirectoryRename] = [],
        functionRenames: [FunctionRename] = [],
        skippedFunctions: [SkippedFunction] = [],
        typeRenames: [TypeRename] = [],
        skippedTypes: [SkippedType] = [],
        ciMetalFileRenames: [FileRename] = [],
        ciMetalFunctionRenames: [FunctionRename] = [],
        ciMetalMergedFile: String? = nil
    ) {
        self.generatedAt = generatedAt
        self.seed = seed
        self.input = input
        self.output = output
        self.excludedPatterns = excludedPatterns
        self.fileRenames = fileRenames
        self.directoryRenames = directoryRenames
        self.functionRenames = functionRenames
        self.skippedFunctions = skippedFunctions
        self.typeRenames = typeRenames
        self.skippedTypes = skippedTypes
        self.ciMetalFileRenames = ciMetalFileRenames
        self.ciMetalFunctionRenames = ciMetalFunctionRenames
        self.ciMetalMergedFile = ciMetalMergedFile
    }
}

public struct ObfuscationSummary: Equatable {
    public let swiftFiles: Int
    public let fileRenames: Int
    public let directoryRenames: Int
    public let functionRenames: Int
    public let skippedFunctions: Int
    public let typeRenames: Int
    public let skippedTypes: Int
    public let ciMetalFileRenames: Int
    public let ciMetalFunctionRenames: Int
    public let ciMetalMergedFiles: Int
    public let output: String
    public let excludedPatterns: [String]

    public init(
        swiftFiles: Int,
        fileRenames: Int,
        directoryRenames: Int,
        functionRenames: Int,
        skippedFunctions: Int,
        typeRenames: Int,
        skippedTypes: Int,
        ciMetalFileRenames: Int,
        ciMetalFunctionRenames: Int,
        ciMetalMergedFiles: Int,
        output: String,
        excludedPatterns: [String]
    ) {
        self.swiftFiles = swiftFiles
        self.fileRenames = fileRenames
        self.directoryRenames = directoryRenames
        self.functionRenames = functionRenames
        self.skippedFunctions = skippedFunctions
        self.typeRenames = typeRenames
        self.skippedTypes = skippedTypes
        self.ciMetalFileRenames = ciMetalFileRenames
        self.ciMetalFunctionRenames = ciMetalFunctionRenames
        self.ciMetalMergedFiles = ciMetalMergedFiles
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
