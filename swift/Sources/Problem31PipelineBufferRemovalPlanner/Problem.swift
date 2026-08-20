// Problem 31: Pipeline Buffer Removal Planner
// Swift 6, macOS 14+ | Staff | approximately 45 minutes
//
// A streaming data pipeline is a chain of stages separated by intermediate
// buffers. Retiring a buffer saves throughput in proportion to its own width
// multiplied by the widths of the two buffers still present on either side of
// it, because that is the fan-in the scheduler no longer has to reconcile. A
// buffer at either end of the chain has a sentinel width of one standing in for
// its missing neighbour.
//
// So the reward for retiring a buffer depends on what has not been retired yet,
// which means the order changes the total and a left-to-right sweep is provably
// short of the best. Later, an optimisation lands that lets consecutive buffers
// of the same stage type be retired together as one run, with a saving
// quadratic in the run length, and that changes the problem's shape rather than
// just its arithmetic.
//
// You choose the internal data structures; the public interface is the contract.
// Store all mutable state in instance properties initialized by init. Never use
// mutable global or static state. Immutable static constants are fine.
//
/*
# Example
let planner = BufferRemovalPlanner()
let chain = [
    PipelineBuffer(id: "buf-a", width: 3, stageType: "parse"),
    PipelineBuffer(id: "buf-b", width: 1, stageType: "map"),
    PipelineBuffer(id: "buf-c", width: 5, stageType: "parse"),
    PipelineBuffer(id: "buf-d", width: 8, stageType: "sink"),
]
try planner.bestSavingExhaustive(chain)      // -> 167
try planner.bestSaving(chain)                // -> 167
try planner.retirementOrder(chain)           // -> ["buf-b", "buf-c", "buf-a", "buf-d"]
try planner.bestSavingWithRunCollapse(chain) // -> 29
*/
//
// PART 1 - Exhaustive saving for a short chain  (~9 min)
// Report the best total saving by trying every order of retirement. This is
// deliberately the slow way, and it is not filler: it is what the next part is
// proved equal to, and the suite asserts that agreement on every fixture short
// enough to reach here. Write the replay of one concrete order as its own
// helper, because Part 3 needs exactly the same replay.
// The work grows as the factorial of the chain length, so refuse a chain longer
// than a documented ceiling as a typed failure rather than trying. Eight is a
// reasonable ceiling. A width of zero or less, a width beyond the documented
// maximum, and a repeated buffer identifier are typed failures too, and the
// width ceiling is not decoration: three widths are multiplied in a single term
// and an unguarded Int overflow in Swift ends the process rather than returning
// a wrong number.
//
// PART 2 - Best saving by interval decomposition  (~14 min)
// Report the same number without enumerating orders. Ask which buffer in an
// interval is retired LAST, not which is retired first. Once the last one is
// fixed, its two neighbours at retirement time are the interval's own bounds,
// and the two sides of it stop interacting; asking which is retired first does
// not decompose, because the two halves still touch.
// Pad the widths with a sentinel of one at each end and the two ends of the
// chain need no special case at all.
// The fill order is the whole part. Entries must be filled by increasing
// interval length, because an entry depends only on strictly shorter ones. A
// plain row-major sweep reads entries that have not been written yet and
// returns a plausible smaller number rather than failing, which is the single
// most common way this is got wrong. There is no rolling-row trick here: an
// entry depends on cells in its own row and its own column at any distance.
//
// PART 3 - Report the retirement order  (~11 min)
// Report the buffer IDs in an order that achieves the saving from Part 2. Do
// not re-derive it greedily. Record, alongside each interval's best saving,
// which buffer closed it, and walk that record: both sides of an interval are
// emitted before the buffer that closes them, which is what "retired last"
// means. Name the shared table-building helper and let both parts call it, so
// there is one decomposition in the file rather than two.
// The suite replays what you return and checks it against Part 2's number, so a
// plausible order that does not actually achieve the saving will be caught.
//
// PART 4 - Collapse runs of one stage type  (~11 min)
// Report the best total saving under a different reward: consecutive buffers of
// the same stage type may be retired together as one run, saving the square of
// the run length scaled by the width of the buffer the run is reconciled at,
// which is its rightmost member. Buffers become consecutive as the ones between
// them are retired, so a run can be assembled rather than only found.
// This part does not reuse Part 2's table, and the reason is the lesson rather
// than an oversight: the saving now depends on how many same-type buffers were
// already folded in from the left, so an interval on its own is no longer
// enough state to describe a sub-problem. Add that count as a third dimension
// and memoise on all three. Each buffer then has two moves - close the run
// here, or clear everything between it and a later buffer of its own type and
// let the run grow - which is what makes this quartic rather than cubic.

/// One intermediate buffer between two pipeline stages.
public struct PipelineBuffer: Equatable, Sendable {
    public let id: String
    public let width: Int
    public let stageType: String

    public init(id: String, width: Int, stageType: String) {
        self.id = id
        self.width = width
        self.stageType = stageType
    }
}

public enum RemovalError: Error, Equatable, Sendable {
    case nonPositiveWidth(String)
    case widthTooLarge(String)
    case duplicateBufferID(String)
    case chainTooLong(Int)
    case notImplemented
}

public struct BufferRemovalPlanner: Sendable {
    /// The longest chain the permutation baseline will attempt.
    public static let maximumExhaustiveChainLength = 8

    /// The longest chain the planners will accept.
    public static let maximumPlannableChainLength = 40

    /// The widest buffer accepted, which is what keeps the arithmetic inside an
    /// Int. See the Part 1 note.
    public static let maximumBufferWidth = 1_000

    public init() {}

    // MARK: Part 1 - Exhaustive saving for a short chain
    public func bestSavingExhaustive(_ buffers: [PipelineBuffer]) throws(RemovalError) -> Int {
        throw .notImplemented
    }

    // MARK: Part 2 - Best saving by interval decomposition
    public func bestSaving(_ buffers: [PipelineBuffer]) throws(RemovalError) -> Int {
        throw .notImplemented
    }

    // MARK: Part 3 - Report the retirement order
    public func retirementOrder(_ buffers: [PipelineBuffer]) throws(RemovalError) -> [String] {
        throw .notImplemented
    }

    // MARK: Part 4 - Collapse runs of one stage type
    public func bestSavingWithRunCollapse(_ buffers: [PipelineBuffer]) throws(RemovalError) -> Int {
        throw .notImplemented
    }
}
