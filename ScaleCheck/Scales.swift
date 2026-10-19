import Foundation

/// The scales from caged (src/Main.elm `scaleIntervals`). The Diagonal family is
/// left out: those are fingering patterns over the same note sets as the
/// pentatonic/major/minor entries, so they would check exactly the same notes.
struct Scale: Identifiable, Hashable {
    let id: String
    let name: String
    let intervals: [Int]
}

struct ScaleGroup: Identifiable {
    let name: String
    let scales: [Scale]
    var id: String { name }
}

let scaleGroups: [ScaleGroup] = [
    ScaleGroup(name: "Pentatonic", scales: [
        Scale(id: "majorPent", name: "Major Pentatonic", intervals: [0, 2, 4, 7, 9]),
        Scale(id: "minorPent", name: "Minor Pentatonic", intervals: [0, 3, 5, 7, 10]),
        Scale(id: "blues", name: "Blues", intervals: [0, 3, 5, 6, 7, 10]),
    ]),
    ScaleGroup(name: "Modes", scales: [
        Scale(id: "ionian", name: "Major (Ionian)", intervals: [0, 2, 4, 5, 7, 9, 11]),
        Scale(id: "dorian", name: "Dorian", intervals: [0, 2, 3, 5, 7, 9, 10]),
        Scale(id: "phrygian", name: "Phrygian", intervals: [0, 1, 3, 5, 7, 8, 10]),
        Scale(id: "lydian", name: "Lydian", intervals: [0, 2, 4, 6, 7, 9, 11]),
        Scale(id: "mixolydian", name: "Mixolydian", intervals: [0, 2, 4, 5, 7, 9, 10]),
        Scale(id: "aeolian", name: "Minor (Aeolian)", intervals: [0, 2, 3, 5, 7, 8, 10]),
        Scale(id: "locrian", name: "Locrian", intervals: [0, 1, 3, 5, 6, 8, 10]),
    ]),
    ScaleGroup(name: "Harmonic", scales: [
        Scale(id: "harmonicMajor", name: "Harmonic Major", intervals: [0, 2, 4, 5, 7, 8, 11]),
        Scale(id: "harmonicMinor", name: "Harmonic Minor", intervals: [0, 2, 3, 5, 7, 8, 11]),
    ]),
    ScaleGroup(name: "Melodic", scales: [
        Scale(id: "melodicMajor", name: "Melodic Major", intervals: [0, 2, 4, 5, 7, 8, 10]),
        Scale(id: "melodicMinor", name: "Melodic Minor", intervals: [0, 2, 3, 5, 7, 9, 11]),
    ]),
    ScaleGroup(name: "Triads", scales: [
        Scale(id: "triadMajor", name: "Major Triad", intervals: [0, 4, 7]),
        Scale(id: "triadMinor", name: "Minor Triad", intervals: [0, 3, 7]),
        Scale(id: "triadDim", name: "Diminished Triad", intervals: [0, 3, 6]),
        Scale(id: "triadAug", name: "Augmented Triad", intervals: [0, 4, 8]),
    ]),
]

let allScales: [Scale] = scaleGroups.flatMap(\.scales)

struct Candidate: Identifiable, Hashable {
    let root: Int
    let scale: Scale
    let notes: Set<Int>
    var id: String { "\(root)-\(scale.id)" }

    init(root: Int, scale: Scale) {
        self.root = root
        self.scale = scale
        notes = Set(scale.intervals.map { (root + $0) % 12 })
    }
}

private let allCandidates = (0..<12).flatMap { root in allScales.map { Candidate(root: root, scale: $0) } }
private let pickerOrder = Dictionary(uniqueKeysWithValues: allScales.enumerated().map { ($1.id, $0) })

/// Every root + scale containing all the `heard` pitch classes, best guess
/// first: fewest notes not yet heard, then rooted on the first note heard
/// (players usually start on the tonic), then picker order.
func candidates(heard: [Int]) -> [Candidate] {
    let heardSet = Set(heard)
    func key(_ c: Candidate) -> (Int, Int, Int, Int) {
        (c.notes.count, c.root == heard.first ? 0 : 1, pickerOrder[c.scale.id]!, c.root)
    }
    return allCandidates
        .filter { heardSet.isSubset(of: $0.notes) }
        .sorted { key($0) < key($1) }
}

/// The scale to pick once the heard notes leave a single note set. Scales that
/// share a note set (A minor pentatonic and C major pentatonic, the seven
/// modes of a key) can't be told apart by ear, so the root breaks the tie.
func detectedScale(heard: [Int]) -> Candidate? {
    guard !heard.isEmpty else { return nil }
    let matches = candidates(heard: heard)
    return Set(matches.map(\.notes)).count == 1 ? matches.first : nil
}

let rootNames = ["C", "D♭", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]

private let sharpNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
private let flatNames = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]

/// Name of pitch class `pc`, using flats in the flat keys (F, B♭, E♭, A♭, D♭).
func noteName(_ pc: Int, root: Int) -> String {
    let names = [1, 3, 5, 8, 10].contains(root) ? flatNames : sharpNames
    return names[((pc % 12) + 12) % 12]
}
