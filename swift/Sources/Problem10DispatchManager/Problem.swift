// Problem 10: Responder Dispatch Manager
// Swift 6, macOS 14+ | Senior | approximately 45 minutes
//
// Build an in-memory dispatch service in three cumulative parts. You choose the
// internal data structures; the public interface is the contract. Store all
// mutable state in instance variables initialized by init; never use mutable
// global or static state.
//
// PART 1 — Registration and matching queries  (~10 min)
// Register uniquely identified responders and incidents. Matching incidents are
// ordered by severity descending, then timestamp and incident ID ascending.
//
// PART 2 — Manual assignment and resolution  (~15 min)
// Enforce existence, single assignment, and responder capacity. Return an
// AssignmentResult snapshot from assignIncident so later behavior can reuse it.
// Resolving an incident frees capacity. Manual assignment does not require a
// responder subscription; subscriptions govern automatic selection.
//
// PART 3 — Strategy-based automatic assignment  (~20 min)
// Ask the injected AssignmentStrategy to select among subscribed responders with
// capacity. Then call assignIncident to perform the assignment; do not duplicate
// its validation or mutation. Produce responder summaries ordered by ID.
//
/*
 * Example
 * var manager = DispatchManager(strategy: LeastLoadedAssignmentStrategy())
 * try manager.registerResponder(Responder(id: "unit-12", name: "Alpha", subscribedTypes: ["fire"], capacity: 2))
 * try manager.addIncident(Incident(id: "inc-001", type: "fire", severity: 5, timestamp: DispatchTimestamp(100)))
 * let assignment = try manager.autoAssign(IncidentID("inc-001"))
 * assignment.responderID // -> ResponderID("unit-12")
 */

public struct ResponderID: Hashable, Comparable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(value) }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
public struct IncidentID: Hashable, Comparable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(value) }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
public struct IncidentType: Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(value) }
}
public struct DispatchTimestamp: Hashable, Comparable, Sendable {
    public let rawValue: Int
    public init(_ rawValue: Int) { self.rawValue = rawValue }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
public struct Responder: Equatable, Sendable {
    public let id: ResponderID; public let name: String
    public let subscribedTypes: Set<IncidentType>; public let capacity: Int
    public init(id: ResponderID, name: String, subscribedTypes: Set<IncidentType>, capacity: Int) {
        self.id = id; self.name = name; self.subscribedTypes = subscribedTypes; self.capacity = capacity
    }
}
public struct Incident: Equatable, Sendable {
    public let id: IncidentID; public let type: IncidentType; public let severity: Int
    public let timestamp: DispatchTimestamp; public var responderID: ResponderID?; public var isResolved: Bool
    public init(id: IncidentID, type: IncidentType, severity: Int, timestamp: DispatchTimestamp, responderID: ResponderID? = nil, isResolved: Bool = false) {
        self.id = id; self.type = type; self.severity = severity; self.timestamp = timestamp; self.responderID = responderID; self.isResolved = isResolved
    }
}
public enum DispatchError: Error, Equatable, Sendable {
    case duplicateResponder(ResponderID), duplicateIncident(IncidentID)
    case unknownResponder(ResponderID), unknownIncident(IncidentID)
    case alreadyAssigned(IncidentID), alreadyResolved(IncidentID)
    case responderAtCapacity(ResponderID), noEligibleResponder(IncidentID), invalidCapacity(Int), notImplemented
}
public struct AssignmentCandidate: Equatable, Sendable {
    public let responder: Responder; public let openCount: Int
    public init(responder: Responder, openCount: Int) { self.responder = responder; self.openCount = openCount }
}
public struct AssignmentResult: Equatable, Sendable {
    public let incident: Incident; public let responder: Responder
    public let openCount: Int; public let availableCapacity: Int
    public var responderID: ResponderID { responder.id }
}
public struct DispatchSummary: Equatable, Sendable {
    public let responderID: ResponderID; public let name: String
    public let capacity: Int; public let openCount: Int; public let availableCapacity: Int
}
public protocol AssignmentStrategy {
    func selectResponder(for incident: Incident, from candidates: [AssignmentCandidate]) -> ResponderID?
}
public struct LeastLoadedAssignmentStrategy: AssignmentStrategy, Sendable {
    public init() {}
    public func selectResponder(for incident: Incident, from candidates: [AssignmentCandidate]) -> ResponderID? {
        candidates.sorted { ($0.openCount, -$0.responder.capacity, $0.responder.id) < ($1.openCount, -$1.responder.capacity, $1.responder.id) }.first?.responder.id
    }
}
public struct DispatchManager {
    public init(strategy: any AssignmentStrategy = LeastLoadedAssignmentStrategy()) { self.strategy = strategy }
    private let strategy: any AssignmentStrategy
    public mutating func registerResponder(_ responder: Responder) throws(DispatchError) { throw .notImplemented }
    public mutating func addIncident(_ incident: Incident) throws(DispatchError) { throw .notImplemented }
    public func incidents(matching responderID: ResponderID) throws(DispatchError) -> [Incident] { throw .notImplemented }
    public mutating func assignIncident(_ incidentID: IncidentID, to responderID: ResponderID) throws(DispatchError) -> AssignmentResult { throw .notImplemented }
    public mutating func resolveIncident(_ incidentID: IncidentID) throws(DispatchError) -> Incident { throw .notImplemented }
    public func openAssignments(for responderID: ResponderID) throws(DispatchError) -> [Incident] { throw .notImplemented }
    public mutating func autoAssign(_ incidentID: IncidentID) throws(DispatchError) -> AssignmentResult { throw .notImplemented }
    public func dispatchSummary() -> [DispatchSummary] { [] }
}
