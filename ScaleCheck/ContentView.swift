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

            VStack(spacing: 24) {
                if listener.isDetecting {
                    detectHeader
                    noteGrid
                    matchList
                } else {
                    pickers
                    noteGrid
                    Spacer()
                    currentNote
                    Spacer()
                }
                LevelControls(listener: listener, gateDB: $gateDB)
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

    /// All twelve notes ringing the one being heard. Normally they run from the
    /// root up with the scale notes filled; while detecting they run from C,
    /// filled as they are heard (the first one, the likely root, in orange), and
    /// tapping one toggles it in case it was misheard.
    private var noteGrid: some View {
        let detecting = listener.isDetecting
        let start = detecting ? 0 : root
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
            ForEach(0..<12, id: \.self) { offset in
                let pc = (start + offset) % 12
                let filled = detecting ? listener.heard.contains(pc) : allowed.contains(pc)
                let isRoot = detecting ? listener.heard.first == pc : offset == 0
                let sounding = listener.currentNote.map { $0 % 12 == pc } ?? false
                Text(noteName(pc, root: start))
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(filled ? Color.white : Color.secondary)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(filled ? (isRoot ? Color.orange : Color.accentColor) : Color.secondary.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary, lineWidth: sounding ? 3 : 0)
                    )
                    .onTapGesture {
                        guard detecting else { return }
                        if let i = listener.heard.firstIndex(of: pc) {
                            listener.heard.remove(at: i)
                        } else {
                            listener.heard.append(pc)
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

/// Its own view so the level, which changes ~50 times a second, only redraws this.
private struct LevelControls: View {
    let listener: Listener
    @Binding var gateDB: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let levelDB = 20 * log10(max(Double(listener.level), 1e-6))
                let fraction = (levelDB + 80) / 80
                let gateFraction = (gateDB + 80) / 80
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.2))
                    Capsule()
                        .fill(levelDB >= gateDB ? Color.green : Color.gray)
                        .frame(width: geo.size.width * min(max(fraction, 0), 1))
                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: 2)
                        .offset(x: geo.size.width * gateFraction - 1)
                }
            }
            .frame(height: 8)
            HStack {
                Text("Mic threshold")
                Slider(value: $gateDB, in: -70 ... -15)
            }
            .font(.footnote)
            if listener.permissionDenied {
                Text("Microphone access is off. Enable it in Settings › Privacy › Microphone.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if let error = listener.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
    }
}

#Preview {
    ContentView()
}
