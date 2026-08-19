// Problem 24: Sensor Drift Window Detector
// Swift 6, macOS 14+ | Mid-level | approximately 45 minutes
//
// Environmental sensors report a signed drift delta per sampling interval:
// positive means the reading is pulling away from calibration. Support wants the
// single contiguous window whose cumulative drift is worst, because that is
// where it dispatches a technician. Some sensors run a circular duty cycle where
// the last interval wraps around to the first, and calibration scoring cares
// about drift magnitude in either direction rather than its sign.
//
// You choose the internal data structures; the public interface is the contract.
// Store all mutable state in instance properties initialized by init. Never use
// mutable global or static state. Every part must run in one pass over the
// series; a scan of every window is the answer you are being asked to improve
// on, not the answer.
//
/*
# Example
let detector = DriftDetector()
let deltas = [-2, 3, -1, 4, -6, 2]
try detector.worstTotal(deltas: deltas)                 // -> 6
try detector.worstWindow(deltas: deltas)                // -> DriftWindow(startIndex: 1, endIndex: 3, total: 6)
try detector.worstTotal(deltas: [-8, -3, -5])           // -> -3
try detector.worstCircularTotal(deltas: [5, -3, 5])     // -> 10
try detector.worstCircularTotal(deltas: deltas)         // -> 6
try detector.largestDriftMagnitude(deltas: deltas)      // -> 6
try detector.largestDriftMagnitude(deltas: [-4, -7, 1]) // -> 11
*/
//
// PART 1 - Worst contiguous drift total  (~9 min)
// Report the largest cumulative drift of any contiguous window. An empty series
// is a typed failure. A series where every interval drifts back toward
// calibration still has a worst window: the least bad single interval. Zero is
// not an answer unless some window actually totals zero.
//
// PART 2 - Report the window bounds  (~12 min)
// Report the worst window itself, bounds included, with endIndex inclusive.
// Part 1 and Part 2 must not be two separate scans: the window carries the
// total, so make the richer method the one that does the work.
// When two windows tie on total, report the one with the earliest start, and
// among those the shortest.
//
// PART 3 - Circular duty cycles  (~12 min)
// Some sensors wrap: the interval after the last one is the first one again.
// Report the worst cumulative drift of any contiguous window on that cycle,
// where a window may now wrap around the end. Do not write a second scan over a
// doubled series. Factor the Part 2 machinery into one private helper that can
// scan for the smallest window as well as the largest, and answer this from two
// calls to it. Watch what your answer says when every interval is negative.
//
// PART 4 - Largest drift magnitude in either direction  (~12 min)
// Calibration scoring wants the largest absolute cumulative drift of any
// contiguous window, in whichever direction it ran. The same private helper from
// Part 3 answers this too; no third scan is needed.

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

    // MARK: Part 1 - Worst contiguous drift total
    public func worstTotal(deltas: [Int]) throws(DriftError) -> Int { throw .notImplemented }

    // MARK: Part 2 - Report the window bounds
    public func worstWindow(deltas: [Int]) throws(DriftError) -> DriftWindow { throw .notImplemented }

    // MARK: Part 3 - Circular duty cycles
    public func worstCircularTotal(deltas: [Int]) throws(DriftError) -> Int { throw .notImplemented }

    // MARK: Part 4 - Largest drift magnitude in either direction
    public func largestDriftMagnitude(deltas: [Int]) throws(DriftError) -> Int { throw .notImplemented }
}
