public struct ChargeSession: Equatable, Sendable {
    public let vehicleID: String
    public let arrival: Int
    public let departure: Int

    public init(vehicleID: String, arrival: Int, departure: Int) {
        self.vehicleID = vehicleID
        self.arrival = arrival
        self.departure = departure
    }
}

public enum ChargeEvent: Equatable, Sendable {
    case arrives(vehicleID: String, at: Int)
    case departs(vehicleID: String, at: Int)

    public var instant: Int {
        switch self {
        case .arrives(_, let at), .departs(_, let at): at
        }
    }

    public var vehicleID: String {
        switch self {
        case .arrives(let vehicleID, _), .departs(let vehicleID, _): vehicleID
        }
    }
}

public struct PeakWindow: Equatable, Sendable {
    public let start: Int
    public let end: Int
    public let occupancy: Int
    public let vehicleIDs: [String]

    public init(start: Int, end: Int, occupancy: Int, vehicleIDs: [String]) {
        self.start = start
        self.end = end
        self.occupancy = occupancy
        self.vehicleIDs = vehicleIDs
    }
}

public enum DepotError: Error, Equatable, Sendable {
    case departureNotAfterArrival(vehicleID: String)
    case duplicateVehicleID(String)
    case tooManySessions(Int)
    case notImplemented
}

/// A binary min-heap, provided because the standard library has none and
/// building one is not what this problem is about. Use it, or do not; the
/// public interface is what the tests read.
public struct MinHeap<Element: Comparable>: Sendable where Element: Sendable {
    private var storage: [Element] = []

    public init() {}

    public var count: Int { storage.count }
    public var isEmpty: Bool { storage.isEmpty }

    /// The smallest element, without removing it.
    public var minimum: Element? { storage.first }

    public mutating func insert(_ element: Element) {
        storage.append(element)
        var child = storage.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard storage[child] < storage[parent] else { break }
            storage.swapAt(child, parent)
            child = parent
        }
    }

    public mutating func popMin() -> Element? {
        guard let smallest = storage.first else { return nil }
        storage.swapAt(0, storage.count - 1)
        storage.removeLast()

        var parent = 0
        while true {
            let left = parent * 2 + 1
            let right = left + 1
            var swap = parent
            if left < storage.count, storage[left] < storage[swap] { swap = left }
            if right < storage.count, storage[right] < storage[swap] { swap = right }
            guard swap != parent else { break }
            storage.swapAt(parent, swap)
            parent = swap
        }
        return smallest
    }
}

public struct ChargerCapacitySizer: Sendable {
    /// The day's schedule is bounded, which is also what makes the quadratic
    /// version of the second part unusable rather than merely slow.
    public static let maximumSessionCount = 100_000

    public init() {}

    // MARK: Part 1 - Decompose into events

    /// The schedule as the arrivals and departures a sweep walks.
    ///
    /// The ordering is the whole boundary decision and it is made once, here.
    /// At a shared instant departures come first, because a bay vacated at 30
    /// is available to a vehicle arriving at 30. Leaving that to the sort's
    /// stability is not a contract, and it is off by one bay on exactly the
    /// schedules a depot cares about.
    public func events(from sessions: [ChargeSession]) throws(DepotError) -> [ChargeEvent] {
        try validate(sessions)

        var timeline: [ChargeEvent] = []
        timeline.reserveCapacity(sessions.count * 2)
        for session in sessions {
            timeline.append(.arrives(vehicleID: session.vehicleID, at: session.arrival))
            timeline.append(.departs(vehicleID: session.vehicleID, at: session.departure))
        }

        return timeline.sorted { left, right in
            if left.instant != right.instant { return left.instant < right.instant }
            if left.isDeparture != right.isDeparture { return left.isDeparture }
            return left.vehicleID < right.vehicleID
        }
    }

    // MARK: Part 2 - Peak occupancy

    /// How many bays the depot must build so that no returning vehicle waits.
    ///
    /// This reads the maximum off the one sweep in the file rather than
    /// running a sweep of its own. The alternative that suggests itself, one
    /// comparison per pair of sessions, is correct and quadratic; at the
    /// supported session count it is ten billion comparisons and no test here
    /// would tell you.
    public func requiredBays(_ sessions: [ChargeSession]) throws(DepotError) -> Int {
        try occupancySegments(sessions).map(\.occupancy).max() ?? 0
    }

    // MARK: Part 3 - When, and who

