import Testing
@testable import Problem35RedirectChainResolver

// ── Fixtures ─────────────────────────────────────────────────────────────────

/// The worked routing table. Three aliases lead to one destination; a loop of
/// three sits beside them with one alias feeding into it from outside.
private let workedTargets: [String: String] = [
    "go/deploy": "go/deploy-v2",
    "go/deploy-v2": "go/ship",
    "go/ship": "docs/shipping-guide",
    "go/old-runbook": "go/runbook",
    "go/runbook": "go/handbook",
    "go/handbook": "go/old-runbook",
    "go/legacy": "go/runbook",
]

/// A loop of three with a tail of two feeding into it. Started from the tail,
/// the two cursors meet somewhere inside the loop and not on its entry, which
/// is what makes phase two observable.
private let tailedLoopTargets: [String: String] = [
    "t-0": "t-1",
    "t-1": "loop-a",
    "loop-a": "loop-b",
    "loop-b": "loop-c",
    "loop-c": "loop-a",
]

/// The smallest loop there is.
private let selfLoopTargets: [String: String] = ["self-a": "self-a"]

/// A loop of two, where a resolver that returns the meeting point as the loop
/// entry happens to be right.
private let pingPongTargets: [String: String] = ["ping": "pong", "pong": "ping"]

private func makeResolver(_ targets: [String: String]) -> ChainResolver {
    ChainResolver(table: AliasTable(targets: targets))
}

// ── Part 1 ───────────────────────────────────────────────────────────────────

@Suite("Part 1 - Probe a chain in constant memory")
struct ResolverPart1Tests {
    @Test("a chain that ends reports its destination")
    func chainThatEnds() throws {
        let resolver = makeResolver(workedTargets)

        #expect(try resolver.probe(from: "go/deploy") == .terminates(finalID: "docs/shipping-guide"))
        #expect(try resolver.probe(from: "go/ship") == .terminates(finalID: "docs/shipping-guide"))
    }

    @Test("a destination probes as itself")
    func destinationProbesAsItself() throws {
        let resolver = makeResolver(workedTargets)

        #expect(try resolver.probe(from: "docs/shipping-guide") == .terminates(finalID: "docs/shipping-guide"))
    }

    @Test("a chain that closes on itself reports a meeting inside the loop")
    func chainThatLoops() throws {
        let resolver = makeResolver(tailedLoopTargets)
        let outcome = try resolver.probe(from: "t-0")

        guard case .loops(let meetingID) = outcome else {
            Issue.record("expected a loop, got \(outcome)")
            return
        }
        #expect(["loop-a", "loop-b", "loop-c"].contains(meetingID))
    }

    @Test("an alias pointing at itself is a loop")
    func selfLoop() throws {
        let resolver = makeResolver(selfLoopTargets)

        #expect(try resolver.probe(from: "self-a") == .loops(meetingID: "self-a"))
    }

    @Test("a loop of two is a loop")
    func loopOfTwo() throws {
        let resolver = makeResolver(pingPongTargets)
        let outcome = try resolver.probe(from: "ping")

        guard case .loops(let meetingID) = outcome else {
            Issue.record("expected a loop, got \(outcome)")
            return
        }
        #expect(["ping", "pong"].contains(meetingID))
    }

    @Test("an id the table has never heard of is a typed failure")
    func unknownAliasFails() {
        let resolver = makeResolver(workedTargets)

        #expect(throws: ChainError.unknownAlias("go/nowhere")) {
            try resolver.probe(from: "go/nowhere")
        }
    }

    @Test("an empty table knows nothing")
    func emptyTable() {
        let resolver = makeResolver([:])

        #expect(throws: ChainError.unknownAlias("anything")) {
            try resolver.probe(from: "anything")
        }
    }
}

// ── Part 2 ───────────────────────────────────────────────────────────────────

@Suite("Part 2 - Resolve to a terminal or a named loop")
struct ResolverPart2Tests {
    @Test("a chain of three hops reports its destination and its length")
    func chainOfThreeHops() {
        let resolver = makeResolver(workedTargets)

        #expect(resolver.resolve(from: "go/deploy") == .terminal(id: "docs/shipping-guide", hops: 3))
        #expect(resolver.resolve(from: "go/deploy-v2") == .terminal(id: "docs/shipping-guide", hops: 2))
        #expect(resolver.resolve(from: "go/ship") == .terminal(id: "docs/shipping-guide", hops: 1))
    }

