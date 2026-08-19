/// One contiguous stretch of sampling intervals, with the cumulative drift it
/// accumulated. `endIndex` is inclusive so a single interval is a legal window.
public struct DriftWindow: Equatable, Sendable {
    public let startIndex: Int
    public let endIndex: Int
    public let total: Int

    public init(startIndex: Int, endIndex: Int, total: Int) {
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.total = total
    }
}

public enum DriftError: Error, Equatable, Sendable {
    case emptySeries
    case notImplemented
}

public struct DriftDetector: Sendable {
    public init() {}

    // MARK: Shared machinery

    /// The one scan every part is built on: the extreme contiguous window of
    /// `deltas`, either the largest total (`maximising`) or the smallest.
    ///
    /// The state that makes this linear is "the extreme window that ends exactly
    /// at `index`". Extending is worth it only when the run so far helps, which
    /// is the sole difference between the two directions, so one function serves
    /// both rather than two near-identical copies drifting apart.
    ///
    /// Ties resolve to the earliest start and then the shortest window. Both fall
    /// out of the same two rules: keep the running start when the run so far is
    /// neutral, and replace the recorded best only on a strict improvement.
    ///
    /// The caller guarantees `deltas` is non-empty; that check belongs to the
    /// public methods, which own the typed failure.
    private func extremeWindow(_ deltas: [Int], maximising: Bool) -> DriftWindow {
        var runningTotal = deltas[0]
        var runningStart = 0
        var best = DriftWindow(startIndex: 0, endIndex: 0, total: deltas[0])

        for index in 1..<deltas.count {
            let delta = deltas[index]
            let runHelps = maximising ? runningTotal >= 0 : runningTotal <= 0
            if runHelps {
                runningTotal += delta
            } else {
                runningTotal = delta
                runningStart = index
            }

            let improved = maximising ? runningTotal > best.total : runningTotal < best.total
            if improved {
                best = DriftWindow(startIndex: runningStart, endIndex: index, total: runningTotal)
            }
        }

        return best
    }

    // MARK: Part 1 - Worst contiguous drift total

    /// The worst window's total. The window itself is the primitive, so this is
    /// a projection of Part 2 rather than a second scan with the bookkeeping
    /// stripped out.
    public func worstTotal(deltas: [Int]) throws(DriftError) -> Int {
        try worstWindow(deltas: deltas).total
    }

    // MARK: Part 2 - Report the window bounds

    public func worstWindow(deltas: [Int]) throws(DriftError) -> DriftWindow {
        guard !deltas.isEmpty else { throw .emptySeries }
        return extremeWindow(deltas, maximising: true)
    }

    // MARK: Part 3 - Circular duty cycles

    /// On a circular cycle the worst window either stays inside the series or
    /// wraps. A wrapping window is exactly the complement of a non-wrapping one,
    /// so the smallest interior window names the best wrap without a second
    /// algorithm.
    ///
    /// The guard matters: when every delta is negative the complement of the
    /// smallest window is the empty window, which is not a window at all. The
    /// non-wrapping answer already is the whole answer there.
    public func worstCircularTotal(deltas: [Int]) throws(DriftError) -> Int {
        guard !deltas.isEmpty else { throw .emptySeries }
        let interior = extremeWindow(deltas, maximising: true).total
        guard interior >= 0 else { return interior }
        let smallest = extremeWindow(deltas, maximising: false).total
        return max(interior, deltas.reduce(0, +) - smallest)
    }

    // MARK: Part 4 - Largest drift magnitude in either direction

    /// Calibration scoring cares how far a stretch pulled away from centre, not
    /// which way. The most negative window is the most positive magnitude once
    /// its sign is dropped, so the same two scans answer this too.
    public func largestDriftMagnitude(deltas: [Int]) throws(DriftError) -> Int {
        guard !deltas.isEmpty else { throw .emptySeries }
        let largest = extremeWindow(deltas, maximising: true).total
        let smallest = extremeWindow(deltas, maximising: false).total
        return max(largest, -smallest)
    }
}
