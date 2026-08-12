import Testing
@testable import Problem19OfflineTelemetryBatchProcessor

private func readings(_ prefix: String, count: Int) -> [TelemetryReading] {
    (1...count).map { TelemetryReading(id: "\(prefix)-\($0)", payload: "value-\($0)") }
}

private func makeFreshProcessor() -> TelemetryBatchProcessor { TelemetryBatchProcessor() }
private func makeSeededProcessor() -> TelemetryBatchProcessor {
    TelemetryBatchProcessor(readings: readings("seed", count: 5))
}

private actor ScriptedSink: TelemetrySink {
    private var failures: [Int: [TelemetrySinkError]]
    private(set) var attempts: [Int: Int] = [:]
    init(failures: [Int: [TelemetrySinkError]] = [:]) { self.failures = failures }
    func send(_ batch: TelemetryBatch) async throws(TelemetrySinkError) {
        attempts[batch.sequence, default: 0] += 1
        if var script = failures[batch.sequence], !script.isEmpty {
            let error = script.removeFirst()
            failures[batch.sequence] = script
            throw error
        }
    }
    func attemptCount(for sequence: Int) -> Int { attempts[sequence, default: 0] }
}

private actor ControlledSink: TelemetrySink {
    private var continuations: [Int: CheckedContinuation<Void, Error>] = [:]
    private var started: [Int] = []
    private var active = 0
    private var peak = 0
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func send(_ batch: TelemetryBatch) async throws(TelemetrySinkError) {
        active += 1
        peak = max(peak, active)
        started.append(batch.sequence)
        let ready = waiters.filter { started.count >= $0.0 }
        waiters.removeAll { started.count >= $0.0 }
        ready.forEach { $0.1.resume() }
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    continuations[batch.sequence] = continuation
                }
            } onCancel: {
                Task { await self.release(sequence: batch.sequence, error: CancellationError()) }
            }
        } catch {
            active -= 1
            throw .retryable(reason: "cancelled")
        }
        active -= 1
    }

    func waitUntilStarted(_ count: Int) async {
        if started.count >= count { return }
        await withTaskCancellationHandler {
            await withCheckedContinuation { waiters.append((count, $0)) }
        } onCancel: {
            Task { await self.cancelWaiters() }
        }
    }
    func cancelWaiters() { let pending = waiters; waiters.removeAll(); pending.forEach { $0.1.resume() } }
    func succeed(_ sequence: Int) { release(sequence: sequence, error: nil) }
    private func release(sequence: Int, error: (any Error)?) {
        guard let continuation = continuations.removeValue(forKey: sequence) else { return }
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }
    func snapshot() -> (started: [Int], active: Int, peak: Int) { (started, active, peak) }
}

private actor StartRace {
    private var continuation: CheckedContinuation<Bool, Never>?
    init(_ continuation: CheckedContinuation<Bool, Never>) { self.continuation = continuation }
    func resolve(_ value: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: value)
    }
}

private func waitForStart(
    _ count: Int,
    sink: ControlledSink,
    run: Task<TelemetryCheckpoint, Error>
) async -> Bool {
    await withCheckedContinuation { continuation in
        let race = StartRace(continuation)
        Task { await sink.waitUntilStarted(count); await race.resolve(true) }
        Task {
            _ = try? await run.value
            await race.resolve(false)
            await sink.cancelWaiters()
        }
    }
}

@Suite("Part 1 — Deduplicate and batch readings")
struct Part1 {
    @Test("deduplicates IDs while preserving first-arrival order")
    func deduplication() throws {
        var processor = makeFreshProcessor()
        processor.ingest([
            TelemetryReading(id: "dedupe-a", payload: "first"),
            TelemetryReading(id: "dedupe-b", payload: "second"),
            TelemetryReading(id: "dedupe-a", payload: "ignored")
        ])
        let candidate = try processor.makeBatch(maxCount: 10)
        let batch = try #require(candidate)
        #expect(batch.readings.map(\.id) == ["dedupe-a", "dedupe-b"])
        #expect(batch.readings.first?.payload == "first")
    }

    @Test("builds stable bounded batches and monotonic sequences")
    func batching() throws {
        var processor = makeSeededProcessor()
        let firstCandidate = try processor.makeBatch(maxCount: 2)
        let secondCandidate = try processor.makeBatch(maxCount: 2)
        let thirdCandidate = try processor.makeBatch(maxCount: 2)
        let first = try #require(firstCandidate)
        let second = try #require(secondCandidate)
        let third = try #require(thirdCandidate)
        #expect([first.readings.count, second.readings.count, third.readings.count] == [2, 2, 1])
        #expect([first.sequence, second.sequence, third.sequence] == [0, 1, 2])
        #expect(try processor.makeBatch(maxCount: 2) == nil)
    }

