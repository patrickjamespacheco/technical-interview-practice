import Foundation

// Problem 18: Inventory Reservation Ledger
// Swift 6, macOS 14+ | Senior | approximately 45 minutes
//
// Build an actor-backed inventory ledger for a commerce checkout flow. You choose
// the internal data structures — the public interface is what matters.
// Store all state in instance variables initialized in init. Mutable global or
// static state will bleed between tests and ledger instances — avoid it.
//
// PART 1 — Typed stock and availability  (~12 min)
// Seed stock by SKU, adjust it with typed Result failures, and return an
// InventorySnapshot from availability. A negative adjustment may consume only
// available stock, never units held by reservations.
//
// PART 2 — Idempotent concurrent reservations  (~18 min)
// Reserve and release stock under readable string IDs and idempotency keys.
// reserve must consume availability's Result directly. Replaying any key returns
// its original reservation, even if the replay's other arguments differ. Because
// all checks and mutations occur inside this actor, concurrent calls must never
// oversell. reservation(id:) is the lookup seam used by release.
//
// PART 3 — Expiry and atomic order commits  (~15 min)
// expireReservations(at:) uses the injected instant and terminates every active
// reservation whose expiry is at or before that instant, returning them in the
// .expired state with their held stock freed. commit validates every
// reservation through reservation(id:) before changing anything, then
// commits the whole order atomically. Centralize terminal reservation bookkeeping
// so release, expiry, and commit never maintain parallel counter logic.
//
/*
 * Example
 * let ledger = InventoryReservationLedger(initialStock: ["camera": 2])
 * async let first = ledger.reserve(id: "res-a", idempotencyKey: "key-a", sku: "camera", quantity: 2, expiresAt: Date(timeIntervalSince1970: 100))
 * async let second = ledger.reserve(id: "res-b", idempotencyKey: "key-b", sku: "camera", quantity: 2, expiresAt: Date(timeIntervalSince1970: 100))
 * let attempts = await [first, second] // -> exactly one success
 * let replay = await ledger.reserve(id: "ignored", idempotencyKey: "key-a", sku: "camera", quantity: 99, expiresAt: .distantFuture) // -> same res-a when key-a won
 * let expired = await ledger.expireReservations(at: Date(timeIntervalSince1970: 100)) // -> winner is .expired; camera available is 2
 */

public struct InventorySnapshot: Equatable, Sendable {
    public let sku: String
    public let onHand: Int
    public let reserved: Int
    public let available: Int

    public init(sku: String, onHand: Int, reserved: Int, available: Int) {
        self.sku = sku
        self.onHand = onHand
        self.reserved = reserved
        self.available = available
    }
}

public enum InventoryError: Error, Equatable, Sendable {
    case invalidQuantity(Int)
    case unknownSKU(String)
    case insufficientAvailable(sku: String, requested: Int, available: Int)
    case duplicateReservationID(String)
    case unknownReservation(String)
    case reservationNotActive(String)
    case duplicateOrderID(String)
    case emptyOrder
    case notImplemented
}

public enum ReservationState: Equatable, Sendable {
    case active
    case released
    case expired
    case committed(orderID: String)
}

public struct Reservation: Equatable, Sendable {
    public let id: String
    public let idempotencyKey: String
    public let sku: String
    public let quantity: Int
    public let expiresAt: Date
    public let state: ReservationState

    public init(id: String, idempotencyKey: String, sku: String, quantity: Int, expiresAt: Date, state: ReservationState = .active) {
        self.id = id
        self.idempotencyKey = idempotencyKey
        self.sku = sku
        self.quantity = quantity
        self.expiresAt = expiresAt
        self.state = state
    }
}

public struct CommittedOrder: Equatable, Sendable {
    public let id: String
    public let reservationIDs: [String]

    public init(id: String, reservationIDs: [String]) {
        self.id = id
        self.reservationIDs = reservationIDs
    }
}

public actor InventoryReservationLedger {
    public init(initialStock: [String: Int] = [:]) {}

    // MARK: Part 1 — typed stock and availability
    public func snapshot(for sku: String) -> Result<InventorySnapshot, InventoryError> { .failure(.notImplemented) }
    public func availability(for sku: String, quantity: Int) -> Result<InventorySnapshot, InventoryError> { .failure(.notImplemented) }
    public func adjustStock(sku: String, by quantity: Int) -> Result<InventorySnapshot, InventoryError> { .failure(.notImplemented) }

    // MARK: Part 2 — idempotent concurrent reservations
    public func reservation(id: String) -> Result<Reservation, InventoryError> { .failure(.notImplemented) }
    public func reserve(id: String, idempotencyKey: String, sku: String, quantity: Int, expiresAt: Date) -> Result<Reservation, InventoryError> { .failure(.notImplemented) }
    public func release(reservationID: String) -> Result<Reservation, InventoryError> { .failure(.notImplemented) }

    // MARK: Part 3 — expiry and atomic commits
    public func expireReservations(at instant: Date) -> [Reservation] { [] }
    public func commit(orderID: String, reservationIDs: [String]) -> Result<CommittedOrder, InventoryError> { .failure(.notImplemented) }
}
