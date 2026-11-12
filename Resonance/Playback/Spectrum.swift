import Accelerate
import AVFoundation
import QuartzCore

/// Turns a block of samples into [bandCount] levels (0...1) on a logarithmic frequency scale.
final class SpectrumAnalyzer {
    static let bandCount = 16
    private let n = 1024
    private let log2n = vDSP_Length(10)
    private let setup: FFTSetup
    private var window: [Float]
    private var peak: Float = 1e-3

    init() {
        setup = vDSP_create_fftsetup(vDSP_Length(10), FFTRadix(kFFTRadix2))!
        window = [Float](repeating: 0, count: 1024)
        vDSP_hann_window(&window, vDSP_Length(1024), Int32(vDSP_HANN_NORM))
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    func process(_ samples: UnsafePointer<Float>, count: Int, sampleRate: Float) -> [Float] {
        var input = [Float](repeating: 0, count: n)
        for i in 0..<min(count, n) { input[i] = samples[i] }
        var windowed = [Float](repeating: 0, count: n)
        vDSP_vmul(input, 1, window, 1, &windowed, 1, vDSP_Length(n))

        var real = [Float](repeating: 0, count: n / 2)
        var imag = [Float](repeating: 0, count: n / 2)
        var mags = [Float](repeating: 0, count: n / 2)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { wp in
                    wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { cp in
                        vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(n / 2))
            }
        }

        let binWidth = sampleRate / Float(n)
        let low: Float = 50
        let high = min(14_000, sampleRate / 2 - 1)
        let ratio = high / low
        var raw = [Float](repeating: 0, count: Self.bandCount)
        for band in 0..<Self.bandCount {
            let f0 = low * powf(ratio, Float(band) / Float(Self.bandCount))
            let f1 = low * powf(ratio, Float(band + 1) / Float(Self.bandCount))
            let b0 = max(1, Int(f0 / binWidth))
            let b1 = min(n / 2 - 1, max(b0 + 1, Int(f1 / binWidth)))
            var sum: Float = 0
            for b in b0..<b1 { sum += mags[b] }
            // Higher bands carry less energy; tilt them up so the whole ring moves.
            raw[band] = sqrtf(sum / Float(b1 - b0)) * (1 + Float(band) * 0.22)
        }
        let top = raw.max() ?? 0
        peak = max(peak * 0.993, top, 1e-3)
        return raw.map { min(1, powf($0 / peak, 0.8)) }
    }
}

/// Published spectrum for the player's ring. It listens to the main mixer only while [active].
final class SpectrumModel: ObservableObject {
    @Published private(set) var bands = [Float](repeating: 0, count: SpectrumAnalyzer.bandCount)
    var active = false

    private let analyzer = SpectrumAnalyzer()
    private var attachedTo: AVAudioNode?

    func attach(to node: AVAudioNode) {
        guard attachedTo == nil else { return }
        attachedTo = node
        node.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let self, self.active, let channel = buffer.floatChannelData?[0] else { return }
            let levels = self.analyzer.process(channel, count: Int(buffer.frameLength), sampleRate: Float(buffer.format.sampleRate))
            DispatchQueue.main.async { self.push(levels) }
        }
    }

    /// Rises quickly, falls slowly: this is what makes a visualizer feel alive.
    private func push(_ levels: [Float]) {
        var next = bands
        for i in 0..<min(next.count, levels.count) {
            next[i] += (levels[i] - next[i]) * (levels[i] > next[i] ? 0.6 : 0.14)
        }
        bands = next
    }

    func calm() {
        bands = [Float](repeating: 0, count: SpectrumAnalyzer.bandCount)
    }
}
