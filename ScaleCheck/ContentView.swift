import SwiftUI

struct ContentView: View {
    @AppStorage("root") private var root = 9
    @AppStorage("scale") private var scaleID = "minorPent"
    @AppStorage("gateDB") private var gateDB = -46.0
    /// Intervals tapped on or off the picked scale, comma separated.
    @AppStorage("toggled") private var toggledStorage = ""
    @State private var listener = Listener()
    @Environment(\.scenePhase) private var scenePhase

    private var scale: Scale {
        allScales.first { $0.id == scaleID } ?? allScales[0]
    }

    private var toggled: Set<Int> {
        Set(toggledStorage.split(separator: ",").compactMap { Int($0) })
    }

    private var allowed: Set<Int> {
        Set(Set(scale.intervals).symmetricDifference(toggled).map { (root + $0) % 12 })
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
        .onChange(of: root) { toggledStorage = "" }
        .onChange(of: scaleID) { toggledStorage = "" }
        .onChange(of: listener.heard) {
            if let match = detectedScale(heard: listener.heard) { pick(match) }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
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
        HStack {
            Button("Cancel") { listener.isDetecting = false }
            Spacer()
            Text(detectStatus).font(.headline)
            Spacer()
            Button("Reset") { listener.heard = [] }
                .disabled(listener.heard.isEmpty)
        }
        .frame(minHeight: 44)
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
    /// Normally they run from the root down with the scale notes filled; while
    /// detecting they run from C, filled as they are heard (the degrees count
    /// from the first one, the likely root). Tapping one toggles it: in the
    /// scale, or among the heard notes in case it was misheard.
    private var noteColumn: some View {
        let detecting = listener.isDetecting
        let start = detecting ? 0 : root
        let degreeRoot = detecting ? listener.heard.first : root
        return VStack(spacing: 6) {
            ForEach(0..<12, id: \.self) { offset in
                let pc = (start + offset) % 12
                let filled = detecting ? listener.heard.contains(pc) : allowed.contains(pc)
                let sounding = listener.currentNote.map { $0 % 12 == pc } ?? false
                // Blue for the picked scale's notes, gray for ones tapped on;
                // outlined when off.
                let color = detecting || scale.intervals.contains(offset) ? Color.accentColor : Color(.systemGray)
                let outline = !detecting && scale.intervals.contains(offset) ? Color.accentColor : Color.secondary.opacity(0.4)
                HStack(spacing: 6) {
                    Text(noteName(pc, root: start))
                        .font(.headline)
                        .frame(width: 52)
                        .frame(maxHeight: .infinity)
                        .foregroundStyle(filled ? Color.white : Color.secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(filled ? color : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(sounding ? Color.primary : outline,
                                              lineWidth: sounding ? 3 : (filled ? 0 : 1.5))
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if detecting {
                                if let i = listener.heard.firstIndex(of: pc) {
                                    listener.heard.remove(at: i)
                                } else {
                                    listener.heard.append(pc)
                                }
                            } else {
                                toggledStorage = toggled.symmetricDifference([offset])
                                    .sorted().map(String.init).joined(separator: ",")
                            }
                        }
                    Text(degreeRoot.map { degreeName(pc - $0, in: detecting ? nil : scale) } ?? "")
                        .font(.subheadline)
                        .foregroundStyle(filled ? Color.primary : Color.secondary)
                        .frame(width: 24, alignment: .leading)
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
                            HStack {
                                Text("\(rootNames[match.root]) \(match.scale.name)")
                                Spacer()
                                Text(unheardNotes(match))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 10)
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
            if let note = listener.currentNote {
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
