import Testing
@testable import Problem69RelayCoveragePlanner

private let corridor = 0...10
private func relays() -> [Relay] { [Relay(id: "left", position: 1, radius: 3), Relay(id: "middle", position: 5, radius: 3), Relay(id: "right", position: 9, radius: 3)] }

@Suite("Part 1 - Reach ranges and gaps") struct RelayPart1Tests {
    @Test func clipsAndFindsGaps() throws {
        let planner = RelayCoveragePlanner()
        #expect(planner.reachRange(of: Relay(id: "clip", position: 0, radius: 3), corridor: corridor) == 0...3)
        #expect(try planner.gaps(coveredBy: [Relay(id: "a-gap", position: 0, radius: 1), Relay(id: "b-gap", position: 5, radius: 1)], corridor: 0...6) == [2...3])
    }
    @Test func validatesAndIsStateless() throws {
        let first = RelayCoveragePlanner(), second = RelayCoveragePlanner(); _ = try first.gaps(coveredBy: relays(), corridor: corridor)
        #expect(try second.gaps(coveredBy: relays(), corridor: corridor).isEmpty)
        #expect(throws: CoverageError.negativeRadius(id: "bad-radius")) { try first.gaps(coveredBy: [Relay(id: "bad-radius", position: 0, radius: -1)], corridor: corridor) }
    }
}
@Suite("Part 2 - How many relays") struct RelayPart2Tests {
    @Test func countsAndExplainsFailure() throws {
        let planner = RelayCoveragePlanner(); #expect(try planner.minimumRelayCount(relays(), corridor: corridor) == 3)
        #expect(throws: CoverageError.uncoverable(gaps: [2...8])) { try planner.minimumRelayCount([Relay(id: "sparse-left", position: 0, radius: 1), Relay(id: "sparse-right", position: 10, radius: 1)], corridor: corridor) }
    }
}
@Suite("Part 3 - Which relays") struct RelayPart3Tests {
    @Test func reconstructsSameGreedy() throws {
        let planner = RelayCoveragePlanner(), input = relays(); let selected = try planner.minimumRelaySelection(input, corridor: corridor)
        #expect(selected == ["left", "middle", "right"]); #expect(selected.count == (try planner.minimumRelayCount(input, corridor: corridor)))
        let selectedRelays = input.filter { selected.contains($0.id) }; #expect(try planner.gaps(coveredBy: selectedRelays, corridor: corridor).isEmpty)
    }
}
@Suite("Part 4 - Minimum handoff overlap") struct RelayPart4Tests {
    @Test func enforcesMargin() throws {
        let planner = RelayCoveragePlanner(); let input = [Relay(id: "wide-left", position: 2, radius: 4), Relay(id: "wide-right", position: 8, radius: 4)]
        #expect(try planner.minimumRelaySelection(input, corridor: corridor, handoffMargin: 2) == ["wide-left", "wide-right"])
        #expect(throws: CoverageError.negativeMargin(-1)) { try planner.minimumRelaySelection(input, corridor: corridor, handoffMargin: -1) }
    }
}
