// Problem 13: Contract Lifecycle
// Swift 6, macOS 14+ | Senior | approximately 45 minutes
//
// Build a typed contract state machine. You choose the internal data structures;
// the public interface is the contract. Store all mutable state in instance
// variables initialized in init; mutable static state will bleed between instances.
// Every transition decision must use an exhaustive switch over ContractState.
//
/*
# Example
var lifecycle = ContractLifecycle()
try lifecycle.createContract(id: "c-001", title: "Vendor MSA", createdAt: 0, actor: "alice")
try lifecycle.transition("c-001", to: .inReview, at: 86_400, actor: "alice") // -> .inReview
try lifecycle.transition("c-001", to: .approved, at: 172_800, actor: "bob") // -> .approved
*/
//
// PART 1 — Typed contracts and exhaustive transitions  (~20 min)
// Create contracts, update string metadata, retrieve immutable contract and audit
// snapshots, and transition only along the documented state machine. Creation
// records an audit entry whose fromState is nil. Expected failures use TransitionError.
//
// PART 2 — Audit queries and bulk advancement  (~15 min)
// Query contracts by state sorted by ID and bulk-advance contracts. bulkAdvance
// must call transition for every ID and continue after individual failures.
//
// PART 3 — Lifecycle reporting  (~10 min)
// Report counts by state using contracts(in:), then find nonterminal contracts
// whose auditTrail(for:) ends more than 30 whole days ago, sorted by days stuck.

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
    public init() {}
    public mutating func createContract(id: String, title: String, createdAt: Int, actor: String) throws(TransitionError) -> Contract { throw .notImplemented }
    public mutating func setField(contractID: String, key: String, value: String) throws(TransitionError) -> Contract { throw .notImplemented }
    public func contract(id: String) throws(TransitionError) -> Contract { throw .notImplemented }
    public func auditTrail(for contractID: String) throws(TransitionError) -> [AuditEntry] { throw .notImplemented }
    public mutating func transition(_ contractID: String, to state: ContractState, at: Int, actor: String) throws(TransitionError) -> Contract { throw .notImplemented }
    public func contracts(in state: ContractState) -> [Contract] { [] }
    public mutating func bulkAdvance(_ contractIDs: [String], to state: ContractState, at: Int, actor: String) -> BulkAdvanceResult { .init(succeeded: [], failed: []) }
    public func lifecycleMetrics() -> LifecycleMetrics { .init(total: 0, byState: [:], terminalCount: 0) }
    public func overdueContracts(asOf: Int) -> [OverdueContract] { [] }
}
