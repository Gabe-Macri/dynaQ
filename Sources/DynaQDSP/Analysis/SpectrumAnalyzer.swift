import Foundation
import Accelerate

/// Real-time spectrum analyzer with logarithmic frequency binning and ballistic smoothing.
public final class SpectrumAnalyzer: @unchecked Sendable {
    public let fftSize: Int
    public let binCount: Int
    private let sampleRate: Float

    private var window: [Float]
    private var inputBuffer: [Float]
    private var inputBufferIndex: Int = 0

    // FFT storage
    private var realParts: [Float]
    private var imagParts: [Float]
    private var magnitudes: [Float]
    private var smoothedBinnedDB: [Float]

    private let fftSetup: vDSP_DFT_Setup?

    public init(fftSize: Int = 1024, binCount: Int = 64, sampleRate: Float = 48000.0) {
        self.fftSize = fftSize
        self.binCount = binCount
        self.sampleRate = sampleRate

        self.inputBuffer = [Float](repeating: 0.0, count: fftSize)
        self.realParts = [Float](repeating: 0.0, count: fftSize)
        self.imagParts = [Float](repeating: 0.0, count: fftSize)
        self.magnitudes = [Float](repeating: 0.0, count: fftSize / 2)
        self.smoothedBinnedDB = [Float](repeating: -80.0, count: binCount)

        // Generate Hann window
        var win = [Float](repeating: 0.0, count: fftSize)
        vDSP_hann_window(&win, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        self.window = win

        // Setup DFT
        self.fftSetup = vDSP_DFT_zrop_CreateSetup(
            nil,
            vDSP_Length(fftSize),
            vDSP_DFT_Direction.FORWARD
        )
    }

    deinit {
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
        }
    }

    /// Feed audio samples (mono or downmixed stereo) into analyzer.
    public func feed(samples: UnsafePointer<Float>, count: Int) {
        for i in 0..<count {
            inputBuffer[inputBufferIndex] = samples[i]
            inputBufferIndex += 1
            if inputBufferIndex >= fftSize {
                inputBufferIndex = 0
                computeFFT()
            }
        }
    }

    private func computeFFT() {
        guard let setup = fftSetup else { return }

        // Window the input
        var windowed = [Float](repeating: 0.0, count: fftSize)
        vDSP_vmul(inputBuffer, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        // Split complex format
        var tempReal = [Float](repeating: 0.0, count: fftSize)
        var tempImag = [Float](repeating: 0.0, count: fftSize)
        windowed.withUnsafeBufferPointer { wPtr in
            for i in 0..<fftSize {
                tempReal[i] = wPtr[i]
                tempImag[i] = 0.0
            }
        }

        tempReal.withUnsafeMutableBufferPointer { rPtr in
            tempImag.withUnsafeMutableBufferPointer { iPtr in
                realParts.withUnsafeMutableBufferPointer { outRPtr in
                    imagParts.withUnsafeMutableBufferPointer { outIPtr in
                        vDSP_DFT_Execute(
                            setup,
                            rPtr.baseAddress!,
                            iPtr.baseAddress!,
                            outRPtr.baseAddress!,
                            outIPtr.baseAddress!
                        )
                    }
                }
            }
        }

        // Calculate magnitudes for first half of spectrum (Nyquist)
        let halfSize = fftSize / 2
        for i in 0..<halfSize {
            let r = realParts[i]
            let im = imagParts[i]
            magnitudes[i] = sqrt(r * r + im * im) / Float(fftSize)
        }

        // Map linearly spaced FFT bins to logarithmic visual frequency bins (20Hz to 20kHz)
        let minFreq: Float = 20.0
        let maxFreq: Float = min(20000.0, sampleRate * 0.49)
        let logMin = log10(minFreq)
        let logMax = log10(maxFreq)
        let freqBinResolution = sampleRate / Float(fftSize)

        for b in 0..<binCount {
            let norm = Float(b) / Float(binCount)
            let fCenter = pow(10.0, logMin + norm * (logMax - logMin))
            let fftIndex = min(max(Int(round(fCenter / freqBinResolution)), 0), halfSize - 1)

            let mag = magnitudes[fftIndex]
            let db = mag > 1e-4 ? 20.0 * log10(mag) : -80.0

            // Smooth ballistics (instant attack, slow decay)
            if db > smoothedBinnedDB[b] {
                smoothedBinnedDB[b] = db
            } else {
                smoothedBinnedDB[b] += (db - smoothedBinnedDB[b]) * 0.15
            }
        }
    }

    /// Read the latest logarithmic spectrum dB levels (-80dB to 0dB).
    public func getSpectrumDB() -> [Float] {
        return smoothedBinnedDB
    }
}
