/// One clause of an agreement, together with what reviewing a change to it
/// costs. The weight is a reviewer-minutes proxy: replacing a payment-terms
/// clause costs a lawyer far more attention than replacing a boilerplate
/// notice, and Part 4 exists because that difference changes which alignment
/// is actually the cheapest one.
public struct Clause: Hashable, Sendable {
    public let id: String
    public let reviewWeight: Int

    public init(id: String, reviewWeight: Int) {
        self.id = id
        self.reviewWeight = reviewWeight
    }
}

/// One step of a diff. An enum with associated values rather than a struct with
/// a kind field, so an operation that carries the wrong number of clause IDs
/// cannot be constructed at all.
public enum EditOperation: Equatable, Sendable {
    case keep(String)
    case delete(String)
    case insert(String)
    case replace(from: String, to: String)
}

/// A diff plus what it costs to review. The cost travels with the operations
/// because the two are always computed from the same walk of the same table,
/// and returning them separately invites them to disagree.
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

    /// How many clauses survive, in order, from one revision into the other.
    ///
    /// This is the length of the alignment table's corner entry. It is written
    /// as a projection of `sharedSpine` rather than as its own table, because
    /// two tables computing the same quantity is exactly how the two answers
    /// drift apart.
    public func sharedSpineLength(_ left: [String], _ right: [String]) -> Int {
        sharedSpine(left, right).count
    }

    // MARK: Part 2 - Emit the spine and the merged revision

    /// The clauses common to both revisions, in the order both agree on.
    ///
    /// The table entry at row i and column j is the length of the shared spine
    /// of the first i clauses on the left and the first j on the right, so the
    /// zero row and the zero column are both empty: an empty revision shares
    /// nothing with anything. The walk back from the corner is where the spine
    /// itself comes from, and it is the reason the whole table is kept rather
    /// than the two rolling rows the length alone would need.
    ///
    /// On a tie the walk steps **up**, dropping a clause from the left. The
    /// rule is documented rather than incidental because a caller that asserts
    /// one particular spine needs the answer to be the same one every time.
    public func sharedSpine(_ left: [String], _ right: [String]) -> [String] {
        let table = spineTable(left, right)
        var spine: [String] = []
        var i = left.count
        var j = right.count

        while i > 0 && j > 0 {
            if left[i - 1] == right[j - 1] {
                spine.append(left[i - 1])
                i -= 1
                j -= 1
            } else if table[i - 1][j] >= table[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }

        return Array(spine.reversed())
    }

    /// The shortest document that contains both revisions as subsequences.
    ///
    /// The same walk as `sharedSpine`, except that the clause stepped over is
    /// emitted rather than discarded. Its length is necessarily the two lengths
    /// added together with the shared spine counted once instead of twice, and
    /// the test suite asserts exactly that against Part 1.
    public func mergedRevision(_ left: [String], _ right: [String]) -> [String] {
        let table = spineTable(left, right)
        var merged: [String] = []
        var i = left.count
        var j = right.count

        while i > 0 && j > 0 {
            if left[i - 1] == right[j - 1] {
                merged.append(left[i - 1])
                i -= 1
                j -= 1
            } else if table[i - 1][j] >= table[i][j - 1] {
                merged.append(left[i - 1])
                i -= 1
            } else {
                merged.append(right[j - 1])
                j -= 1
            }
        }
        while i > 0 {
            merged.append(left[i - 1])
            i -= 1
        }
        while j > 0 {
            merged.append(right[j - 1])
            j -= 1
        }

        return Array(merged.reversed())
    }

    // MARK: Part 3 - Minimal edit script

    /// The fewest single-clause edits that turn the left revision into the right.
    ///
    /// A projection of `editScript`, for the same reason `sharedSpineLength` is
    /// a projection of `sharedSpine`: there is one alignment table in this file
    /// and every number in this part comes out of it.
    public func editDistance(_ left: [String], _ right: [String]) -> Int {
        editScript(left, right).totalCost
    }

    /// The fewest edits when replacement is forbidden and only insertion and
    /// deletion are available.
    ///
    /// Nothing new is computed. Every clause outside the shared spine has to be
    /// deleted from the left or inserted into the right, so the answer is the
    /// two lengths added together with the spine removed from each of them.
    /// This is Part 3 proving itself against Part 1, and the suite asserts the
    /// identity directly on a spread of fixtures.
    public func deleteOnlyDistance(_ left: [String], _ right: [String]) -> Int {
        left.count + right.count - 2 * sharedSpineLength(left, right)
    }

    /// The cheapest script of keeps, deletes, inserts and replacements that
    /// turns the left revision into the right, under unit review cost.
    ///
    /// The unit cost model is the weighted model of Part 4 with no weights
    /// supplied, so this method is a call into the shared machinery rather than
    /// a second implementation of it.
    public func editScript(_ left: [String], _ right: [String]) -> EditScript {
        alignedScript(left, right, cost: .unit)
    }

    // MARK: Part 4 - Price the script with review weights

    /// The cheapest script under per-clause review weights.
    ///
    /// Same table, same walk, different cost function. A clause with no listed
    /// weight reviews like any other, so it costs one; the default lives in the
    /// cost model rather than being spread through the table.
    public func weightedEditScript(
        _ left: [String],
        _ right: [String],
        weights: [Clause]
    ) throws(DiffError) -> EditScript {
        var byID: [String: Int] = [:]
        for clause in weights {
            guard clause.reviewWeight >= 0 else { throw .negativeReviewWeight(clause.id) }
            guard byID[clause.id] == nil else { throw .duplicateClauseWeight(clause.id) }
            byID[clause.id] = clause.reviewWeight
        }
        return alignedScript(left, right, cost: ReviewCostModel(weights: byID))
    }

    // MARK: Shared machinery

    /// What one edit costs the reviewer.
    ///
    /// A replacement is priced by the more sensitive of the two clauses
    /// involved, because the review time is set by whichever side needs the
    /// closer reading. With no weights listed every edit costs one, which is
    /// why Part 3 is this model rather than a separate table.
    private struct ReviewCostModel: Sendable {
        let weights: [String: Int]

        static let unit = ReviewCostModel(weights: [:])

        func removal(_ id: String) -> Int { weights[id] ?? 1 }
        func addition(_ id: String) -> Int { weights[id] ?? 1 }
        func substitution(from: String, to: String) -> Int {
            max(removal(from), addition(to))
        }
    }

    /// The shared-spine table. Entry i, j is the length of the shared spine of
    /// the first i clauses on the left and the first j on the right.
    ///
    /// Filled ascending in both dimensions, which is what makes the three
    /// entries every transition reads - above, to the left, and diagonally
    /// above-left - already present when the transition needs them.
    private func spineTable(_ left: [String], _ right: [String]) -> [[Int]] {
        var table = Array(
            repeating: Array(repeating: 0, count: right.count + 1),
            count: left.count + 1
        )
        guard !left.isEmpty && !right.isEmpty else { return table }

        for i in 1...left.count {
            for j in 1...right.count {
                if left[i - 1] == right[j - 1] {
                    table[i][j] = table[i - 1][j - 1] + 1
                } else {
                    table[i][j] = max(table[i - 1][j], table[i][j - 1])
                }
            }
        }
        return table
    }

    /// The alignment table for a given cost model. Entry i, j is the cheapest
    /// review cost that turns the first i clauses on the left into the first j
    /// on the right.
    ///
    /// The zero row and the zero column are **not** zero here, and that single
    /// difference from the spine table is what separates the two objectives:
    /// turning a prefix into nothing means deleting all of it, and turning
    /// nothing into a prefix means inserting all of it.
    private func alignmentTable(
        _ left: [String],
        _ right: [String],
        cost: ReviewCostModel
    ) -> [[Int]] {
        var table = Array(
            repeating: Array(repeating: 0, count: right.count + 1),
            count: left.count + 1
        )
        if !left.isEmpty {
            for i in 1...left.count {
                table[i][0] = table[i - 1][0] + cost.removal(left[i - 1])
            }
        }
        if !right.isEmpty {
            for j in 1...right.count {
                table[0][j] = table[0][j - 1] + cost.addition(right[j - 1])
            }
        }
        guard !left.isEmpty && !right.isEmpty else { return table }

        for i in 1...left.count {
            for j in 1...right.count {
                let deleting = table[i - 1][j] + cost.removal(left[i - 1])
                let inserting = table[i][j - 1] + cost.addition(right[j - 1])
                let diagonal: Int
                if left[i - 1] == right[j - 1] {
                    diagonal = table[i - 1][j - 1]
                } else {
                    diagonal = table[i - 1][j - 1]
                        + cost.substitution(from: left[i - 1], to: right[j - 1])
                }
                table[i][j] = min(diagonal, min(deleting, inserting))
            }
        }
        return table
    }

    /// The cheapest script under a cost model, walked back out of the table.
    ///
    /// The walk has to break ties, and the rule is fixed and documented: keep
    /// first where the clauses match, then replace, then delete, then insert.
    /// Any other rule is equally correct arithmetically and produces a
    /// different script, which is precisely why the caller is told which one
    /// this is.
    private func alignedScript(
        _ left: [String],
        _ right: [String],
        cost: ReviewCostModel
    ) -> EditScript {
        let table = alignmentTable(left, right, cost: cost)
        var operations: [EditOperation] = []
        var i = left.count
        var j = right.count

        while i > 0 || j > 0 {
            if i > 0 && j > 0 && left[i - 1] == right[j - 1]
                && table[i][j] == table[i - 1][j - 1] {
                operations.append(.keep(left[i - 1]))
                i -= 1
                j -= 1
            } else if i > 0 && j > 0
                && table[i][j] == table[i - 1][j - 1]
                    + cost.substitution(from: left[i - 1], to: right[j - 1]) {
                operations.append(.replace(from: left[i - 1], to: right[j - 1]))
                i -= 1
                j -= 1
            } else if i > 0 && table[i][j] == table[i - 1][j] + cost.removal(left[i - 1]) {
                operations.append(.delete(left[i - 1]))
                i -= 1
            } else {
                operations.append(.insert(right[j - 1]))
                j -= 1
            }
        }

        return EditScript(
            operations: Array(operations.reversed()),
            totalCost: table[left.count][right.count]
        )
    }
}
