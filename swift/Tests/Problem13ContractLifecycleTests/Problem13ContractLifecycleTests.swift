import Testing
@testable import Problem13ContractLifecycle

private func makeFreshLifecycle() -> ContractLifecycle { ContractLifecycle() }
private func makeSeededLifecycle() throws -> ContractLifecycle {
    var lifecycle = ContractLifecycle()
    try lifecycle.createContract(id: "contract-seeded-approved", title: "Services", createdAt: 0, actor: "alice")
    try lifecycle.transition("contract-seeded-approved", to: .inReview, at: 100, actor: "alice")
    try lifecycle.transition("contract-seeded-approved", to: .approved, at: 200, actor: "bob")
    return lifecycle
}

@Suite("Part 1 — Typed contracts and exhaustive transitions")
struct ContractLifecyclePart1Tests {
    @Test func creationProducesDraftAndImmutableAuditValue() throws {
        var lifecycle = makeFreshLifecycle()
        let contract = try lifecycle.createContract(id: "contract-create", title: "NDA", createdAt: 10, actor: "creator")
        #expect(contract == Contract(id: "contract-create", title: "NDA", state: .draft, createdAt: 10, fields: [:]))
        #expect(try lifecycle.auditTrail(for: "contract-create") == [AuditEntry(contractID: "contract-create", fromState: nil, toState: .draft, timestamp: 10, actor: "creator")])
    }

    @Test func duplicateAndUnknownIDsAreTypedFailures() throws {
        var lifecycle = makeFreshLifecycle()
        try lifecycle.createContract(id: "contract-duplicate", title: "One", createdAt: 0, actor: "a")
        #expect(throws: TransitionError.duplicateContract("contract-duplicate")) { try lifecycle.createContract(id: "contract-duplicate", title: "Two", createdAt: 1, actor: "b") }
        #expect(throws: TransitionError.unknownContract("contract-missing")) { try lifecycle.contract(id: "contract-missing") }
    }

    @Test func metadataUpdatesReturnSnapshots() throws {
        var lifecycle = try makeSeededLifecycle()
        let before = try lifecycle.contract(id: "contract-seeded-approved")
        let after = try lifecycle.setField(contractID: "contract-seeded-approved", key: "region", value: "west")
        #expect(before.fields.isEmpty)
        #expect(after.fields == ["region": "west"])
    }

    @Test(arguments: [
        (ContractState.draft, ContractState.inReview), (.inReview, .approved), (.inReview, .draft),
        (.approved, .executed), (.executed, .active), (.active, .expiringSoon),
        (.active, .terminated), (.expiringSoon, .expired), (.expiringSoon, .active),
        (.expiringSoon, .terminated)
    ])
    func everyDocumentedTransitionIsAccepted(from: ContractState, to: ContractState) throws {
        var lifecycle = makeFreshLifecycle()
        try lifecycle.createContract(id: "contract-edge-\(from.rawValue)-\(to.rawValue)", title: "Edge", createdAt: 0, actor: "a")
        let path: [ContractState]
        switch from {
        case .draft: path = []
        case .inReview: path = [.inReview]
        case .approved: path = [.inReview, .approved]
        case .executed: path = [.inReview, .approved, .executed]
        case .active: path = [.inReview, .approved, .executed, .active]
        case .expiringSoon: path = [.inReview, .approved, .executed, .active, .expiringSoon]
        case .expired, .terminated: path = []
        }
        let id = "contract-edge-\(from.rawValue)-\(to.rawValue)"
        for (offset, state) in path.enumerated() { try lifecycle.transition(id, to: state, at: offset + 1, actor: "setup") }
        #expect(try lifecycle.transition(id, to: to, at: 99, actor: "tester").state == to)
    }

    @Test func invalidAndTerminalTransitionsAreRejectedWithoutAudit() throws {
        var lifecycle = makeFreshLifecycle()
        try lifecycle.createContract(id: "contract-invalid", title: "Invalid", createdAt: 0, actor: "a")
        #expect(throws: TransitionError.invalidTransition(from: .draft, to: .approved)) { try lifecycle.transition("contract-invalid", to: .approved, at: 1, actor: "a") }
        #expect(try lifecycle.auditTrail(for: "contract-invalid").count == 1)
    }

