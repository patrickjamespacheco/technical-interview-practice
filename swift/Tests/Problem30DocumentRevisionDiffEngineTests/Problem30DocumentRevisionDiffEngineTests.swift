import Testing
@testable import Problem30DocumentRevisionDiffEngine

/// The worked pair of revisions. One clause is dropped, one is added, and three
/// survive in order, so it exercises the spine, the merge and the script.
private let workedLeft = ["recitals", "payment-terms", "liability", "notices"]
private let workedRight = ["recitals", "liability", "arbitration", "notices"]

/// A pair whose first clauses match but whose longest agreement lies elsewhere.
/// A run that takes the first match it sees reports one instead of three.
private let greedyTrapLeft = ["intro", "fee", "term", "exit"]
private let greedyTrapRight = ["fee", "term", "exit", "intro"]

/// Two clauses that swap places. Both revisions contain the same clauses, so
/// several alignments cost the same under unit review and only the weights
/// separate them.
private let swappedLeft = ["payment-terms", "notices"]
private let swappedRight = ["notices", "payment-terms"]

/// A spread of pairs used for the identities that must hold on all of them.
private let alignmentFixtures: [(left: [String], right: [String])] = [
    (workedLeft, workedRight),
    (greedyTrapLeft, greedyTrapRight),
    (swappedLeft, swappedRight),
    ([], ["indemnity", "notices"]),
    (["indemnity", "notices"], []),
    (["term", "term", "term"], ["term"]),
]

private func makeEngine() -> RevisionDiffEngine {
    RevisionDiffEngine()
}

/// Whether `candidate` appears inside `document` in order, with gaps allowed.
/// Written out rather than leaning on a string search, because a clause ID can
/// be a prefix of another one and containment would then lie.
private func isSubsequence(_ candidate: [String], of document: [String]) -> Bool {
    var position = document.startIndex
    for clause in candidate {
        guard let found = document[position...].firstIndex(of: clause) else { return false }
        position = document.index(after: found)
    }
    return true
}

/// Runs an edit script against a revision and returns what it produces. This is
/// the strongest single assertion available in this problem: a script whose
/// cost is right but whose operations are wrong fails here and nowhere else.
private func apply(_ operations: [EditOperation], to document: [String]) -> [String] {
    var produced: [String] = []
    var position = 0
    for operation in operations {
        switch operation {
        case .keep(let id):
            produced.append(id)
            position += 1
        case .delete:
            position += 1
        case .insert(let id):
            produced.append(id)
        case .replace(_, let to):
            produced.append(to)
            position += 1
        }
    }
    produced.append(contentsOf: document[min(position, document.count)...])
    return produced
}

@Suite("Part 1 - Measure the shared spine")
struct DiffPart1Tests {
    @Test("two identical revisions share every clause")
    func identicalRevisions() {
        let engine = makeEngine()
        #expect(engine.sharedSpineLength(workedLeft, workedLeft) == workedLeft.count)
    }

    @Test("revisions with nothing in common share nothing")
    func disjointRevisions() {
        let engine = makeEngine()
        #expect(engine.sharedSpineLength(["alpha-term"], ["beta-term", "gamma-term"]) == 0)
    }

    @Test("an empty revision shares nothing, from either side")
    func emptyRevisions() {
        let engine = makeEngine()
        #expect(engine.sharedSpineLength([], workedRight) == 0)
        #expect(engine.sharedSpineLength(workedLeft, []) == 0)
        #expect(engine.sharedSpineLength([], []) == 0)
    }

    @Test("the worked revisions share three clauses")
    func workedPair() {
        let engine = makeEngine()
        #expect(engine.sharedSpineLength(workedLeft, workedRight) == 3)
    }

    @Test("taking the first clause that matches is not enough")
    func greedyFirstMatchIsWrong() {
        let engine = makeEngine()
        // Matching intro first leaves one clause of agreement; skipping it
        // leaves three.
        #expect(engine.sharedSpineLength(greedyTrapLeft, greedyTrapRight) == 3)
    }