    @Test("a destination is zero hops from itself")
    func destinationIsZeroHops() {
        let resolver = makeResolver(workedTargets)

        #expect(resolver.resolve(from: "docs/shipping-guide") == .terminal(id: "docs/shipping-guide", hops: 0))
    }

    @Test("an alias feeding a loop from outside names the loop's entry, not the meeting point")
    func tailIntoLoopNamesTheEntry() {
        let resolver = makeResolver(tailedLoopTargets)

        // Started from the tail the cursors meet on loop-b, not on loop-a.
        // A resolver that hands back the meeting point answers loop-b here.
        #expect(resolver.resolve(from: "t-0") == .cycle(entryID: "loop-a", length: 3))
        #expect(resolver.resolve(from: "t-1") == .cycle(entryID: "loop-a", length: 3))
    }

    @Test("an id already inside a loop is its own entry")
    func idInsideALoopIsItsOwnEntry() {
        let resolver = makeResolver(tailedLoopTargets)

        #expect(resolver.resolve(from: "loop-a") == .cycle(entryID: "loop-a", length: 3))
        #expect(resolver.resolve(from: "loop-b") == .cycle(entryID: "loop-b", length: 3))
        #expect(resolver.resolve(from: "loop-c") == .cycle(entryID: "loop-c", length: 3))
    }

    @Test("the smallest loops report their true lengths")
    func smallLoopLengths() {
        #expect(makeResolver(selfLoopTargets).resolve(from: "self-a") == .cycle(entryID: "self-a", length: 1))
        #expect(makeResolver(pingPongTargets).resolve(from: "ping") == .cycle(entryID: "ping", length: 2))
        #expect(makeResolver(pingPongTargets).resolve(from: "pong") == .cycle(entryID: "pong", length: 2))
    }

    @Test("the worked table's outside alias enters the loop one hop in")
    func workedTableLoopEntry() {
        let resolver = makeResolver(workedTargets)

        #expect(resolver.resolve(from: "go/legacy") == .cycle(entryID: "go/runbook", length: 3))
    }

    @Test("an unknown id is one of the answers rather than a failure")
    func unknownIsAnAnswer() {
        let resolver = makeResolver(workedTargets)

        #expect(resolver.resolve(from: "go/nowhere") == .unknownAlias("go/nowhere"))
        #expect(makeResolver([:]).resolve(from: "anything") == .unknownAlias("anything"))
    }

    @Test("resolving agrees with the probe on every id in the table")
    func resolvingAgreesWithProbing() throws {
        for targets in [workedTargets, tailedLoopTargets, selfLoopTargets, pingPongTargets] {
            let resolver = makeResolver(targets)
            for alias in AliasTable(targets: targets).aliasIDs {
                let probe = try resolver.probe(from: alias)
                switch (probe, resolver.resolve(from: alias)) {
                case (.terminates(let finalID), .terminal(let id, _)):
                    #expect(finalID == id)
                case (.loops, .cycle(_, let length)):
                    #expect(length >= 1)
                default:
                    Issue.record("probe and resolve disagree about \(alias)")
                }
            }
        }
    }
}

// ── Part 3 ───────────────────────────────────────────────────────────────────

@Suite("Part 3 - Positional queries on a terminating chain")
struct ResolverPart3Tests {
    @Test("the midpoint of a four-id chain is the third id")
    func midpointOfEvenChain() throws {
        let resolver = makeResolver(workedTargets)

        // go/deploy, go/deploy-v2, go/ship, docs/shipping-guide: the later of
        // the two middles.
        #expect(try resolver.midpointID(from: "go/deploy") == "go/ship")
    }

    @Test("the midpoint of a three-id chain is the middle id")
    func midpointOfOddChain() throws {
        let resolver = makeResolver(workedTargets)

        #expect(try resolver.midpointID(from: "go/deploy-v2") == "go/ship")
    }