    @Test func instancesAreIsolated() throws {
        var first = makeFreshLifecycle(); let second = makeFreshLifecycle()
        try first.createContract(id: "contract-isolation", title: "Only first", createdAt: 0, actor: "a")
        #expect(throws: TransitionError.unknownContract("contract-isolation")) { try second.contract(id: "contract-isolation") }
    }
}

@Suite("Part 2 — Audit queries and bulk advancement")
struct ContractLifecyclePart2Tests {
    @Test func auditIsOrderedAndStateQueryIsSorted() throws {
        var lifecycle = makeFreshLifecycle()
        for id in ["contract-zulu", "contract-alpha", "contract-mike"] { try lifecycle.createContract(id: id, title: id, createdAt: 0, actor: "a") }
        #expect(lifecycle.contracts(in: .draft).map(\.id) == ["contract-alpha", "contract-mike", "contract-zulu"])
        try lifecycle.transition("contract-alpha", to: .inReview, at: 1, actor: "b")
        #expect(try lifecycle.auditTrail(for: "contract-alpha").map(\.toState) == [.draft, .inReview])
    }

    @Test func bulkAdvanceReusesTransitionAndContinuesAfterFailures() throws {
        var lifecycle = makeFreshLifecycle()
        try lifecycle.createContract(id: "contract-bulk-ok", title: "OK", createdAt: 0, actor: "a")
        try lifecycle.createContract(id: "contract-bulk-bad", title: "Bad", createdAt: 0, actor: "a")
        try lifecycle.transition("contract-bulk-bad", to: .inReview, at: 1, actor: "a")
        let result = lifecycle.bulkAdvance(["contract-bulk-ok", "contract-missing-bulk", "contract-bulk-bad"], to: .inReview, at: 2, actor: "bulk")
        #expect(result.succeeded == ["contract-bulk-ok"])
        #expect(result.failed == [
            BulkFailure(contractID: "contract-missing-bulk", error: .unknownContract("contract-missing-bulk")),
            BulkFailure(contractID: "contract-bulk-bad", error: .invalidTransition(from: .inReview, to: .inReview))
        ])
        #expect(try lifecycle.auditTrail(for: "contract-bulk-ok").last?.actor == "bulk")
    }
}

@Suite("Part 3 — Lifecycle reporting")
struct ContractLifecyclePart3Tests {
    @Test func metricsCountStatesAndTerminals() throws {
        var lifecycle = try makeSeededLifecycle()
        try lifecycle.createContract(id: "contract-metric-draft", title: "Draft", createdAt: 0, actor: "a")
        try lifecycle.createContract(id: "contract-metric-terminal", title: "Terminal", createdAt: 0, actor: "a")
        for state in [ContractState.inReview, .approved, .executed, .active, .terminated] { try lifecycle.transition("contract-metric-terminal", to: state, at: 1, actor: "a") }
        #expect(lifecycle.lifecycleMetrics() == LifecycleMetrics(total: 3, byState: [.approved: 1, .draft: 1, .terminated: 1], terminalCount: 1))
    }

    @Test func overdueUsesLatestAuditExcludesTerminalAndSorts() throws {
        var lifecycle = makeFreshLifecycle()
        try lifecycle.createContract(id: "contract-older", title: "Older", createdAt: 0, actor: "a")
        try lifecycle.createContract(id: "contract-newer", title: "Newer", createdAt: 86_400 * 10, actor: "a")
        try lifecycle.createContract(id: "contract-terminal", title: "Done", createdAt: 0, actor: "a")
        for state in [ContractState.inReview, .approved, .executed, .active, .terminated] { try lifecycle.transition("contract-terminal", to: state, at: 1, actor: "a") }
        let overdue = lifecycle.overdueContracts(asOf: 86_400 * 45)
        #expect(overdue.map(\.contract.id) == ["contract-older", "contract-newer"])
        #expect(overdue.map(\.daysStuck) == [45, 35])
    }
}