    @Test("rejects non-positive bounds without consuming readings")
    func invalidBound() throws {
        var processor = makeSeededProcessor()
        #expect(throws: TelemetryProcessorError.invalidBatchSize) { try processor.makeBatch(maxCount: 0) }
        #expect(processor.pendingCount == 5)
    }

    @Test("processors own independent mutable state")
    func isolation() throws {
        var first = makeFreshProcessor()
        let second = makeFreshProcessor()
        first.ingest([TelemetryReading(id: "isolation-reading", payload: "only-first")])
        #expect(first.pendingCount == 1)
        #expect(second.pendingCount == 0)
    }
}

@Suite("Part 2 — Typed delivery outcomes")
struct Part2 {
    @Test("retryable failures retry and retain the original batch")
    func retryable() async throws {
        var processor = makeSeededProcessor()
        let candidate = try processor.makeBatch(maxCount: 2)
        let batch = try #require(candidate)
        let sink = ScriptedSink(failures: [0: [.retryable(reason: "offline")]])
        let outcome = try await processor.deliver(batch: batch, to: sink, maxRetries: 2)
        #expect(outcome == .delivered(batch: batch, attempts: 2))
        #expect(await sink.attemptCount(for: 0) == 2)
    }

    @Test("permanent failures are never retried")
    func permanent() async throws {
        var processor = makeSeededProcessor()
        let candidate = try processor.makeBatch(maxCount: 2)
        let batch = try #require(candidate)
        let error = TelemetrySinkError.permanent(reason: "invalid schema")
        let sink = ScriptedSink(failures: [0: [error]])
        #expect(try await processor.deliver(batch: batch, to: sink, maxRetries: 4) == .failed(batch: batch, attempts: 1, error: error))
    }

    @Test("retry exhaustion and invalid limits are explicit")
    func exhaustion() async throws {
        var processor = makeSeededProcessor()
        let candidate = try processor.makeBatch(maxCount: 2)
        let batch = try #require(candidate)
        let error = TelemetrySinkError.retryable(reason: "still offline")
        let sink = ScriptedSink(failures: [0: [error, error, error]])
        #expect(try await processor.deliver(batch: batch, to: sink, maxRetries: 1) == .failed(batch: batch, attempts: 2, error: error))
        await #expect(throws: TelemetryProcessorError.invalidRetryLimit) {
            try await processor.deliver(batch: batch, to: sink, maxRetries: -1)
        }
    }
}

@Suite("Part 3 — Bounded coordination and checkpoints")
struct Part3 {
    @Test("never exceeds the in-flight bound")
    func boundedConcurrency() async throws {
        let sink = ControlledSink()
        let coordinator = TelemetryCoordinator(readings: readings("bounded", count: 6), batchSize: 1, maxInFlight: 2, maxRetries: 0)
        let run = Task { try await coordinator.run(sink: sink) }
        try #require(await waitForStart(2, sink: sink, run: run))
        #expect(await sink.snapshot().peak == 2)
        // Which of the two in-flight batches reaches the sink first is up to the
        // scheduler, so assert the membership of the first window, not its order.
        // The peak assertion above is what proves the bound is respected.
        #expect(Set(await sink.snapshot().started) == [0, 1])
        await sink.succeed(0)
        try #require(await waitForStart(3, sink: sink, run: run))
        for sequence in 1..<6 {
            await sink.succeed(sequence)
            if sequence < 5 { try #require(await waitForStart(sequence + 2, sink: sink, run: run)) }
        }
        _ = try await run.value
        #expect(await sink.snapshot().peak == 2)
    }

    @Test("out-of-order completion advances only contiguous checkpoints")
    func orderedCheckpoint() async throws {
        let sink = ControlledSink()
        let coordinator = TelemetryCoordinator(readings: readings("ordered", count: 4), batchSize: 2, maxInFlight: 2, maxRetries: 0)
        let run = Task { try await coordinator.run(sink: sink) }
        try #require(await waitForStart(2, sink: sink, run: run))
        await sink.succeed(1)
        #expect(await coordinator.checkpoint().deliveredReadingIDs.isEmpty)
        await sink.succeed(0)
        #expect(try await run.value.deliveredReadingIDs == ["ordered-1", "ordered-2", "ordered-3", "ordered-4"])
    }

    @Test("cancellation stops scheduling queued batches")
    func cancellation() async throws {
        let sink = ControlledSink()
        let coordinator = TelemetryCoordinator(readings: readings("cancel", count: 5), batchSize: 1, maxInFlight: 2, maxRetries: 0)
        let run = Task { try await coordinator.run(sink: sink) }
        try #require(await waitForStart(2, sink: sink, run: run))
        run.cancel()
        _ = try await run.value
        #expect(await sink.snapshot().started.count == 2)
    }
}
