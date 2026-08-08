// Active placeholder. The runner temporarily replaces this file with an answer.

public struct TelemetryReading: Equatable, Sendable {
    public let id: String
    public let payload: String
    public init(id: String, payload: String) { self.id = id; self.payload = payload }
}
public struct TelemetryBatch: Equatable, Sendable {
    public let sequence: Int
    public let readings: [TelemetryReading]
    public init(sequence: Int, readings: [TelemetryReading]) { self.sequence = sequence; self.readings = readings }
}
public enum TelemetryProcessorError: Error, Equatable, Sendable { case invalidBatchSize, invalidRetryLimit, notImplemented }
public enum TelemetrySinkError: Error, Equatable, Sendable { case retryable(reason: String), permanent(reason: String) }
public protocol TelemetrySink: Sendable { func send(_ batch: TelemetryBatch) async throws(TelemetrySinkError) }
public enum DeliveryOutcome: Equatable, Sendable {
    case delivered(batch: TelemetryBatch, attempts: Int)
    case failed(batch: TelemetryBatch, attempts: Int, error: TelemetrySinkError)
    public var batch: TelemetryBatch { switch self { case let .delivered(batch, _), let .failed(batch, _, _): batch } }
}
public struct TelemetryBatchProcessor: Sendable {
    public init(readings: [TelemetryReading] = []) {}
    public mutating func ingest(_ readings: [TelemetryReading]) {}
    public mutating func makeBatch(maxCount: Int) throws(TelemetryProcessorError) -> TelemetryBatch? { throw .notImplemented }
    public var pendingCount: Int { 0 }
    public func deliver<S: TelemetrySink>(batch: TelemetryBatch, to sink: S, maxRetries: Int) async throws(TelemetryProcessorError) -> DeliveryOutcome { throw .notImplemented }
}
public struct TelemetryCheckpoint: Equatable, Sendable {
    public let deliveredReadingIDs: [String]
    public init(deliveredReadingIDs: [String] = []) { self.deliveredReadingIDs = deliveredReadingIDs }
}
public actor TelemetryCoordinator {
    public init(readings: [TelemetryReading], batchSize: Int, maxInFlight: Int, maxRetries: Int) {}
    public func run<S: TelemetrySink>(sink: S) async throws(TelemetryProcessorError) -> TelemetryCheckpoint { throw .notImplemented }
    public func checkpoint() -> TelemetryCheckpoint { TelemetryCheckpoint() }
}
