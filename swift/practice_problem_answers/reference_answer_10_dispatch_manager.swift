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
    private var responders: [ResponderID: Responder] = [:]
    private var incidentsByID: [IncidentID: Incident] = [:]

    // MARK: Part 1 — registration and matching queries

    public mutating func registerResponder(_ responder: Responder) throws(DispatchError) {
        guard responder.capacity > 0 else { throw .invalidCapacity(responder.capacity) }
        guard responders[responder.id] == nil else { throw .duplicateResponder(responder.id) }
        responders[responder.id] = responder
    }

    public mutating func addIncident(_ incident: Incident) throws(DispatchError) {
        guard incidentsByID[incident.id] == nil else { throw .duplicateIncident(incident.id) }
        incidentsByID[incident.id] = incident
    }

    public func incidents(matching responderID: ResponderID) throws(DispatchError) -> [Incident] {
        guard let responder = responders[responderID] else { throw .unknownResponder(responderID) }
        return dispatchOrdered(incidentsByID.values.filter { responder.subscribedTypes.contains($0.type) })
    }

    /// The one ordering rule for every incident list: worst first, then oldest,
    /// then by ID so the result is stable.
    private func dispatchOrdered(_ incidents: [Incident]) -> [Incident] {
        incidents.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
            return lhs.id < rhs.id
        }
    }

    // MARK: Part 2 — manual assignment and resolution

    public mutating func assignIncident(_ incidentID: IncidentID, to responderID: ResponderID) throws(DispatchError) -> AssignmentResult {
        guard let incident = incidentsByID[incidentID] else { throw .unknownIncident(incidentID) }
        guard let responder = responders[responderID] else { throw .unknownResponder(responderID) }
        guard !incident.isResolved else { throw .alreadyResolved(incidentID) }
        guard incident.responderID == nil else { throw .alreadyAssigned(incidentID) }
        let openCount = try openAssignments(for: responderID).count
        guard openCount < responder.capacity else { throw .responderAtCapacity(responderID) }
        incidentsByID[incidentID]!.responderID = responderID
        return AssignmentResult(
            incident: incidentsByID[incidentID]!,
            responder: responder,
            openCount: openCount + 1,
            availableCapacity: responder.capacity - (openCount + 1)
        )
    }

    public mutating func resolveIncident(_ incidentID: IncidentID) throws(DispatchError) -> Incident {
        guard let incident = incidentsByID[incidentID] else { throw .unknownIncident(incidentID) }
        guard !incident.isResolved else { throw .alreadyResolved(incidentID) }
        incidentsByID[incidentID]!.isResolved = true
        return incidentsByID[incidentID]!
    }

    public func openAssignments(for responderID: ResponderID) throws(DispatchError) -> [Incident] {
        guard responders[responderID] != nil else { throw .unknownResponder(responderID) }
        return dispatchOrdered(incidentsByID.values.filter { $0.responderID == responderID && !$0.isResolved })
    }

    // MARK: Part 3 — strategy-based automatic assignment

    public mutating func autoAssign(_ incidentID: IncidentID) throws(DispatchError) -> AssignmentResult {
        guard let incident = incidentsByID[incidentID] else { throw .unknownIncident(incidentID) }
        let candidates = try eligibleCandidates(for: incident)
        guard let selected = strategy.selectResponder(for: incident, from: candidates) else {
            throw .noEligibleResponder(incidentID)
        }
        // Delegate every validation and the mutation itself to Part 2.
        return try assignIncident(incidentID, to: selected)
    }

    private func eligibleCandidates(for incident: Incident) throws(DispatchError) -> [AssignmentCandidate] {
        var candidates: [AssignmentCandidate] = []
        for responder in responders.values.sorted(by: { $0.id < $1.id })
        where responder.subscribedTypes.contains(incident.type) {
            let openCount = try openAssignments(for: responder.id).count
            if openCount < responder.capacity {
                candidates.append(AssignmentCandidate(responder: responder, openCount: openCount))
            }
        }
        return candidates
    }

    public func dispatchSummary() -> [DispatchSummary] {
        responders.values.sorted { $0.id < $1.id }.map { responder in
            let openCount = ((try? openAssignments(for: responder.id)) ?? []).count
            return DispatchSummary(
                responderID: responder.id,
                name: responder.name,
                capacity: responder.capacity,
                openCount: openCount,
                availableCapacity: responder.capacity - openCount
            )
        }
    }
}