    /// Every stretch of the day at which the depot is at its peak, with the
    /// vehicles parked during it.
    ///
    /// Consecutive stretches stay separate even when both sit at the peak: an
    /// event between them changed who is parked, and merging them would report
    /// a set of vehicles that were never simultaneously present.
    public func peakWindows(_ sessions: [ChargeSession]) throws(DepotError) -> [PeakWindow] {
        let segments = try occupancySegments(sessions)
        guard let peak = segments.map(\.occupancy).max() else { return [] }
        return segments.filter { $0.occupancy == peak }
    }

    // MARK: Part 4 - Assign a bay to every session

    /// The bay each vehicle should be sent to, using no more bays than the
    /// depot must build.
    ///
    /// The running counter of the sweep cannot answer this: it knows how many
    /// vehicles are parked, never which bay each is in. Releasing a bay means
    /// knowing when its occupant leaves, so the occupied bays live in a heap
    /// keyed by departure and the free ones in a heap keyed by index, which is
    /// what keeps the assignment reproducible.
    public func bayAssignment(_ sessions: [ChargeSession]) throws(DepotError) -> [String: Int] {
        try validate(sessions)

        let byArrival = sessions.sorted { left, right in
            left.arrival == right.arrival
                ? left.vehicleID < right.vehicleID
                : left.arrival < right.arrival
        }

        var assignment: [String: Int] = [:]
        var occupied = MinHeap<OccupiedBay>()
        var free = MinHeap<Int>()
        var opened = 0

        for session in byArrival {
            // Half-open again: a bay whose occupant departs exactly now is
            // free now, so the release test is `<=` rather than `<`.
            while let head = occupied.minimum, head.releasesAt <= session.arrival {
                _ = occupied.popMin()
                free.insert(head.bay)
            }

            let bay: Int
            if let reused = free.popMin() {
                bay = reused
            } else {
                bay = opened
                opened += 1
            }

            assignment[session.vehicleID] = bay
            occupied.insert(OccupiedBay(releasesAt: session.departure, bay: bay))
        }

        return assignment
    }

    // MARK: The one sweep

    /// Every stretch between two consecutive events, with who is parked during
    /// it. Parts 2 and 3 are both projections of this, which is what keeps a
    /// single sweep in the file.
    private func occupancySegments(_ sessions: [ChargeSession]) throws(DepotError) -> [PeakWindow] {
        var segments: [PeakWindow] = []
        var parked: Set<String> = []
        var cursor: Int?

        for event in try events(from: sessions) {
            if let start = cursor, event.instant > start, !parked.isEmpty {
                segments.append(
                    PeakWindow(
                        start: start,
                        end: event.instant,
                        occupancy: parked.count,
                        vehicleIDs: parked.sorted()
                    )
                )
            }

            switch event {
            case .arrives(let vehicleID, _): parked.insert(vehicleID)
            case .departs(let vehicleID, _): parked.remove(vehicleID)
            }
            cursor = event.instant
        }

        return segments
    }

    /// One occupied bay, ordered by the instant it frees up so the heap always
    /// offers the bay that becomes available soonest.
    private struct OccupiedBay: Comparable, Sendable {
        let releasesAt: Int
        let bay: Int

        static func < (lhs: OccupiedBay, rhs: OccupiedBay) -> Bool {
            lhs.releasesAt == rhs.releasesAt ? lhs.bay < rhs.bay : lhs.releasesAt < rhs.releasesAt
        }
    }

    // MARK: Shared validation

    /// The precondition every part rests on. Parts 2 and 3 reach it through
    /// the event decomposition; Part 4 does not walk events at all, so it
    /// calls this directly.
    private func validate(_ sessions: [ChargeSession]) throws(DepotError) {
        guard sessions.count <= Self.maximumSessionCount else {
            throw .tooManySessions(sessions.count)
        }
        var seen = Set<String>()
        seen.reserveCapacity(sessions.count)
        for session in sessions {
            guard session.departure > session.arrival else {
                throw .departureNotAfterArrival(vehicleID: session.vehicleID)
            }
            guard seen.insert(session.vehicleID).inserted else {
                throw .duplicateVehicleID(session.vehicleID)
            }
        }
    }
}

private extension ChargeEvent {
    /// Departures sort before arrivals at a shared instant, so the sweep needs
    /// to tell them apart without unwrapping their payloads.
    var isDeparture: Bool {
        if case .departs = self { return true }
        return false
    }
}
