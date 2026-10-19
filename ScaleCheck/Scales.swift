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

let rootNames = ["C", "D♭", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]

private let sharpNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
private let flatNames = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]

/// Name of pitch class `pc`, using flats in the flat keys (F, B♭, E♭, A♭, D♭).
func noteName(_ pc: Int, root: Int) -> String {
    let names = [1, 3, 5, 8, 10].contains(root) ? flatNames : sharpNames
    return names[((pc % 12) + 12) % 12]
}
