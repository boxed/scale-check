import AVFoundation
import Observation
import UIKit

/// Turns detected notes into confirmed ones and decides when to flash for a
/// wrong one.
@MainActor
@Observable
final class Listener {
    var isListening = false
    var permissionDenied = false
    var errorMessage: String?
    /// The MIDI notes currently sounding, empty when quiet.
    var currentNotes: Set<Int> = []
    /// The loudest of them.
    var loudestNote: Int?
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
    /// Consecutive windows each note has been found in.
    private var streaks: [Int: Int] = [:]
    /// Confirmed notes, with how many windows in a row each has been missing.
    private var confirmed: [Int: Int] = [:]
    private var silentCount = 0
    private var clearTask: Task<Void, Never>?

    /// Consecutive windows (~21 ms apart) a note must be found in before it
    /// counts. Filters out the noisy pick attack and single-window glitches.
    private let framesToConfirm = 3
    /// Windows a confirmed note may go missing before it's dropped, so the
    /// notes of a ringing chord don't flicker.
    private let framesToDrop = 3
    /// A wrong note must be found this many windows in a row to flash, so a
    /// brief artifact (pick attack, distortion) doesn't.
    private let framesToFlash = 5

    init() {
        detector.gate = gate
        detector.onNotes = { [weak self] notes, rms in
            Task { @MainActor in self?.handle(notes: notes, rms: rms) }
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
        currentNotes = []
        loudestNote = nil
        isWrong = false
        level = 0
        streaks = [:]
        confirmed = [:]
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func handle(notes: [Int], rms: Float) {
        guard isListening else { return }
        level = rms
        let found = Set(notes)
        streaks = Dictionary(uniqueKeysWithValues: found.map { ($0, (streaks[$0] ?? 0) + 1) })
        for note in confirmed.keys where !found.contains(note) {
            confirmed[note]! += 1
            if confirmed[note]! > framesToDrop { confirmed[note] = nil }
        }
        for note in found where streaks[note]! >= framesToConfirm {
            confirmed[note] = 0
        }
        guard !confirmed.isEmpty else {
            silentCount += 1
            if silentCount > 10 {
                currentNotes = []
                loudestNote = nil
            }
            return
        }
        silentCount = 0
        currentNotes = Set(confirmed.keys)
        // Notes come strongest first; while a confirmed one is missing for a
        // window the loudest stays as it was.
        if let loudest = notes.first(where: { confirmed[$0] != nil }) { loudestNote = loudest }
        let pcs = notes.filter { confirmed[$0] != nil }.map { $0 % 12 }
        if isDetecting {
            for pc in pcs where !heard.contains(pc) { heard.append(pc) }
        } else if notes.contains(where: { streaks[$0]! >= framesToFlash && !allowed.contains($0 % 12) }) {
            flash()
        } else if currentNotes.allSatisfy({ allowed.contains($0 % 12) }) {
            // Right notes end the flash at once, so the red never sits
            // behind notes that are in the scale.
            clearTask?.cancel()
            isWrong = false
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
