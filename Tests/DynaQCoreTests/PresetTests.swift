import XCTest
@testable import DynaQCore

final class PresetTests: XCTestCase {

    func testFactoryPresetsNonEmpty() {
        let presets = DefaultPresets.all
        XCTAssertGreaterThanOrEqual(presets.count, 5)

        for p in presets {
            XCTAssertFalse(p.name.isEmpty)
            XCTAssertFalse(p.bands.isEmpty)
            XCTAssertTrue(p.isFactory)
        }
    }

    func testProfileCodableSerialization() throws {
        let original = DefaultPresets.vocalClarityAndDeEss

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(EQProfile.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.bands.count, original.bands.count)
        XCTAssertEqual(decoded.bands[4].isDynamic, true)
    }

    func testDuplicateProfile() {
        let original = DefaultPresets.studioFlat
        let copy = original.duplicate(newName: "My Custom Flat")

        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.name, "My Custom Flat")
        XCTAssertFalse(copy.isFactory)
        XCTAssertEqual(copy.bands.count, original.bands.count)
    }
}

