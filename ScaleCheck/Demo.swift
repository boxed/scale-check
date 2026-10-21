#if DEBUG
import Foundation

/// A scripted performance fed through the listener in place of the mic, for
/// recording the README's demo (tools/record-demo.sh). Launched with `-demo`.
enum DemoStep {
    /// Notes loudest first, as the detector reports them.
    case play([Int], seconds: Double)
    case rest(seconds: Double)
    case detect
}

let demoScript: [DemoStep] = {
    var steps: [DemoStep] = [.rest(seconds: 1.2)]
    func melody(_ notes: [Int], seconds: Double = 0.45) {
        for note in notes {
            steps.append(.play([note], seconds: seconds))
            steps.append(.rest(seconds: 0.08))
        }
    }
    // Up A minor pentatonic, a slip onto B♭, and back down.
    melody([57, 60, 62, 64, 67, 69])
    melody([70], seconds: 0.6)
    melody([69, 67, 64])
    steps.append(.rest(seconds: 0.5))
    // An A minor chord, then one with an F sneaking in.
    steps.append(.play([45, 52, 57, 60, 64], seconds: 1.4))
    steps.append(.rest(seconds: 0.4))
    steps.append(.play([53, 57, 60], seconds: 1.0))
    steps.append(.rest(seconds: 0.8))
    // Detect: a D major scale narrows it down to D major.
    steps.append(.detect)
    steps.append(.rest(seconds: 0.8))
    melody([62, 64, 66, 67, 69, 71, 73], seconds: 0.5)
    steps.append(.rest(seconds: 2.0))
    return steps
}()

extension Listener {
    /// Plays `demoScript` through the same per-window handling the mic gets,
    /// then quits so the recording script knows it's done.
    func runDemo() async {
        isListening = true
        let window = Duration.milliseconds(21)
        for step in demoScript {
            switch step {
            case .detect:
                isDetecting = true
            case let .play(notes, seconds):
                // The level decays like a plucked string.
                let frames = Int(seconds / 0.021)
                for frame in 0..<frames {
                    let rms = 0.08 * Float(exp(-2.0 * Double(frame) * 0.021))
                    handle(notes: notes, rms: rms)
                    try? await Task.sleep(for: window)
                }
            case let .rest(seconds):
                for _ in 0..<Int(seconds / 0.021) {
                    handle(notes: [], rms: 0.001)
                    try? await Task.sleep(for: window)
                }
            }
        }
        exit(0)
    }
}
#endif
