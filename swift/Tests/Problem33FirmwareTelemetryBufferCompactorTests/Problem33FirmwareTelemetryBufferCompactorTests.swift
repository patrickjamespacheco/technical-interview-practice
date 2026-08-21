import Testing
@testable import Problem33FirmwareTelemetryBufferCompactor

// ── Fixtures ─────────────────────────────────────────────────────────────────

private func sample(
    _ sensorID: String,
    _ value: Int,
    _ severity: Severity = .info,
    valid: Bool = true
) -> Sample {
    Sample(sensorID: sensorID, value: value, severity: severity, isValid: valid)
}

/// The worked uplink batch. One invalid reading, a run of three identical
/// informational readings and a run of two identical warnings.
private let workedBatch: [Sample] = [
    sample("temp-a", 2010),
    sample("temp-a", 2010),
    sample("temp-a", 2010),
    sample("vib-3", 41, .critical, valid: false),
    sample("temp-a", 2115, .warning),
    sample("temp-a", 2115, .warning),
    sample("vib-3", 47, .critical),
]

/// A single run of four identical readings. A compactor that compares the
/// sample being read against the previous sample read keeps one of these
/// whatever the limit says; the committed-slot comparison keeps the limit.
private let singleRunBatch: [Sample] = [
    sample("vib-9", 500),
    sample("vib-9", 500),
    sample("vib-9", 500),
    sample("vib-9", 500),
]

/// Two sensors interleaved, so a compactor that tracks only "the last value"
/// without its sensor treats two different sensors as one run.
private let interleavedBatch: [Sample] = [
    sample("temp-b", 100),
    sample("humid-1", 100),
    sample("temp-b", 100),
    sample("humid-1", 100),
]

/// A batch whose tail is informational, which is what makes a partition that
/// advances the read cursor after a tail swap look correct.
private let tailInfoBatch: [Sample] = [
    sample("gas-1", 7, .critical),
    sample("gas-1", 8, .warning),
    sample("gas-1", 9, .critical),
    sample("gas-1", 10, .info),
]

/// Nothing survives validation.
private let allInvalidBatch: [Sample] = [
    sample("temp-c", 1, .warning, valid: false),
    sample("temp-c", 2, .warning, valid: false),
]

private let batches: [[Sample]] = [
    workedBatch,
    singleRunBatch,
    interleavedBatch,
    tailInfoBatch,
    allInvalidBatch,
    [sample("solo-1", 3, .critical)],
    [],
]

/// Order-insensitive identity of a buffer's contents, for the invariants that
/// say a reordering moved samples around without inventing or losing any.
private func multiset(_ samples: [Sample]) -> [String: Int] {
    var counts: [String: Int] = [:]
    for entry in samples {
        let key = "\(entry.sensorID)|\(entry.value)|\(entry.severity.rawValue)|\(entry.isValid)"
        counts[key, default: 0] += 1
    }
    return counts
}

// ── Part 1 ───────────────────────────────────────────────────────────────────

@Suite("Part 1 - Drop invalid readings in place")
struct CompactorPart1Tests {
    @Test("the worked batch loses its one invalid reading and says which sensor lost it")
    func workedBatchDropsInvalid() throws {
        var buffer = TelemetryBuffer(samples: workedBatch)
        let report = buffer.dropInvalid()

        #expect(report.keptCount == 6)
        #expect(report.droppedCount == 1)
        #expect(report.droppedBySensor == ["vib-3": 1])
        #expect(buffer.samples.count == 6)
        #expect(buffer.samples.allSatisfy { $0.isValid })
    }

    @Test("the surviving samples keep their original order")
    func orderIsPreserved() throws {
        var buffer = TelemetryBuffer(samples: workedBatch)
        buffer.dropInvalid()

        try #require(buffer.samples.count == 6)
        #expect(buffer.samples.map(\.value) == [2010, 2010, 2010, 2115, 2115, 47])
    }

    @Test("a batch with nothing valid compacts to nothing")
    func everythingInvalid() {
        var buffer = TelemetryBuffer(samples: allInvalidBatch)
        let report = buffer.dropInvalid()

        #expect(report.keptCount == 0)
        #expect(report.droppedCount == 2)
        #expect(report.droppedBySensor == ["temp-c": 2])
        #expect(buffer.samples.isEmpty)
    }

    @Test("a batch with nothing invalid is left exactly as it was")
    func nothingInvalid() {
        var buffer = TelemetryBuffer(samples: singleRunBatch)
        let report = buffer.dropInvalid()

        #expect(report.keptCount == 4)
        #expect(report.droppedCount == 0)
        #expect(report.droppedBySensor.isEmpty)
        #expect(buffer.samples == singleRunBatch)
    }

