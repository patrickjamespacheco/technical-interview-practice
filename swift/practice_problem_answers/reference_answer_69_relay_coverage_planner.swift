public struct Relay: Equatable, Sendable {
    public let id: String
    public let position: Int
    public let radius: Int
    public init(id: String, position: Int, radius: Int) { self.id = id; self.position = position; self.radius = radius }
}

public enum CoverageError: Error, Equatable, Sendable {
    case uncoverable(gaps: [ClosedRange<Int>])
    case nonPositiveCorridorLength(Int)
    case negativeRadius(id: String)
    case duplicateRelayID(String)
    case tooManyRelays(Int)
    case negativeMargin(Int)
    case notImplemented
}

public struct RelayCoveragePlanner: Sendable {
    public static let maximumRelayCount = 100_000
    public init() {}

    public func reachRange(of relay: Relay, corridor: ClosedRange<Int>) -> ClosedRange<Int>? {
        guard relay.radius >= 0, corridor.lowerBound < corridor.upperBound else { return nil }
        let low = max(corridor.lowerBound, relay.position - relay.radius)
        let high = min(corridor.upperBound, relay.position + relay.radius)
        return low <= high ? low...high : nil
    }

    public func gaps(coveredBy relays: [Relay], corridor: ClosedRange<Int>) throws(CoverageError) -> [ClosedRange<Int>] {
        try validate(relays, corridor: corridor)
        let ranges = relays.compactMap { reachRange(of: $0, corridor: corridor) }.sorted {
            $0.lowerBound == $1.lowerBound ? $0.upperBound > $1.upperBound : $0.lowerBound < $1.lowerBound
        }
        var result: [ClosedRange<Int>] = []
        var next = corridor.lowerBound
        for range in ranges where next <= corridor.upperBound {
            if range.lowerBound > next { result.append(next...(range.lowerBound - 1)) }
            next = max(next, range.upperBound + 1)
        }
        if next <= corridor.upperBound { result.append(next...corridor.upperBound) }
        return result
    }

    public func minimumRelayCount(_ relays: [Relay], corridor: ClosedRange<Int>) throws(CoverageError) -> Int {
        try scan(relays, corridor: corridor, margin: 0).count
    }

    public func minimumRelaySelection(_ relays: [Relay], corridor: ClosedRange<Int>) throws(CoverageError) -> [String] {
        try scan(relays, corridor: corridor, margin: 0)
    }

    public func minimumRelaySelection(_ relays: [Relay], corridor: ClosedRange<Int>, handoffMargin: Int) throws(CoverageError) -> [String] {
        guard handoffMargin >= 0 else { throw .negativeMargin(handoffMargin) }
        return try scan(relays, corridor: corridor, margin: handoffMargin)
    }

    private func scan(_ relays: [Relay], corridor: ClosedRange<Int>, margin: Int) throws(CoverageError) -> [String] {
        try validate(relays, corridor: corridor)
        let uncovered = try gaps(coveredBy: relays, corridor: corridor)
        guard uncovered.isEmpty else { throw .uncoverable(gaps: uncovered) }
        let candidates = relays.compactMap { relay -> (Relay, ClosedRange<Int>)? in
            guard let range = reachRange(of: relay, corridor: corridor) else { return nil }
            return (relay, range)
        }
        var chosen: [String] = []
        var frontier = corridor.lowerBound
        var previousEnd: Int?
        while frontier <= corridor.upperBound {
            let eligibility = previousEnd.map { $0 - margin + 1 } ?? frontier
            let available = candidates.filter { pair in
                pair.1.lowerBound <= frontier && (previousEnd == nil || pair.1.lowerBound <= eligibility)
            }
            guard let best = available.max(by: { left, right in
                left.1.upperBound == right.1.upperBound ? left.0.id > right.0.id : left.1.upperBound < right.1.upperBound
            }), best.1.upperBound >= frontier else {
                throw .uncoverable(gaps: [frontier...corridor.upperBound])
            }
            chosen.append(best.0.id)
            if best.1.upperBound >= corridor.upperBound { break }
            guard best.1.upperBound >= frontier else { throw .uncoverable(gaps: [frontier...corridor.upperBound]) }
            previousEnd = best.1.upperBound
            frontier = best.1.upperBound + 1
        }
        return chosen
    }

    private func validate(_ relays: [Relay], corridor: ClosedRange<Int>) throws(CoverageError) {
        guard corridor.lowerBound < corridor.upperBound else { throw .nonPositiveCorridorLength(corridor.upperBound - corridor.lowerBound) }
        guard relays.count <= Self.maximumRelayCount else { throw .tooManyRelays(relays.count) }
        var ids = Set<String>()
        for relay in relays {
            guard relay.radius >= 0 else { throw .negativeRadius(id: relay.id) }
            guard ids.insert(relay.id).inserted else { throw .duplicateRelayID(relay.id) }
        }
    }
}
