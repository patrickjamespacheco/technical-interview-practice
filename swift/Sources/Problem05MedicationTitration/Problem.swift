import Foundation

// Problem 05: Medication Titration Tracker
// Swift 6, macOS 14+ | Senior | approximately 45 minutes
//
// Reduce out-of-order medication events into immutable clinical snapshots.
// Values and identifiers are pre-given. TitrationTracker itself is immutable:
// adding an event returns a new tracker and never changes the original value.
// No wall clock is used; every temporal value arrives through an event.
//
// PART 1 — Patient medication snapshots  (~12 min)
// Return chronological history and active medication snapshots. The latest event
// determines activity and dose; a stop event makes the medication inactive.
//
// PART 2 — Patient-level reductions  (~10 min)
// Count events, optionally by direction, and summarize decreases plus stops per
// medication. Reuse history rather than creating a parallel filtering path.
//
// PART 3 — Population-level reductions  (~13 min)
// Find sorted active patients and the most-titrated medications across patients.
// Reuse the Part 1 snapshot behavior when determining active medications.
//
// PART 4 — Immutable event ingestion  (~10 min)
// Return a new tracker containing the event. For the same patient, medication,
// and timestamp, the new event replaces the old event (last write wins).
//
/*
 * Example
 * let events = [MedicationEvent(patientID: "pt-1", medicationID: "metformin", direction: .start, dose: Dose(milligrams: 500), timestamp: MedicationTimestamp(10))]
 * let tracker = TitrationTracker(events: events)
 * tracker.currentMedications(for: "pt-1").first?.dose // -> Dose(milligrams: 500)
 * tracker.adding(MedicationEvent(patientID: "pt-1", medicationID: "metformin", direction: .stop, dose: .zero, timestamp: MedicationTimestamp(20))).currentMedications(for: "pt-1") // -> []
 */

public struct PatientID: Hashable, Comparable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String; public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(value) }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
public struct MedicationID: Hashable, Comparable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String; public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(value) }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
public struct MedicationTimestamp: Hashable, Comparable, Sendable {
    public let rawValue: Int; public init(_ rawValue: Int) { self.rawValue = rawValue }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
public struct Dose: Equatable, Sendable {
    public let milligrams: Decimal
    public init(milligrams: Decimal) { self.milligrams = milligrams }
    public static let zero = Dose(milligrams: 0)
}
public enum TitrationDirection: Equatable, Sendable { case start, increase, decrease, stop }
public struct MedicationEvent: Equatable, Sendable {
    public let patientID: PatientID; public let medicationID: MedicationID
    public let direction: TitrationDirection; public let dose: Dose; public let timestamp: MedicationTimestamp
    public init(patientID: PatientID, medicationID: MedicationID, direction: TitrationDirection, dose: Dose, timestamp: MedicationTimestamp) {
        self.patientID = patientID; self.medicationID = medicationID; self.direction = direction; self.dose = dose; self.timestamp = timestamp
    }
}
public struct MedicationSnapshot: Equatable, Sendable {
    public let medicationID: MedicationID; public let dose: Dose
    public let lastChanged: MedicationTimestamp; public let totalChanges: Int
}
public struct MedicationCount: Equatable, Sendable {
    public let medicationID: MedicationID; public let count: Int
}
public struct TitrationTracker: Sendable {
    public init(events: [MedicationEvent] = []) { self.events = events }
    private let events: [MedicationEvent]
    public func medicationHistory(for patientID: PatientID, medicationID: MedicationID) -> [MedicationEvent] { [] }
    public func currentMedications(for patientID: PatientID) -> [MedicationSnapshot] { [] }
    public func titrationCount(for patientID: PatientID, medicationID: MedicationID, direction: TitrationDirection? = nil) -> Int { 0 }
    public func deEscalationSummary(for patientID: PatientID) -> [MedicationID: Int] { [:] }
    public func patients(on medicationID: MedicationID) -> [PatientID] { [] }
    public func mostTitratedMedications(limit: Int = 3) -> [MedicationCount] { [] }
    public func adding(_ event: MedicationEvent) -> TitrationTracker { self }
}
