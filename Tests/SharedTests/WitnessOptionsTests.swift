
import XCTest
import Shared

final class WitnessOptionsTests: XCTestCase {

    func test_init_withSingleOptionStringLiteral() {
        let options = WitnessOptions(stringLiteral: "utilities")
        XCTAssertEqual(options, .utilities)
        XCTAssertTrue(options?.contains(.utilities) ?? false)
        XCTAssertFalse(options?.contains(.conformanceInit) ?? true)
        XCTAssertEqual(options?.identifiers, ["utilities"])
    }

    func test_init_withMultipleOptionsStringLiteral() {
        let options = WitnessOptions(stringLiteral: "[.utilities, .conformanceInit]")
        let expectedOptions: WitnessOptions = [.utilities, .conformanceInit]
        XCTAssertEqual(options, expectedOptions)
        XCTAssertTrue(options?.contains(.utilities) ?? false)
        XCTAssertTrue(options?.contains(.conformanceInit) ?? false)
        XCTAssertEqual(options?.identifiers.sorted(), ["conformanceInit", "utilities"].sorted())
    }

    func test_init_withMultipleOptionsStringLiteral_withSpaces() {
        let options = WitnessOptions(stringLiteral: "[ .utilities , .conformanceInit ]")
        let expectedOptions: WitnessOptions = [.utilities, .conformanceInit]
        XCTAssertEqual(options, expectedOptions)
        XCTAssertTrue(options?.contains(.utilities) ?? false)
        XCTAssertTrue(options?.contains(.conformanceInit) ?? false)
        XCTAssertEqual(options?.identifiers.sorted(), ["conformanceInit", "utilities"].sorted())
    }

    func test_init_withsynthesizedByTableConformanceOption() throws {
        let options = WitnessOptions(stringLiteral: "synthesizedByTableConformance")
        XCTAssertEqual(options, .synthesizedByTableConformance)
        let identifiers = try XCTUnwrap(options?.identifiers)
        XCTAssert(identifiers.contains(["synthesizedByTableConformance"]))
    }

    func test_init_withAllOptions() {
        let options = WitnessOptions(stringLiteral: "[.utilities, .conformanceInit, .synthesizedByTableConformance]")
        let expectedOptions: WitnessOptions = [.utilities, .conformanceInit, .synthesizedByTableConformance]
        XCTAssertEqual(options, expectedOptions)
        XCTAssertTrue(options?.contains(.utilities) ?? false)
        XCTAssertTrue(options?.contains(.conformanceInit) ?? false)
        XCTAssertTrue(options?.contains(.synthesizedByTableConformance) ?? false)
    }

    func test_init_withEmptyArrayStringLiteral() {
        let options = WitnessOptions(stringLiteral: "[]")
        XCTAssertEqual(options, [])
        XCTAssertTrue(options?.isEmpty ?? false)
        XCTAssertEqual(options?.identifiers, [])
    }

    func test_init_withUnrecognizedStringLiteral() {
        let options = WitnessOptions(stringLiteral: "unknownOption")
        XCTAssertNil(options)
    }

    func test_init_withMixedValidAndInvalidStringLiteral() {
        let options = WitnessOptions(stringLiteral: "[.utilities, .invalidOption]")
        XCTAssertNil(options)
    }

    func test_identifiers_forEmptyOptionSet() {
        let options: WitnessOptions = []
        XCTAssertEqual(options.identifiers, [])
    }
}
