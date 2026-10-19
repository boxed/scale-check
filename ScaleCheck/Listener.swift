import AVFoundation
import Observation
import UIKit

/// Turns pitch estimates into notes and decides when to flash for a wrong one.
@MainActor
@Observable
final class Listener {
    var isListening = false
    var permissionDenied = false
    var errorMessage: String?
    /// The MIDI note currently sounding, nil when quiet.
    var currentNote: Int?
    var isWrong = false
    var level: Float = 0
    /// Pitch classes (0 = C) that are allowed.
    var allowed: Set<Int> = []
    /// In detect mode notes are collected into `heard` instead of checked.
    var isDetecting = false {
        didSet { heard = [] }
    }
    /// Pitch classes heard while detecting, in the order first played.
    var heard: [Int] = []

    var gate: Float = 0.005 {
        didSet { detector.gate = gate }
    }

    private let detector = PitchDetector()
    /// Set while waiting on the permission prompt, so a second start can't slip in.
    private var isStarting = false
    private var candidate: Int?
    private var candidateCount = 0
    private var silentCount = 0
    private var clearTask: Task<Void, Never>?

    /// Consecutive windows (~21 ms apart) that must agree before a note counts.
    /// Filters out the noisy pick attack and single-window octave glitches.
    private let framesToConfirm = 3

    init() {
        detector.gate = gate
        detector.onPitch = { [weak self] freq, rms in
            Task { @MainActor in self?.handle(freq: freq, rms: rms) }
        }
    }

    func start() async {
        guard !isListening, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        guard await AVAudioApplication.requestRecordPermission() else {
            permissionDenied = true
            return
        }
        permissionDenied = false
        do {
            try detector.start()
            isListening = true
            errorMessage = nil
            UIApplication.shared.isIdleTimerDisabled = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        guard isListening else { return }
        detector.stop()
        isListening = false
        currentNote = nil
        isWrong = false
        level = 0
        candidate = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func handle(freq: Float?, rms: Float) {
        guard isListening else { return }
        level = rms
        guard let freq else {
            candidate = nil
            candidateCount = 0
            silentCount += 1
            if silentCount > 10 { currentNote = nil }
            return
        }
        silentCount = 0
        let note = Int((69 + 12 * log2(freq / 440)).rounded())
        if note == candidate {
            candidateCount += 1
        } else {
            candidate = note
            candidateCount = 1
        }
        guard candidateCount >= framesToConfirm else { return }
        currentNote = note
        let pc = ((note % 12) + 12) % 12
        if isDetecting {
            if !heard.contains(pc) { heard.append(pc) }
        } else if !allowed.contains(pc) {
            flash()
        }
    }

    private func flash() {
        isWrong = true
        clearTask?.cancel()
        clearTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            isWrong = false
        }
    }
}
