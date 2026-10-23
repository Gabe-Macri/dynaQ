import Foundation

public enum DefaultPresets {
    public static var all: [EQProfile] {
        return [
            // Studio Reference
            studioFlat,
            // Headphone Targets
            harmanHeadphoneTarget,
            harmanInEarTarget,
            sennheiserHD600,
            sonyWH1000XM,
            airpodsPro2,
            beyerdynamicDT990,
            audioTechnicaM50x,
            // Mastering & Studio Polish
            masteringWarmOpen,
            masteringPultecTrick,
            stereoWidenerMonoSub,
            tapeWarmthAndDrive,
            boxinessAndMudCleaner,
            loudnessCompensator,
            // Music Genres
            lowEndPunch,
            hipHopHeavy808,
            modernPopVocalForward,
            rockWallOfSound,
            lofiChillVinyl,
            acousticSpace,
            classicalSymphonicSpace,
            // Voice & Speech
            podcastBroadcast,
            vocalClarityAndDeEss,
            dialogueIntelligibility,
            // Gaming & Utility
            gamingFPSFootstep,
            antiFatigueDesk
        ]
    }

    // MARK: - Studio Reference

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

    // MARK: - Headphone Targets

    public static let harmanHeadphoneTarget = EQProfile(
        name: "Audiophile Harman Curve (Over-Ear)",
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

    public static let harmanInEarTarget = EQProfile(
        name: "Harman In-Ear Target (2019)",
        category: "Headphones",
        notes: "Precise acoustic tuning for IEMs: deeper sub-bass shelf and pinna-gain compensation at 2.8kHz.",
        bands: [
            EQBand(index: 0, frequency: 20.0, gain: 0.0, q: 0.707, filterType: .highPass),
            EQBand(index: 1, frequency: 80.0, gain: 5.5, q: 0.7, filterType: .lowShelf),
            EQBand(index: 2, frequency: 220.0, gain: -1.8, q: 1.2, filterType: .bell),
            EQBand(index: 3, frequency: 1000.0, gain: -0.8, q: 2.0, filterType: .bell),
            EQBand(index: 4, frequency: 2800.0, gain: 3.8, q: 1.6, filterType: .bell),
            EQBand(index: 5, frequency: 5500.0, gain: -2.0, q: 2.5, filterType: .bell),
            EQBand(index: 6, frequency: 12500.0, gain: 2.5, q: 0.8, filterType: .highShelf)
        ],
        preampGain: -1.5,
        isFactory: true
    )

    public static let sennheiserHD600 = EQProfile(
        name: "Sennheiser HD600 / HD650 Neutralizer",
        category: "Headphones",
        notes: "Extends sub-bass roll-off below 60Hz and dissolves the traditional Sennheiser veil in the upper treble.",
        bands: [
            EQBand(index: 0, frequency: 35.0, gain: 4.5, q: 1.2, filterType: .lowShelf),
            EQBand(index: 1, frequency: 140.0, gain: -1.0, q: 1.4, filterType: .bell),
            EQBand(index: 2, frequency: 1200.0, gain: -0.5, q: 2.0, filterType: .bell),
            EQBand(index: 3, frequency: 3400.0, gain: -1.2, q: 2.5, filterType: .bell),
            EQBand(index: 4, frequency: 5800.0, gain: 1.5, q: 2.0, filterType: .bell),
            EQBand(index: 5, frequency: 10500.0, gain: 2.8, q: 0.9, filterType: .highShelf)
        ],
        preampGain: -1.0,
        isFactory: true
    )

    public static let sonyWH1000XM = EQProfile(
        name: "Sony WH-1000XM4 / XM5 Clarify & De-Bloat",
        category: "Headphones",
        notes: "Removes boomy 180Hz mid-bass resonance and elevates vocal presence and top-end micro-detail.",
        bands: [
            EQBand(index: 0, frequency: 40.0, gain: 1.5, q: 1.0, filterType: .bell),
            EQBand(index: 1, frequency: 180.0, gain: -4.5, q: 1.2, filterType: .bell),
            EQBand(index: 2, frequency: 650.0, gain: 1.2, q: 1.6, filterType: .bell),
            EQBand(index: 3, frequency: 2400.0, gain: 3.2, q: 1.5, filterType: .bell),
            EQBand(index: 4, frequency: 6200.0, gain: -1.5, q: 3.0, filterType: .bell),
            EQBand(index: 5, frequency: 10000.0, gain: 3.5, q: 0.8, filterType: .highShelf)
        ],
        preampGain: -0.5,
        stereoWidth: 1.1,
        isFactory: true
    )

    public static let airpodsPro2 = EQProfile(
        name: "Apple AirPods Pro 2 Natural Acoustic",
        category: "Headphones",
        notes: "Refines ANC ear-canal resonance, smoothing the 7kHz sibilance region for natural fatigue-free listening.",
        bands: [
            EQBand(index: 0, frequency: 32.0, gain: 1.8, q: 0.9, filterType: .lowShelf),
            EQBand(index: 1, frequency: 280.0, gain: -1.2, q: 1.5, filterType: .bell),
            EQBand(index: 2, frequency: 1500.0, gain: 0.8, q: 2.0, filterType: .bell),
            EQBand(index: 3, frequency: 4200.0, gain: 1.2, q: 2.0, filterType: .bell),
            EQBand(index: 4, frequency: 7200.0, gain: -2.5, q: 3.5, filterType: .bell),
            EQBand(index: 5, frequency: 12000.0, gain: 1.5, q: 1.0, filterType: .highShelf)
        ],
        isFactory: true
    )

    public static let beyerdynamicDT990 = EQProfile(
        name: "Beyerdynamic DT 990 / 770 Treble Tame",
        category: "Headphones",
        notes: "Surgically notches out notorious 5.9kHz and 8.6kHz treble spikes while boosting warm chest resonance.",
        bands: [
            EQBand(index: 0, frequency: 50.0, gain: 2.5, q: 0.9, filterType: .lowShelf),
            EQBand(index: 1, frequency: 200.0, gain: 1.0, q: 1.4, filterType: .bell),
            EQBand(index: 2, frequency: 1000.0, gain: 0.5, q: 2.0, filterType: .bell),
            EQBand(index: 3, frequency: 5900.0, gain: -4.5, q: 4.0, filterType: .bell),
            EQBand(index: 4, frequency: 8600.0, gain: -5.0, q: 4.5, filterType: .bell),
            EQBand(index: 5, frequency: 14000.0, gain: 1.0, q: 1.0, filterType: .highShelf)
        ],
        isFactory: true
    )

    public static let audioTechnicaM50x = EQProfile(
        name: "Audio-Technica ATH-M50x Balance",
        category: "Headphones",
        notes: "Cleans up congested 160Hz mid-bass resonance and widens the soundstage with linear midrange balance.",
        bands: [
            EQBand(index: 0, frequency: 30.0, gain: 0.0, q: 0.707, filterType: .highPass),
            EQBand(index: 1, frequency: 160.0, gain: -3.2, q: 1.5, filterType: .bell),
            EQBand(index: 2, frequency: 450.0, gain: 1.5, q: 1.8, filterType: .bell),
            EQBand(index: 3, frequency: 3000.0, gain: -1.8, q: 2.0, filterType: .bell),
            EQBand(index: 4, frequency: 9500.0, gain: -2.0, q: 3.0, filterType: .bell),
            EQBand(index: 5, frequency: 13500.0, gain: 2.0, q: 0.8, filterType: .highShelf)
        ],
        stereoWidth: 1.15,
        isFactory: true
    )

    // MARK: - Mastering & Studio Polish

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

    public static let masteringPultecTrick = EQProfile(
        name: "Mastering: Pultec Low/High Trick",
        category: "Mastering",
        notes: "Simultaneous 60Hz shelf boost and 300Hz scoop combined with open 16kHz air and analog saturation.",
        bands: [
            EQBand(index: 0, frequency: 28.0, gain: 0.0, q: 0.707, filterType: .highPass),
            EQBand(index: 1, frequency: 60.0, gain: 3.0, q: 0.8, filterType: .lowShelf),
            EQBand(index: 2, frequency: 280.0, gain: -1.8, q: 1.4, filterType: .bell),
            EQBand(index: 3, frequency: 3500.0, gain: 1.0, q: 1.8, filterType: .bell),
            EQBand(index: 4, frequency: 16000.0, gain: 3.5, q: 0.6, filterType: .highShelf)
        ],
        preampGain: -1.0,
        analogDrive: 0.15,
        isFactory: true
    )

    public static let stereoWidenerMonoSub = EQProfile(
        name: "Stereo Widener & Mono Sub (< 90Hz)",
        category: "Mastering",
        notes: "Sums all sub-bass below 90Hz to solid mono while expanding side-channel stereo width by 135%.",
        bands: [
            EQBand(index: 0, frequency: 24.0, gain: 0.0, q: 0.707, filterType: .highPass),
            EQBand(index: 1, frequency: 100.0, gain: 1.2, q: 1.0, filterType: .bell, routing: .mid),
            EQBand(index: 2, frequency: 450.0, gain: -0.8, q: 1.4, filterType: .bell),
            EQBand(index: 3, frequency: 3200.0, gain: 1.2, q: 1.5, filterType: .bell, routing: .side),
            EQBand(index: 4, frequency: 12000.0, gain: 2.0, q: 0.8, filterType: .highShelf, routing: .side)
        ],
        stereoWidth: 1.35,
        monoBassCutoff: 90.0,
        isFactory: true
    )

    public static let tapeWarmthAndDrive = EQProfile(
        name: "Analog Tape Warmth & Saturation",
        category: "Mastering",
        notes: "Imparts gentle Baxandall tilt warmth, analog soft-knee tape saturation, and smoothed transient tops.",
        bands: [
            EQBand(index: 0, frequency: 28.0, gain: 0.0, q: 0.707, filterType: .highPass),
            EQBand(index: 1, frequency: 1000.0, gain: -1.2, q: 0.7, filterType: .tiltShelf),
            EQBand(index: 2, frequency: 3500.0, gain: 0.8, q: 1.5, filterType: .bell),
            EQBand(index: 3, frequency: 15000.0, gain: -1.0, q: 0.7, filterType: .highShelf)
        ],
        preampGain: -0.5,
        analogDrive: 0.35,
        isFactory: true
    )

    public static let boxinessAndMudCleaner = EQProfile(
        name: "Mix Mud & Boxiness Remover",
        category: "Mastering",
        notes: "Carves out congested 320Hz and 650Hz boxy build-up to open space for kick, bass, and lead vocals.",
        bands: [
            EQBand(index: 0, frequency: 32.0, gain: 0.0, q: 0.707, filterType: .highPass),
            EQBand(index: 1, frequency: 180.0, gain: 0.8, q: 1.2, filterType: .bell),
            EQBand(index: 2, frequency: 320.0, gain: -2.8, q: 2.0, filterType: .bell),
            EQBand(index: 3, frequency: 650.0, gain: -1.8, q: 2.2, filterType: .bell),
            EQBand(index: 4, frequency: 2800.0, gain: 1.2, q: 1.6, filterType: .bell),
            EQBand(index: 5, frequency: 11000.0, gain: 1.8, q: 0.9, filterType: .highShelf)
        ],
        isFactory: true
    )

    public static let loudnessCompensator = EQProfile(
        name: "Loudness War / Fletcher-Munson Equalizer",
        category: "Mastering",
        notes: "Equal-loudness compensation curve: boosts deep sub and air frequencies for full-bodied low-volume listening.",
        bands: [
            EQBand(index: 0, frequency: 22.0, gain: 0.0, q: 0.707, filterType: .highPass),
            EQBand(index: 1, frequency: 75.0, gain: 4.8, q: 0.7, filterType: .lowShelf),
            EQBand(index: 2, frequency: 500.0, gain: -1.5, q: 1.0, filterType: .bell),
            EQBand(index: 3, frequency: 2500.0, gain: 1.0, q: 1.4, filterType: .bell),
            EQBand(index: 4, frequency: 10000.0, gain: 4.2, q: 0.7, filterType: .highShelf)
        ],
        preampGain: -1.5,
        isFactory: true
    )

    // MARK: - Music Genres

    public static let lowEndPunch = EQProfile(
        name: "EDM & Club Low-End Punch",
        category: "Electronic",
        notes: "Carves out mud while delivering punchy kick transients and controlled sub bass with 80Hz mono summing.",
        bands: [
            EQBand(index: 0, frequency: 30.0, gain: 0.0, q: 0.8, filterType: .highPass),
            EQBand(index: 1, frequency: 55.0, gain: 4.2, q: 1.8, filterType: .bell),
            EQBand(index: 2, frequency: 220.0, gain: -2.8, q: 1.5, filterType: .bell),
            EQBand(index: 3, frequency: 1200.0, gain: 0.8, q: 1.8, filterType: .bell),
            EQBand(index: 4, frequency: 4500.0, gain: 1.8, q: 1.4, filterType: .bell),
            EQBand(index: 5, frequency: 10500.0, gain: 2.2, q: 1.0, filterType: .highShelf)
        ],
        preampGain: -1.2,
        stereoWidth: 1.2,
        monoBassCutoff: 80.0,
        isFactory: true
    )

    public static let hipHopHeavy808 = EQProfile(
        name: "Hip-Hop & Trap 808 Foundation",
        category: "Electronic",
        notes: "Massive 42Hz sub-bass pressure, carved lower-mid pocket, crisp trap snare bite, and shimmering hi-hats.",
        bands: [
            EQBand(index: 0, frequency: 25.0, gain: 0.0, q: 0.707, filterType: .highPass),
            EQBand(index: 1, frequency: 42.0, gain: 5.5, q: 1.6, filterType: .bell),
            EQBand(index: 2, frequency: 180.0, gain: -2.5, q: 1.8, filterType: .bell),
            EQBand(index: 3, frequency: 1400.0, gain: 1.2, q: 2.0, filterType: .bell),
            EQBand(index: 4, frequency: 3800.0, gain: 2.0, q: 1.6, filterType: .bell),
            EQBand(index: 5, frequency: 12500.0, gain: 3.0, q: 0.8, filterType: .highShelf)
        ],
        preampGain: -1.8,
        monoBassCutoff: 90.0,
        isFactory: true
    )

    public static let modernPopVocalForward = EQProfile(
        name: "Modern Pop Vocal Forward",
        category: "Vocals",
        notes: "Polished radio-ready profile: vocal presence push at 3kHz with dynamic 7kHz de-essing and silky air.",
        bands: [
            EQBand(index: 0, frequency: 35.0, gain: 0.0, q: 0.707, filterType: .highPass),
            EQBand(index: 1, frequency: 95.0, gain: 2.0, q: 1.0, filterType: .lowShelf),
            EQBand(index: 2, frequency: 400.0, gain: -1.5, q: 1.6, filterType: .bell),
            EQBand(index: 3, frequency: 2900.0, gain: 2.8, q: 1.5, filterType: .bell),
            EQBand(index: 4, frequency: 7200.0, gain: -1.0, q: 3.2, filterType: .bell,
                   isDynamic: true, dynamicThreshold: -15.0, dynamicRange: -5.0, dynamicRatio: 3.5, attackMs: 2.0, releaseMs: 50.0),
            EQBand(index: 5, frequency: 13000.0, gain: 2.5, q: 0.8, filterType: .highShelf)
        ],
        preampGain: -0.8,
        stereoWidth: 1.1,
        isFactory: true
    )

    public static let rockWallOfSound = EQProfile(
        name: "Rock & Metal Wall of Sound",
        category: "Rock & Metal",
        notes: "High-octane energy: tight punch at 80Hz, scooped 400Hz mud, and aggressive guitar bite at 2.4kHz.",
        bands: [
            EQBand(index: 0, frequency: 38.0, gain: 0.0, q: 0.707, filterType: .highPass),
            EQBand(index: 1, frequency: 85.0, gain: 3.0, q: 1.4, filterType: .bell),
            EQBand(index: 2, frequency: 380.0, gain: -2.8, q: 1.5, filterType: .bell),
            EQBand(index: 3, frequency: 1100.0, gain: 1.0, q: 2.0, filterType: .bell),
            EQBand(index: 4, frequency: 2400.0, gain: 2.8, q: 1.8, filterType: .bell),
            EQBand(index: 5, frequency: 8000.0, gain: 1.8, q: 1.2, filterType: .highShelf)
        ],
        preampGain: -0.8,
        analogDrive: 0.1,
        isFactory: true
    )

    public static let lofiChillVinyl = EQProfile(
        name: "Lo-Fi Chill & Vinyl Nostalgia",
        category: "Electronic",
        notes: "Vintage warmth: band-limited high-frequency rolloff, warm mid-bass bump, and analog tape drive character.",
        bands: [
            EQBand(index: 0, frequency: 45.0, gain: 0.0, q: 0.707, filterType: .highPass),
            EQBand(index: 1, frequency: 160.0, gain: 3.2, q: 1.1, filterType: .bell),
            EQBand(index: 2, frequency: 600.0, gain: 1.0, q: 1.4, filterType: .bell),
            EQBand(index: 3, frequency: 2500.0, gain: -1.5, q: 1.5, filterType: .bell),
            EQBand(index: 4, frequency: 9500.0, gain: 0.0, q: 0.707, filterType: .lowPass)
        ],
        stereoWidth: 0.9,
        analogDrive: 0.3,
        isFactory: true
    )

    public static let acousticSpace = EQProfile(
        name: "Acoustic Instrument Air",
        category: "Acoustic",
        notes: "Gives acoustic guitars, strings, and piano airy sparkle without digital harshness.",
        bands: [
            EQBand(index: 0, frequency: 45.0, gain: 0.0, q: 0.707, filterType: .highPass),
            EQBand(index: 1, frequency: 180.0, gain: -1.2, q: 1.5, filterType: .bell),
            EQBand(index: 2, frequency: 800.0, gain: 0.8, q: 2.0, filterType: .bell),
            EQBand(index: 3, frequency: 3200.0, gain: 1.5, q: 1.6, filterType: .bell),
            EQBand(index: 4, frequency: 12000.0, gain: 3.2, q: 0.7, filterType: .highShelf)
        ],
        stereoWidth: 1.15,
        isFactory: true
    )

    public static let classicalSymphonicSpace = EQProfile(
        name: "Classical & Orchestral Space",
        category: "Acoustic",
        notes: "Transparent concert hall acoustic widening with ultra-flat phase linearity and natural dynamics.",
        bands: [
            EQBand(index: 0, frequency: 24.0, gain: 0.0, q: 0.707, filterType: .highPass),
            EQBand(index: 1, frequency: 80.0, gain: 1.0, q: 0.8, filterType: .lowShelf),
            EQBand(index: 2, frequency: 320.0, gain: -0.8, q: 1.4, filterType: .bell),
            EQBand(index: 3, frequency: 2400.0, gain: 0.8, q: 1.8, filterType: .bell),
            EQBand(index: 4, frequency: 14000.0, gain: 2.0, q: 0.7, filterType: .highShelf)
        ],
        stereoWidth: 1.25,
        isFactory: true
    )

    // MARK: - Voice & Speech

    public static let podcastBroadcast = EQProfile(
        name: "Broadcast Voice (SM7B / Podcast)",
        category: "Speech",
        notes: "Optimized for dynamic broadcast mics: eliminates desk rumble, controls proximity boom, lifts articulation.",
        bands: [
            EQBand(index: 0, frequency: 85.0, gain: 0.0, q: 0.707, filterType: .highPass),
            EQBand(index: 1, frequency: 160.0, gain: 1.2, q: 1.2, filterType: .bell),
            EQBand(index: 2, frequency: 320.0, gain: -2.5, q: 1.4, filterType: .bell),
            EQBand(index: 3, frequency: 2800.0, gain: 2.4, q: 1.6, filterType: .bell),
            EQBand(index: 4, frequency: 5500.0, gain: 1.0, q: 2.0, filterType: .bell),
            EQBand(index: 5, frequency: 11000.0, gain: 2.0, q: 0.8, filterType: .highShelf)
        ],
        isFactory: true
    )

    public static let vocalClarityAndDeEss = EQProfile(
        name: "Vocal Clarity & Dynamic De-Ess",
        category: "Speech",
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

    public static let dialogueIntelligibility = EQProfile(
        name: "Dialogue Intelligibility (Conferencing/Laptop)",
        category: "Speech",
        notes: "Aggressive low-end cleaning and speech formant boost for crystal-clear Zoom/Meet speech comprehension.",
        bands: [
            EQBand(index: 0, frequency: 120.0, gain: 0.0, q: 0.707, filterType: .highPass),
            EQBand(index: 1, frequency: 250.0, gain: -3.5, q: 1.5, filterType: .bell),
            EQBand(index: 2, frequency: 1500.0, gain: 2.0, q: 1.8, filterType: .bell),
            EQBand(index: 3, frequency: 3200.0, gain: 3.5, q: 1.5, filterType: .bell),
            EQBand(index: 4, frequency: 8000.0, gain: -1.0, q: 1.4, filterType: .bell)
        ],
        isFactory: true
    )

    // MARK: - Gaming & Utility

    public static let gamingFPSFootstep = EQProfile(
        name: "Competitive FPS: Footsteps & Spatial Cues",
        category: "Gaming",
        notes: "Cuts muddy explosion rumbles below 150Hz while boosting key 2-4kHz audio cues (footsteps, reload, pin pulls).",
        bands: [
            EQBand(index: 0, frequency: 90.0, gain: 0.0, q: 0.707, filterType: .highPass),
            EQBand(index: 1, frequency: 150.0, gain: -4.0, q: 1.4, filterType: .bell),
            EQBand(index: 2, frequency: 800.0, gain: -1.5, q: 2.0, filterType: .bell),
            EQBand(index: 3, frequency: 2200.0, gain: 3.5, q: 1.8, filterType: .bell),
            EQBand(index: 4, frequency: 4000.0, gain: 3.0, q: 2.2, filterType: .bell),
            EQBand(index: 5, frequency: 12000.0, gain: -1.0, q: 1.0, filterType: .highShelf)
        ],
        stereoWidth: 1.25,
        isFactory: true
    )

    public static let antiFatigueDesk = EQProfile(
        name: "Anti-Fatigue Office & Long Sessions",
        category: "Utility",
        notes: "Subtle psychoacoustic relaxation curve: dips 3.5-5kHz listener fatigue frequencies for hours of coding and focus.",
        bands: [
            EQBand(index: 0, frequency: 30.0, gain: 0.0, q: 0.707, filterType: .highPass),
            EQBand(index: 1, frequency: 120.0, gain: 1.5, q: 1.0, filterType: .lowShelf),
            EQBand(index: 2, frequency: 800.0, gain: 0.5, q: 1.5, filterType: .bell),
            EQBand(index: 3, frequency: 3800.0, gain: -2.8, q: 2.0, filterType: .bell),
            EQBand(index: 4, frequency: 6500.0, gain: -2.0, q: 2.2, filterType: .bell),
            EQBand(index: 5, frequency: 14000.0, gain: -1.0, q: 0.8, filterType: .highShelf)
        ],
        isFactory: true
    )
}
