import Accelerate

/// A note found in a window, and how far off its exact pitch it is.
struct DetectedNote: Equatable {
    /// MIDI note number.
    let note: Int
    /// Cents above (or, negative, below) the note's equal-tempered pitch at
    /// A = 440 Hz; nil when no harmonic was clear enough to measure.
    let cents: Float?
}

/// Finds the notes sounding together in a window of samples, by iterative
/// harmonic summation (after Klapuri 2006): score every candidate note by the
/// weighted spectrum peaks at its harmonics, take the best, take its harmonics
/// out of the spectrum, and repeat until what is left is too weak.
final class Polyphony {
    let windowSize: Int
    let sampleRate: Float
    /// MIDI notes considered: a 7-string guitar's low B up to the 24th fret of
    /// the high E.
    var noteRange = 35...88
    /// A further note counts only if it scores at least this fraction of the
    /// strongest one. Set high since distortion's intermodulation tones look
    /// like quieter notes.
    var relativeThreshold: Float = 0.65
    var maxNotes = 6
    /// Harmonics measured to tell how in tune a note is.
    var maxTuningHarmonic = 5

    private let fftSize: Int
    private let setup: vDSP_DFT_Setup
    private let hann: [Float]

    init(windowSize: Int, sampleRate: Float) {
        self.windowSize = windowSize
        self.sampleRate = sampleRate
        // Zero padded to twice the window, so peaks fall closer to bin centers.
        fftSize = windowSize * 2
        setup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(fftSize), .FORWARD)!
        hann = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: windowSize, isHalfWindow: false)
    }

    deinit {
        vDSP_DFT_DestroySetup(setup)
    }

    /// The notes found, strongest first.
    func notes(_ x: [Float]) -> [DetectedNote] {
        let raw = magnitudes(x)
        var spectrum = whitened(raw)
        var found: [Int] = []
        var strongest: Float = 0
        while found.count < maxNotes {
            var best: (note: Int, score: Float)?
            for note in noteRange where !found.contains(note) {
                let score = salience(note, spectrum)
                if score > (best?.score ?? 0) { best = (note, score) }
            }
            guard let best else { break }
            if found.isEmpty {
                strongest = best.score
            } else if best.score < strongest * relativeThreshold {
                break
            }
            found.append(best.note)
            remove(best.note, from: &spectrum)
        }
        return found.map { note in
            DetectedNote(note: note, cents: cents(note, raw, others: found.filter { $0 != note }))
        }
    }

    private func magnitudes(_ x: [Float]) -> [Float] {
        let windowed = vDSP.multiply(x, hann)
        let half = fftSize / 2
        // zrop takes the real input split into even and odd samples.
        var evens = [Float](repeating: 0, count: half)
        var odds = [Float](repeating: 0, count: half)
        for i in 0..<windowSize / 2 {
            evens[i] = windowed[2 * i]
            odds[i] = windowed[2 * i + 1]
        }
        var re = [Float](repeating: 0, count: half)
        var im = [Float](repeating: 0, count: half)
        vDSP_DFT_Execute(setup, evens, odds, &re, &im)
        // Bin 0 packs DC and Nyquist; neither matters here.
        re[0] = 0
        im[0] = 0
        var mags = [Float](repeating: 0, count: half)
        re.withUnsafeMutableBufferPointer { r in
            im.withUnsafeMutableBufferPointer { i in
                var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                vDSP_zvabs(&split, 1, &mags, 1, vDSP_Length(half))
            }
        }
        return mags
    }

    /// Flattens the spectral envelope (Klapuri's whitening, ν = 0.33), so a
    /// low note's many weak upper partials can outweigh one loud high peak.
    private func whitened(_ mags: [Float]) -> [Float] {
        var squares = [Float](repeating: 0, count: mags.count + 1)
        for k in 0..<mags.count { squares[k + 1] = squares[k] + mags[k] * mags[k] }
        let floor = (squares.last! / Float(mags.count)).squareRoot() * 1e-3 + 1e-9
        return mags.indices.map { k in
            // RMS over about a sixth of an octave around the bin.
            let lo = max(0, min(k - 3, Int(Float(k) / 1.06)))
            let hi = min(mags.count, max(k + 4, Int(Float(k) * 1.06) + 1))
            let rms = ((squares[hi] - squares[lo]) / Float(hi - lo)).squareRoot()
            return mags[k] * pow(max(rms, floor), 0.33 - 1)
        }
    }

    private func frequency(_ note: Int) -> Float {
        440 * pow(2, Float(note - 69) / 12)
    }

    /// The bins to search for harmonic `h` of `f0`: a quarter semitone either
    /// side, widening upward since plucked strings run sharp in the high
    /// harmonics.
    private func band(_ f0: Float, _ h: Int, count: Int) -> ClosedRange<Int>? {
        let f = f0 * Float(h)
        guard f < 5000 else { return nil }
        let center = f * Float(fftSize) / sampleRate
        let lo = Int((center * pow(2, -0.25 / 12)).rounded(.down))
        let hi = Int((center * pow(2, (0.25 + 0.01 * Float(h)) / 12)).rounded(.up))
        guard lo >= 1, hi < count else { return nil }
        return lo...max(hi, lo + 1)
    }

    /// How far `note` is from its exact pitch, from where its lower harmonics'
    /// peaks really are. Each peak is located between bins by fitting a
    /// parabola to the log magnitudes around it (exact for a Gaussian, close
    /// for a Hann window's main lobe). Higher harmonics pin the fundamental
    /// down more finely but run sharp on a stiff string, so only the first
    /// few are used, weighted by their size and number. In a chord, a
    /// harmonic that overlaps one of the `others`' is skipped, since the
    /// two peaks pull on each other, unless that would leave none.
    private func cents(_ note: Int, _ mags: [Float], others: [Int]) -> Float? {
        let f0 = frequency(note)
        let binHz = sampleRate / Float(fftSize)
        // Within this many bins two peaks' main lobes overlap.
        let lobe: Float = 4
        let clashes = (1...maxTuningHarmonic).filter { h in
            others.contains { other in
                let ratio = f0 * Float(h) / frequency(other)
                let j = max(1, ratio.rounded())
                return abs(f0 * Float(h) - j * frequency(other)) < lobe * binHz
            }
        }
        let harmonics = (1...maxTuningHarmonic).filter { !clashes.contains($0) }
        var sum: Float = 0
        var weight: Float = 0
        for h in harmonics.isEmpty ? Array(1...maxTuningHarmonic) : harmonics {
            let center = f0 * Float(h) / binHz
            // Half a semitone either side: the whole range the note covers.
            let lo = Int((center * pow(2, -0.5 / 12)).rounded(.down))
            let hi = Int((center * pow(2, 0.5 / 12)).rounded(.up))
            guard lo >= 2, hi < mags.count - 1 else { break }
            let k = (lo...hi).max { mags[$0] < mags[$1] }!
            guard mags[k] > 0, mags[k] >= mags[k - 1], mags[k] >= mags[k + 1] else { continue }
            let a = log(max(mags[k - 1], 1e-12))
            let b = log(mags[k])
            let c = log(max(mags[k + 1], 1e-12))
            let curve = a - 2 * b + c
            let offset = curve < 0 ? 0.5 * (a - c) / curve : 0
            let f = (Float(k) + offset) * binHz / Float(h)
            let w = mags[k] * Float(h)
            sum += w * log2(f / f0)
            weight += w
        }
        return weight > 0 ? 1200 * sum / weight : nil
    }

    private func harmonicCount(_ f0: Float) -> Int {
        min(20, Int(5000 / f0))
    }

    private func salience(_ note: Int, _ spectrum: [Float]) -> Float {
        let f0 = frequency(note)
        var score: Float = 0
        for h in 1...harmonicCount(f0) {
            guard let band = band(f0, h, count: spectrum.count) else { break }
            let peak = spectrum[band].max()!
            score += (f0 + 27) / (Float(h) * f0 + 320) * peak
        }
        return score
    }

    /// Takes `note`'s harmonics out of the spectrum. Each is reduced by a
    /// smoothed estimate of its height rather than zeroed, so a peak another
    /// note shares (G's 2nd harmonic is C's 3rd) keeps that note's share.
    private func remove(_ note: Int, from spectrum: inout [Float]) {
        let f0 = frequency(note)
        var bands: [ClosedRange<Int>] = []
        for h in 1...harmonicCount(f0) {
            guard let band = band(f0, h, count: spectrum.count) else { break }
            bands.append(band)
        }
        let peaks = bands.map { spectrum[$0].max()! }
        for (i, band) in bands.enumerated() {
            let neighbors = peaks[max(0, i - 1)...min(peaks.count - 1, i + 1)]
            let smooth = min(peaks[i], neighbors.reduce(0, +) / Float(neighbors.count))
            guard peaks[i] > 0 else { continue }
            let keep = 1 - smooth / peaks[i]
            // Widened by the window's main lobe so the peak's skirts go too.
            for b in max(1, band.lowerBound - 2)...min(spectrum.count - 1, band.upperBound + 2) {
                spectrum[b] *= keep
            }
        }
    }
}
