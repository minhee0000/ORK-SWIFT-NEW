import Foundation

public struct ORKSwiftNew {
    private let fileManager: FileManager
    private let dateProvider: () -> Date
    private let manifestWriter: ManifestWriter

    public init(
        fileManager: FileManager = .default,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.dateProvider = dateProvider
        self.manifestWriter = ManifestWriter(fileManager: fileManager)
    }

    public func run(_ options: ObfuscationOptions) throws -> ObfuscationResult {
        try validate(options)

        let excludePatterns = (options.useDefaultExcludes ? defaultExcludePatterns : []) + options.excludePatterns
        let pathFilter = PathFilter(patterns: excludePatterns)
        let input = makeURL(options.inputPath)

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: input.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ORKSwiftNewError.invalidInput("Input directory does not exist: \(input.path)")
        }

        let workingRoot: URL
        if options.dryRun || options.inPlace {
            workingRoot = input
        } else {
            guard let outputPath = options.outputPath else {
                throw ORKSwiftNewError.invalidConfiguration("Use --output, --in-place, or --dry-run")
            }
            let output = makeURL(outputPath)
            try copySourceTree(
                from: input,
                to: output,
                pruning: options.useDefaultExcludes ? defaultCopyPrunePatterns : [],
                fileManager: fileManager
            )
            workingRoot = output
        }

        let outputDescription = options.dryRun ? "(dry-run) \(workingRoot.path)" : workingRoot.path
        var manifest = ObfuscationManifest(
            generatedAt: ISO8601DateFormatter().string(from: dateProvider()),
            seed: options.seed,
            input: input.path,
            output: outputDescription,
            excludedPatterns: excludePatterns
        )

        if options.renameTypes {
            try SourceTypeTransformer(fileManager: fileManager).transform(
                in: workingRoot,
                seed: options.seed,
                filter: pathFilter,
                dryRun: options.dryRun,
                manifest: &manifest
            )
        }

        if options.renamePrivateFunctions {
            try SourceFunctionTransformer(fileManager: fileManager).transform(
                in: workingRoot,
                seed: options.seed,
                filter: pathFilter,
                dryRun: options.dryRun,
                manifest: &manifest
            )
        }

        if options.renameFiles {
            try SwiftFileRenamer(fileManager: fileManager).rename(
                in: workingRoot,
                seed: options.seed,
                filter: pathFilter,
                dryRun: options.dryRun,
                manifest: &manifest
            )
        }

        if options.renameCIMetalFiles || options.mergeCIMetalFiles {
            try CIMetalFileRenamer(fileManager: fileManager).rename(
                in: workingRoot,
                seed: options.seed,
                filter: pathFilter,
                dryRun: options.dryRun,
                mergeIntoSingle: options.mergeCIMetalFiles,
                manifest: &manifest
            )
        }

        if options.renameDirectories {
            try SwiftDirectoryRenamer(fileManager: fileManager).rename(
                in: workingRoot,
                seed: options.seed,
                filter: pathFilter,
                dryRun: options.dryRun,
                manifest: &manifest
            )
        }

        try manifestWriter.write(manifest, to: options.manifestPath)

        let summary = ObfuscationSummary(
            swiftFiles: swiftFiles(in: workingRoot, excluding: pathFilter, fileManager: fileManager).count,
            fileRenames: manifest.fileRenames.count,
            directoryRenames: manifest.directoryRenames.count,
            functionRenames: manifest.functionRenames.count,
            skippedFunctions: manifest.skippedFunctions.count,
            typeRenames: manifest.typeRenames.count,
            skippedTypes: manifest.skippedTypes.count,
            ciMetalFileRenames: manifest.ciMetalFileRenames.count,
            ciMetalFunctionRenames: manifest.ciMetalFunctionRenames.count,
            ciMetalMergedFiles: manifest.ciMetalMergedFile == nil ? 0 : 1,
            output: outputDescription,
            excludedPatterns: excludePatterns
        )

        return ObfuscationResult(manifest: manifest, summary: summary)
    }

    private func validate(_ options: ObfuscationOptions) throws {
        guard options.renameFiles || options.renameDirectories || options.renamePrivateFunctions || options.renameTypes || options.renameCIMetalFiles || options.mergeCIMetalFiles else {
            throw ORKSwiftNewError.invalidConfiguration(
                "Select at least one transform: --rename-files, --rename-directories, --rename-private-functions, --rename-types, --rename-ci-metal-files, or --merge-ci-metal-files"
            )
        }

        if options.inPlace, options.outputPath != nil {
            throw ORKSwiftNewError.invalidConfiguration("Use either --output or --in-place, not both")
        }

        if options.dryRun, options.outputPath != nil || options.inPlace {
            throw ORKSwiftNewError.invalidConfiguration("--dry-run does not write output; omit --output and --in-place")
        }

        if !options.dryRun, !options.inPlace, options.outputPath == nil {
            throw ORKSwiftNewError.invalidConfiguration("Use --output, --in-place, or --dry-run")
        }
    }
}
