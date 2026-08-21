// Problem 35: Redirect Chain Resolver
// Swift 6, macOS 14+ | Senior | approximately 45 minutes
//
// A routing layer holds an alias table: each alias resolves to at most one
// target, and that target may itself be an alias. Chains get long, and one bad
// edit can make a chain close on itself. The resolver runs on every request, on
// a machine that will not allocate a visited-set per resolution, so detecting a
// loop has to cost a fixed amount of memory no matter how long the chain is.
//
// This is the same two-pointer family as a sorted-array sweep, with the array
// taken away. There is no ordering here and no random access, only the promise
// that each id has at most one successor. What is left of the family is the
// only thing it ever really needed: two cursors moving over the same structure
// at different rates.
//
// `AliasTable` is given to you. You choose everything else; the public
// interface is the contract. Store all mutable state in instance properties
// initialized by init. Never use mutable global or static state. Immutable
// static constants are fine.
//
/*
# Example
let table = AliasTable(targets: [
    "go/deploy": "go/deploy-v2",
    "go/deploy-v2": "go/ship",
    "go/ship": "docs/shipping-guide",
    "go/old-runbook": "go/runbook",
    "go/runbook": "go/handbook",
    "go/handbook": "go/old-runbook",
    "go/legacy": "go/runbook",
])
let resolver = ChainResolver(table: table)

try resolver.probe(from: "go/deploy")
// -> .terminates(finalID: "docs/shipping-guide")

resolver.resolve(from: "go/deploy")
// -> .terminal(id: "docs/shipping-guide", hops: 3)
resolver.resolve(from: "go/legacy")
// -> .cycle(entryID: "go/runbook", length: 3)
resolver.resolve(from: "docs/shipping-guide")
// -> .terminal(id: "docs/shipping-guide", hops: 0)

try resolver.midpointID(from: "go/deploy")                  // -> "go/ship"
try resolver.id(from: "go/deploy", hopsFromEnd: 2)          // -> "go/ship"

resolver.audit()
// -> ChainAudit(terminalCount: 3, cyclicCount: 4,
//               longestChain: LongestChain(startID: "go/deploy", hops: 3),
//               cycleEntryIDs: ["go/handbook", "go/old-runbook", "go/runbook"])
*/
//
// PART 1 - Probe a chain in constant memory  (~10 min)
// Walk the chain from an id with one cursor taking a single hop per step and
// another taking two, and report what happened: the chain ended at a real
// destination, or the two cursors met, which can only happen inside a loop.
// An id the table has never heard of, neither as an alias nor as something an
// alias points at, is a typo rather than a destination, and it is a typed
// failure.
// The return type is the design decision in this problem and it is worth making
// deliberately. A probe that answered yes or no would tell Part 2 that a loop
// exists and nothing about where, so Part 2 would have to run this entire walk
// again to recover something this walk already knew. Report the meeting id.
//
// PART 2 - Resolve to a terminal or a named loop  (~13 min)
// Say where an id actually ends up: a real destination and how many hops away
// it is, or the loop it falls into and how long that loop is. This one does not
// fail; an unknown id is one of the answers.
// Part 1 is phase one. On a chain that ends, what is left is a single walk that
// counts hops. On a chain that loops, what is left is phase two, and phase two
// is a proof rather than a coding detail: the distance from the start to the
// loop entry is equal to the distance from the meeting point to the loop entry.
// Work out why before writing it. Resetting one cursor to the start and
// stepping both one hop at a time is what that proof licenses, and the
// plausible variants - resetting to the meeting point, or stepping the fast
// cursor two - are right on a loop of one and wrong on a loop of three.
// An id that is already a destination is zero hops from itself, and an
// off-by-one here is invisible until a chain of one.
//
// PART 3 - Positional queries on a terminating chain  (~11 min)
// Two questions about a chain that ends: which id sits halfway along it, and
// which id sits a given number of places from the end, counting the destination
// itself as one.
// Both are the rate trick doing something completely different from Part 1,
// which is the point: when the fast cursor runs out of chain, the slow cursor
// is standing on the middle. Where the chain has an even number of ids, take
// the later of the two middles.
// For the query from the end, send one cursor out ahead by the offset and then
// step both together. An offset of zero or less is a typed failure, and so is
// an offset longer than the chain.
// Neither question means anything on a chain that loops, so both refuse one,
// naming the loop entry. Ask Part 2 rather than re-deriving that: it already
// knows, and it is where the gate belongs.
//
// PART 4 - Audit the whole table  (~11 min)
// Summarise the whole table: how many aliases reach a destination, how many
// fall into a loop, the alias with the longest chain to a destination, and
// every distinct loop entry, sorted and deduplicated.
// This is Part 2 applied across the table and nothing else. Where two aliases
// tie on chain length the earlier id wins, so the audit never depends on
// dictionary ordering.

