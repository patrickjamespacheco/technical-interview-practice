import Testing
@testable import Problem10DispatchManager

private final class RecordingStrategy: AssignmentStrategy {
    var candidateIDs: [ResponderID] = []
    let selectedID: ResponderID?
    init(selectedID: ResponderID?) { self.selectedID = selectedID }
    func selectResponder(for incident: Incident, from candidates: [AssignmentCandidate]) -> ResponderID? {
        candidateIDs = candidates.map(\.responder.id)
        return selectedID
    }
}
private func responder(_ id: ResponderID, types: Set<IncidentType> = ["fire"], capacity: Int = 2) -> Responder {
    Responder(id: id, name: "Team \(id.rawValue)", subscribedTypes: types, capacity: capacity)
}
private func incident(_ id: IncidentID, type: IncidentType = "fire", severity: Int = 3, time: Int = 10) -> Incident {
    Incident(id: id, type: type, severity: severity, timestamp: DispatchTimestamp(time))
}
private func makeFreshManager(strategy: any AssignmentStrategy = LeastLoadedAssignmentStrategy()) -> DispatchManager { DispatchManager(strategy: strategy) }
private func makeSeededManager() throws -> DispatchManager {
    var manager = makeFreshManager()
    try manager.registerResponder(responder("unit-12", types: ["fire", "rescue"], capacity: 3))
    try manager.registerResponder(responder("unit-14", types: ["medical"], capacity: 2))
    try manager.addIncident(incident("inc-seed-high", severity: 5, time: 20))
    try manager.addIncident(incident("inc-seed-old", severity: 3, time: 10))
    try manager.addIncident(incident("inc-medical", type: "medical", severity: 4, time: 30))
    _ = try manager.assignIncident("inc-seed-high", to: "unit-12")
    return manager
}

@Suite("Part 1 — Registration and matching queries")
struct DispatchPart1 {
    @Test("typed records register and duplicate IDs fail")
    func registration() throws {
        var manager = makeFreshManager()
        try manager.registerResponder(responder("unit-registration", capacity: 4))
        #expect(throws: DispatchError.duplicateResponder("unit-registration")) { try manager.registerResponder(responder("unit-registration")) }
        let created = incident("incident-registration", severity: 2)
        try manager.addIncident(created)
        #expect(throws: DispatchError.duplicateIncident("incident-registration")) { try manager.addIncident(created) }
    }
    @Test("invalid capacity is rejected")
    func capacity() {
        var manager = makeFreshManager()
        #expect(throws: DispatchError.invalidCapacity(0)) { try manager.registerResponder(responder("unit-zero-capacity", capacity: 0)) }
    }
    @Test("matching incidents use subscription, severity, timestamp, and ID ordering")
    func matching() throws {
        var manager = makeFreshManager()
        try manager.registerResponder(responder("unit-matching", types: ["fire"]))
        try manager.addIncident(incident("inc-low", severity: 2, time: 1))
        try manager.addIncident(incident("inc-late", severity: 5, time: 2))
        try manager.addIncident(incident("inc-early-b", severity: 5, time: 1))
        try manager.addIncident(incident("inc-early-a", severity: 5, time: 1))
        try manager.addIncident(incident("inc-other", type: "medical", severity: 5, time: 0))
        #expect(try manager.incidents(matching: "unit-matching").map(\.id) == ["inc-early-a", "inc-early-b", "inc-late", "inc-low"])
        #expect(throws: DispatchError.unknownResponder("unit-missing-query")) { try manager.incidents(matching: "unit-missing-query") }
    }
    @Test("manager instances are isolated")
    func isolation() throws {
        var first = makeFreshManager(); let second = makeFreshManager()
        try first.registerResponder(responder("unit-isolation"))
        #expect(throws: DispatchError.unknownResponder("unit-isolation")) { try second.incidents(matching: "unit-isolation") }
    }
}

