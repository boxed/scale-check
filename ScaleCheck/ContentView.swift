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
                pickers
                noteGrid
                Spacer()
                currentNote
                Spacer()
                levelControls
            }
            .padding()
        }
        .onAppear { applySettings() }
        .onChange(of: allowed) { applySettings() }
        .onChange(of: gateDB) { applySettings() }
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
        }
        .pickerStyle(.menu)
        .font(.title3)
    }

    /// All twelve notes from the root up: scale notes filled, the rest faint,
    /// and the note being heard ringed.
    private var noteGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
            ForEach(0..<12, id: \.self) { offset in
                let pc = (root + offset) % 12
                let inScale = allowed.contains(pc)
                let heard = listener.currentNote.map { $0 % 12 == pc } ?? false
                Text(noteName(pc, root: root))
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(inScale ? Color.white : Color.secondary)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(inScale ? (offset == 0 ? Color.orange : Color.accentColor) : Color.secondary.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary, lineWidth: heard ? 3 : 0)
                    )
            }
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

    private var levelControls: some View {
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