    @Test("run against its own reverse, the spine measures how symmetric a revision is")
    func spineAgainstReversedRevision() {
        let engine = makeEngine()
        let clauses = ["intro", "fee", "term", "fee", "exit"]
        // fee, term, fee reads the same in both directions, so three of the five
        // clauses already agree with the reversed order and two must be added.
        let symmetric = engine.sharedSpineLength(clauses, clauses.reversed())
        #expect(symmetric == 3)
        #expect(clauses.count - symmetric == 2)
    }
}

@Suite("Part 2 - Emit the spine and the merged revision")
struct DiffPart2Tests {
    @Test("the worked spine is the three surviving clauses in order")
    func workedSpine() throws {
        let engine = makeEngine()
        let spine = engine.sharedSpine(workedLeft, workedRight)
        try #require(spine.count == 3)
        #expect(spine == ["recitals", "liability", "notices"])
    }

    @Test("the spine appears in order inside both revisions")
    func spineIsSubsequenceOfBoth() {
        let engine = makeEngine()
        for fixture in alignmentFixtures {
            let spine = engine.sharedSpine(fixture.left, fixture.right)
            #expect(isSubsequence(spine, of: fixture.left))
            #expect(isSubsequence(spine, of: fixture.right))
        }
    }

    @Test("the spine and the spine length agree everywhere")
    func spineAndLengthAgree() {
        let engine = makeEngine()
        for fixture in alignmentFixtures {
            #expect(
                engine.sharedSpine(fixture.left, fixture.right).count
                    == engine.sharedSpineLength(fixture.left, fixture.right)
            )
        }
    }

    @Test("the worked merge holds both revisions in five clauses")
    func workedMerge() throws {
        let engine = makeEngine()
        let merged = engine.mergedRevision(workedLeft, workedRight)
        try #require(merged.count == 5)
        #expect(merged == ["recitals", "payment-terms", "liability", "arbitration", "notices"])
    }

    @Test("the merge counts the shared spine once and everything else twice over")
    func mergeLengthIdentity() {
        let engine = makeEngine()
        for fixture in alignmentFixtures {
            let merged = engine.mergedRevision(fixture.left, fixture.right)
            let expected = fixture.left.count + fixture.right.count
                - engine.sharedSpineLength(fixture.left, fixture.right)
            #expect(merged.count == expected)
        }
    }

    @Test("both revisions appear in order inside the merge")
    func bothRevisionsAreSubsequencesOfMerge() {
        let engine = makeEngine()
        for fixture in alignmentFixtures {
            let merged = engine.mergedRevision(fixture.left, fixture.right)
            #expect(isSubsequence(fixture.left, of: merged))
            #expect(isSubsequence(fixture.right, of: merged))
        }
    }

    @Test("a tie in the walk drops a clause from the left, as documented")
    func documentedTieBreak() throws {
        let engine = makeEngine()
        // Both single-clause spines are equally long here, so only the stated
        // rule decides which one comes back.
        let spine = engine.sharedSpine(swappedLeft, swappedRight)
        try #require(spine.count == 1)
        #expect(spine == ["payment-terms"])
    }
}

@Suite("Part 3 - Minimal edit script")
struct DiffPart3Tests {
    @Test("the worked revisions are two edits apart")
    func workedDistance() {
        let engine = makeEngine()
        #expect(engine.editDistance(workedLeft, workedRight) == 2)
    }

    @Test("turning a revision into nothing costs one edit per clause, in both directions")
    func emptyInEitherDirection() {
        let engine = makeEngine()
        #expect(engine.editDistance(workedLeft, []) == 4)
        #expect(engine.editDistance([], workedRight) == 4)
        #expect(engine.editDistance([], []) == 0)
    }

    @Test("an unchanged revision needs no edits")
    func unchangedRevision() {
        let engine = makeEngine()
        #expect(engine.editDistance(workedLeft, workedLeft) == 0)
    }

