import AVFoundation
import Accelerate

/// Listens to the microphone and reports the notes being played, chords
/// included, on overlapping windows.
final class PitchDetector {
    /// Called on the audio thread with the MIDI notes found, strongest first
    /// (empty below the gate), and the window's RMS level.
    var onNotes: (([Int], Float) -> Void)?

    private let engine = AVAudioEngine()
    /// ~85 ms at 48 kHz: long enough to tell apart the low notes' partials.
    private let windowSize = 4096
    private let hop = 1024
    private var polyphony: Polyphony?
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
        if polyphony?.sampleRate != sampleRate {
            polyphony = Polyphony(windowSize: windowSize, sampleRate: sampleRate)
        }
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
            let notes = rms >= gate ? polyphony?.notes(window) ?? [] : []
            onNotes?(notes, rms)
        }
    }
}
