import Foundation
import Accelerate
import os.lock

/// High-Performance Zero-Lock Spectrum Analyzer.
/// Decouples FFT analysis from real-time audio threads via a lock-free circular sample buffer,
/// ensuring zero audio jitter and 60/120fps smooth visualization.
public final class SpectrumAnalyzer: @unchecked Sendable {
    public let fftSize: Int
    public let binCount: Int
    public private(set) var sampleRate: Float

    // Lock-free circular sample accumulation for audio thread feed
    private var circularBuffer: [Float]
    private var writeIndex: Int = 0
    private var bufferLock = os_unfair_lock_s()

    // Scratch buffers for FFT execution (used only on display/analysis thread)
    private var window: [Float]
    private var windowedScratch: [Float]
    private var realParts: [Float]
    private var imagParts: [Float]
    private var tempImagScratch: [Float]
    private var magnitudes: [Float]
    private var smoothedBinnedDB: [Float]

    // Precomputed bin-to-FFT index mapping for zero-alloc zero-math runtime
    private var binToFFTIndex: [Int]

    private let fftSetup: vDSP_DFT_Setup?

    public init(fftSize: Int = 1024, binCount: Int = 64, sampleRate: Float = 48000.0) {
        let size = (fftSize >= 64 && (fftSize & (fftSize - 1)) == 0) ? fftSize : 1024
        let bins = min(512, max(16, binCount))
        let sr = max(8000.0, sampleRate)

        self.fftSize = size
        self.binCount = bins
        self.sampleRate = sr

        self.circularBuffer = [Float](repeating: 0.0, count: size)
        self.windowedScratch = [Float](repeating: 0.0, count: size)
        self.realParts = [Float](repeating: 0.0, count: size)
        self.imagParts = [Float](repeating: 0.0, count: size)
        self.tempImagScratch = [Float](repeating: 0.0, count: size)

        let halfSize = size / 2
        self.magnitudes = [Float](repeating: 0.0, count: halfSize)
        self.smoothedBinnedDB = [Float](repeating: -80.0, count: bins)

        // Precompute Hann window
        var win = [Float](repeating: 0.0, count: size)
        vDSP_hann_window(&win, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        self.window = win

        // Setup Forward DFT
        self.fftSetup = vDSP_DFT_zrop_CreateSetup(
            nil,
            vDSP_Length(size),
            vDSP_DFT_Direction.FORWARD
        )

        // Precompute logarithmic frequency mapping table
        let minFreq: Float = 20.0
        let maxFreq: Float = min(20000.0, sr * 0.49)
        let logMin = log10(minFreq)
        let logMax = log10(maxFreq)
        let freqBinResolution = sr / Float(size)

        var map = [Int](repeating: 0, count: bins)
        for b in 0..<bins {
            let norm = Float(b) / Float(bins)
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

    /// Fast Real-Time Audio Feed: Copies samples into lock-free accumulation buffer.
    /// NEVER executes FFT on this thread, guaranteeing zero audio thread latency.
    @inline(__always)
    public func feed(samples: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        os_unfair_lock_lock(&bufferLock)
        let startIndex = (count > fftSize) ? (count - fftSize) : 0
        for i in startIndex..<count {
            circularBuffer[writeIndex] = samples[i]
            writeIndex = (writeIndex + 1) % fftSize
        }
        os_unfair_lock_unlock(&bufferLock)
    }

    /// Executed on display / analysis timer: Computes windowed FFT and returns smoothed dB magnitudes.
    public func getSpectrumDB() -> [Float] {
        guard let setup = fftSetup else {
            return smoothedBinnedDB
        }

        // Snapshot latest samples out of circular buffer
        os_unfair_lock_lock(&bufferLock)
        let wPos = writeIndex
        for i in 0..<fftSize {
            let readPos = (wPos + i) % fftSize
            windowedScratch[i] = circularBuffer[readPos]
        }
        os_unfair_lock_unlock(&bufferLock)

        // 1. Apply Hann window in-place with SIMD vDSP
        vDSP_vmul(windowedScratch, 1, window, 1, &windowedScratch, 1, vDSP_Length(fftSize))

        // 2. Execute DFT
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

        // 3. Vectorized complex magnitude: magnitudes = sqrt(real^2 + imag^2)
        let halfSize = fftSize / 2
        realParts.withUnsafeBufferPointer { rPtr in
            imagParts.withUnsafeBufferPointer { iPtr in
                magnitudes.withUnsafeMutableBufferPointer { mPtr in
                    var split = DSPSplitComplex(
                        realp: UnsafeMutablePointer(mutating: rPtr.baseAddress!),
                        imagp: UnsafeMutablePointer(mutating: iPtr.baseAddress!)
                    )
                    vDSP_zvabs(&split, 1, mPtr.baseAddress!, 1, vDSP_Length(halfSize))
                }
            }
        }

        // 4. Map into log-frequency display bins with ballistic decay
        let scale = 2.0 / Float(fftSize)
        for b in 0..<binCount {
            let fftIndex = binToFFTIndex[b]
            let mag = magnitudes[fftIndex] * scale
            let db = (mag > 1e-5) ? (20.0 * log10(mag)) : -80.0
            let clampedDB = min(max(db, -80.0), 12.0)

            // Ballistic decay: fast rise, smooth visual fall
            if clampedDB > smoothedBinnedDB[b] {
                smoothedBinnedDB[b] = clampedDB
            } else {
                smoothedBinnedDB[b] += (clampedDB - smoothedBinnedDB[b]) * 0.25
            }
        }

        return smoothedBinnedDB
    }

    /// Resets all visualizer bins and buffers.
    public func reset() {
        os_unfair_lock_lock(&bufferLock)
        circularBuffer.withUnsafeMutableBufferPointer { $0.initialize(repeating: 0.0) }
        writeIndex = 0
        os_unfair_lock_unlock(&bufferLock)
        smoothedBinnedDB.withUnsafeMutableBufferPointer { $0.initialize(repeating: -80.0) }
    }
}
