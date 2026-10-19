import AVFoundation
import Accelerate

/// Listens to the microphone and reports the fundamental frequency of whatever
/// is being played, using the YIN algorithm on overlapping windows.
final class PitchDetector {
    /// Called on the audio thread with the detected frequency (nil when there is
    /// no clear pitch or the signal is below the gate) and the window's RMS level.
    var onPitch: ((Float?, Float) -> Void)?

    private let engine = AVAudioEngine()
    private let windowSize = 2048
    private let hop = 1024
    private var samples: [Float] = []
    private var sampleRate: Float = 48_000

    private let lock = NSLock()
    private var _gate: Float = 0.005
    /// RMS level below which the input counts as silence.
    var gate: Float {
        get { lock.withLock { _gate } }
        set { lock.withLock { _gate = newValue } }
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        // Measurement mode turns off the automatic gain control and voice processing.
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        sampleRate = Float(format.sampleRate)
        samples.removeAll(keepingCapacity: true)
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(hop), format: format) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        samples.append(contentsOf: UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
        while samples.count >= windowSize {
            let window = Array(samples[0..<windowSize])
            samples.removeFirst(hop)
            var rms: Float = 0
            vDSP_rmsqv(window, 1, &rms, vDSP_Length(windowSize))
            let freq = rms >= gate ? Self.yin(window, sampleRate: sampleRate) : nil
            onPitch?(freq, rms)
        }
    }

    /// YIN pitch estimate (de Cheveigné & Kawahara 2002). The range covers a
    /// 7-string guitar's low B up to the top of a 24-fret neck with headroom.
    static func yin(_ x: [Float], sampleRate: Float, minFreq: Float = 55, maxFreq: Float = 1600, threshold: Float = 0.15) -> Float? {
        let tauMax = min(Int(sampleRate / minFreq), x.count / 2)
        let tauMin = max(2, Int(sampleRate / maxFreq))
        // Integration window; tau runs to tauMax + 1 for the interpolation below.
        let w = x.count - tauMax - 1
        var d = [Float](repeating: 0, count: tauMax + 2)

        x.withUnsafeBufferPointer { p in
            let base = p.baseAddress!
            var e0: Float = 0
            vDSP_svesq(base, 1, &e0, vDSP_Length(w))
            var et = e0
            for tau in 1...tauMax + 1 {
                // Energy of x[tau ..< tau + w], slid along one sample at a time.
                et += base[tau + w - 1] * base[tau + w - 1] - base[tau - 1] * base[tau - 1]
                var c: Float = 0
                vDSP_dotpr(base, 1, base + tau, 1, &c, vDSP_Length(w))
                d[tau] = max(0, e0 + et - 2 * c)
            }
        }

        // Cumulative mean normalized difference.
        var cmnd = [Float](repeating: 1, count: tauMax + 2)
        var running: Float = 0
        for tau in 1...tauMax + 1 {
            running += d[tau]
            cmnd[tau] = running > 0 ? d[tau] * Float(tau) / running : 1
        }

        var tau = tauMin
        while tau <= tauMax {
            if cmnd[tau] < threshold {
                while tau + 1 <= tauMax && cmnd[tau + 1] < cmnd[tau] { tau += 1 }
                break
            }
            tau += 1
        }
        if tau > tauMax { return nil }

        let s0 = cmnd[tau - 1], s1 = cmnd[tau], s2 = cmnd[tau + 1]
        let denom = s0 + s2 - 2 * s1
        let refined = denom != 0 ? Float(tau) + (s0 - s2) / (2 * denom) : Float(tau)
        return sampleRate / refined
    }
}
