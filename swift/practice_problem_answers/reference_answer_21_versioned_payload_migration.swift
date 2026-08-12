import Foundation

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

    // MARK: Part 1 — decode a versioned envelope

    public func detectVersion(_ data: Data) -> Result<Int, PayloadError> {
        guard let envelope = envelope(data), let version = envelope["version"] as? Int else {
            return .failure(.malformedEnvelope)
        }
        return .success(version)
    }

    public func payloadDocument(_ data: Data) -> Result<PayloadDocument, PayloadError> {
        // The envelope version is readable even when the body is not, so the
        // body failure can name the version it belongs to.
        detectVersion(data).flatMap { version in
            guard let body = envelope(data)?["body"] as? [String: Any] else {
                return .failure(.malformedBody(version: version))
            }
            var fields: [String: String] = [:]
            for (key, value) in body {
                guard let text = value as? String else { return .failure(.malformedBody(version: version)) }
                fields[key] = text
            }
            return .success(PayloadDocument(version: version, fields: fields))
        }
    }

    public func decodeCurrent(_ data: Data) -> Result<DecodedPayload, PayloadError> {
        payloadDocument(data).flatMap(decodeCurrent)
    }

    /// The one place that knows what a current payload requires. A migration
    /// pipeline ends here too, so there is no second copy of these rules.
    func decodeCurrent(_ document: PayloadDocument) -> Result<DecodedPayload, PayloadError> {
        guard document.version == currentVersion else { return .failure(.unknownVersion(document.version)) }
        guard let firstName = document.fields["firstName"] else {
            return .failure(.missingRequiredField(field: "firstName", version: document.version))
        }
        guard let lastName = document.fields["lastName"] else {
            return .failure(.missingRequiredField(field: "lastName", version: document.version))
        }
        guard let locale = document.fields["locale"] else {
            return .failure(.missingRequiredField(field: "locale", version: document.version))
        }
        return .success(DecodedPayload(version: document.version, firstName: firstName, lastName: lastName, locale: locale))
    }

    private func envelope(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
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
    private var migrationsByFromVersion: [Int: any Migration] = [:]

    public init(decoder: PayloadDecoder = PayloadDecoder(), migrations: [any Migration] = []) {
        self.decoder = decoder
        for migration in migrations { register(migration) }
    }

    // MARK: Part 2 — compose migration steps

    public mutating func register(_ migration: any Migration) {
        migrationsByFromVersion[migration.fromVersion] = migration
    }

    public func migrationChain(from data: Data) -> Result<[any Migration], MigrationError> {
        decoder.detectVersion(data)
            .mapError(MigrationError.payload)
            .flatMap { version in
                guard version <= decoder.currentVersion else { return .failure(.payload(.unknownVersion(version))) }
                var chain: [any Migration] = []
                var reached = version
                // Registration order is irrelevant: the chain is built by
                // following versions forward from the payload's own.
                while reached < decoder.currentVersion {
                    guard let step = migrationsByFromVersion[reached] else {
                        return .failure(.missingStep(from: reached, to: reached + 1))
                    }
                    guard step.toVersion > reached, step.toVersion <= decoder.currentVersion else {
                        return .failure(.invalidStep(from: reached, to: step.toVersion))
                    }
                    chain.append(step)
                    reached = step.toVersion
                }
                return .success(chain)
            }
    }

    public func migrate(_ data: Data) -> MigrationOutcome {
        let chain: [any Migration]
        switch migrationChain(from: data) {
        case let .failure(error): return .failed(error)
        case let .success(steps): chain = steps
        }
        guard let fromVersion = chain.first?.fromVersion else {
            // No steps means the payload already speaks the current version.
            switch decoder.decodeCurrent(data) {
            case let .success(payload): return .alreadyCurrent(payload)
            case let .failure(error): return .failed(.payload(error))
            }
        }
        var document: PayloadDocument
        switch decoder.payloadDocument(data) {
        case let .failure(error): return .failed(.payload(error))
        case let .success(value): document = value
        }
        for step in chain {
            switch step.apply(to: document) {
            case let .failure(error): return .failed(error)
            case let .success(value): document = value
            }
        }
        switch decoder.decodeCurrent(document) {
        case let .success(payload): return .migrated(fromVersion: fromVersion, payload: payload)
        case let .failure(error): return .failed(.payload(error))
        }
    }

    public func registeredVersions() -> [Int] { migrationsByFromVersion.keys.sorted() }
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
    // MARK: Part 3 — migrate a batch and report

    func migrateBatch(_ payloads: [BatchPayload]) -> MigrationReport {
        // `map` keeps the caller's order and leaves the input untouched.
        let results = payloads.map { BatchPayloadResult(id: $0.id, outcome: migrate($0.data)) }
        func count(where matches: (MigrationOutcome) -> Bool) -> Int {
            results.filter { matches($0.outcome) }.count
        }
        return MigrationReport(
            results: results,
            migratedCount: count { if case .migrated = $0 { true } else { false } },
            alreadyCurrentCount: count { if case .alreadyCurrent = $0 { true } else { false } },
            failedCount: count { if case .failed = $0 { true } else { false } }
        )
    }
}
