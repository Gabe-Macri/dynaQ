import XCTest
@testable import DynaQCore

final class PresetTests: XCTestCase {

    func testFactoryPresetsNonEmpty() {
        let presets = DefaultPresets.all
        XCTAssertGreaterThanOrEqual(presets.count, 25, "Factory presets library should contain comprehensive targets (>= 25).")

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for p in presets {
            XCTAssertFalse(p.name.isEmpty, "Preset name must not be empty.")
            XCTAssertFalse(p.category.isEmpty, "Preset category must not be empty.")
            XCTAssertFalse(p.notes.isEmpty, "Preset notes must not be empty.")
            XCTAssertFalse(p.bands.isEmpty, "Preset must have at least one band.")
            XCTAssertTrue(p.isFactory, "Factory presets must have isFactory flag set.")
            XCTAssertGreaterThanOrEqual(p.stereoWidth, 0.0)
            XCTAssertLessThanOrEqual(p.stereoWidth, 2.0)
            XCTAssertGreaterThanOrEqual(p.monoBassCutoff, 0.0)
            XCTAssertLessThanOrEqual(p.monoBassCutoff, 300.0)
            XCTAssertGreaterThanOrEqual(p.analogDrive, 0.0)
            XCTAssertLessThanOrEqual(p.analogDrive, 1.0)

            // Test round-trip serialization
            guard let data = try? encoder.encode(p),
                  let roundtrip = try? decoder.decode(EQProfile.self, from: data) else {
                XCTFail("Failed to round-trip serialize factory preset '\(p.name)'")
                continue
            }
            XCTAssertEqual(roundtrip.name, p.name)
            XCTAssertEqual(roundtrip.bands.count, p.bands.count)
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

