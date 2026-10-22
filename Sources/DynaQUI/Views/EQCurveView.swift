import SwiftUI
import DynaQCore
import DynaQDSP

/// High-performance Studio Parametric EQ Curve with zero-allocation discrete RTA spectrum analyzer,
/// Frequency Modulation (FM) visual sweep zones, and draggable precision terminal reticle nodes.
/// Tuned for 120fps display refresh with cached vector paths and direct Canvas rendering.
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
    @State private var isDraggingNode: Bool = false

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

                // 2. Real-time Discrete RTA Spectrum Analyzer Bars (Zero-Allocation Canvas)
                if !spectrumDB.isEmpty {
                    TerminalSpectrumCanvas(spectrumDB: spectrumDB)
                        .padding(.bottom, 22)
                }

                // 3. FM Modulation Sweep Bands (Visualizes active Frequency Modulation zones)
                ForEach(profile.bands.indices, id: \.self) { index in
                    let band = profile.bands[index]
                    if band.isFMEnabled && band.isEnabled {
                        let color = DynaQTheme.bandColors[index % DynaQTheme.bandColors.count]
                        FMSweepBandOverlay(
                            band: band,
                            color: color,
                            size: geo.size,
                            xForFreq: { xFor(frequency: $0, width: geo.size.width) }
                        )
                    }
                }

                // 4. Composite EQ Response Curve
                cachedPath
                    .stroke(
                        profile.isBypassed ? DynaQTheme.textMuted : DynaQTheme.phosphorGreen,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .square, lineJoin: .miter)
                    )

                // 5. Interactive Draggable Reticle Nodes
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
                        onDragStart: {
                            isDraggingNode = true
                        },
                        onDrag: { newPoint in
                            updateBand(at: index, with: newPoint, size: geo.size)
                            rebuildCachedPath(size: geo.size)
                        },
                        onDragEnd: {
                            isDraggingNode = false
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
                if !isDraggingNode {
                    rebuildCachedPath(size: lastViewSize)
                }
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

        let anySolo = profile.bands.contains { $0.isSolo }
        let activeBands = profile.bands.filter { b in
            anySolo ? (b.isSolo && b.isEnabled) : b.isEnabled
        }

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

// MARK: - Zero-Allocation Canvas RTA Spectrum Bars

private struct TerminalSpectrumCanvas: View {
    let spectrumDB: [Float]

    var body: some View {
        Canvas { context, size in
            let barCount = spectrumDB.count
            guard barCount > 0 else { return }
            let spacing: CGFloat = 1.0
            let totalSpacing = spacing * CGFloat(barCount - 1)
            let barWidth = max((size.width - totalSpacing) / CGFloat(barCount), 1.0)

            for i in 0..<barCount {
                let db = spectrumDB[i]
                let norm = CGFloat(min(max((db + 80.0) / 80.0, 0.0), 1.0))
                let barH = max(size.height * norm, 1.0)
                let x = CGFloat(i) * (barWidth + spacing)
                let y = size.height - barH
                let rect = CGRect(x: x, y: y, width: barWidth, height: barH)
                context.fill(Path(rect), with: .color(DynaQTheme.phosphorGreen.opacity(0.32)))
            }
        }
    }
}

// MARK: - Frequency Modulation (FM) Sweep Visualizer

private struct FMSweepBandOverlay: View {
    let band: EQBand
    let color: Color
    let size: CGSize
    let xForFreq: (Float) -> CGFloat

    var body: some View {
        let fLow = band.frequency * pow(2.0, -abs(band.fmDepth))
        let fHigh = band.frequency * pow(2.0, abs(band.fmDepth))
        let x1 = xForFreq(max(fLow, 20.0))
        let x2 = xForFreq(min(fHigh, 20000.0))
        let width = max(x2 - x1, 4.0)

        Rectangle()
            .fill(color.opacity(0.08))
            .frame(width: width, height: size.height)
            .position(x: x1 + width / 2.0, y: size.height / 2.0)
            .overlay(
                Rectangle()
                    .stroke(color.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: width, height: size.height)
                    .position(x: x1 + width / 2.0, y: size.height / 2.0)
            )
    }
}

// MARK: - Draggable Terminal Reticle Node

private struct TerminalBandNode: View {
    let band: EQBand
    let color: Color
    let isSelected: Bool
    let position: CGPoint
    let onDragStart: () -> Void
    let onDrag: (CGPoint) -> Void
    let onDragEnd: () -> Void
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
                    HStack(spacing: 4) {
                        Text("\(band.filterType.shortName) | \(band.routing.shortBadge) | Q:\(String(format: "%.2f", band.q))")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(color)
                        if band.isFMEnabled {
                            Text("| FM:\(band.fmMode.shortBadge) \(String(format: "%+.1f", band.fmDepth))Oct")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(DynaQTheme.terminalCyan)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(DynaQTheme.surfaceElevated)
                .overlay(
                    Rectangle().stroke(color, lineWidth: 1)
                )
                .offset(y: -34)
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
                    if !isDragging {
                        isDragging = true
                        onDragStart()
                    }
                    onSelect()
                    onDrag(gesture.location)
                }
                .onEnded { _ in
                    isDragging = false
                    onDragEnd()
                }
        )
        .onTapGesture {
            onSelect()
        }
    }
}