    @Test("the midpoint of a two-id chain is the destination and of a one-id chain is itself")
    func midpointOfShortChains() throws {
        let resolver = makeResolver(workedTargets)

        #expect(try resolver.midpointID(from: "go/ship") == "docs/shipping-guide")
        #expect(try resolver.midpointID(from: "docs/shipping-guide") == "docs/shipping-guide")
    }

    @Test("counting from the end reaches the destination at one and the start at the full length")
    func countingFromTheEnd() throws {
        let resolver = makeResolver(workedTargets)

        #expect(try resolver.id(from: "go/deploy", hopsFromEnd: 1) == "docs/shipping-guide")
        #expect(try resolver.id(from: "go/deploy", hopsFromEnd: 2) == "go/ship")
        #expect(try resolver.id(from: "go/deploy", hopsFromEnd: 3) == "go/deploy-v2")
        #expect(try resolver.id(from: "go/deploy", hopsFromEnd: 4) == "go/deploy")
    }

    @Test("counting from the end of a one-id chain reaches only that id")
    func countingFromTheEndOfAOneIDChain() throws {
        let resolver = makeResolver(workedTargets)

        #expect(try resolver.id(from: "docs/shipping-guide", hopsFromEnd: 1) == "docs/shipping-guide")
    }

    @Test("an offset past the start of the chain is a typed failure carrying both numbers")
    func offsetBeyondChainFails() {
        let resolver = makeResolver(workedTargets)

        #expect(throws: ChainError.offsetBeyondChain(offset: 5, length: 4)) {
            try resolver.id(from: "go/deploy", hopsFromEnd: 5)
        }
        #expect(throws: ChainError.offsetBeyondChain(offset: 2, length: 1)) {
            try resolver.id(from: "docs/shipping-guide", hopsFromEnd: 2)
        }
    }

    @Test("an offset of zero or less is a typed failure")
    func nonPositiveOffsetFails() {
        let resolver = makeResolver(workedTargets)

        #expect(throws: ChainError.nonPositiveOffset(0)) {
            try resolver.id(from: "go/deploy", hopsFromEnd: 0)
        }
        #expect(throws: ChainError.nonPositiveOffset(-3)) {
            try resolver.id(from: "go/deploy", hopsFromEnd: -3)
        }
    }

    @Test("neither question means anything on a chain that loops")
    func loopingChainsRefuseBothQuestions() {
        let resolver = makeResolver(tailedLoopTargets)

        #expect(throws: ChainError.cyclicChain(entryID: "loop-a")) {
            try resolver.midpointID(from: "t-0")
        }
        #expect(throws: ChainError.cyclicChain(entryID: "loop-a")) {
            try resolver.id(from: "t-0", hopsFromEnd: 2)
        }
        #expect(throws: ChainError.cyclicChain(entryID: "self-a")) {
            try makeResolver(selfLoopTargets).midpointID(from: "self-a")
        }
    }

    @Test("an unknown id is a typed failure for both questions")
    func unknownIDFailsBothQueries() {
        let resolver = makeResolver(workedTargets)

        #expect(throws: ChainError.unknownAlias("go/nowhere")) {
            try resolver.midpointID(from: "go/nowhere")
        }
        #expect(throws: ChainError.unknownAlias("go/nowhere")) {
            try resolver.id(from: "go/nowhere", hopsFromEnd: 1)
        }
    }

    @Test("the offset that reaches the start is exactly one more than the hop count")
    func offsetAtFullLengthReturnsTheStart() throws {
        let resolver = makeResolver(workedTargets)

        for alias in ["go/deploy", "go/deploy-v2", "go/ship", "docs/shipping-guide"] {
            guard case .terminal(_, let hops) = resolver.resolve(from: alias) else {
                Issue.record("\(alias) should reach a destination")
                continue
            }
            #expect(try resolver.id(from: alias, hopsFromEnd: hops + 1) == alias)
            #expect(throws: ChainError.offsetBeyondChain(offset: hops + 2, length: hops + 1)) {
                try resolver.id(from: alias, hopsFromEnd: hops + 2)
            }
        }
    }
}

