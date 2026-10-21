import Foundation
import Accelerate

/// High-performance spectrum analyzer with precomputed logarithmic frequency bins and fast FFT execution.
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
    private var windowedScratch: [Float]
    private var tempImagScratch: [Float]

    // Precomputed bin-to-FFT index mapping for zero-alloc zero-math runtime
    private var binToFFTIndex: [Int]

    private let fftSetup: vDSP_DFT_Setup?
    private let lock = NSLock()

    public init(fftSize: Int = 1024, binCount: Int = 64, sampleRate: Float = 48000.0) {
        self.fftSize = fftSize
        self.binCount = binCount
        self.sampleRate = sampleRate

        self.inputBuffer = [Float](repeating: 0.0, count: fftSize)
        self.realParts = [Float](repeating: 0.0, count: fftSize)
        self.imagParts = [Float](repeating: 0.0, count: fftSize)
        self.windowedScratch = [Float](repeating: 0.0, count: fftSize)
        self.tempImagScratch = [Float](repeating: 0.0, count: fftSize)
        let halfSize = fftSize / 2
        self.magnitudes = [Float](repeating: 0.0, count: halfSize)
        self.smoothedBinnedDB = [Float](repeating: -80.0, count: binCount)

        // Precompute Hann window
        var win = [Float](repeating: 0.0, count: fftSize)
        vDSP_hann_window(&win, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        self.window = win

        // Setup DFT
        self.fftSetup = vDSP_DFT_zrop_CreateSetup(
            nil,
            vDSP_Length(fftSize),
            vDSP_DFT_Direction.FORWARD
        )

        // Precompute logarithmic frequency mapping table
        let minFreq: Float = 20.0
        let maxFreq: Float = min(20000.0, sampleRate * 0.49)
        let logMin = log10(minFreq)
        let logMax = log10(maxFreq)
        let freqBinResolution = sampleRate / Float(fftSize)

        var map = [Int](repeating: 0, count: binCount)
        for b in 0..<binCount {
            let norm = Float(b) / Float(binCount)
            let fCenter = pow(10.0, logMin + norm * (logMax - logMin))
            let fftIndex = min(max(Int(round(fCenter / freqBinResolution)), 0), halfSize - 1)
            map[b] = fftIndex
        }
        self.binToFFTIndex = map
    }

    deinit {
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
        }
    }

    /// Feed audio samples into analyzer.
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

        // Window the input in-place into scratch buffer
        vDSP_vmul(inputBuffer, 1, window, 1, &windowedScratch, 1, vDSP_Length(fftSize))

        windowedScratch.withUnsafeBufferPointer { wPtr in
            realParts.withUnsafeMutableBufferPointer { outRPtr in
                imagParts.withUnsafeMutableBufferPointer { outIPtr in
                    tempImagScratch.withUnsafeMutableBufferPointer { tIPtr in
                        vDSP_DFT_Execute(
                            setup,
                            wPtr.baseAddress!,
                            tIPtr.baseAddress!,
                            outRPtr.baseAddress!,
                            outIPtr.baseAddress!
                        )
                    }
                }
            }
        }

        let halfSize = fftSize / 2
        var invSize = 1.0 / Float(fftSize)

        // Hardware-accelerated SIMD magnitude calculation
        realParts.withUnsafeBufferPointer { rPtr in
            imagParts.withUnsafeBufferPointer { iPtr in
                var split = DSPSplitComplex(
                    realp: UnsafeMutablePointer(mutating: rPtr.baseAddress!),
                    imagp: UnsafeMutablePointer(mutating: iPtr.baseAddress!)
                )
                magnitudes.withUnsafeMutableBufferPointer { mPtr in
                    vDSP_zvabs(&split, 1, mPtr.baseAddress!, 1, vDSP_Length(halfSize))
                    vDSP_vsmul(mPtr.baseAddress!, 1, &invSize, mPtr.baseAddress!, 1, vDSP_Length(halfSize))
                }
            }
        }

        // Apply precomputed logarithmic bins
        lock.lock()
        defer { lock.unlock() }

        for b in 0..<binCount {
            let fftIndex = binToFFTIndex[b]
            let mag = magnitudes[fftIndex]
            let db = mag > 1e-4 ? 20.0 * log10(mag) : -80.0

            if db > smoothedBinnedDB[b] {
                smoothedBinnedDB[b] = db
            } else {
                smoothedBinnedDB[b] += (db - smoothedBinnedDB[b]) * 0.18
            }
        }
    }

    /// Read the latest logarithmic spectrum dB levels.
    public func getSpectrumDB() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return smoothedBinnedDB
    }
}
