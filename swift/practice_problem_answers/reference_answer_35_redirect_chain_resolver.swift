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

    /// Walk the chain with one cursor at one hop per step and another at two,
    /// and say what happened.
    ///
    /// The return carries the meeting id rather than a bare yes or no, because
    /// the meeting point is the only thing phase two has to start from. A probe
    /// that answered `true` would leave the next part re-running this entire
    /// walk to recover something this one already knew.
    public func probe(from id: String) throws(ChainError) -> ChainProbe {
        guard table.contains(id) else { throw .unknownAlias(id) }

        var slow = id
        var fast = id

        while true {
            guard let oneHop = table.target(of: fast) else { return .terminates(finalID: fast) }
            guard let twoHops = table.target(of: oneHop) else { return .terminates(finalID: oneHop) }
            fast = twoHops
            // Safe: the fast cursor got two hops out of this position, so the
            // slow cursor, which is behind it, can certainly take one.
            slow = table.target(of: slow) ?? slow
            if slow == fast { return .loops(meetingID: slow) }
        }
    }

    // MARK: Part 2 - Resolve to a terminal or a named loop

    /// Where this id actually ends up: a real destination and how far away it
    /// is, or the loop it falls into and how big that loop is.
    ///
    /// The probe is phase one. On a chain that terminates the work left is a
    /// single walk that counts hops. On a chain that loops the work left is
    /// phase two, and phase two is a proof rather than a coding detail: the
    /// distance from the start to the loop entry equals the distance from the
    /// meeting point to the loop entry, so resetting one cursor to the start
    /// and stepping both one hop at a time lands them together on the entry.
    public func resolve(from id: String) -> Resolution {
        guard let outcome = try? probe(from: id) else { return .unknownAlias(id) }

        switch outcome {
        case .terminates(let finalID):
            var hops = 0
            var cursor = id
            while cursor != finalID, let next = table.target(of: cursor) {
                cursor = next
                hops += 1
            }
            return .terminal(id: finalID, hops: hops)

        case .loops(let meetingID):
            var fromStart = id
            var fromMeeting = meetingID
            while fromStart != fromMeeting {
                fromStart = table.target(of: fromStart) ?? fromStart
                fromMeeting = table.target(of: fromMeeting) ?? fromMeeting
            }
            let entry = fromStart

            var length = 1
            var cursor = table.target(of: entry) ?? entry
            while cursor != entry {
                cursor = table.target(of: cursor) ?? cursor
                length += 1
            }
            return .cycle(entryID: entry, length: length)
        }
    }

    // MARK: Part 3 - Positional queries on a terminating chain

    /// The id halfway along a chain that terminates, taking the later of the
    /// two middles when the chain has an even number of ids.
    ///
    /// Two cursors again, and the rate difference is doing something completely
    /// different from what it did in Part 1: when the fast cursor runs out of
    /// chain the slow one is standing on the middle.
    public func midpointID(from id: String) throws(ChainError) -> String {
        try requireTerminating(id)

        var slow = id
        var fast: String? = id
        while let position = fast, let oneHop = table.target(of: position) {
            slow = table.target(of: slow) ?? slow
            fast = table.target(of: oneHop)
        }
        return slow
    }

    /// The id `offset` places from the end of a chain that terminates, counting
    /// the destination itself as one.
    ///
    /// A lead cursor goes `offset - 1` hops out first, then both cursors step
    /// together until the lead reaches the destination. The gap between them is
    /// the answer, and nothing has to be stored to find it.
    public func id(from start: String, hopsFromEnd offset: Int) throws(ChainError) -> String {
        guard offset > 0 else { throw .nonPositiveOffset(offset) }
        try requireTerminating(start)

        var lead = start
        var length = 1
        for _ in 1..<offset {
            guard let next = table.target(of: lead) else {
                throw .offsetBeyondChain(offset: offset, length: length)
            }
            lead = next
            length += 1
        }

        var trail = start
        while let next = table.target(of: lead) {
            lead = next
            trail = table.target(of: trail) ?? trail
        }
        return trail
    }

    // MARK: Part 4 - Audit the whole table

    /// Resolve every alias in the table and summarise what came back.
    ///
    /// This is Part 2 applied across the table and nothing else. Where two
    /// aliases tie on length the earlier id wins, so the audit does not depend
    /// on dictionary ordering.
    public func audit() -> ChainAudit {
        var terminalCount = 0
        var cyclicCount = 0
        var longest: LongestChain?
        var entries: Set<String> = []

        for alias in table.aliasIDs {
            switch resolve(from: alias) {
            case .terminal(_, let hops):
                terminalCount += 1
                if hops > (longest?.hops ?? -1) {
                    longest = LongestChain(startID: alias, hops: hops)
                }
            case .cycle(let entryID, _):
                cyclicCount += 1
                entries.insert(entryID)
            case .unknownAlias:
                continue
            }
        }

        return ChainAudit(
            terminalCount: terminalCount,
            cyclicCount: cyclicCount,
            longestChain: longest,
            cycleEntryIDs: entries.sorted()
        )
    }

    // MARK: Shared gate for the positional queries

    /// The positional queries only mean anything on a chain that ends, so they
    /// share one gate, and that gate is Part 2 rather than a second walk.
    private func requireTerminating(_ id: String) throws(ChainError) {
        switch resolve(from: id) {
        case .terminal:
            return
        case .cycle(let entryID, _):
            throw .cyclicChain(entryID: entryID)
        case .unknownAlias(let missing):
            throw .unknownAlias(missing)
        }
    }
}
