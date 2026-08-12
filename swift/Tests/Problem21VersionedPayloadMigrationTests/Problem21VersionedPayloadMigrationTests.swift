import Foundation
import Testing
@testable import Problem21VersionedPayloadMigration

private func json(_ text: String) -> Data { Data(text.utf8) }
private let v1Ada = json(#"{"version":1,"body":{"name":"Ada Lovelace"}}"#)
private let v2Katherine = json(#"{"version":2,"body":{"firstName":"Katherine","lastName":"Johnson"}}"#)
private let v3Grace = json(#"{"version":3,"body":{"firstName":"Grace","lastName":"Hopper","locale":"en-US"}}"#)

private struct SplitNameMigration: Migration {
    let fromVersion = 1
    let toVersion = 2
    func apply(to document: PayloadDocument) -> Result<PayloadDocument, MigrationError> {
        guard document.version == fromVersion else { return .failure(.invalidStep(from: document.version, to: toVersion)) }
        guard let name = document.fields["name"] else { return .failure(.stepFailed(from: 1, to: 2, reason: "missing name")) }
        let pieces = name.split(separator: " ", maxSplits: 1).map(String.init)
        guard pieces.count == 2 else { return .failure(.stepFailed(from: 1, to: 2, reason: "name must contain two parts")) }
        return .success(PayloadDocument(version: 2, fields: ["firstName": pieces[0], "lastName": pieces[1]]))
    }
}

private struct AddLocaleMigration: Migration {
    let fromVersion = 2
    let toVersion = 3
    func apply(to document: PayloadDocument) -> Result<PayloadDocument, MigrationError> {
        guard document.version == fromVersion else { return .failure(.invalidStep(from: document.version, to: toVersion)) }
        var fields = document.fields
        fields["locale"] = "en-US"
        return .success(PayloadDocument(version: 3, fields: fields))
    }
}

private func makeFreshRegistry() -> MigrationRegistry { MigrationRegistry() }
private func makeSeededRegistry() -> MigrationRegistry {
    MigrationRegistry(migrations: [SplitNameMigration(), AddLocaleMigration()])
}

@Suite("Part 1 — Decode a versioned envelope")
struct Part1 {
    @Test("decodes a complete current-version payload")
    func currentDecode() {
        let decoder = PayloadDecoder()
        #expect(decoder.decodeCurrent(v3Grace) == .success(DecodedPayload(version: 3, firstName: "Grace", lastName: "Hopper", locale: "en-US")))
    }

    @Test("detects versions independently of body validation")
    func versionDetection() {
        let decoder = PayloadDecoder()
        #expect(decoder.detectVersion(v1Ada) == .success(1))
        #expect(decoder.detectVersion(json(#"{"version":9,"body":null}"#)) == .success(9))
    }

    @Test("distinguishes malformed envelopes and malformed bodies")
    func malformedCases() {
        let decoder = PayloadDecoder()
        #expect(decoder.detectVersion(json(#"{"body":{}}"#)) == .failure(.malformedEnvelope))
        #expect(decoder.payloadDocument(json(#"{"version":3,"body":["wrong"]}"#)) == .failure(.malformedBody(version: 3)))
    }

    @Test("names a missing current field")
    func missingField() {
        let decoder = PayloadDecoder()
        let missing = json(#"{"version":3,"body":{"firstName":"No","lastName":"Locale"}}"#)
        #expect(decoder.decodeCurrent(missing) == .failure(.missingRequiredField(field: "locale", version: 3)))
    }

    @Test("reports unsupported versions precisely")
    func unknownVersion() {
        let decoder = PayloadDecoder()
        #expect(decoder.decodeCurrent(json(#"{"version":9,"body":{}}"#)) == .failure(.unknownVersion(9)))
    }

    @Test("decoder configurations remain independent")
    func isolation() {
        let first = PayloadDecoder(currentVersion: 3)
        let second = PayloadDecoder(currentVersion: 4)
        #expect(first.decodeCurrent(v3Grace).successValue?.version == 3)
        #expect(second.decodeCurrent(v3Grace) == .failure(.unknownVersion(3)))
    }
}

@Suite("Part 2 — Compose migration steps")
struct Part2 {
    @Test("applies one migration step")
    func singleStep() {
        let registry = MigrationRegistry(migrations: [AddLocaleMigration()])
        #expect(registry.migrate(v2Katherine) == .migrated(fromVersion: 2, payload: DecodedPayload(version: 3, firstName: "Katherine", lastName: "Johnson", locale: "en-US")))
    }

    @Test("chains multiple migrations")
    func multipleSteps() {
        let registry = makeSeededRegistry()
        #expect(registry.migrate(v1Ada) == .migrated(fromVersion: 1, payload: DecodedPayload(version: 3, firstName: "Ada", lastName: "Lovelace", locale: "en-US")))
    }

    @Test("names a missing intermediate step")
    func missingStep() {
        let registry = MigrationRegistry(migrations: [SplitNameMigration()])
        #expect(registry.migrate(v1Ada) == .failed(.missingStep(from: 2, to: 3)))
    }

    @Test("registry order does not determine chain order")
    func outOfOrderRegistry() {
        let registry = MigrationRegistry(migrations: [AddLocaleMigration(), SplitNameMigration()])
        let chain = try? registry.migrationChain(from: v1Ada).get()
        #expect(chain?.map(\.fromVersion) == [1, 2])
    }

    @Test("registered steps are isolated by registry instance")
    func registryIsolation() {
        var first = makeFreshRegistry()
        let second = makeFreshRegistry()
        first.register(SplitNameMigration())
        #expect(first.registeredVersions() == [1])
        #expect(second.registeredVersions().isEmpty)
    }
}

@Suite("Part 3 — Migrate a batch and report")
struct Part3 {
    @Test("returns one result per payload with aggregate counts")
    func resultsAndCounts() throws {
        let registry = makeSeededRegistry()
        let inputs = [BatchPayload(id: "payload-old", data: v1Ada), BatchPayload(id: "payload-current", data: v3Grace), BatchPayload(id: "payload-unknown", data: json(#"{"version":9,"body":{}}"#))]
        let report = registry.migrateBatch(inputs)
        #expect(report.migratedCount == 1)
        #expect(report.alreadyCurrentCount == 1)
        #expect(report.failedCount == 1)
        // Establish the count before indexing: an unimplemented batch migration
        // returns no results, and a trap here would take down the whole run.
        try #require(report.results.count == inputs.count)
        #expect(report.results[2].outcome == .failed(.payload(.unknownVersion(9))))
    }

    @Test("preserves stable input ordering")
    func stableOrdering() {
        let registry = makeSeededRegistry()
        let inputs = [BatchPayload(id: "payload-zulu", data: v3Grace), BatchPayload(id: "payload-alpha", data: v1Ada), BatchPayload(id: "payload-mike", data: v2Katherine)]
        #expect(registry.migrateBatch(inputs).results.map(\.id) == ["payload-zulu", "payload-alpha", "payload-mike"])
    }

    @Test("does not mutate input fixtures")
    func inputValueSemantics() {
        let registry = makeSeededRegistry()
        let inputs = [BatchPayload(id: "payload-value", data: v1Ada)]
        let original = inputs
        _ = registry.migrateBatch(inputs)
        #expect(inputs == original)
    }
}

private extension Result {
    var successValue: Success? { try? get() }
}
