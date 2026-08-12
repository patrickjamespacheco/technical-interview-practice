public enum ContractState: String, CaseIterable, Sendable {
    case draft, inReview, approved, executed, active, expiringSoon, expired, terminated

    public var isTerminal: Bool { self == .expired || self == .terminated }
}

public enum TransitionError: Error, Equatable, Sendable {
    case duplicateContract(String)
    case unknownContract(String)
    case invalidTransition(from: ContractState, to: ContractState)
    case notImplemented
}

public struct AuditEntry: Equatable, Sendable {
    public let contractID: String
    public let fromState: ContractState?
    public let toState: ContractState
    public let timestamp: Int
    public let actor: String
    public init(contractID: String, fromState: ContractState?, toState: ContractState, timestamp: Int, actor: String) {
        self.contractID = contractID; self.fromState = fromState; self.toState = toState; self.timestamp = timestamp; self.actor = actor
    }
}

public struct Contract: Equatable, Sendable {
    public let id: String
    public let title: String
    public let state: ContractState
    public let createdAt: Int
    public let fields: [String: String]
    public init(id: String, title: String, state: ContractState, createdAt: Int, fields: [String: String]) {
        self.id = id; self.title = title; self.state = state; self.createdAt = createdAt; self.fields = fields
    }
}

public struct BulkFailure: Equatable, Sendable { public let contractID: String; public let error: TransitionError; public init(contractID: String, error: TransitionError) { self.contractID = contractID; self.error = error } }
public struct BulkAdvanceResult: Equatable, Sendable { public let succeeded: [String]; public let failed: [BulkFailure]; public init(succeeded: [String], failed: [BulkFailure]) { self.succeeded = succeeded; self.failed = failed } }
public struct LifecycleMetrics: Equatable, Sendable { public let total: Int; public let byState: [ContractState: Int]; public let terminalCount: Int; public init(total: Int, byState: [ContractState: Int], terminalCount: Int) { self.total = total; self.byState = byState; self.terminalCount = terminalCount } }
public struct OverdueContract: Equatable, Sendable { public let contract: Contract; public let stuckSince: Int; public let daysStuck: Int; public init(contract: Contract, stuckSince: Int, daysStuck: Int) { self.contract = contract; self.stuckSince = stuckSince; self.daysStuck = daysStuck } }

public struct ContractLifecycle: Sendable {
    private var contractsByID: [String: Contract] = [:]
    private var audits: [String: [AuditEntry]] = [:]

    public init() {}

    // MARK: Part 1 — typed contracts and exhaustive transitions

    @discardableResult
    public mutating func createContract(id: String, title: String, createdAt: Int, actor: String) throws(TransitionError) -> Contract {
        guard contractsByID[id] == nil else { throw .duplicateContract(id) }
        let contract = Contract(id: id, title: title, state: .draft, createdAt: createdAt, fields: [:])
        contractsByID[id] = contract
        // Creation is itself an audited event; it has no origin state.
        audits[id] = [AuditEntry(contractID: id, fromState: nil, toState: .draft, timestamp: createdAt, actor: actor)]
        return contract
    }

    @discardableResult
    public mutating func setField(contractID: String, key: String, value: String) throws(TransitionError) -> Contract {
        let existing = try contract(id: contractID)
        var fields = existing.fields
        fields[key] = value
        let updated = Contract(id: existing.id, title: existing.title, state: existing.state, createdAt: existing.createdAt, fields: fields)
        contractsByID[contractID] = updated
        return updated
    }

    public func contract(id: String) throws(TransitionError) -> Contract {
        guard let contract = contractsByID[id] else { throw .unknownContract(id) }
        return contract
    }

    public func auditTrail(for contractID: String) throws(TransitionError) -> [AuditEntry] {
        _ = try contract(id: contractID)
        return audits[contractID] ?? []
    }

    @discardableResult
    public mutating func transition(_ contractID: String, to state: ContractState, at: Int, actor: String) throws(TransitionError) -> Contract {
        let existing = try contract(id: contractID)
        guard allowedTransitions(from: existing.state).contains(state) else {
            throw .invalidTransition(from: existing.state, to: state)
        }
        let updated = Contract(id: existing.id, title: existing.title, state: state, createdAt: existing.createdAt, fields: existing.fields)
        contractsByID[contractID] = updated
        audits[contractID, default: []].append(
            AuditEntry(contractID: contractID, fromState: existing.state, toState: state, timestamp: at, actor: actor)
        )
        return updated
    }

    /// The whole state machine in one exhaustive switch: adding a case to
    /// `ContractState` breaks the build here rather than silently allowing it.
    private func allowedTransitions(from state: ContractState) -> Set<ContractState> {
        switch state {
        case .draft: [.inReview]
        case .inReview: [.approved, .draft]
        case .approved: [.executed]
        case .executed: [.active]
        case .active: [.expiringSoon, .terminated]
        case .expiringSoon: [.active, .expired, .terminated]
        case .expired, .terminated: []
        }
    }

    // MARK: Part 2 — audit queries and bulk advancement

    public func contracts(in state: ContractState) -> [Contract] {
        contractsByID.values.filter { $0.state == state }.sorted { $0.id < $1.id }
    }

    public mutating func bulkAdvance(_ contractIDs: [String], to state: ContractState, at: Int, actor: String) -> BulkAdvanceResult {
        var succeeded: [String] = []
        var failed: [BulkFailure] = []
        for contractID in contractIDs {
            do {
                // One transition rule, exercised through the same entry point.
                try transition(contractID, to: state, at: at, actor: actor)
                succeeded.append(contractID)
            } catch {
                failed.append(BulkFailure(contractID: contractID, error: error))
            }
        }
        return BulkAdvanceResult(succeeded: succeeded, failed: failed)
    }

    // MARK: Part 3 — lifecycle reporting

    public func lifecycleMetrics() -> LifecycleMetrics {
        var byState: [ContractState: Int] = [:]
        for state in ContractState.allCases {
            let count = contracts(in: state).count
            if count > 0 { byState[state] = count }
        }
        return LifecycleMetrics(
            total: contractsByID.count,
            byState: byState,
            terminalCount: byState.filter { $0.key.isTerminal }.values.reduce(0, +)
        )
    }

    public func overdueContracts(asOf: Int) -> [OverdueContract] {
        let secondsPerDay = 86_400
        return contractsByID.values
            .filter { !$0.state.isTerminal }
            .compactMap { contract -> OverdueContract? in
                guard let stuckSince = (try? auditTrail(for: contract.id))?.last?.timestamp else { return nil }
                let daysStuck = (asOf - stuckSince) / secondsPerDay
                guard daysStuck > 30 else { return nil }
                return OverdueContract(contract: contract, stuckSince: stuckSince, daysStuck: daysStuck)
            }
            .sorted { lhs, rhs in
                lhs.daysStuck == rhs.daysStuck ? lhs.contract.id < rhs.contract.id : lhs.daysStuck > rhs.daysStuck
            }
    }
}