    @Test("an empty buffer reports nothing kept and nothing dropped")
    func emptyBuffer() {
        var buffer = TelemetryBuffer(samples: [])
        let report = buffer.dropInvalid()

        #expect(report.keptCount == 0)
        #expect(report.droppedCount == 0)
        #expect(report.droppedBySensor.isEmpty)
        #expect(buffer.samples.isEmpty)
    }

    @Test("dropping twice drops nothing the second time")
    func droppingIsIdempotent() {
        var buffer = TelemetryBuffer(samples: workedBatch)
        buffer.dropInvalid()
        let second = buffer.dropInvalid()

        #expect(second.keptCount == 6)
        #expect(second.droppedCount == 0)
        #expect(second.droppedBySensor.isEmpty)
    }
}

// ── Part 2 ───────────────────────────────────────────────────────────────────

@Suite("Part 2 - Cap repeated readings per sensor")
struct CompactorPart2Tests {
    @Test("a run of four keeps exactly the limit")
    func runOfFourKeepsTheLimit() throws {
        var buffer = TelemetryBuffer(samples: singleRunBatch)
        let report = try buffer.capRepeats(perSensor: 2)

        // Comparing the sample being read against the previous sample read
        // would keep one here, not two.
        #expect(report.keptCount == 2)
        #expect(report.droppedCount == 2)
        #expect(report.droppedBySensor == ["vib-9": 2])
        #expect(buffer.samples.count == 2)
    }

    @Test("a limit of one keeps the first of each run")
    func limitOfOne() throws {
        var buffer = TelemetryBuffer(samples: singleRunBatch)
        let report = try buffer.capRepeats(perSensor: 1)

        #expect(report.keptCount == 1)
        #expect(report.droppedCount == 3)
    }

    @Test("a limit at or above the longest run drops nothing")
    func generousLimit() throws {
        var buffer = TelemetryBuffer(samples: singleRunBatch)
        let report = try buffer.capRepeats(perSensor: 4)

        #expect(report.keptCount == 4)
        #expect(report.droppedCount == 0)
        #expect(buffer.samples == singleRunBatch)
    }

    @Test("the worked batch loses one repeat and keeps the invalid reading")
    func workedBatchCapsRepeats() throws {
        var buffer = TelemetryBuffer(samples: workedBatch)
        let report = try buffer.capRepeats(perSensor: 2)

        // The run of three informational readings loses one. The invalid
        // reading is not this method's business, so it stays.
        #expect(report.keptCount == 6)
        #expect(report.droppedCount == 1)
        #expect(report.droppedBySensor == ["temp-a": 1])
        try #require(buffer.samples.count == 6)
        #expect(buffer.samples.map(\.value) == [2010, 2010, 41, 2115, 2115, 47])
    }

    @Test("two sensors reporting the same value are two runs, not one")
    func interleavedSensorsAreSeparateRuns() throws {
        var buffer = TelemetryBuffer(samples: interleavedBatch)
        let report = try buffer.capRepeats(perSensor: 1)

        #expect(report.keptCount == 4)
        #expect(report.droppedCount == 0)
        #expect(buffer.samples == interleavedBatch)
    }

    @Test("a run interrupted and resumed is two runs")
    func interruptedRunRestarts() throws {
        var buffer = TelemetryBuffer(samples: [
            sample("flow-2", 12),
            sample("flow-2", 12),
            sample("flow-2", 99),
            sample("flow-2", 12),
            sample("flow-2", 12),
        ])
        let report = try buffer.capRepeats(perSensor: 1)

        #expect(report.keptCount == 3)
        #expect(report.droppedCount == 2)
        try #require(buffer.samples.count == 3)
        #expect(buffer.samples.map(\.value) == [12, 99, 12])
    }

    @Test("capping after dropping the invalid readings reaches the worked answer")
    func dropThenCap() throws {
        var buffer = TelemetryBuffer(samples: workedBatch)
        buffer.dropInvalid()
        let report = try buffer.capRepeats(perSensor: 2)

        #expect(report.keptCount == 5)
        #expect(report.droppedCount == 1)
        #expect(report.droppedBySensor == ["temp-a": 1])
        try #require(buffer.samples.count == 5)
        #expect(buffer.samples.map(\.value) == [2010, 2010, 2115, 2115, 47])
    }

    @Test("an empty buffer caps to nothing")
    func emptyBuffer() throws {
        var buffer = TelemetryBuffer(samples: [])
        let report = try buffer.capRepeats(perSensor: 3)

        #expect(report.keptCount == 0)
        #expect(report.droppedCount == 0)
    }

    @Test("a limit of zero or less is a typed failure carrying the limit")
    func nonPositiveLimitFails() {
        var buffer = TelemetryBuffer(samples: workedBatch)
        #expect(throws: BufferError.nonPositiveRepeatLimit(0)) {
            try buffer.capRepeats(perSensor: 0)
        }
        #expect(throws: BufferError.nonPositiveRepeatLimit(-2)) {
            try buffer.capRepeats(perSensor: -2)
        }
        #expect(buffer.samples == workedBatch)
    }
}

