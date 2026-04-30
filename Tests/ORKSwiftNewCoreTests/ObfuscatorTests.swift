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
