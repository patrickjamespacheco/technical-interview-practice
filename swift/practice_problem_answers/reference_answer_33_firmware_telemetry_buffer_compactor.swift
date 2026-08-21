public enum Severity: Int, Comparable, Sendable, CaseIterable {
    case info
    case warning
    case critical

    public static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct Sample: Equatable, Sendable {
    public let sensorID: String
    public let value: Int
    public let severity: Severity
    public let isValid: Bool

    public init(sensorID: String, value: Int, severity: Severity, isValid: Bool) {
        self.sensorID = sensorID
        self.value = value
        self.severity = severity
        self.isValid = isValid
    }
}

public struct CompactionReport: Equatable, Sendable {
    public let keptCount: Int
    public let droppedCount: Int
    public let droppedBySensor: [String: Int]

    public init(keptCount: Int, droppedCount: Int, droppedBySensor: [String: Int]) {
        self.keptCount = keptCount
        self.droppedCount = droppedCount
        self.droppedBySensor = droppedBySensor
    }
}

public enum BufferError: Error, Equatable, Sendable {
    case nonPositiveRepeatLimit(Int)
    case notImplemented
}

public struct TelemetryBuffer: Sendable {
    public private(set) var samples: [Sample]

    public init(samples: [Sample]) {
        self.samples = samples
    }

    // MARK: The shared compaction cursor

    /// One read cursor sweeping every slot, one write cursor that only advances
    /// when a sample is kept. Everything below `write` is final output;
    /// everything at or above `read` is unexamined; the span between them is
    /// the hole left by dropped samples, not a candidate answer.
    ///
    /// The keep test is handed the buffer as it stands, so it can look at what
    /// has already been committed - that is the only reason Part 2 works
    /// without a second array. It is also handed both cursors, because a keep
    /// test that only sees the read cursor cannot express a repeat limit.
    private mutating func compact(
        keeping shouldKeep: (_ buffer: [Sample], _ read: Int, _ write: Int) -> Bool
    ) -> CompactionReport {
        var write = 0
        var droppedBySensor: [String: Int] = [:]

        for read in 0..<samples.count {
            if shouldKeep(samples, read, write) {
                samples[write] = samples[read]
                write += 1
            } else {
                droppedBySensor[samples[read].sensorID, default: 0] += 1
            }
        }

        let droppedCount = samples.count - write
        samples.removeLast(droppedCount)
        return CompactionReport(
            keptCount: write,
            droppedCount: droppedCount,
            droppedBySensor: droppedBySensor
        )
    }

    // MARK: Part 1 - Drop invalid readings in place

    /// Remove every reading the sensor flagged as bad, rewriting the buffer in
    /// place and reporting what went.
    ///
    /// The report carries the per-sensor attribution rather than only a new
    /// length, because Part 2 needs exactly that and a bare count would force
    /// it to walk the buffer a second time to rebuild it.
    @discardableResult
    public mutating func dropInvalid() -> CompactionReport {
        compact { buffer, read, _ in buffer[read].isValid }
    }

    // MARK: Part 2 - Cap repeated readings per sensor

    /// Keep at most `limit` samples from each run of identical readings.
    ///
    /// A run is a stretch of consecutive samples sharing a sensor and a value:
    /// a sensor that reports the same number ten times in a row has said one
    /// thing, and the uplink budget only pays for `limit` of them.
    ///
    /// The keep test compares against the sample committed `limit` slots back,
    /// not against the previous read. Comparing reads keeps one sample per run
    /// whatever the limit says.
    @discardableResult
    public mutating func capRepeats(perSensor limit: Int) throws(BufferError) -> CompactionReport {
        guard limit > 0 else { throw .nonPositiveRepeatLimit(limit) }

        return compact { buffer, read, write in
            guard write >= limit else { return true }
            let committed = buffer[write - limit]
            return committed.sensorID != buffer[read].sensorID || committed.value != buffer[read].value
        }
    }

    // MARK: Part 3 - Partition by severity in one pass

    /// Reorder the buffer so every informational sample comes first, then every
    /// warning, then every critical one, and report the range each band
    /// occupies.
    ///
    /// This is the same invariant with three regions instead of two, so the
    /// keep-or-drop cursor has nothing to decide and `compact` does not apply.
    /// A low cursor marks the end of the settled informational band, a high
    /// cursor marks the start of the settled critical band, and the read cursor
    /// walks the unclassified middle.
    ///
    /// After a swap with the high cursor the read cursor must stay where it is:
    /// the sample that arrived from the tail has not been looked at yet.
    ///
    /// Every severity appears in the result, with an empty range when the
    /// buffer holds none of that band.
    public mutating func partitionBySeverity() -> [Severity: Range<Int>] {
        var low = 0
        var read = 0
        var high = samples.count - 1

        while read <= high {
            switch samples[read].severity {
            case .info:
                samples.swapAt(low, read)
                low += 1
                read += 1
            case .warning:
                read += 1
            case .critical:
                samples.swapAt(read, high)
                high -= 1
            }
        }

        return [
            .info: 0..<low,
            .warning: low..<read,
            .critical: read..<samples.count,
        ]
    }
}