@Suite("Part 2 — Manual assignment and resolution")
struct DispatchPart2 {
    @Test("assignment returns a reusable snapshot and rejects expected failures")
    func assignment() throws {
        var manager = try makeSeededManager()
        let result = try manager.assignIncident("inc-seed-old", to: "unit-12")
        #expect(result.responderID == "unit-12")
        #expect(result.openCount == 2 && result.availableCapacity == 1)
        #expect(result.incident.responderID == "unit-12")
        #expect(throws: DispatchError.alreadyAssigned("inc-seed-old")) { try manager.assignIncident("inc-seed-old", to: "unit-12") }
        #expect(throws: DispatchError.unknownIncident("inc-missing-assignment")) { try manager.assignIncident("inc-missing-assignment", to: "unit-12") }
        #expect(throws: DispatchError.unknownResponder("unit-missing-assignment")) { try manager.assignIncident("inc-medical", to: "unit-missing-assignment") }
    }
    @Test("capacity counts only unresolved assignments")
    func resolution() throws {
        var manager = makeFreshManager()
        try manager.registerResponder(responder("unit-capacity", capacity: 1))
        try manager.addIncident(incident("inc-capacity-first")); try manager.addIncident(incident("inc-capacity-next", time: 20))
        _ = try manager.assignIncident("inc-capacity-first", to: "unit-capacity")
        #expect(throws: DispatchError.responderAtCapacity("unit-capacity")) { try manager.assignIncident("inc-capacity-next", to: "unit-capacity") }
        let resolved = try manager.resolveIncident("inc-capacity-first")
        #expect(resolved.isResolved)
        #expect(try manager.openAssignments(for: "unit-capacity") == [])
        _ = try manager.assignIncident("inc-capacity-next", to: "unit-capacity")
        #expect(throws: DispatchError.alreadyResolved("inc-capacity-first")) { try manager.resolveIncident("inc-capacity-first") }
    }
    @Test("open assignments retain canonical ordering")
    func openOrdering() throws {
        var manager = makeFreshManager(); try manager.registerResponder(responder("unit-open", capacity: 3))
        try manager.addIncident(incident("inc-open-low", severity: 1, time: 1)); try manager.addIncident(incident("inc-open-high", severity: 5, time: 2))
        _ = try manager.assignIncident("inc-open-low", to: "unit-open"); _ = try manager.assignIncident("inc-open-high", to: "unit-open")
        #expect(try manager.openAssignments(for: "unit-open").map(\.id) == ["inc-open-high", "inc-open-low"])
    }
}

@Suite("Part 3 — Strategy-based automatic assignment")
struct DispatchPart3 {
    @Test("default strategy is least loaded, then highest capacity, then ID")
    func defaultSelection() throws {
        var manager = makeFreshManager()
        try manager.registerResponder(responder("unit-b", capacity: 4)); try manager.registerResponder(responder("unit-a", capacity: 4)); try manager.registerResponder(responder("unit-small", capacity: 1))
        try manager.addIncident(incident("inc-default-selection"))
        #expect(try manager.autoAssign("inc-default-selection").responderID == "unit-a")
    }
    @Test("strategy sees only subscribed responders with available capacity")
    func strategySeam() throws {
        let strategy = RecordingStrategy(selectedID: "unit-eligible")
        var manager = makeFreshManager(strategy: strategy)
        try manager.registerResponder(responder("unit-eligible")); try manager.registerResponder(responder("unit-wrong-type", types: ["medical"])); try manager.registerResponder(responder("unit-full", capacity: 1))
        try manager.addIncident(incident("inc-fill")); _ = try manager.assignIncident("inc-fill", to: "unit-full")
        try manager.addIncident(incident("inc-strategy")); let result = try manager.autoAssign("inc-strategy")
        #expect(strategy.candidateIDs == ["unit-eligible"])
        #expect(result.openCount == 1 && result.responderID == "unit-eligible")
    }
    @Test("automatic assignment surfaces typed eligibility errors")
    func errors() throws {
        var manager = makeFreshManager(); try manager.registerResponder(responder("unit-medical-only", types: ["medical"])); try manager.addIncident(incident("inc-no-eligible"))
        #expect(throws: DispatchError.noEligibleResponder("inc-no-eligible")) { try manager.autoAssign("inc-no-eligible") }
        #expect(throws: DispatchError.unknownIncident("inc-missing-auto")) { try manager.autoAssign("inc-missing-auto") }
    }
    @Test("automatic assignment delegates the strategy selection to manual assignment")
    func delegatesToManualAssignment() throws {
        let strategy = RecordingStrategy(selectedID: "unit-strategy-unknown")
        var manager = makeFreshManager(strategy: strategy)
        try manager.registerResponder(responder("unit-visible-candidate"))
        try manager.addIncident(incident("inc-delegation"))
        #expect(throws: DispatchError.unknownResponder("unit-strategy-unknown")) {
            try manager.autoAssign("inc-delegation")
        }
        #expect(strategy.candidateIDs == ["unit-visible-candidate"])
    }
    @Test("summary reports current capacity in responder order")
    func summary() throws {
        let manager = try makeSeededManager(); let summary = manager.dispatchSummary()
        #expect(summary.map(\.responderID) == ["unit-12", "unit-14"])
        // Establish the count before indexing, so an empty summary fails here
        // instead of trapping and taking down the whole run.
        try #require(!summary.isEmpty)
        #expect(summary[0].openCount == 1 && summary[0].availableCapacity == 2)
    }
}
