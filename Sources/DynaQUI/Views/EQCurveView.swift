import SwiftUI
import DynaQCore
import DynaQDSP

/// High-performance Studio Parametric EQ Curve with real-time discrete RTA spectrum analyzer and draggable terminal reticle nodes.
/// Optimized for 60fps rendering with precalculated curve caching and zero allocations during audio playback.
public struct EQCurveView: View {
    @Binding public var profile: EQProfile
    @Binding public var selectedBandID: UUID?
    public let spectrumDB: [Float]
    public let sampleRate: Float

    private let minFreq: Float = 20.0
    private let maxFreq: Float = 20000.0
    private let minDB: Float = -24.0
    private let maxDB: Float = 24.0

    // Static precalculated frequency points across 128 logarithmic steps
    private static let samplePoints: Int = 128
    private static let sampleFrequencies: [Float] = {
        let logMin = log10(Float(20.0))
        let logMax = log10(Float(20000.0))
        return (0...samplePoints).map { step in
            let norm = Float(step) / Float(samplePoints)
            return pow(10.0, logMin + norm * (logMax - logMin))
        }
    }()

    @State private var cachedPath: Path = Path()
    @State private var lastViewSize: CGSize = .zero

    public init(
        profile: Binding<EQProfile>,
        selectedBandID: Binding<UUID?>,
        spectrumDB: [Float] = [],
        sampleRate: Float = 48000.0
    ) {
        self._profile = profile
        self._selectedBandID = selectedBandID
        self.spectrumDB = spectrumDB
        self.sampleRate = sampleRate
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                // 1. Terminal Canvas Grid & Frequency Scales
                Canvas { context, size in
                    drawGrid(context: context, size: size)
                    drawOctaveHeader(context: context, size: size)
                }

                // 2. Real-time Discrete RTA Spectrum Analyzer Bars (Hardware Test Instrument Style)
                if !spectrumDB.isEmpty {
                    TerminalSpectrumBars(spectrumDB: spectrumDB)
                        .padding(.bottom, 22) // Leave room for bottom frequency axis
                }

                // 3. Composite EQ Response Curve (Cached Path, Zero Math on Telemetry Ticks)
                cachedPath
                    .stroke(
                        profile.isBypassed ? DynaQTheme.textMuted : DynaQTheme.phosphorGreen,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .square, lineJoin: .miter)
                    )

                // 4. Interactive Draggable Reticle Nodes
                ForEach(profile.bands.indices, id: \.self) { index in
                    let band = profile.bands[index]
                    let isSelected = (selectedBandID == band.id)
                    let pt = pointFor(frequency: band.frequency, gainDB: band.gain, size: geo.size)
                    let bandColor = DynaQTheme.bandColors[index % DynaQTheme.bandColors.count]

                    TerminalBandNode(
                        band: band,
                        color: bandColor,
                        isSelected: isSelected,
                        position: pt,
                        onDrag: { newPoint in
                            updateBand(at: index, with: newPoint, size: geo.size)
                            rebuildCachedPath(size: geo.size)
                        },
                        onSelect: {
                            selectedBandID = band.id
                        }
                    )
                }
            }
            .background(DynaQTheme.bg)
            .overlay(
                Rectangle().stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
            )
            .onAppear {
                lastViewSize = geo.size
                rebuildCachedPath(size: geo.size)
            }
            .onChange(of: geo.size) { _, newSize in
                lastViewSize = newSize
                rebuildCachedPath(size: newSize)
            }
            .onChange(of: profile) { _, _ in
                rebuildCachedPath(size: lastViewSize)
            }
        }
    }

    // MARK: - Frequency & Coordinate Mapping

    private func xFor(frequency: Float, width: CGFloat) -> CGFloat {
        let logMin = log10(minFreq)
        let logMax = log10(maxFreq)
        let norm = (log10(min(max(frequency, minFreq), maxFreq)) - logMin) / (logMax - logMin)
        return CGFloat(norm) * width
    }

    private func frequencyFor(x: CGFloat, width: CGFloat) -> Float {
        let logMin = log10(minFreq)
        let logMax = log10(maxFreq)
        let norm = Float(min(max(x / width, 0.0), 1.0))
        return pow(10.0, logMin + norm * (logMax - logMin))
    }

    private func yFor(gainDB: Float, height: CGFloat) -> CGFloat {
        let norm = (min(max(gainDB, minDB), maxDB) - minDB) / (maxDB - minDB)
        return (1.0 - CGFloat(norm)) * height
    }

    private func gainFor(y: CGFloat, height: CGFloat) -> Float {
        let norm = 1.0 - Float(min(max(y / height, 0.0), 1.0))
        return minDB + norm * (maxDB - minDB)
    }

    private func pointFor(frequency: Float, gainDB: Float, size: CGSize) -> CGPoint {
        return CGPoint(
            x: xFor(frequency: frequency, width: size.width),
            y: yFor(gainDB: gainDB, height: size.height)
        )
    }

    private func updateBand(at index: Int, with point: CGPoint, size: CGSize) {
        guard index < profile.bands.count else { return }
        var band = profile.bands[index]
        band.frequency = frequencyFor(x: point.x, width: size.width)
        if band.filterType.supportsGain {
            band.gain = gainFor(y: point.y, height: size.height)
        }
        profile.bands[index] = band
    }

    // MARK: - High Performance Curve Cache Builder

    private func rebuildCachedPath(size: CGSize) {
        guard size.width > 10, size.height > 10 else { return }

        let activeBands = profile.bands.filter { $0.isEnabled }

        // Compute filter coefficients ONCE per active band (8 calculations instead of 1128!)
        let activeCoeffs = activeBands.map { band in
            BiquadCoefficients.calculate(
                type: band.filterType,
                frequency: band.frequency,
                gainDB: band.gain,
                q: band.q,
                sampleRate: sampleRate
            )
        }

        var path = Path()
        let freqs = Self.sampleFrequencies

        for i in 0..<freqs.count {
            let f = freqs[i]
            var totalDB: Float = profile.preampGain + profile.masterGain

            for c in activeCoeffs {
                totalDB += c.magnitudeResponse(at: f, sampleRate: sampleRate)
            }

            let pt = pointFor(frequency: f, gainDB: totalDB, size: size)
            if i == 0 {
                path.move(to: pt)
            } else {
                path.addLine(to: pt)
            }
        }

        self.cachedPath = path
    }

    // MARK: - Drawing Routines

    private func drawOctaveHeader(context: GraphicsContext, size: CGSize) {
        let octaves: [(label: String, startF: Float, endF: Float)] = [
            ("SUB", 20, 60),
            ("BASS", 60, 250),
            ("LOW-MID", 250, 500),
            ("MID", 500, 2000),
            ("HIGH-MID", 2000, 4000),
            ("PRESENCE", 4000, 6000),
            ("BRILLIANCE", 6000, 20000)
        ]

        for oct in octaves {
            let xStart = xFor(frequency: oct.startF, width: size.width)
            let xEnd = xFor(frequency: oct.endF, width: size.width)
            let midX = (xStart + xEnd) * 0.5

            context.draw(
                Text("[ \(oct.label) ]")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(DynaQTheme.textMuted.opacity(0.8)),
                at: CGPoint(x: midX, y: 10)
            )
        }
    }

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        // Frequency lines (vertical)
        let gridFrequencies: [Float] = [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000]
        for f in gridFrequencies {
            let x = xFor(frequency: f, width: size.width)
            var path = Path()
            path.move(to: CGPoint(x: x, y: 18))
            path.addLine(to: CGPoint(x: x, y: size.height - 20))
            context.stroke(path, with: .color(DynaQTheme.gridLine), lineWidth: 1)

            let label = f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))"
            context.draw(
                Text(label)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(DynaQTheme.gridText),
                at: CGPoint(x: x, y: size.height - 10)
            )
        }

        // Decibel lines (horizontal)
        let gridDBs: [Float] = [18, 12, 6, 0, -6, -12, -18]
        for db in gridDBs {
            let y = yFor(gainDB: db, height: size.height)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            let isZero = (db == 0)
            context.stroke(
                path,
                with: .color(isZero ? DynaQTheme.gridLineZero : DynaQTheme.gridLine),
                lineWidth: isZero ? 1.5 : 1
            )

            let label = db > 0 ? "+\(Int(db))" : "\(Int(db))"
            context.draw(
                Text("\(label) dB")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(isZero ? DynaQTheme.textSecondary : DynaQTheme.gridText),
                at: CGPoint(x: 22, y: y - 6)
            )
        }
    }
}