    @Test("a swap of two clauses costs two edits")
    func swappedRevisions() {
        let engine = makeEngine()
        #expect(engine.editDistance(swappedLeft, swappedRight) == 2)
    }

    @Test("the script costs exactly what the distance says")
    func scriptCostMatchesDistance() {
        let engine = makeEngine()
        for fixture in alignmentFixtures {
            #expect(
                engine.editScript(fixture.left, fixture.right).totalCost
                    == engine.editDistance(fixture.left, fixture.right)
            )
        }
    }

    @Test("running the script against the left revision produces the right one")
    func scriptReproducesTheTarget() {
        let engine = makeEngine()
        for fixture in alignmentFixtures {
            let script = engine.editScript(fixture.left, fixture.right)
            #expect(apply(script.operations, to: fixture.left) == fixture.right)
        }
    }

    @Test("the worked script is the documented one")
    func workedScript() throws {
        let engine = makeEngine()
        let script = engine.editScript(workedLeft, workedRight)
        try #require(script.operations.count == 4)
        // Replacing twice and deleting-then-inserting both cost two here, and
        // the documented precedence prefers a replacement.
        #expect(script.operations == [
            .keep("recitals"),
            .replace(from: "payment-terms", to: "liability"),
            .replace(from: "liability", to: "arbitration"),
            .keep("notices"),
        ])
    }

    @Test("forbidding replacement costs the two revisions minus the spine twice over")
    func deleteOnlyMatchesTheSpine() {
        let engine = makeEngine()
        for fixture in alignmentFixtures {
            let expected = fixture.left.count + fixture.right.count
                - 2 * engine.sharedSpineLength(fixture.left, fixture.right)
            #expect(engine.deleteOnlyDistance(fixture.left, fixture.right) == expected)
        }
    }

    @Test("forbidding replacement never costs less than allowing it")
    func deleteOnlyIsNeverCheaper() {
        let engine = makeEngine()
        for fixture in alignmentFixtures {
            #expect(
                engine.deleteOnlyDistance(fixture.left, fixture.right)
                    >= engine.editDistance(fixture.left, fixture.right)
            )
        }
    }
}

@Suite("Part 4 - Price the script with review weights")
struct DiffPart4Tests {
    @Test("weighting every clause the same reproduces the unweighted cost")
    func unitWeightsReproducePartThree() throws {
        let engine = makeEngine()
        for fixture in alignmentFixtures {
            let ids = Set(fixture.left + fixture.right).sorted()
            let weights = ids.map { Clause(id: $0, reviewWeight: 1) }
            let weighted = try engine.weightedEditScript(fixture.left, fixture.right, weights: weights)
            #expect(weighted.totalCost == engine.editScript(fixture.left, fixture.right).totalCost)
        }
    }

    @Test("supplying no weights at all is the same as weighting everything the same")
    func noWeightsIsUnitWeights() throws {
        let engine = makeEngine()
        let weighted = try engine.weightedEditScript(workedLeft, workedRight, weights: [])
        #expect(weighted == engine.editScript(workedLeft, workedRight))
    }

    @Test("a clause with no listed weight reviews like an ordinary one")
    func unlistedClauseDefaultsToOne() throws {
        let engine = makeEngine()
        // Only one of the four clauses is listed, and the other three still cost
        // what an ordinary clause costs.
        let weighted = try engine.weightedEditScript(
            workedLeft, workedRight,
            weights: [Clause(id: "payment-terms", reviewWeight: 9)]
        )
        #expect(weighted.totalCost == 10)
    }

