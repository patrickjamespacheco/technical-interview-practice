// Problem 70: Depot Charger Capacity Sizer
// Swift 6, macOS 14+ | Senior | approximately 45 minutes
//
// An electric delivery fleet returns to a depot on a known schedule. Each
// vehicle occupies a charging bay from the minute it arrives until the minute
// it leaves, and the depot is deciding how many bays to build. Planning wants
// four things from one schedule: the schedule decomposed into the events a
// sweep can walk, how many bays the day actually demands, when the depot is at
// that demand and which vehicles are responsible, and finally a concrete bay
// for every vehicle so the yard can be signposted.
//
// Sessions are half-open, in minutes from the start of the planning day: a
// vehicle leaving at 30 and one arriving at 30 never share a bay.
//
// This is the greedy family's resource-count corner. The answer is not a
// selection out of the schedule, it is a number the schedule forces, and the
// greedy sweep needs a structure beside it. Two correct formulations exist for
// the count and only one of them extends to naming bays, so pick deliberately
// rather than by reflex.
//
// You choose the internal data structures; the public interface is the
// contract. Store all mutable state in instance properties initialized by init.
// Never use mutable global or static state. Immutable static constants are
// fine. A MinHeap is provided below because the standard library has none and
// writing one is not this problem's lesson.
//
/*
# Example
let sizer = ChargerCapacitySizer()
let sessions = [
    ChargeSession(vehicleID: "v1", arrival: 0,  departure: 30),
    ChargeSession(vehicleID: "v2", arrival: 5,  departure: 10),
    ChargeSession(vehicleID: "v3", arrival: 15, departure: 20),
    ChargeSession(vehicleID: "v4", arrival: 25, departure: 40),
]

try sizer.events(from: sessions).count            // -> 8
try sizer.requiredBays(sessions)                  // -> 2
try sizer.peakWindows(sessions)
// -> [PeakWindow(start: 5,  end: 10, occupancy: 2, vehicleIDs: ["v1", "v2"]),
//     PeakWindow(start: 15, end: 20, occupancy: 2, vehicleIDs: ["v1", "v3"]),
//     PeakWindow(start: 25, end: 30, occupancy: 2, vehicleIDs: ["v1", "v4"])]
try sizer.bayAssignment(sessions)                 // -> ["v1": 0, "v2": 1, "v3": 1, "v4": 1]
*/
//
// PART 1 - Decompose into events  (~9 min)
// Turn the schedule into the arrivals and departures a sweep walks, in the one
// order every later part will read them in.
// The whole boundary question lives in this ordering, so settle it here and
// never again. At a shared instant departures come before arrivals: a bay
// vacated at 30 is available to a vehicle arriving at 30, and an order that
// leaves that to the sort's stability is not an order, it is a coincidence
// that happens to hold today.
// Two events of the same kind at the same instant still need a deterministic
// order, so break that tie by vehicle id.
// A session whose departure is not after its arrival is a fault, and so is a
// schedule that repeats a vehicle id or exceeds the supported session count.
// Each is a typed failure naming what broke.
//
// PART 2 - Peak occupancy  (~10 min)
// Report how many bays the depot must build so that no returning vehicle ever
// waits.
// Walk the previous part's events with a running count and keep the largest
// value it reaches. That is the answer, and it is O(n log n) because of the
// sort. Comparing every pair of sessions is also correct, also obvious, and
// quadratic; at the supported session count that version does not finish, and
// no test here times it, so the decision is yours to make deliberately.
// This part and the next both need the same walk, so put the walk in one
// private helper and let each of them read what it needs off the result. That
// seam is deliberate: there must be exactly one sweep in this file.
//
// PART 3 - When, and who  (~12 min)
// Report every stretch of the day at which the depot is at that peak, with the
// occupancy and the vehicles parked during it.
// A planner cannot act on a number alone; it needs the windows to look at and
// the vehicles to talk to. Each window runs between two consecutive events, so
// a stretch that ends the instant it begins is not a window and should not be
// reported. List each window's vehicle ids in ascending id order.
// Consecutive stretches are separate windows even when both are at the peak,
// because an event between them changed who is parked, and a merged window
// would claim a set of vehicles that were never simultaneously present.
//
// PART 4 - Assign a bay to every session  (~14 min)
// Report which bay each vehicle should be sent to, using no more bays than the
// second part said were needed.
// The running counter cannot answer this and it is worth seeing why: it knows
// how many vehicles are parked, never which bay each one is in. Freeing a bay
// requires knowing when the vehicle occupying it leaves, so a fresh structure
// is needed and the provided MinHeap is what it is there for.
// Walk the sessions in arrival order. Before placing a vehicle, release every
// bay whose occupant has already departed, then take a free bay if there is
// one and open a new bay only when there is not. Take the lowest free bay
// index so the assignment is reproducible.
// Two properties have to hold together and it is easy to get only the first:
// the number of distinct bays used equals the second part's answer, and no two
// vehicles sharing a bay overlap in time.

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
    public func events(from sessions: [ChargeSession]) throws(DepotError) -> [ChargeEvent] {
        throw .notImplemented
    }

    // MARK: Part 2 - Peak occupancy
    public func requiredBays(_ sessions: [ChargeSession]) throws(DepotError) -> Int {
        throw .notImplemented
    }

    // MARK: Part 3 - When, and who
    public func peakWindows(_ sessions: [ChargeSession]) throws(DepotError) -> [PeakWindow] {
        throw .notImplemented
    }

    // MARK: Part 4 - Assign a bay to every session
    public func bayAssignment(_ sessions: [ChargeSession]) throws(DepotError) -> [String: Int] {
        throw .notImplemented
    }
}
