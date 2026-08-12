public struct TelemetryReading: Equatable, Sendable {
    public let id: String
    public let payload: String
    public init(id: String, payload: String) { self.id = id; self.payload = payload }
}

public struct TelemetryBatch: Equatable, Sendable {
    public let sequence: Int
    public let readings: [TelemetryReading]
    public init(sequence: Int, readings: [TelemetryReading]) {
        self.sequence = sequence; self.readings = readings
    }
}

public enum TelemetryProcessorError: Error, Equatable, Sendable {
    case invalidBatchSize
    case invalidRetryLimit
    case notImplemented
}

public enum TelemetrySinkError: Error, Equatable, Sendable {
    case retryable(reason: String)
    case permanent(reason: String)
}

public protocol TelemetrySink: Sendable {
    func send(_ batch: TelemetryBatch) async throws(TelemetrySinkError)
}

public enum DeliveryOutcome: Equatable, Sendable {
    case delivered(batch: TelemetryBatch, attempts: Int)
    case failed(batch: TelemetryBatch, attempts: Int, error: TelemetrySinkError)

    public var batch: TelemetryBatch {
        switch self {
        case let .delivered(batch, _), let .failed(batch, _, _): batch
        }
    }
}

public struct TelemetryBatchProcessor: Sendable {
    private var pending: [TelemetryReading] = []
    private var seenIDs: Set<String> = []
    private var nextSequence = 0

    public init(readings: [TelemetryReading] = []) { ingest(readings) }

    // MARK: Part 1 — deterministic ingestion and batching

    public mutating func ingest(_ readings: [TelemetryReading]) {
        for reading in readings where seenIDs.insert(reading.id).inserted {
            pending.append(reading)
        }
    }

    public mutating func makeBatch(maxCount: Int) throws(TelemetryProcessorError) -> TelemetryBatch? {
        guard maxCount > 0 else { throw .invalidBatchSize }
        guard !pending.isEmpty else { return nil }
        let readings = Array(pending.prefix(maxCount))
        pending.removeFirst(readings.count)
        defer { nextSequence += 1 }
        return TelemetryBatch(sequence: nextSequence, readings: readings)
    }

    public var pendingCount: Int { pending.count }

    // MARK: Part 2 — typed delivery and retry policy

    public func deliver<S: TelemetrySink>(
        batch: TelemetryBatch,
        to sink: S,
        maxRetries: Int
    ) async throws(TelemetryProcessorError) -> DeliveryOutcome {
        guard maxRetries >= 0 else { throw .invalidRetryLimit }
        var attempts = 0
        while true {
            attempts += 1
            do {
                try await sink.send(batch)
                return .delivered(batch: batch, attempts: attempts)
            } catch {
                switch error {
                case .permanent:
                    // Nothing about a permanent failure improves by trying again.
                    return .failed(batch: batch, attempts: attempts, error: error)
                case .retryable:
                    guard attempts <= maxRetries else {
                        return .failed(batch: batch, attempts: attempts, error: error)
                    }
                }
            }
        }
    }
}

public struct TelemetryCheckpoint: Equatable, Sendable {
    public let deliveredReadingIDs: [String]
    public init(deliveredReadingIDs: [String] = []) { self.deliveredReadingIDs = deliveredReadingIDs }
}

public actor TelemetryCoordinator {
    private var processor: TelemetryBatchProcessor
    private let batchSize: Int
    private let maxInFlight: Int
    private let maxRetries: Int
    private var outcomes: [Int: DeliveryOutcome] = [:]
    private var deliveredReadingIDs: [String] = []
    private var nextCheckpointSequence = 0

    public init(readings: [TelemetryReading], batchSize: Int, maxInFlight: Int, maxRetries: Int) {
        self.processor = TelemetryBatchProcessor(readings: readings)
        self.batchSize = batchSize
        self.maxInFlight = maxInFlight
        self.maxRetries = maxRetries
    }

    // MARK: Part 3 — bounded concurrency and ordered checkpointing

    public func run<S: TelemetrySink>(sink: S) async throws(TelemetryProcessorError) -> TelemetryCheckpoint {
        guard batchSize > 0, maxInFlight > 0 else { throw .invalidBatchSize }
        guard maxRetries >= 0 else { throw .invalidRetryLimit }
        // `deliver` reads no processor state, so a value copy is a safe, Sendable
        // way to reuse Part 2 from inside the task group.
        let deliverer = processor
        let retries = maxRetries
        // Exactly `maxInFlight` workers, each pulling the next batch when it is
        // free. The bound is the worker count, so it cannot be exceeded.
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<maxInFlight {
                group.addTask { [self] in
                    while let batch = await claimNextBatch() {
                        guard let outcome = try? await deliverer.deliver(batch: batch, to: sink, maxRetries: retries) else { return }
                        await record(outcome)
                    }
                }
            }
        }
        return checkpoint()
    }

    public func checkpoint() -> TelemetryCheckpoint {
        TelemetryCheckpoint(deliveredReadingIDs: deliveredReadingIDs)
    }

    /// Cancellation is cooperative: a cancelled run stops handing out work and
    /// lets the deliveries already in flight finish reporting.
    private func claimNextBatch() -> TelemetryBatch? {
        guard !Task.isCancelled else { return nil }
        return try? processor.makeBatch(maxCount: batchSize)
    }

    /// Outcomes arrive in completion order; the checkpoint only ever moves
    /// forward across an unbroken run of delivered batches.
    private func record(_ outcome: DeliveryOutcome) {
        outcomes[outcome.batch.sequence] = outcome
        while case let .delivered(batch, _)? = outcomes[nextCheckpointSequence] {
            deliveredReadingIDs.append(contentsOf: batch.readings.map(\.id))
            nextCheckpointSequence += 1
        }
    }
}
