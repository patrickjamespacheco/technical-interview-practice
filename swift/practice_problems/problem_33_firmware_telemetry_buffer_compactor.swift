// Problem 33: Firmware Telemetry Buffer Compactor
// Swift 6, macOS 14+ | Senior | approximately 45 minutes
//
// A constrained device parks telemetry in a fixed-capacity buffer between
// uplinks. It has no room for a second buffer of the same size, so every
// cleanup pass rewrites the buffer where it stands and reports a new logical
// count. Allocating a fresh array and assigning it back is the one thing this
// device cannot afford.
//
// Every part is the same shape: one read cursor sweeps the buffer, and a second
// cursor lags behind it marking how much of the buffer is final. Everything
// below the lagging cursor is settled output. Everything at or above the read
// cursor is unexamined. The gap between them is the hole left by what was
// dropped, and it is not a candidate answer - nothing is ever summed over it.
//
// You choose the internal data structures; the public interface is the contract.
// Store all mutable state in instance properties initialized by init. Never use
// mutable global or static state. Immutable static constants are fine.
//
/*
# Example
var buffer = TelemetryBuffer(samples: [
    Sample(sensorID: "temp-a", value: 2010, severity: .info, isValid: true),
    Sample(sensorID: "temp-a", value: 2010, severity: .info, isValid: true),
    Sample(sensorID: "temp-a", value: 2010, severity: .info, isValid: true),
    Sample(sensorID: "vib-3", value: 41, severity: .critical, isValid: false),
    Sample(sensorID: "temp-a", value: 2115, severity: .warning, isValid: true),
    Sample(sensorID: "temp-a", value: 2115, severity: .warning, isValid: true),
    Sample(sensorID: "vib-3", value: 47, severity: .critical, isValid: true),
])

buffer.dropInvalid()
// -> CompactionReport(keptCount: 6, droppedCount: 1, droppedBySensor: ["vib-3": 1])

try buffer.capRepeats(perSensor: 2)
// -> CompactionReport(keptCount: 5, droppedCount: 1, droppedBySensor: ["temp-a": 1])

buffer.samples.count            // -> 5
buffer.partitionBySeverity()    // -> [.info: 0..<2, .warning: 2..<4, .critical: 4..<5]
*/
//
// PART 1 - Drop invalid readings in place  (~13 min)
// Remove every sample the sensor flagged as bad, rewriting the buffer where it
// stands, and report what went: how many survived, how many went, and how many
// each sensor lost.
// Write this as one private compaction helper that takes a keep test, and let
// the public method be a one-line call into it. Part 2 is a different keep test
// over the same helper, so decide now what that test needs to see - the buffer
// as it stands, and both cursors, is the answer, and a helper that hands over
// only the read cursor cannot express Part 2 at all.
// The report carries the per-sensor attribution rather than only a new length,
// because Part 2 needs exactly that, and a bare count would make Part 2 walk
// the buffer a second time to rebuild it.
//
// PART 2 - Cap repeated readings per sensor  (~16 min)
// A sensor that reports the same number ten times running has said one thing,
// and the uplink budget only pays for a few of them. Keep at most `limit`
// samples from each run of consecutive samples sharing a sensor and a value.
// This is the same helper from Part 1 with a different keep test. The test
// compares the sample being read against the sample already committed `limit`
// slots back, not against the previous sample read. Comparing reads keeps one
// sample per run whatever the limit says, and it is invisible on any buffer
// whose runs are no longer than the limit plus one.
// A limit of zero or less is a typed failure carrying the limit that was asked
// for.
//
// PART 3 - Partition by severity in one pass  (~16 min)
// Reorder the buffer so every informational sample comes first, then every
// warning, then every critical one, and report the range each band occupies.
// Every severity appears in the result, with an empty range when the buffer
// holds none of that band. Order within a band is not preserved and nothing
// depends on it.
// The keep-or-drop helper has nothing to decide here, so it does not apply.
// What carries over is the invariant, restated for three regions instead of
// two: a low cursor ends the settled informational band, a high cursor starts
// the settled critical band, and the read cursor walks the unclassified middle
// between them.
// After swapping a sample in from the high cursor the read cursor must not
// advance. The sample that just arrived from the tail has not been looked at,
// and advancing past it is invisible on any buffer whose tail happens to hold
// an informational sample.

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

    // MARK: Part 1 - Drop invalid readings in place
    @discardableResult
    public mutating func dropInvalid() -> CompactionReport {
        CompactionReport(keptCount: 0, droppedCount: 0, droppedBySensor: [:])
    }

    // MARK: Part 2 - Cap repeated readings per sensor
    @discardableResult
    public mutating func capRepeats(perSensor limit: Int) throws(BufferError) -> CompactionReport {
        throw .notImplemented
    }

    // MARK: Part 3 - Partition by severity in one pass
    public mutating func partitionBySeverity() -> [Severity: Range<Int>] {
        [:]
    }
}
