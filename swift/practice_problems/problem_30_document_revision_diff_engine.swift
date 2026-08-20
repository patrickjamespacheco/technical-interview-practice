// Problem 30: Document Revision Diff Engine
// Swift 6, macOS 14+ | Staff | approximately 45 minutes
//
// A contract management system stores each agreement as an ordered list of
// clause identifiers. When two parties return edited revisions, the reviewer
// needs four things: which clauses survived unchanged and in order, a merged
// document that still contains both revisions, the shortest script of edits
// that turns one revision into the other, and - because a lawyer spends far
// longer re-reading a payment-terms clause than a boilerplate notice - the
// cheapest such script once each clause carries a review weight.
//
// All four parts are the same table. One entry stands for a prefix of the left
// revision paired with a prefix of the right, and every transition is the same
// three-way choice: the two last clauses aligned together, or one of them
// dropped from its own side. Only the objective changes. Part 3 is not a new
// implementation of Part 1; it is Part 1's table with a different quantity in
// it, and the parts are ordered so that seeing this is the point.
//
// You choose the internal data structures; the public interface is the contract.
// Store all mutable state in instance properties initialized by init. Never use
// mutable global or static state. Immutable static constants are fine.
//
/*
# Example
let engine = RevisionDiffEngine()
let left  = ["recitals", "payment-terms", "liability", "notices"]
let right = ["recitals", "liability", "arbitration", "notices"]
engine.sharedSpineLength(left, right)   // -> 3
engine.sharedSpine(left, right)         // -> ["recitals", "liability", "notices"]
engine.mergedRevision(left, right)
// -> ["recitals", "payment-terms", "liability", "arbitration", "notices"]
engine.editDistance(left, right)        // -> 2
engine.deleteOnlyDistance(left, right)  // -> 2
engine.editScript(left, right).operations
// -> [.keep("recitals"),
//     .replace(from: "payment-terms", to: "liability"),
//     .replace(from: "liability", to: "arbitration"),
//     .keep("notices")]
try engine.weightedEditScript(left, right,
    weights: [Clause(id: "payment-terms", reviewWeight: 9)]).totalCost
// -> 10
*/
//
// PART 1 - Measure the shared spine  (~10 min)
// Report how many clauses survive from one revision into the other in the same
// order, with gaps allowed on both sides. Say what one table entry means before
// writing a transition, because the entire problem is that sentence: it is the
// answer for a prefix of the left paired with a prefix of the right, which
// makes the zero row and the zero column the empty revision and fixes the base
// case for every later part.
// Taking the first clause that matches is wrong and looks right on small
// inputs. A fixture in the suite is built precisely to punish it.
//
// PART 2 - Emit the spine and the merged revision  (~12 min)
// Report the surviving clauses themselves, and the shortest document that still
// contains both revisions in order. The table alone gives a number; the
// clauses come from walking back out of it from the corner, which is why the
// whole table is kept rather than the two rolling rows the number alone needs.
// Fix the tie-break and document it. Where the two sides of a step are equally
// good the walk here steps up, dropping a clause from the left. An unstated
// rule makes this untestable, and the suite asserts a specific spine on a
// fixture where the two rules disagree.
// The merge is the same walk, emitting the clause you step over rather than
// discarding it. Its length is forced: a test asserts it against Part 1.
//
// PART 3 - Minimal edit script  (~12 min)
// Report the fewest keeps, deletes, inserts and replacements that turn the left
// revision into the right, and the script itself. Same table shape, different
// objective, and one thing genuinely changes: the zero row and the zero column
// are no longer zero, because turning a prefix into nothing means deleting all
// of it. Pasting the base case from Part 1 is the single highest-frequency bug
// here and it reports distances that are far too small.
// The script needs its own documented precedence at each step: keep where the
// clauses match, then replace, then delete, then insert.
// deleteOnlyDistance forbids replacement. Do not build a third table for it -
// with only inserts and deletes available, every clause outside the shared
// spine has to move, and Part 1 already knows how big the spine is. A test
// asserts that identity, which is this problem proving itself against itself.
//
// PART 4 - Price the script with review weights  (~11 min)
// Report the cheapest script once each clause carries a review weight, with any
// clause not listed reviewing like an ordinary one. This is Part 3's table with
// a cost function in place of the constant one, so factor the cost out first
// and let Part 3 be the case where every weight is one. A test asserts exactly
// that on a spread of fixtures, so a second table here will be caught.
// Decide what replacing one clause with another costs and say so; the suite
// assumes the more sensitive of the two clauses sets the price. A negative
// weight and the same clause weighted twice are both typed failures.

/// One clause of an agreement, together with what reviewing a change to it
/// costs. The weight is a reviewer-minutes proxy: zero means the clause is
/// boilerplate, one means ordinary.
public struct Clause: Hashable, Sendable {
    public let id: String
    public let reviewWeight: Int

    public init(id: String, reviewWeight: Int) {
        self.id = id
        self.reviewWeight = reviewWeight
    }
}

/// One step of a diff.
public enum EditOperation: Equatable, Sendable {
    case keep(String)
    case delete(String)
    case insert(String)
    case replace(from: String, to: String)
}

/// A diff plus what it costs to review.
public struct EditScript: Equatable, Sendable {
    public let operations: [EditOperation]
    public let totalCost: Int

    public init(operations: [EditOperation], totalCost: Int) {
        self.operations = operations
        self.totalCost = totalCost
    }
}

public enum DiffError: Error, Equatable, Sendable {
    case negativeReviewWeight(String)
    case duplicateClauseWeight(String)
    case notImplemented
}

public struct RevisionDiffEngine: Sendable {
    public init() {}

    // MARK: Part 1 - Measure the shared spine
    public func sharedSpineLength(_ left: [String], _ right: [String]) -> Int {
        0
    }

    // MARK: Part 2 - Emit the spine and the merged revision
    public func sharedSpine(_ left: [String], _ right: [String]) -> [String] {
        []
    }

    public func mergedRevision(_ left: [String], _ right: [String]) -> [String] {
        []
    }

    // MARK: Part 3 - Minimal edit script
    public func editDistance(_ left: [String], _ right: [String]) -> Int {
        0
    }

    public func deleteOnlyDistance(_ left: [String], _ right: [String]) -> Int {
        0
    }

    public func editScript(_ left: [String], _ right: [String]) -> EditScript {
        EditScript(operations: [], totalCost: 0)
    }

    // MARK: Part 4 - Price the script with review weights
    public func weightedEditScript(
        _ left: [String],
        _ right: [String],
        weights: [Clause]
    ) throws(DiffError) -> EditScript {
        throw .notImplemented
    }
}