// MARK: - Discrete RTA Spectrum Bars (Hardware Test Instrument Aesthetic)

private struct TerminalSpectrumBars: View {
    let spectrumDB: [Float]

    var body: some View {
        GeometryReader { geo in
            let barCount = spectrumDB.count
            let spacing: CGFloat = 1.0
            let totalSpacing = spacing * CGFloat(max(barCount - 1, 0))
            let barWidth = max((geo.size.width - totalSpacing) / CGFloat(barCount), 1.0)

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    let db = spectrumDB[i]
                    // Map -80 dB ... 0 dB to 0 ... 1
                    let norm = CGFloat(min(max((db + 80.0) / 80.0, 0.0), 1.0))
                    let barH = max(geo.size.height * norm, 1.0)

                    Rectangle()
                        .fill(DynaQTheme.phosphorGreen.opacity(0.32))
                        .frame(width: barWidth, height: barH)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

// MARK: - Draggable Terminal Reticle Node

private struct TerminalBandNode: View {
    let band: EQBand
    let color: Color
    let isSelected: Bool
    let position: CGPoint
    let onDrag: (CGPoint) -> Void
    let onSelect: () -> Void

    @State private var isDragging: Bool = false

    var body: some View {
        ZStack {
            // Live Monospace Reticle Tooltip
            if isSelected || isDragging {
                VStack(spacing: 2) {
                    Text("[ BAND \(String(format: "%02d", band.index + 1)) // \(band.formattedFrequency) // \(band.formattedGain) ]")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(DynaQTheme.textPrimary)
                    Text("\(band.filterType.shortName) | \(band.routing.shortBadge) | Q:\(String(format: "%.2f", band.q))")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(color)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(DynaQTheme.surfaceElevated)
                .overlay(
                    Rectangle().stroke(color, lineWidth: 1)
                )
                .offset(y: -32)
            }

            // Crosshair tick lines when selected
            if isSelected {
                Group {
                    Rectangle().fill(color.opacity(0.7)).frame(width: 24, height: 1)
                    Rectangle().fill(color.opacity(0.7)).frame(width: 1, height: 24)
                }
            }

            // Reticle square box
            Rectangle()
                .fill(DynaQTheme.surface)
                .frame(width: 18, height: 18)
                .overlay(
                    Rectangle().stroke(color, lineWidth: isSelected ? 2.0 : 1.0)
                )

            // Monospace Band Index Digit
            Text("\(band.index + 1)")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundColor(isSelected ? Color.white : color)
        }
        .position(position)
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { gesture in
                    isDragging = true
                    onSelect()
                    onDrag(gesture.location)
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
        .onTapGesture {
            onSelect()
        }
    }
}
