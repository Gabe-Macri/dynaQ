import SwiftUI
import DynaQCore
import DynaQDSP

/// High-resolution Studio Parametric EQ Curve with real-time FFT spectrum background and draggable nodes.
public struct EQCurveView: View {
    @Binding public var profile: EQProfile
    @Binding public var selectedBandID: UUID?
    public let spectrumDB: [Float]
    public let sampleRate: Float

    private let minFreq: Float = 20.0
    private let maxFreq: Float = 20000.0
    private let minDB: Float = -24.0
    private let maxDB: Float = 24.0

    @State private var hoveredBandIndex: Int? = nil

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
                // 1. Dark Studio Background & Grid
                Canvas { context, size in
                    drawGrid(context: context, size: size)
                    drawOctaveBands(context: context, size: size)
                }

                // 2. Real-time Live Audio Spectrum Analyzer Layer
                if !spectrumDB.isEmpty {
                    SpectrumShape(spectrumDB: spectrumDB)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    DynaQTheme.cyan.opacity(0.32),
                                    DynaQTheme.blue.opacity(0.12),
                                    Color.clear
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }

                // 3. Composite EQ Response Curve
                Path { path in
                    drawCompositeCurve(path: &path, size: geo.size)
                }
                .stroke(
                    LinearGradient(
                        colors: [DynaQTheme.cyan, DynaQTheme.blue, DynaQTheme.amber],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: DynaQTheme.cyan.opacity(0.35), radius: 6)

                // 4. Interactive Draggable Band Nodes with Routing Badges & Tooltips
                ForEach(profile.bands.indices, id: \.self) { index in
                    let band = profile.bands[index]
                    let isSelected = (selectedBandID == band.id)
                    let pt = pointFor(frequency: band.frequency, gainDB: band.gain, size: geo.size)
                    let bandColor = DynaQTheme.bandColors[index % DynaQTheme.bandColors.count]

                    BandNode(
                        band: band,
                        color: bandColor,
                        isSelected: isSelected,
                        position: pt,
                        onDrag: { newPoint in
                            updateBand(at: index, with: newPoint, size: geo.size)
                        },
                        onSelect: {
                            selectedBandID = band.id
                        }
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(DynaQTheme.surfaceBorder, lineWidth: 1)
            )
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

    // MARK: - Drawing Routines

    private func drawOctaveBands(context: GraphicsContext, size: CGSize) {
        // Octave labels along the top edge
        let octaves: [(label: String, startF: Float, endF: Float)] = [
            ("SUB", 20, 60),
            ("BASS", 60, 250),
            ("LOW MID", 250, 500),
            ("MID", 500, 2000),
            ("HIGH MID", 2000, 4000),
            ("PRESENCE", 4000, 6000),
            ("BRILLIANCE", 6000, 20000)
        ]

        for oct in octaves {
            let xStart = xFor(frequency: oct.startF, width: size.width)
            let xEnd = xFor(frequency: oct.endF, width: size.width)
            let midX = (xStart + xEnd) * 0.5

            context.draw(
                Text(oct.label)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(DynaQTheme.textMuted.opacity(0.7)),
                at: CGPoint(x: midX, y: 12)
            )
        }
    }

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        // Frequency lines (vertical)
        let gridFrequencies: [Float] = [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000]
        for f in gridFrequencies {
            let x = xFor(frequency: f, width: size.width)
            var path = Path()
            path.move(to: CGPoint(x: x, y: 20))
            path.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(path, with: .color(DynaQTheme.gridLine), lineWidth: 1)

            let label = f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))"
            context.draw(
                Text(label).font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundColor(DynaQTheme.gridText),
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
                with: .color(isZero ? DynaQTheme.textSecondary.opacity(0.3) : DynaQTheme.gridLine),
                lineWidth: isZero ? 1.5 : 1
            )

            let label = db > 0 ? "+\(Int(db))" : "\(Int(db))"
            context.draw(
                Text(label).font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundColor(DynaQTheme.gridText),
                at: CGPoint(x: 16, y: y - 6)
            )
        }
    }

    private func drawCompositeCurve(path: inout Path, size: CGSize) {
        let samplePoints = 140
        let logMin = log10(minFreq)
        let logMax = log10(maxFreq)

        let activeBands = profile.bands.filter { $0.isEnabled }

        for step in 0...samplePoints {
            let norm = Float(step) / Float(samplePoints)
            let freq = pow(10.0, logMin + norm * (logMax - logMin))

            var totalDB: Float = 0.0
            for band in activeBands {
                let coeffs = BiquadCoefficients.calculate(
                    type: band.filterType,
                    frequency: band.frequency,
                    gainDB: band.gain,
                    q: band.q,
                    sampleRate: sampleRate
                )
                totalDB += coeffs.magnitudeResponse(at: freq, sampleRate: sampleRate)
            }

            let pt = pointFor(frequency: freq, gainDB: totalDB, size: size)
            if step == 0 {
                path.move(to: pt)
            } else {
                path.addLine(to: pt)
            }
        }
    }
}

// MARK: - Draggable Band Handle with Tooltip

private struct BandNode: View {
    let band: EQBand
    let color: Color
    let isSelected: Bool
    let position: CGPoint
    let onDrag: (CGPoint) -> Void
    let onSelect: () -> Void

    @State private var isDragging: Bool = false

    var body: some View {
        ZStack {
            // Live Floating Tooltip when dragged or selected
            if isSelected || isDragging {
                VStack(spacing: 2) {
                    Text("\(band.formattedFrequency) • \(band.formattedGain)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Text("\(band.filterType.shortName) | \(band.routing.shortBadge)")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundColor(color)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(DynaQTheme.surface.opacity(0.95))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(color.opacity(0.5), lineWidth: 1)
                )
                .offset(y: -28)
            }

            // Glow halo when selected
            if isSelected {
                Circle()
                    .stroke(color.opacity(0.4), lineWidth: 6)
                    .frame(width: 32, height: 32)
            }

            // Outer node border
            Circle()
                .fill(DynaQTheme.surface)
                .frame(width: 22, height: 22)
                .overlay(
                    Circle().stroke(color, lineWidth: isSelected ? 2.5 : 1.5)
                )

            // Center band index & routing badge
            Text("\(band.index + 1)")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundColor(isSelected ? Color.white : color)
        }
        .position(position)
        .gesture(
            DragGesture()
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

// MARK: - Spectrum Wave Shape

private struct SpectrumShape: Shape {
    let spectrumDB: [Float]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !spectrumDB.isEmpty else { return path }

        path.move(to: CGPoint(x: 0, y: rect.height))

        let stepX = rect.width / CGFloat(max(spectrumDB.count - 1, 1))
        for (i, db) in spectrumDB.enumerated() {
            let x = CGFloat(i) * stepX
            let norm = CGFloat(min(max((db + 80.0) / 80.0, 0.0), 1.0))
            let y = rect.height - norm * rect.height
            path.addLine(to: CGPoint(x: x, y: y))
        }

        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.closeSubpath()
        return path
    }
}
