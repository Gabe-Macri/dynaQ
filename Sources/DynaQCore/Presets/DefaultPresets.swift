import Foundation

public enum DefaultPresets {
    public static var all: [EQProfile] {
        return [
            studioFlat,
            harmanHeadphoneTarget,
            masteringWarmOpen,
            vocalClarityAndDeEss,
            lowEndPunch,
            podcastBroadcast,
            acousticSpace
        ]
    }

    public static let studioFlat = EQProfile(
        name: "Studio Reference Flat",
        category: "Studio",
        notes: "Zeroed 6-band baseline curve for transparent monitoring.",
        bands: [
            EQBand(index: 0, frequency: 30.0, gain: 0.0, q: 0.707, filterType: .highPass),
            EQBand(index: 1, frequency: 100.0, gain: 0.0, q: 1.0, filterType: .lowShelf),
            EQBand(index: 2, frequency: 450.0, gain: 0.0, q: 1.4, filterType: .bell),
            EQBand(index: 3, frequency: 2000.0, gain: 0.0, q: 1.4, filterType: .bell),
            EQBand(index: 4, frequency: 8000.0, gain: 0.0, q: 1.0, filterType: .highShelf),
            EQBand(index: 5, frequency: 18500.0, gain: 0.0, q: 0.707, filterType: .lowPass)
        ],
        isFactory: true
    )

    public static let harmanHeadphoneTarget = EQProfile(
        name: "Audiophile Harman Curve",
        category: "Headphones",
        notes: "Tuned to the Harman headphone listener target: tactile sub-bass with linear midrange and smooth treble.",
        bands: [
            EQBand(index: 0, frequency: 25.0, gain: 0.0, q: 0.707, filterType: .highPass),
            EQBand(index: 1, frequency: 105.0, gain: 4.5, q: 0.8, filterType: .lowShelf),
            EQBand(index: 2, frequency: 240.0, gain: -1.2, q: 1.5, filterType: .bell),
            EQBand(index: 3, frequency: 1200.0, gain: 0.5, q: 2.0, filterType: .bell),
            EQBand(index: 4, frequency: 3200.0, gain: 2.8, q: 1.8, filterType: .bell),
            EQBand(index: 5, frequency: 6500.0, gain: -1.5, q: 3.0, filterType: .bell),
            EQBand(index: 6, frequency: 11000.0, gain: 2.0, q: 0.9, filterType: .highShelf)
        ],
        isFactory: true
    )

    public static let masteringWarmOpen = EQProfile(
        name: "Mastering: Warm & Open",
        category: "Mastering",
        notes: "Pultec-inspired analog curve that broadens the stereo field and imparts polished high-end sheen.",
        bands: [
            EQBand(index: 0, frequency: 32.0, gain: -0.5, q: 1.0, filterType: .highPass),
            EQBand(index: 1, frequency: 80.0, gain: 1.8, q: 0.7, filterType: .lowShelf),
            EQBand(index: 2, frequency: 380.0, gain: -1.0, q: 1.2, filterType: .bell),
            EQBand(index: 3, frequency: 2800.0, gain: 1.2, q: 1.6, filterType: .bell),
            EQBand(index: 4, frequency: 12500.0, gain: 2.2, q: 0.7, filterType: .highShelf)
        ],
        preampGain: -0.5,
        limiterCeiling: -0.3,
        isFactory: true
    )

    public static let vocalClarityAndDeEss = EQProfile(
        name: "Vocal Clarity & Dynamic De-Ess",
        category: "Vocals",
        notes: "Shapes dialog and vocal lines while automatically squashing sibilance with dynamic EQ.",
        bands: [
            EQBand(index: 0, frequency: 80.0, gain: 0.0, q: 0.707, filterType: .highPass),
            EQBand(index: 1, frequency: 250.0, gain: -1.5, q: 1.4, filterType: .bell),
            EQBand(index: 2, frequency: 1000.0, gain: -1.0, q: 1.8, filterType: .bell),
            EQBand(index: 3, frequency: 3500.0, gain: 2.5, q: 1.4, filterType: .bell),
            EQBand(index: 4, frequency: 7200.0, gain: -0.5, q: 2.8, filterType: .bell,
                   isDynamic: true, dynamicThreshold: -16.0, dynamicRange: -5.0, dynamicRatio: 3.5, attackMs: 2.0, releaseMs: 60.0),
            EQBand(index: 5, frequency: 14000.0, gain: 1.8, q: 0.8, filterType: .highShelf)
        ],
        isFactory: true
    )

    public static let lowEndPunch = EQProfile(
        name: "Low-End Punch & Tight Sub",
        category: "Electronic",
        notes: "Carves out mud while delivering punchy kick transients and controlled sub bass.",
        bands: [
            EQBand(index: 0, frequency: 30.0, gain: 0.0, q: 0.8, filterType: .highPass),
            EQBand(index: 1, frequency: 62.0, gain: 3.5, q: 1.6, filterType: .bell),
            EQBand(index: 2, frequency: 220.0, gain: -2.8, q: 1.5, filterType: .bell),
            EQBand(index: 3, frequency: 1200.0, gain: 0.8, q: 1.8, filterType: .bell),
            EQBand(index: 4, frequency: 4500.0, gain: 1.5, q: 1.4, filterType: .bell),
            EQBand(index: 5, frequency: 10000.0, gain: 1.0, q: 1.0, filterType: .highShelf)
        ],
        preampGain: -1.0,
        isFactory: true
    )

    public static let podcastBroadcast = EQProfile(
        name: "Broadcast Voice (SM7B/Podcast)",
        category: "Speech",
        notes: "Optimized for broadcast microphones to eliminate plosives and boominess, lifting presence.",
        bands: [
            EQBand(index: 0, frequency: 85.0, gain: 0.0, q: 0.707, filterType: .highPass),
            EQBand(index: 1, frequency: 160.0, gain: 1.0, q: 1.2, filterType: .bell),
            EQBand(index: 2, frequency: 320.0, gain: -2.5, q: 1.4, filterType: .bell),
            EQBand(index: 3, frequency: 2800.0, gain: 2.2, q: 1.6, filterType: .bell),
            EQBand(index: 4, frequency: 5500.0, gain: 1.0, q: 2.0, filterType: .bell),
            EQBand(index: 5, frequency: 11000.0, gain: 2.0, q: 0.8, filterType: .highShelf)
        ],
        isFactory: true
    )

    public static let acousticSpace = EQProfile(
        name: "Acoustic Instrument Air",
        category: "Instruments",
        notes: "Gives acoustic guitars, strings, and piano airy sparkle without digital harshness.",
        bands: [
            EQBand(index: 0, frequency: 45.0, gain: 0.0, q: 0.707, filterType: .highPass),
            EQBand(index: 1, frequency: 180.0, gain: -1.2, q: 1.5, filterType: .bell),
            EQBand(index: 2, frequency: 800.0, gain: 0.8, q: 2.0, filterType: .bell),
            EQBand(index: 3, frequency: 3200.0, gain: 1.5, q: 1.6, filterType: .bell),
            EQBand(index: 4, frequency: 12000.0, gain: 3.2, q: 0.7, filterType: .highShelf)
        ],
        isFactory: true
    )
}
