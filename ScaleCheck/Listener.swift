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
    /// Cents off the exact pitch for each sounding pitch class (0 = C), from
    /// its loudest note, smoothed over a few windows.
    var tuning: [Int: Float] = [:]
    var isWrong = false
    var level: Float = 0
    /// Pitch classes (0 = C) that are allowed.
    var allowed: Set<Int> = []
    /// In detect mode notes are tallied into `evidence` instead of checked.
    var isDetecting = false {
        didSet { resetHeard() }
    }
    /// Seconds each pitch class has sounded while detecting.
    private(set) var evidence: [Int: Double] = [:]
    /// Pitch classes in the order first played.
    private var heardOrder: [Int] = []

    /// Pitch classes played enough to count, in the order first played. A
    /// note counts once it has 5% of the time heard (at least 0.15 s, at most
    /// 1 s), so a stray resonance or fluffed note doesn't rule scales out.
    var heard: [Int] {
        let threshold = min(max(0.15, 0.05 * evidence.values.reduce(0, +)), 1)
        return heardOrder.filter { evidence[$0, default: 0] >= threshold }
    }

    func resetHeard() {
        evidence = [:]
        heardOrder = []
    }

    /// Fixes a misheard note: drops one that counts, or makes one count by
    /// giving it as much time as the most played note.
    func toggleHeard(_ pc: Int) {
        if heard.contains(pc) {
            evidence[pc] = 0
        } else {
            evidence[pc] = max(evidence.values.max() ?? 0, 0.15)
            if !heardOrder.contains(pc) { heardOrder.append(pc) }
        }
    }

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
    /// Smoothed cents off for each confirmed note.
    private var cents: [Int: Float] = [:]
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
    /// How much of each new tuning reading goes into the shown one: enough to
    /// follow a sung slide or vibrato, while evening out window-to-window noise.
    private let tuningSmoothing: Float = 0.25
    /// Time between windows: the detector's 1024-sample hop at 48 kHz.
    private let windowSeconds = 1024.0 / 48_000

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
        tuning = [:]
        isWrong = false
        level = 0
        streaks = [:]
        confirmed = [:]
        cents = [:]
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func handle(notes detected: [DetectedNote], rms: Float) {
        guard isListening else { return }
        level = rms
        let notes = detected.map(\.note)
        let found = Set(notes)
        streaks = Dictionary(uniqueKeysWithValues: found.map { ($0, (streaks[$0] ?? 0) + 1) })
        for note in confirmed.keys where !found.contains(note) {
            confirmed[note]! += 1
            if confirmed[note]! > framesToDrop { confirmed[note] = nil }
        }
        for note in found where streaks[note]! >= framesToConfirm {
            confirmed[note] = 0
        }
        cents = cents.filter { confirmed[$0.key] != nil }
        for note in detected where confirmed[note.note] != nil {
            guard let reading = note.cents else { continue }
            cents[note.note] = cents[note.note].map { $0 + tuningSmoothing * (reading - $0) } ?? reading
        }
        guard !confirmed.isEmpty else {
            silentCount += 1
            if silentCount > 10 {
                currentNotes = []
                loudestNote = nil
                tuning = [:]
            }
            return
        }
        silentCount = 0
        currentNotes = Set(confirmed.keys)
        var tuning: [Int: Float] = [:]
        for note in notes + confirmed.keys.sorted() where tuning[note % 12] == nil {
            tuning[note % 12] = cents[note]
        }
        self.tuning = tuning
        // Notes come strongest first; while a confirmed one is missing for a
        // window the loudest stays as it was.
        if let loudest = notes.first(where: { confirmed[$0] != nil }) { loudestNote = loudest }
        let pcs = notes.filter { confirmed[$0] != nil }.map { $0 % 12 }
        if isDetecting {
            for pc in Set(pcs) {
                evidence[pc, default: 0] += windowSeconds
                if !heardOrder.contains(pc) { heardOrder.append(pc) }
            }
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
