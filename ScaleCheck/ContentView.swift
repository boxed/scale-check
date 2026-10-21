import SwiftUI

struct ContentView: View {
    @AppStorage("root") private var root = 9
    @AppStorage("scale") private var scaleID = "minorPent"
    @AppStorage("gateDB") private var gateDB = -46.0
    @State private var listener = Listener()
    @Environment(\.scenePhase) private var scenePhase

    private var scale: Scale {
        allScales.first { $0.id == scaleID } ?? allScales[0]
    }

    private var allowed: Set<Int> {
        Set(scale.intervals.map { (root + $0) % 12 })
    }

    var body: some View {
        ZStack {
            (listener.isWrong ? Color.red : Color(.systemBackground))
                .ignoresSafeArea()
                .animation(.easeOut(duration: listener.isWrong ? 0.05 : 0.3), value: listener.isWrong)

            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    noteColumn
                    VStack(spacing: 24) {
                        if listener.isDetecting {
                            detectHeader
                            matchList
                        } else {
                            Spacer()
                            currentNote
                            Spacer()
                        }
                        micMessages
                    }
                    .frame(maxWidth: .infinity)
                    LevelMeter(listener: listener, gateDB: $gateDB)
                }
                if !listener.isDetecting {
                    pickers
                }
            }
            .padding()
        }
        .onAppear { applySettings() }
        .onChange(of: allowed) { applySettings() }
        .onChange(of: gateDB) { applySettings() }
        .onChange(of: listener.heard) {
            if let match = detectedScale(heard: listener.heard) { pick(match) }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                #if DEBUG
                if CommandLine.arguments.contains("-demo") {
                    root = 9
                    scaleID = "minorPent"
                    gateDB = -46
                    Task { await listener.runDemo() }
                    return
                }
                #endif
                Task { await listener.start() }
            } else {
                listener.stop()
            }
        }
    }

    private func applySettings() {
        listener.allowed = allowed
        listener.gate = Float(pow(10, gateDB / 20))
    }

    private func pick(_ match: Candidate) {
        root = match.root
        scaleID = match.scale.id
        listener.isDetecting = false
    }

    private var pickers: some View {
        HStack {
            Picker("Root", selection: $root) {
                ForEach(0..<12, id: \.self) { Text(rootNames[$0]).tag($0) }
            }
            Picker("Scale", selection: $scaleID) {
                ForEach(scaleGroups) { group in
                    Section(group.name) {
                        ForEach(group.scales) { Text($0.name).tag($0.id) }
                    }
                }
            }
            .fixedSize()
            Spacer(minLength: 0)
            Button("Detect") { listener.isDetecting = true }
                .buttonStyle(.bordered)
                .font(.body)
        }
        .pickerStyle(.menu)
        .font(.title3)
    }

    private var detectHeader: some View {
        VStack(spacing: 4) {
            HStack {
                Button("Cancel") { listener.isDetecting = false }
                Spacer()
                Button("Reset") { listener.resetHeard() }
                    .disabled(listener.evidence.isEmpty)
            }
            .frame(minHeight: 44)
            Text(detectStatus).font(.headline)
        }
    }

    private var detectStatus: String {
        if listener.heard.isEmpty { return "Play some notes" }
        switch candidates(heard: listener.heard).count {
        case 0: return "No scale matches"
        case 1: return "1 match"
        case let n: return "\(n) matches"
        }
    }

    /// All twelve notes ringing the one being heard, each with its scale degree.
    /// Normally they run from the root down with the scale notes outlined in
    /// blue; while detecting they run from C, filled once played enough to
    /// count (the degrees count from the first one, the likely root), with a
    /// bar of how long each has sounded, and tapping one toggles it in case it
    /// was misheard.
    private var noteColumn: some View {
        let detecting = listener.isDetecting
        let start = detecting ? 0 : root
        let heard = listener.heard
        let degreeRoot = detecting ? heard.first : root
        let mostHeard = listener.evidence.values.max() ?? 0
        return VStack(spacing: 6) {
            ForEach(0..<12, id: \.self) { offset in
                let pc = (start + offset) % 12
                let filled = detecting && heard.contains(pc)
                let inScale = !detecting && allowed.contains(pc)
                let sounding = listener.currentNotes.contains { $0 % 12 == pc }
                HStack(spacing: 6) {
                    Text(noteName(pc, root: start))
                        .font(.headline)
                        .frame(width: 52)
                        .frame(maxHeight: .infinity)
                        .foregroundStyle(filled ? Color.white : inScale ? Color.accentColor : Color.secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(filled ? Color.accentColor : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(sounding ? Color.primary : inScale ? Color.accentColor : Color.secondary.opacity(0.4),
                                              lineWidth: sounding ? 3 : (filled ? 0 : 1.5))
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if detecting { listener.toggleHeard(pc) }
                        }
                    Text(degreeRoot.map { degreeName(pc - $0, in: detecting ? nil : scale) } ?? "")
                        .font(.subheadline)
                        .foregroundStyle(filled || inScale ? Color.primary : Color.secondary)
                        .frame(width: 24, alignment: .leading)
                    if detecting {
                        let share = mostHeard > 0 ? listener.evidence[pc, default: 0] / mostHeard : 0
                        Capsule()
                            .fill(filled ? Color.accentColor : Color.secondary.opacity(0.5))
                            .frame(width: 28 * share, height: 8)
                            .frame(width: 28, alignment: .leading)
                    }
                }
            }
        }
    }

    /// The scales the notes so far fit, each with the notes it adds; tap to pick.
    private var matchList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !listener.heard.isEmpty {
                    ForEach(candidates(heard: listener.heard)) { match in
                        Button { pick(match) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(rootNames[match.root]) \(match.scale.name)")
                                Text(unheardNotes(match))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func unheardNotes(_ match: Candidate) -> String {
        match.scale.intervals
            .map { (match.root + $0) % 12 }
            .filter { !listener.heard.contains($0) }
            .map { "+" + noteName($0, root: match.root) }
            .joined(separator: " ")
    }

    @ViewBuilder
    private var micMessages: some View {
        if listener.permissionDenied {
            Text("Microphone access is off. Enable it in Settings › Privacy › Microphone.")
                .font(.footnote)
                .foregroundStyle(.red)
        }
        if let error = listener.errorMessage {
            Text(error).font(.footnote).foregroundStyle(.red)
        }
    }

    private var currentNote: some View {
        VStack {
            if let note = listener.loudestNote {
                Text(noteName(note % 12, root: root))
                    .font(.system(size: 120, weight: .bold, design: .rounded))
                Text("octave \(note / 12 - 1)")
                    .foregroundStyle(.secondary)
            } else {
                Text("–")
                    .font(.system(size: 120, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
                // Holds the octave line's height so the note doesn't jump.
                Text(" ")
            }
        }
    }
}

/// The mic level, rising from the bottom, with the threshold as a handle that
/// can be dragged up and down. Its own view so the level, which changes ~50
/// times a second, only redraws this.
private struct LevelMeter: View {
    let listener: Listener
    @Binding var gateDB: Double

    private let floorDB = -80.0
    private let gateRange = -70.0 ... -15.0

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let levelDB = 20 * log10(max(Double(listener.level), 1e-6))
            let fraction = min(max((levelDB - floorDB) / -floorDB, 0), 1)
            let gateY = height * (1 - (gateDB - floorDB) / -floorDB)
            ZStack(alignment: .bottom) {
                Capsule().fill(Color.secondary.opacity(0.2))
                    .frame(width: 10)
                Capsule()
                    .fill(levelDB >= gateDB ? Color.green : Color.gray)
                    .frame(width: 10, height: height * fraction)
                Capsule()
                    .fill(Color.primary)
                    .frame(width: 28, height: 6)
                    .position(x: geo.size.width / 2, y: gateY)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    let db = floorDB * (drag.location.y / height)
                    gateDB = min(max(db, gateRange.lowerBound), gateRange.upperBound)
                }
            )
        }
        .frame(width: 36)
        .accessibilityElement()
        .accessibilityLabel("Mic threshold")
        .accessibilityValue("\(Int(gateDB)) dB")
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 2.0 : -2.0
            gateDB = min(max(gateDB + step, gateRange.lowerBound), gateRange.upperBound)
        }
    }
}

#Preview {
    ContentView()
}
