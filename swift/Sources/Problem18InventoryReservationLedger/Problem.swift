import Foundation

public struct InventorySnapshot: Equatable, Sendable {
    public let sku: String
    public let onHand: Int
    public let reserved: Int
    public let available: Int
    public init(sku: String, onHand: Int, reserved: Int, available: Int) {
        self.sku = sku; self.onHand = onHand; self.reserved = reserved; self.available = available
    }
}
public enum InventoryError: Error, Equatable, Sendable {
    case invalidQuantity(Int), unknownSKU(String)
    case insufficientAvailable(sku: String, requested: Int, available: Int)
    case duplicateReservationID(String), unknownReservation(String), reservationNotActive(String)
    case duplicateOrderID(String), emptyOrder, notImplemented
}
public enum ReservationState: Equatable, Sendable { case active, released, expired, committed(orderID: String) }
public struct Reservation: Equatable, Sendable {
    public let id: String, idempotencyKey: String, sku: String
    public let quantity: Int
    public let expiresAt: Date
    public let state: ReservationState
    public init(id: String, idempotencyKey: String, sku: String, quantity: Int, expiresAt: Date, state: ReservationState = .active) {
        self.id = id; self.idempotencyKey = idempotencyKey; self.sku = sku; self.quantity = quantity; self.expiresAt = expiresAt; self.state = state
    }
}
public struct CommittedOrder: Equatable, Sendable {
    public let id: String
    public let reservationIDs: [String]
    public init(id: String, reservationIDs: [String]) { self.id = id; self.reservationIDs = reservationIDs }
}
public actor InventoryReservationLedger {
    public init(initialStock: [String: Int] = [:]) {}
    public func snapshot(for sku: String) -> Result<InventorySnapshot, InventoryError> { .failure(.notImplemented) }
    public func availability(for sku: String, quantity: Int) -> Result<InventorySnapshot, InventoryError> { .failure(.notImplemented) }
    public func adjustStock(sku: String, by quantity: Int) -> Result<InventorySnapshot, InventoryError> { .failure(.notImplemented) }
    public func reservation(id: String) -> Result<Reservation, InventoryError> { .failure(.notImplemented) }
    public func reserve(id: String, idempotencyKey: String, sku: String, quantity: Int, expiresAt: Date) -> Result<Reservation, InventoryError> { .failure(.notImplemented) }
    public func release(reservationID: String) -> Result<Reservation, InventoryError> { .failure(.notImplemented) }
    public func expireReservations(at instant: Date) -> [Reservation] { [] }
    public func commit(orderID: String, reservationIDs: [String]) -> Result<CommittedOrder, InventoryError> { .failure(.notImplemented) }
}
