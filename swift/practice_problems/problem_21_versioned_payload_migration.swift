import Foundation

// Problem 21: Versioned Payload Migration
// Swift 6, macOS 14+ | Senior | approximately 45 minutes
//
// Persisted mobile data can outlive several app releases. Build a decoder and
// migration pipeline that upgrades older payloads without hiding why one failed.
// You choose the internal data structures; the public interface is the contract.
// Store all mutable state in instance properties initialized by init. Never use
// mutable global or static state. Migrations must be pure value transformations.
//
// PART 1 — Decode a versioned envelope  (~15 min)
// detectVersion reads the envelope version without validating a version-specific
// body. payloadDocument uses detectVersion and parses the body as string fields.
// decodeCurrent accepts only currentVersion and requires firstName, lastName, and
// locale. Preserve the distinct typed failures below.
//
// PART 2 — Compose migration steps  (~17 min)
// Migration describes one forward version step. MigrationRegistry stores steps
// by instance, accepts them in any order, and builds a contiguous chain by calling
// the Part 1 detectVersion query. migrate must consume that chain, apply each step
// once, then decode the resulting current document. Name any missing version gap.
//
// PART 3 — Migrate a batch and report  (~13 min)
// migrateBatch calls migrate for every input in its original order. Return one
// result per payload plus aggregate counts for migrated, already-current, and
// failed items. Do not mutate the input collection or reorder the report.
//
/*
 * Example
 * let v1 = #"{"version":1,"body":{"name":"Ada Lovelace"}}"#.data(using: .utf8)!
 * let v3 = #"{"version":3,"body":{"firstName":"Grace","lastName":"Hopper","locale":"en-US"}}"#.data(using: .utf8)!
 * let v9 = #"{"version":9,"body":{}}"#.data(using: .utf8)!
 * registry.migrate(v1) // -> migrated from 1 through 2 to a DecodedPayload at 3
 * registry.migrate(v3) // -> alreadyCurrent with Grace Hopper unchanged
 * registry.migrate(v9) // -> failure(.unknownVersion(9))
 */

public enum PayloadError: Error, Equatable, Sendable {
    case malformedEnvelope
    case malformedBody(version: Int)
    case missingRequiredField(field: String, version: Int)
    case unknownVersion(Int)
    case notImplemented
}

public struct PayloadDocument: Equatable, Sendable {
    public let version: Int
    public let fields: [String: String]
    public init(version: Int, fields: [String: String]) {
        self.version = version
        self.fields = fields
    }
}

public struct DecodedPayload: Equatable, Sendable {
    public let version: Int
    public let firstName: String
    public let lastName: String
    public let locale: String
    public init(version: Int, firstName: String, lastName: String, locale: String) {
        self.version = version
        self.firstName = firstName
        self.lastName = lastName
        self.locale = locale
    }
}

public struct PayloadDecoder: Sendable {
    public let currentVersion: Int
    public init(currentVersion: Int = 3) { self.currentVersion = currentVersion }

    public func detectVersion(_ data: Data) -> Result<Int, PayloadError> {
        .failure(.notImplemented)
    }

    public func payloadDocument(_ data: Data) -> Result<PayloadDocument, PayloadError> {
        .failure(.notImplemented)
    }

    public func decodeCurrent(_ data: Data) -> Result<DecodedPayload, PayloadError> {
        .failure(.notImplemented)
    }
}

public enum MigrationError: Error, Equatable, Sendable {
    case payload(PayloadError)
    case invalidStep(from: Int, to: Int)
    case missingStep(from: Int, to: Int)
    case stepFailed(from: Int, to: Int, reason: String)
    case notImplemented
}

public protocol Migration: Sendable {
    var fromVersion: Int { get }
    var toVersion: Int { get }
    func apply(to document: PayloadDocument) -> Result<PayloadDocument, MigrationError>
}

public enum MigrationOutcome: Equatable, Sendable {
    case migrated(fromVersion: Int, payload: DecodedPayload)
    case alreadyCurrent(DecodedPayload)
    case failed(MigrationError)
}

public struct MigrationRegistry: Sendable {
    public let decoder: PayloadDecoder
    public init(decoder: PayloadDecoder = PayloadDecoder(), migrations: [any Migration] = []) {
        self.decoder = decoder
    }

    public mutating func register(_ migration: any Migration) {}

    public func migrationChain(from data: Data) -> Result<[any Migration], MigrationError> {
        .failure(.notImplemented)
    }

    public func migrate(_ data: Data) -> MigrationOutcome {
        .failed(.notImplemented)
    }

    public func registeredVersions() -> [Int] { [] }
}

public struct BatchPayload: Equatable, Sendable {
    public let id: String
    public let data: Data
    public init(id: String, data: Data) { self.id = id; self.data = data }
}

public struct BatchPayloadResult: Equatable, Sendable {
    public let id: String
    public let outcome: MigrationOutcome
    public init(id: String, outcome: MigrationOutcome) { self.id = id; self.outcome = outcome }
}

public struct MigrationReport: Equatable, Sendable {
    public let results: [BatchPayloadResult]
    public let migratedCount: Int
    public let alreadyCurrentCount: Int
    public let failedCount: Int
    public init(results: [BatchPayloadResult], migratedCount: Int, alreadyCurrentCount: Int, failedCount: Int) {
        self.results = results
        self.migratedCount = migratedCount
        self.alreadyCurrentCount = alreadyCurrentCount
        self.failedCount = failedCount
    }
}

public extension MigrationRegistry {
    func migrateBatch(_ payloads: [BatchPayload]) -> MigrationReport {
        MigrationReport(results: [], migratedCount: 0, alreadyCurrentCount: 0, failedCount: 0)
    }
}
