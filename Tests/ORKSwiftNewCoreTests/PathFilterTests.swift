import XCTest
@testable import ORKSwiftNewCore

final class PathFilterTests: XCTestCase {
    func testPlainComponentPatternMatchesAnyPathComponent() {
        let filter = PathFilter(patterns: ["Security"])

        XCTAssertTrue(filter.isExcluded(relativePath: "App/Security/KeyStore.swift"))
        XCTAssertFalse(filter.isExcluded(relativePath: "App/SecureKeyStore.swift"))
    }

    func testPathPatternMatchesDirectoryPrefix() {
        let filter = PathFilter(patterns: ["Features/Generated"])

        XCTAssertTrue(filter.isExcluded(relativePath: "Features/Generated/API.swift"))
        XCTAssertFalse(filter.isExcluded(relativePath: "Generated/API.swift"))
    }

    func testGlobPatternMatchesBasenameAndRelativePath() {
        let filter = PathFilter(patterns: ["*.generated.swift", "Snapshots/*.swift"])

        XCTAssertTrue(filter.isExcluded(relativePath: "App/Models/User.generated.swift"))
        XCTAssertTrue(filter.isExcluded(relativePath: "Snapshots/Foo.swift"))
        XCTAssertFalse(filter.isExcluded(relativePath: "App/Models/User.swift"))
    }
}
