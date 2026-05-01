import Foundation
import XCTest
@testable import ORKSwiftNewCore

final class ObfuscatorTests: XCTestCase {
    private var fileManager: FileManager!
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        fileManager = FileManager.default
        temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("ORKSwiftNewTests")
            .appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? fileManager.removeItem(at: temporaryRoot)
        }
        temporaryRoot = nil
        fileManager = nil
    }

    func testCopiesTreeRenamesFilesAndSafePrivateFunctions() throws {
        let input = temporaryRoot.appendingPathComponent("Input")
        let output = temporaryRoot.appendingPathComponent("Output")
        try fileManager.createDirectory(at: input, withIntermediateDirectories: true)
        let source = input.appendingPathComponent("Demo.swift")
        try """
        struct Demo {
            func run() {
                privateWork()
                self.privateWork()
                let value = "\\(stringy)"
                _ = value
            }

            private func privateWork() {
                helper()
            }

            private func helper() {}
            private func stringy() {}
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let result = try ORKSwiftNew(
            fileManager: fileManager,
            dateProvider: { Date(timeIntervalSince1970: 0) }
        ).run(.init(
            inputPath: input.path,
            outputPath: output.path,
            seed: "unit-test",
            renameFiles: true,
            renamePrivateFunctions: true,
            useDefaultExcludes: false
        ))

        XCTAssertEqual(result.manifest.fileRenames.count, 1)
        XCTAssertEqual(result.manifest.functionRenames.count, 2)
        XCTAssertTrue(result.manifest.skippedFunctions.contains { $0.name == "stringy" })

        let renamedFile = output.appendingPathComponent(result.manifest.fileRenames[0].to)
        let transformed = try String(contentsOf: renamedFile, encoding: .utf8)

        XCTAssertFalse(transformed.contains("privateWork("))
        XCTAssertFalse(transformed.contains("helper("))
        XCTAssertTrue(transformed.contains("private func stringy()"))
        XCTAssertTrue(transformed.contains("func f_"))
    }

    func testRenamesCIMetalFilesAndLoaderStringLiterals() throws {
        let input = temporaryRoot.appendingPathComponent("Input")
        let output = temporaryRoot.appendingPathComponent("Output")
        let filters = input.appendingPathComponent("Filters")
        try fileManager.createDirectory(at: filters, withIntermediateDirectories: true)

        let shader = filters.appendingPathComponent("DetailBlurShader.ci.metal")
        try "kernel void detailBlur() {}\n".write(to: shader, atomically: true, encoding: .utf8)

        let source = input.appendingPathComponent("Loader.swift")
        try """
        enum Demo {
            static func load() {
                _ = CIMetalLibraryLoader.url(named: "DetailBlurShader")
                _ = CIKernel(functionName: "detailBlur", fromMetalLibraryData: Data())
                _ = ["DetailBlurShader", "default"]
            }
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let result = try ORKSwiftNew(
            fileManager: fileManager,
            dateProvider: { Date(timeIntervalSince1970: 0) }
        ).run(.init(
            inputPath: input.path,
            outputPath: output.path,
            seed: "unit-test",
            renameCIMetalFiles: true,
            useDefaultExcludes: false
        ))

        XCTAssertEqual(result.manifest.ciMetalFileRenames.count, 1)
        XCTAssertEqual(result.manifest.ciMetalFunctionRenames.count, 1)
        let rename = try XCTUnwrap(result.manifest.ciMetalFileRenames.first)
        let functionRename = try XCTUnwrap(result.manifest.ciMetalFunctionRenames.first)
        XCTAssertEqual(rename.from, "Filters/DetailBlurShader.ci.metal")
        XCTAssertTrue(rename.to.hasPrefix("Filters/R_"))
        XCTAssertTrue(rename.to.hasSuffix(".ci.metal"))
        XCTAssertEqual(functionRename.file, "Filters/DetailBlurShader.ci.metal")
        XCTAssertEqual(functionRename.from, "detailBlur")
        XCTAssertTrue(functionRename.to.hasPrefix("r_"))
        XCTAssertFalse(fileManager.fileExists(atPath: output.appendingPathComponent("Filters/DetailBlurShader.ci.metal").path))
        XCTAssertTrue(fileManager.fileExists(atPath: output.appendingPathComponent(rename.to).path))

        let transformed = try String(contentsOf: output.appendingPathComponent("Loader.swift"), encoding: .utf8)
        let newLoaderName = URL(fileURLWithPath: rename.to).lastPathComponent
            .replacingOccurrences(of: ".ci.metal", with: "")
        XCTAssertFalse(transformed.contains("DetailBlurShader"))
        XCTAssertFalse(transformed.contains("detailBlur"))
        XCTAssertTrue(transformed.contains("\"\(newLoaderName)\""))
        XCTAssertTrue(transformed.contains("\"\(functionRename.to)\""))
        XCTAssertTrue(transformed.contains("\"default\""))

        let transformedShader = try String(contentsOf: output.appendingPathComponent(rename.to), encoding: .utf8)
        XCTAssertFalse(transformedShader.contains("detailBlur"))
        XCTAssertTrue(transformedShader.contains("kernel void \(functionRename.to)()"))
    }

    func testMergesCIMetalFilesIntoSingleGeneratedSource() throws {
        let input = temporaryRoot.appendingPathComponent("Input")
        let output = temporaryRoot.appendingPathComponent("Output")
        let filters = input.appendingPathComponent("Filters")
        try fileManager.createDirectory(at: filters, withIntermediateDirectories: true)

        try """
        extern "C" {
            float4 detailBlur(sampler input) { return sample(input, input.coord()); }
        }
        """.write(to: filters.appendingPathComponent("DetailBlurShader.ci.metal"), atomically: true, encoding: .utf8)
        try """
        extern "C" {
            float4 darkCornerBlend(sampler input) { return sample(input, input.coord()); }
        }
        """.write(to: filters.appendingPathComponent("DarkCornerBlendShader.ci.metal"), atomically: true, encoding: .utf8)

        try """
        enum Demo {
            static func load() {
                _ = CIMetalLibraryLoader.url(named: "DetailBlurShader")
                _ = CIMetalLibraryLoader.url(named: "DarkCornerBlendShader")
                _ = CIKernel(functionName: "detailBlur", fromMetalLibraryData: Data())
                _ = CIKernel(functionName: "darkCornerBlend", fromMetalLibraryData: Data())
            }
        }
        """.write(to: input.appendingPathComponent("Loader.swift"), atomically: true, encoding: .utf8)

        let result = try ORKSwiftNew(
            fileManager: fileManager,
            dateProvider: { Date(timeIntervalSince1970: 0) }
        ).run(.init(
            inputPath: input.path,
            outputPath: output.path,
            seed: "unit-test",
            renameCIMetalFiles: true,
            mergeCIMetalFiles: true,
            useDefaultExcludes: false
        ))

        XCTAssertEqual(result.manifest.ciMetalFileRenames.count, 2)
        XCTAssertEqual(result.manifest.ciMetalFunctionRenames.count, 2)
        let mergedRelative = try XCTUnwrap(result.manifest.ciMetalMergedFile)
        XCTAssertTrue(mergedRelative.hasPrefix("R_"))
        XCTAssertTrue(mergedRelative.hasSuffix(".ci.metal"))

        let ciMetalFiles = try fileManager.contentsOfDirectory(
            at: output,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasSuffix(".ci.metal") }
        XCTAssertEqual(ciMetalFiles.map(\.lastPathComponent), [URL(fileURLWithPath: mergedRelative).lastPathComponent])

        let mergedName = URL(fileURLWithPath: mergedRelative).lastPathComponent
            .replacingOccurrences(of: ".ci.metal", with: "")
        let transformed = try String(contentsOf: output.appendingPathComponent("Loader.swift"), encoding: .utf8)
        XCTAssertFalse(transformed.contains("DetailBlurShader"))
        XCTAssertFalse(transformed.contains("DarkCornerBlendShader"))
        XCTAssertFalse(transformed.contains("detailBlur"))
        XCTAssertFalse(transformed.contains("darkCornerBlend"))
        XCTAssertEqual(transformed.components(separatedBy: "\"\(mergedName)\"").count - 1, 2)
        XCTAssertEqual(result.summary.ciMetalMergedFiles, 1)
    }

    func testExcludedDirectoriesAreCopiedButNotTransformed() throws {
        let input = temporaryRoot.appendingPathComponent("Input")
        let output = temporaryRoot.appendingPathComponent("Output")
        let generatedDirectory = input.appendingPathComponent("Generated")
        try fileManager.createDirectory(at: generatedDirectory, withIntermediateDirectories: true)
        try "private func generatedName() {}\n".write(
            to: generatedDirectory.appendingPathComponent("Auto.swift"),
            atomically: true,
            encoding: .utf8
        )

        let result = try ORKSwiftNew(fileManager: fileManager).run(.init(
            inputPath: input.path,
            outputPath: output.path,
            seed: "unit-test",
            renameFiles: true,
            renamePrivateFunctions: true,
            useDefaultExcludes: false,
            excludePatterns: ["Generated"]
        ))

        XCTAssertEqual(result.manifest.fileRenames.count, 0)
        XCTAssertEqual(result.manifest.functionRenames.count, 0)
        XCTAssertTrue(fileManager.fileExists(atPath: output.appendingPathComponent("Generated/Auto.swift").path))
    }

    func testOutputCopyPrunesDefaultBuildArtifacts() throws {
        let input = temporaryRoot.appendingPathComponent("Input")
        let output = temporaryRoot.appendingPathComponent("Output")
        try fileManager.createDirectory(at: input.appendingPathComponent(".build"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: input.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: input.appendingPathComponent("build"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: input.appendingPathComponent("DerivedData"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: input.appendingPathComponent("tmp"), withIntermediateDirectories: true)
        try "private func normalWork() {}\n".write(
            to: input.appendingPathComponent("Normal.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "private func cachedWork() {}\n".write(
            to: input.appendingPathComponent(".build/Cache.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "config\n".write(
            to: input.appendingPathComponent(".git/config"),
            atomically: true,
            encoding: .utf8
        )

        let result = try ORKSwiftNew(fileManager: fileManager).run(.init(
            inputPath: input.path,
            outputPath: output.path,
            seed: "unit-test",
            renameFiles: true,
            renamePrivateFunctions: true
        ))

        XCTAssertFalse(fileManager.fileExists(atPath: output.appendingPathComponent(".build").path))
        XCTAssertFalse(fileManager.fileExists(atPath: output.appendingPathComponent(".git").path))
        XCTAssertFalse(fileManager.fileExists(atPath: output.appendingPathComponent("build").path))
        XCTAssertFalse(fileManager.fileExists(atPath: output.appendingPathComponent("DerivedData").path))
        XCTAssertFalse(fileManager.fileExists(atPath: output.appendingPathComponent("tmp").path))
        XCTAssertEqual(result.manifest.fileRenames.count, 1)
        XCTAssertEqual(result.manifest.functionRenames.count, 1)
    }

    func testFileRenameManifestKeepsRelativeDirectoriesUnderTmpRoot() throws {
        let root = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("ORKSwiftNewTests")
            .appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: root) }

        let input = root.appendingPathComponent("Input")
        let output = root.appendingPathComponent("Output")
        let sources = input.appendingPathComponent("Sources/App")
        try fileManager.createDirectory(at: sources, withIntermediateDirectories: true)
        try "struct Demo {}\n".write(
            to: sources.appendingPathComponent("Demo.swift"),
            atomically: true,
            encoding: .utf8
        )

        let result = try ORKSwiftNew(fileManager: fileManager).run(.init(
            inputPath: input.path,
            outputPath: output.path,
            seed: "unit-test",
            renameFiles: true,
            useDefaultExcludes: false
        ))

        XCTAssertEqual(result.manifest.fileRenames.first?.from, "Sources/App/Demo.swift")
        XCTAssertTrue(result.manifest.fileRenames.first?.to.hasPrefix("Sources/App/S_") == true)
    }

    func testDefaultExcludesPreservePackageManifest() throws {
        let input = temporaryRoot.appendingPathComponent("Input")
        let output = temporaryRoot.appendingPathComponent("Output")
        let sources = input.appendingPathComponent("Sources/Library")
        try fileManager.createDirectory(at: sources, withIntermediateDirectories: true)
        try "// swift-tools-version: 5.9\n".write(
            to: input.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "private func internalWork() {}\n".write(
            to: sources.appendingPathComponent("Library.swift"),
            atomically: true,
            encoding: .utf8
        )

        let result = try ORKSwiftNew(fileManager: fileManager).run(.init(
            inputPath: input.path,
            outputPath: output.path,
            seed: "unit-test",
            renameFiles: true,
            renamePrivateFunctions: true
        ))

        XCTAssertTrue(fileManager.fileExists(atPath: output.appendingPathComponent("Package.swift").path))
        XCTAssertEqual(result.manifest.fileRenames.count, 1)
        XCTAssertFalse(result.manifest.fileRenames.contains { $0.from == "Package.swift" })
    }

    func testDefaultExcludesPreserveSwiftPMEntrypoints() throws {
        let input = temporaryRoot.appendingPathComponent("Input")
        let output = temporaryRoot.appendingPathComponent("Output")
        let executable = input.appendingPathComponent("Sources/Tool")
        try fileManager.createDirectory(at: executable, withIntermediateDirectories: true)
        try "print(\"hello\")\n".write(
            to: executable.appendingPathComponent("main.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "private func helper() {}\n".write(
            to: executable.appendingPathComponent("Helper.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "// XCTest entrypoint\n".write(
            to: input.appendingPathComponent("LinuxMain.swift"),
            atomically: true,
            encoding: .utf8
        )

        let result = try ORKSwiftNew(fileManager: fileManager).run(.init(
            inputPath: input.path,
            outputPath: output.path,
            seed: "unit-test",
            renameFiles: true,
            renamePrivateFunctions: true
        ))

        XCTAssertTrue(fileManager.fileExists(atPath: output.appendingPathComponent("Sources/Tool/main.swift").path))
        XCTAssertTrue(fileManager.fileExists(atPath: output.appendingPathComponent("LinuxMain.swift").path))
        XCTAssertEqual(result.manifest.fileRenames.count, 1)
        XCTAssertFalse(result.manifest.fileRenames.contains { $0.from.hasSuffix("main.swift") })
        XCTAssertFalse(result.manifest.fileRenames.contains { $0.from == "LinuxMain.swift" })
    }

    func testAccessControlledImportDirectoriesPreserveSwiftFilenames() throws {
        let input = temporaryRoot.appendingPathComponent("Input")
        let output = temporaryRoot.appendingPathComponent("Output")
        let importSensitive = input.appendingPathComponent("Sources/ImportSensitive")
        let normal = input.appendingPathComponent("Sources/Normal")
        try fileManager.createDirectory(at: importSensitive, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: normal, withIntermediateDirectories: true)
        try "internal import Foundation\nstruct InternalImport {}\n".write(
            to: importSensitive.appendingPathComponent("InternalImport.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "import Foundation\nstruct PlainImport {}\n".write(
            to: importSensitive.appendingPathComponent("PlainImport.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "struct Normal {}\n".write(
            to: normal.appendingPathComponent("Normal.swift"),
            atomically: true,
            encoding: .utf8
        )

        let result = try ORKSwiftNew(fileManager: fileManager).run(.init(
            inputPath: input.path,
            outputPath: output.path,
            seed: "unit-test",
            renameFiles: true,
            useDefaultExcludes: false
        ))

        XCTAssertTrue(fileManager.fileExists(
            atPath: output.appendingPathComponent("Sources/ImportSensitive/InternalImport.swift").path
        ))
        XCTAssertTrue(fileManager.fileExists(
            atPath: output.appendingPathComponent("Sources/ImportSensitive/PlainImport.swift").path
        ))
        XCTAssertEqual(result.manifest.fileRenames.count, 1)
        XCTAssertEqual(result.manifest.fileRenames.first?.from, "Sources/Normal/Normal.swift")
    }

    func testRenamesInternalTypesAndReferences() throws {
        let input = temporaryRoot.appendingPathComponent("Input")
        let output = temporaryRoot.appendingPathComponent("Output")
        let sources = input.appendingPathComponent("Sources/App")
        try fileManager.createDirectory(at: sources, withIntermediateDirectories: true)
        try """
        struct ProfileCoordinator {
            let value: String
        }
        """.write(
            to: sources.appendingPathComponent("ProfileCoordinator.swift"),
            atomically: true,
            encoding: .utf8
        )
        try """
        struct ProfileFactory {
            static func make() -> ProfileCoordinator {
                ProfileCoordinator(value: "ready")
            }
        }
        """.write(
            to: sources.appendingPathComponent("ProfileFactory.swift"),
            atomically: true,
            encoding: .utf8
        )

        let result = try ORKSwiftNew(fileManager: fileManager).run(.init(
            inputPath: input.path,
            outputPath: output.path,
            seed: "unit-test",
            renameTypes: true,
            useDefaultExcludes: false
        ))

        let coordinatorRename = try XCTUnwrap(result.manifest.typeRenames.first { $0.from == "ProfileCoordinator" })
        XCTAssertEqual(result.manifest.typeRenames.count, 2)
        XCTAssertTrue(coordinatorRename.to.hasPrefix("T_"))

        let transformedFactory = try String(
            contentsOf: output.appendingPathComponent("Sources/App/ProfileFactory.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(transformedFactory.contains("ProfileCoordinator"))
        XCTAssertTrue(transformedFactory.contains("-> \(coordinatorRename.to)"))
        XCTAssertTrue(transformedFactory.contains("\(coordinatorRename.to)(value:"))
    }

    func testTypeNamesInsideStringLiteralsAreSkipped() throws {
        let input = temporaryRoot.appendingPathComponent("Input")
        let output = temporaryRoot.appendingPathComponent("Output")
        try fileManager.createDirectory(at: input, withIntermediateDirectories: true)
        let source = input.appendingPathComponent("ProfileCoordinator.swift")
        try """
        let reflected = "ProfileCoordinator"

        struct ProfileCoordinator {}
        """.write(to: source, atomically: true, encoding: .utf8)

        let result = try ORKSwiftNew(fileManager: fileManager).run(.init(
            inputPath: input.path,
            outputPath: output.path,
            seed: "unit-test",
            renameTypes: true,
            useDefaultExcludes: false
        ))

        XCTAssertEqual(result.manifest.typeRenames.count, 0)
        XCTAssertTrue(result.manifest.skippedTypes.contains { skipped in
            skipped.name == "ProfileCoordinator"
                && skipped.reason == "identifier appears inside a string literal or interpolation"
        })
    }

    func testNestedTypesAreSkipped() throws {
        let input = temporaryRoot.appendingPathComponent("Input")
        let output = temporaryRoot.appendingPathComponent("Output")
        try fileManager.createDirectory(at: input, withIntermediateDirectories: true)
        let source = input.appendingPathComponent("Container.swift")
        try """
        struct Container {
            struct NestedType {}
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let result = try ORKSwiftNew(fileManager: fileManager).run(.init(
            inputPath: input.path,
            outputPath: output.path,
            seed: "unit-test",
            renameTypes: true,
            useDefaultExcludes: false
        ))

        XCTAssertTrue(result.manifest.typeRenames.contains { $0.from == "Container" })
        XCTAssertFalse(result.manifest.typeRenames.contains { $0.from == "NestedType" })
        XCTAssertTrue(result.manifest.skippedTypes.contains { skipped in
            skipped.name == "NestedType" && skipped.reason == "nested type declarations are skipped"
        })
    }

    func testQualifiedExternalTypeOccurrencesCauseTypeRenameSkip() throws {
        let input = temporaryRoot.appendingPathComponent("Input")
        let output = temporaryRoot.appendingPathComponent("Output")
        try fileManager.createDirectory(at: input, withIntermediateDirectories: true)
        let source = input.appendingPathComponent("Subscription.swift")
        try """
        class Subscription {}

        let external: Combine.Subscription? = nil
        """.write(to: source, atomically: true, encoding: .utf8)

        let result = try ORKSwiftNew(fileManager: fileManager).run(.init(
            inputPath: input.path,
            outputPath: output.path,
            seed: "unit-test",
            renameTypes: true,
            useDefaultExcludes: false
        ))

        XCTAssertFalse(result.manifest.typeRenames.contains { $0.from == "Subscription" })
        XCTAssertTrue(result.manifest.skippedTypes.contains { skipped in
            skipped.name == "Subscription"
                && skipped.reason.contains("qualified member or external type reference")
        })
    }

    func testFunctionNamesInsideStringLiteralsAreSkipped() throws {
        let input = temporaryRoot.appendingPathComponent("Input")
        let output = temporaryRoot.appendingPathComponent("Output")
        try fileManager.createDirectory(at: input, withIntermediateDirectories: true)
        let source = input.appendingPathComponent("URLRequest.swift")
        try """
        import Foundation

        func render(url: URL) -> String {
            "\\(url.sortingQueryItems()!.absoluteString)"
        }

        extension URL {
            fileprivate func sortingQueryItems() -> URL? {
                self
            }
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let result = try ORKSwiftNew(fileManager: fileManager).run(.init(
            inputPath: input.path,
            outputPath: output.path,
            seed: "unit-test",
            renamePrivateFunctions: true,
            useDefaultExcludes: false
        ))

        XCTAssertEqual(result.manifest.functionRenames.count, 0)
        XCTAssertTrue(result.manifest.skippedFunctions.contains { skipped in
            skipped.name == "sortingQueryItems"
                && skipped.reason == "identifier appears inside a string literal or interpolation"
        })
        XCTAssertEqual(
            try String(contentsOf: output.appendingPathComponent("URLRequest.swift"), encoding: .utf8),
            try String(contentsOf: source, encoding: .utf8)
        )
    }

    func testFunctionNamesWithMismatchedCallLabelsAreSkipped() throws {
        let input = temporaryRoot.appendingPathComponent("Input")
        let output = temporaryRoot.appendingPathComponent("Output")
        try fileManager.createDirectory(at: input, withIntermediateDirectories: true)
        let source = input.appendingPathComponent("Rule.swift")
        try """
        struct Rule {
            private func diagnose(_ node: Int, type: Int) {}

            private func emitDiagnostic(replace: String, with fixIt: String, on node: Int?) {
                diagnose("message", on: node)
            }
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let result = try ORKSwiftNew(fileManager: fileManager).run(.init(
            inputPath: input.path,
            outputPath: output.path,
            seed: "unit-test",
            renamePrivateFunctions: true,
            useDefaultExcludes: false
        ))

        XCTAssertFalse(result.manifest.functionRenames.contains { $0.from == "diagnose" })
        XCTAssertTrue(result.manifest.functionRenames.contains { $0.from == "emitDiagnostic" })
        XCTAssertTrue(result.manifest.skippedFunctions.contains { skipped in
            skipped.name == "diagnose"
                && skipped.reason.hasPrefix("call labels do not match private function signature")
        })
    }

    func testFunctionNamesWithSameNameCallsInsideTheirOwnBodyAreSkipped() throws {
        let input = temporaryRoot.appendingPathComponent("Input")
        let output = temporaryRoot.appendingPathComponent("Output")
        try fileManager.createDirectory(at: input, withIntermediateDirectories: true)
        let source = input.appendingPathComponent("Text.swift")
        try """
        extension Text {
            fileprivate func hasSuffix(_ other: String) -> Bool {
                self.hasSuffix(other)
            }
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let result = try ORKSwiftNew(fileManager: fileManager).run(.init(
            inputPath: input.path,
            outputPath: output.path,
            seed: "unit-test",
            renamePrivateFunctions: true,
            useDefaultExcludes: false
        ))

        XCTAssertFalse(result.manifest.functionRenames.contains { $0.from == "hasSuffix" })
        XCTAssertTrue(result.manifest.skippedFunctions.contains { skipped in
            skipped.name == "hasSuffix"
                && skipped.reason == "same-name call inside function body may resolve to another overload"
        })
    }

    func testSwiftSymlinkTargetsAreNotRenamed() throws {
        let input = temporaryRoot.appendingPathComponent("Input")
        let output = temporaryRoot.appendingPathComponent("Output")
        let primary = input.appendingPathComponent("Sources/Primary")
        let secondary = input.appendingPathComponent("Sources/Secondary")
        try fileManager.createDirectory(at: primary, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: secondary, withIntermediateDirectories: true)
        try "struct Shared {}\n".write(
            to: primary.appendingPathComponent("Shared.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "struct Normal {}\n".write(
            to: primary.appendingPathComponent("Normal.swift"),
            atomically: true,
            encoding: .utf8
        )
        try fileManager.createSymbolicLink(
            atPath: secondary.appendingPathComponent("Shared.swift").path,
            withDestinationPath: "../Primary/Shared.swift"
        )

        let result = try ORKSwiftNew(fileManager: fileManager).run(.init(
            inputPath: input.path,
            outputPath: output.path,
            seed: "unit-test",
            renameFiles: true,
            useDefaultExcludes: false
        ))

        XCTAssertTrue(fileManager.fileExists(atPath: output.appendingPathComponent("Sources/Primary/Shared.swift").path))
        XCTAssertTrue(fileManager.fileExists(atPath: output.appendingPathComponent("Sources/Secondary/Shared.swift").path))
        XCTAssertEqual(
            try fileManager.destinationOfSymbolicLink(atPath: output.appendingPathComponent("Sources/Secondary/Shared.swift").path),
            "../Primary/Shared.swift"
        )
        XCTAssertEqual(result.manifest.fileRenames.count, 1)
        XCTAssertEqual(result.manifest.fileRenames.first?.from, "Sources/Primary/Normal.swift")
    }

    func testDryRunDoesNotWriteOutputOrModifyInput() throws {
        let input = temporaryRoot.appendingPathComponent("Input")
        try fileManager.createDirectory(at: input, withIntermediateDirectories: true)
        let source = input.appendingPathComponent("Demo.swift")
        try "private func privateWork() {}\n".write(to: source, atomically: true, encoding: .utf8)

        let result = try ORKSwiftNew(fileManager: fileManager).run(.init(
            inputPath: input.path,
            seed: "unit-test",
            dryRun: true,
            renameFiles: true,
            renamePrivateFunctions: true,
            useDefaultExcludes: false
        ))

        XCTAssertEqual(result.manifest.fileRenames.count, 1)
        XCTAssertEqual(result.manifest.functionRenames.count, 1)
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "private func privateWork() {}\n")
    }
}