public struct AliasTable: Sendable {
    private let targets: [String: String]
    private let known: Set<String>

    public init(targets: [String: String]) {
        self.targets = targets
        self.known = Set(targets.keys).union(targets.values)
    }

    /// The next id in the chain, or nil when this id resolves to itself: it is
    /// a real destination rather than another alias.
    public func target(of id: String) -> String? {
        targets[id]
    }

    /// Whether this id appears in the table at all, either as an alias or as
    /// something an alias points at. An id that does not is a typo rather than
    /// a terminal.
    public func contains(_ id: String) -> Bool {
        known.contains(id)
    }

    /// Every id the table redirects away from, sorted, so an audit walks the
    /// table in a stable order.
    public var aliasIDs: [String] {
        targets.keys.sorted()
    }
}

public enum ChainProbe: Equatable, Sendable {
    case terminates(finalID: String)
    case loops(meetingID: String)
}

public enum Resolution: Equatable, Sendable {
    case terminal(id: String, hops: Int)
    case cycle(entryID: String, length: Int)
    case unknownAlias(String)
}

public enum ChainError: Error, Equatable, Sendable {
    case unknownAlias(String)
    case cyclicChain(entryID: String)
    case nonPositiveOffset(Int)
    case offsetBeyondChain(offset: Int, length: Int)
    case notImplemented
}

public struct LongestChain: Equatable, Sendable {
    public let startID: String
    public let hops: Int

    public init(startID: String, hops: Int) {
        self.startID = startID
        self.hops = hops
    }
}

public struct ChainAudit: Equatable, Sendable {
    public let terminalCount: Int
    public let cyclicCount: Int
    public let longestChain: LongestChain?
    public let cycleEntryIDs: [String]

    public init(
        terminalCount: Int,
        cyclicCount: Int,
        longestChain: LongestChain?,
        cycleEntryIDs: [String]
    ) {
        self.terminalCount = terminalCount
        self.cyclicCount = cyclicCount
        self.longestChain = longestChain
        self.cycleEntryIDs = cycleEntryIDs
    }
}

public struct ChainResolver: Sendable {
    private let table: AliasTable

    public init(table: AliasTable) {
        self.table = table
    }

    // MARK: Part 1 - Probe a chain in constant memory
    public func probe(from id: String) throws(ChainError) -> ChainProbe {
        throw .notImplemented
    }

    // MARK: Part 2 - Resolve to a terminal or a named loop
    public func resolve(from id: String) -> Resolution {
        .unknownAlias(id)
    }

    // MARK: Part 3 - Positional queries on a terminating chain
    public func midpointID(from id: String) throws(ChainError) -> String {
        throw .notImplemented
    }

    public func id(from start: String, hopsFromEnd offset: Int) throws(ChainError) -> String {
        throw .notImplemented
    }

    // MARK: Part 4 - Audit the whole table
    public func audit() -> ChainAudit {
        ChainAudit(terminalCount: 0, cyclicCount: 0, longestChain: nil, cycleEntryIDs: [])
    }
}