// ── Part 3 ───────────────────────────────────────────────────────────────────

@Suite("Part 3 - Partition by severity in one pass")
struct CompactorPart3Tests {
    @Test("the worked batch partitions into two, two and one after the earlier passes")
    func workedBatchPartitions() throws {
        var buffer = TelemetryBuffer(samples: workedBatch)
        buffer.dropInvalid()
        _ = try buffer.capRepeats(perSensor: 2)
        let ranges = buffer.partitionBySeverity()

        #expect(ranges[.info] == 0..<2)
        #expect(ranges[.warning] == 2..<4)
        #expect(ranges[.critical] == 4..<5)
    }

    @Test("every band appears, empty when the buffer holds none of it")
    func everyBandAppears() {
        var buffer = TelemetryBuffer(samples: singleRunBatch)
        let ranges = buffer.partitionBySeverity()

        #expect(ranges.count == 3)
        #expect(ranges[.info] == 0..<4)
        #expect(ranges[.warning] == 4..<4)
        #expect(ranges[.critical] == 4..<4)
    }

    @Test("an informational sample at the tail is not skipped when it is swapped in")
    func tailSampleIsClassified() throws {
        var buffer = TelemetryBuffer(samples: tailInfoBatch)
        let ranges = buffer.partitionBySeverity()

        // A partition that advances the read cursor after a swap from the tail
        // leaves this informational sample sitting in the critical band.
        #expect(ranges[.info] == 0..<1)
        #expect(ranges[.warning] == 1..<2)
        #expect(ranges[.critical] == 2..<4)
        try #require(buffer.samples.count == 4)
        #expect(buffer.samples[0].severity == .info)
        #expect(buffer.samples[1].severity == .warning)
    }

    @Test("an empty buffer partitions into three empty bands")
    func emptyBuffer() {
        var buffer = TelemetryBuffer(samples: [])
        let ranges = buffer.partitionBySeverity()

        #expect(ranges[.info] == 0..<0)
        #expect(ranges[.warning] == 0..<0)
        #expect(ranges[.critical] == 0..<0)
    }

    @Test("the bands tile the buffer end to end and each holds only its own severity")
    func bandsTileTheBuffer() throws {
        for batch in batches {
            var buffer = TelemetryBuffer(samples: batch)
            let ranges = buffer.partitionBySeverity()

            let info = try #require(ranges[.info])
            let warning = try #require(ranges[.warning])
            let critical = try #require(ranges[.critical])

            #expect(info.lowerBound == 0)
            #expect(info.upperBound == warning.lowerBound)
            #expect(warning.upperBound == critical.lowerBound)
            #expect(critical.upperBound == buffer.samples.count)

            for (severity, range) in [(Severity.info, info), (.warning, warning), (.critical, critical)] {
                #expect(buffer.samples[range].allSatisfy { $0.severity == severity })
            }
        }
    }

    @Test("partitioning moves samples around without inventing or losing any")
    func partitioningPreservesContents() {
        for batch in batches {
            var buffer = TelemetryBuffer(samples: batch)
            _ = buffer.partitionBySeverity()
            #expect(multiset(buffer.samples) == multiset(batch))
        }
    }

    @Test("partitioning and dropping the invalid readings commute")
    func partitionAndDropCommute() {
        for batch in batches {
            var partitionFirst = TelemetryBuffer(samples: batch)
            _ = partitionFirst.partitionBySeverity()
            partitionFirst.dropInvalid()

            var dropFirst = TelemetryBuffer(samples: batch)
            dropFirst.dropInvalid()
            _ = dropFirst.partitionBySeverity()

            #expect(multiset(partitionFirst.samples) == multiset(dropFirst.samples))
            #expect(partitionFirst.samples.count == dropFirst.samples.count)
        }
    }

    @Test("one buffer's compaction leaves a copy of it untouched")
    func buffersHaveValueSemantics() throws {
        let original = TelemetryBuffer(samples: workedBatch)
        var working = original

        working.dropInvalid()
        _ = try working.capRepeats(perSensor: 1)
        _ = working.partitionBySeverity()

        // The copy taken before any of that still holds the whole batch, which
        // is what a compactor backed by shared reference storage would break.
        #expect(original.samples == workedBatch)
        #expect(working.samples.count == 3)

        // A second buffer built from the same batch still reports the
        // documented answers, which is what a count cached in static storage
        // would break.
        var fresh = TelemetryBuffer(samples: workedBatch)
        let report = fresh.dropInvalid()
        #expect(report.keptCount == 6)
        #expect(report.droppedBySensor == ["vib-3": 1])
    }
}