// ── Part 4 ───────────────────────────────────────────────────────────────────

@Suite("Part 4 - Audit the whole table")
struct ResolverPart4Tests {
    @Test("the worked table audits to three terminating aliases and four caught in loops")
    func workedTableAudit() {
        let resolver = makeResolver(workedTargets)
        let audit = resolver.audit()

        #expect(audit.terminalCount == 3)
        #expect(audit.cyclicCount == 4)
        #expect(audit.longestChain == LongestChain(startID: "go/deploy", hops: 3))
        #expect(audit.cycleEntryIDs == ["go/handbook", "go/old-runbook", "go/runbook"])
    }

    @Test("a table that is nothing but a loop has no longest chain")
    func allCyclicTable() {
        let resolver = makeResolver(tailedLoopTargets)
        let audit = resolver.audit()

        #expect(audit.terminalCount == 0)
        #expect(audit.cyclicCount == 5)
        #expect(audit.longestChain == nil)
        #expect(audit.cycleEntryIDs == ["loop-a", "loop-b", "loop-c"])
    }

    @Test("an empty table audits to nothing at all")
    func emptyTableAudit() {
        let audit = makeResolver([:]).audit()

        #expect(audit == ChainAudit(terminalCount: 0, cyclicCount: 0, longestChain: nil, cycleEntryIDs: []))
    }

    @Test("a table with no loops reports every alias as terminating")
    func acyclicTableAudit() {
        let resolver = makeResolver([
            "a": "b",
            "b": "c",
            "c": "dest",
            "solo": "dest",
        ])
        let audit = resolver.audit()

        #expect(audit.terminalCount == 4)
        #expect(audit.cyclicCount == 0)
        #expect(audit.longestChain == LongestChain(startID: "a", hops: 3))
        #expect(audit.cycleEntryIDs.isEmpty)
    }

    @Test("aliases tied on chain length resolve to the earlier id")
    func tiedLongestChainsResolveToTheEarlierID() {
        let resolver = makeResolver([
            "zeta": "zeta-dest",
            "alpha": "alpha-dest",
        ])
        let audit = resolver.audit()

        #expect(audit.longestChain == LongestChain(startID: "alpha", hops: 1))
    }

    @Test("the counts add up to the number of aliases the table holds")
    func countsAddUp() {
        for targets in [workedTargets, tailedLoopTargets, selfLoopTargets, pingPongTargets, [:]] {
            let audit = makeResolver(targets).audit()
            #expect(audit.terminalCount + audit.cyclicCount == targets.count)
            #expect(audit.cycleEntryIDs == audit.cycleEntryIDs.sorted())
            #expect(Set(audit.cycleEntryIDs).count == audit.cycleEntryIDs.count)
        }
    }

    @Test("resolvers are independent and never depend on how often they have been used")
    func resolversAreIndependent() throws {
        let table = AliasTable(targets: workedTargets)
        let busy = ChainResolver(table: table)
        let fresh = ChainResolver(table: table)

        for _ in 0..<200 {
            _ = busy.resolve(from: "go/deploy")
            _ = busy.resolve(from: "go/legacy")
            _ = busy.audit()
        }

        // A second resolver over the same table still reports the documented
        // answers, which is what a resolution memo held in static storage would
        // break.
        #expect(fresh.resolve(from: "go/deploy") == .terminal(id: "docs/shipping-guide", hops: 3))
        #expect(fresh.resolve(from: "go/legacy") == .cycle(entryID: "go/runbook", length: 3))
        #expect(try fresh.midpointID(from: "go/deploy") == "go/ship")

        // And the busy one has not drifted.
        #expect(busy.audit() == fresh.audit())
        #expect(busy.resolve(from: "go/ship") == .terminal(id: "docs/shipping-guide", hops: 1))

        // A resolver over a different table answers for that table, not for
        // whichever one was asked first.
        let other = ChainResolver(table: AliasTable(targets: tailedLoopTargets))
        #expect(other.resolve(from: "t-0") == .cycle(entryID: "loop-a", length: 3))
        #expect(fresh.resolve(from: "go/deploy") == .terminal(id: "docs/shipping-guide", hops: 3))
    }
}