    @Test("the worked weighted script prices the sensitive clause at its weight")
    func workedWeightedScript() throws {
        let engine = makeEngine()
        let weighted = try engine.weightedEditScript(
            workedLeft, workedRight,
            weights: [Clause(id: "payment-terms", reviewWeight: 9)]
        )
        try #require(weighted.operations.count == 4)
        #expect(weighted.operations == [
            .keep("recitals"),
            .replace(from: "payment-terms", to: "liability"),
            .replace(from: "liability", to: "arbitration"),
            .keep("notices"),
        ])
    }

    @Test("a heavy clause changes which alignment is chosen")
    func weightsChangeTheChosenScript() throws {
        let engine = makeEngine()
        let unweighted = engine.editScript(swappedLeft, swappedRight)
        try #require(unweighted.operations.count == 2)
        #expect(unweighted.operations == [
            .replace(from: "payment-terms", to: "notices"),
            .replace(from: "notices", to: "payment-terms"),
        ])

        let weighted = try engine.weightedEditScript(
            swappedLeft, swappedRight,
            weights: [Clause(id: "payment-terms", reviewWeight: 9)]
        )
        try #require(weighted.operations.count == 3)
        // Moving the boilerplate clause around the sensitive one costs two,
        // where rewriting the sensitive clause twice would have cost eighteen.
        #expect(weighted.operations == [
            .insert("notices"),
            .keep("payment-terms"),
            .delete("notices"),
        ])
        #expect(weighted.totalCost == 2)
        #expect(weighted.operations != unweighted.operations)
    }

    @Test("the weighted script still turns the left revision into the right one")
    func weightedScriptReproducesTheTarget() throws {
        let engine = makeEngine()
        let weights = [
            Clause(id: "payment-terms", reviewWeight: 9),
            Clause(id: "notices", reviewWeight: 0),
        ]
        for fixture in alignmentFixtures {
            let script = try engine.weightedEditScript(fixture.left, fixture.right, weights: weights)
            #expect(apply(script.operations, to: fixture.left) == fixture.right)
        }
    }

    @Test("a negative review weight is a typed failure naming the clause")
    func negativeWeightFails() {
        let engine = makeEngine()
        #expect(throws: DiffError.negativeReviewWeight("liability")) {
            try engine.weightedEditScript(
                workedLeft, workedRight,
                weights: [Clause(id: "liability", reviewWeight: -1)]
            )
        }
    }

    @Test("the same clause weighted twice is a typed failure naming the clause")
    func duplicateWeightFails() {
        let engine = makeEngine()
        #expect(throws: DiffError.duplicateClauseWeight("notices")) {
            try engine.weightedEditScript(
                workedLeft, workedRight,
                weights: [
                    Clause(id: "notices", reviewWeight: 2),
                    Clause(id: "notices", reviewWeight: 3),
                ]
            )
        }
    }

    @Test("engines are independent and never mutate the revisions they are given")
    func enginesAreIndependentAndNonMutating() throws {
        let busy = makeEngine()
        let fresh = makeEngine()

        var left = workedLeft
        var right = workedRight
        let originalLeft = left
        let originalRight = right

        for _ in 0..<5 {
            _ = busy.mergedRevision(greedyTrapLeft, greedyTrapRight)
            _ = busy.editScript(left, right)
            _ = try busy.weightedEditScript(
                swappedLeft, swappedRight,
                weights: [Clause(id: "payment-terms", reviewWeight: 9)]
            )
        }

        // A second engine still reports the documented answers, which is what a
        // table cached in static storage would break.
        #expect(fresh.sharedSpineLength(workedLeft, workedRight) == 3)
        #expect(fresh.sharedSpine(workedLeft, workedRight) == ["recitals", "liability", "notices"])
        #expect(fresh.editDistance(workedLeft, workedRight) == 2)
        #expect(busy.editScript(workedLeft, workedRight) == fresh.editScript(workedLeft, workedRight))

        // The caller's revisions are untouched, and a caller mutating its own
        // copies changes nothing about a later call.
        #expect(left == originalLeft)
        #expect(right == originalRight)
        left.removeLast()
        right.removeAll()
        #expect(fresh.editDistance(originalLeft, originalRight) == 2)
    }
}
