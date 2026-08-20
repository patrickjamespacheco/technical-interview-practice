/// One benchmark run: a build identifier and the score that build recorded.
public struct BuildResult: Equatable, Sendable {
    public let id: String
    public let score: Int

    public init(id: String, score: Int) {
        self.id = id
        self.score = score
    }
}

/// The container limits a build ran under. One envelope fits strictly inside
/// another only when both of its limits are strictly smaller.
public struct ResourceEnvelope: Equatable, Sendable {
    public let cpuMillicores: Int
    public let memoryMebibytes: Int

    public init(cpuMillicores: Int, memoryMebibytes: Int) {
        self.cpuMillicores = cpuMillicores
        self.memoryMebibytes = memoryMebibytes
    }
}

public enum ChainError: Error, Equatable, Sendable {
    case emptyHistory
    case noValidPeak
    case notImplemented
}

public struct ChainAnalyzer: Sendable {
    public init() {}

    // MARK: Part 1 - Longest improving chain length

    /// How many builds are in the longest strictly improving chain.
    ///
    /// The chain itself is the primitive and this is its length, so the two can
    /// never disagree about what the longest chain is. Filling a second table
    /// that only produces the number would be the same work twice.
    public func longestImprovingChainLength(_ builds: [BuildResult]) -> Int {
        longestImprovingChain(builds).count
    }

    // MARK: Part 2 - Name the builds in the chain

    /// The identifiers of the longest strictly improving chain, in build order.
    ///
    /// One quadratic table plus one predecessor array. `best[i]` is the length of
    /// the longest improving chain that ends exactly at build `i`, which is what
    /// makes the entries comparable: every chain has to end somewhere, so the
    /// answer is the largest entry rather than the last one.
    ///
    /// Both tie-breaks are deliberate and both are what make the returned list
    /// deterministic: among equally good predecessors the earliest wins, and
    /// among equally long chains the one ending earliest wins.
    public func longestImprovingChain(_ builds: [BuildResult]) -> [String] {
        guard !builds.isEmpty else { return [] }

        var best = Array(repeating: 1, count: builds.count)
        var predecessor = Array(repeating: -1, count: builds.count)

        for index in builds.indices {
            for earlier in 0..<index where builds[earlier].score < builds[index].score {
                // Strictly greater, so the earliest qualifying predecessor is the
                // one that survives a tie.
                if best[earlier] + 1 > best[index] {
                    best[index] = best[earlier] + 1
                    predecessor[index] = earlier
                }
            }
        }

        var endIndex = 0
        for index in builds.indices where best[index] > best[endIndex] {
            endIndex = index
        }

        var chain: [String] = []
        var cursor = endIndex
        while cursor >= 0 {
            chain.append(builds[cursor].id)
            cursor = predecessor[cursor]
        }
        return chain.reversed()
    }

    // MARK: Part 3 - Log-linear chain length

    /// The same number as Part 1, computed without the quadratic table.
    ///
    /// This is the one part that does not reuse an earlier part, and that is the
    /// lesson: the fast formulation abandons the table entirely. What it keeps
    /// instead is one sorted array whose length is the answer.
    public func longestImprovingChainLengthFast(_ builds: [BuildResult]) -> Int {
        tailsScan(builds.map(\.score)).tails.count
    }

    /// The tails array left behind by that scan.
    ///
    /// Entry `L` is the smallest value that can end an improving chain of length
    /// `L + 1`. The array is always sorted, which is exactly what licenses the
    /// binary search, and it is **not** in general a chain from the input:
    /// returning it as the answer to Part 2 is the confident wrong answer this
    /// method exists to make visible.
    public func improvingChainTails(_ builds: [BuildResult]) -> [Int] {
        tailsScan(builds.map(\.score)).tails
    }

    // MARK: Part 4 - Nested envelopes and peak-shaped trains

    /// The deepest run of envelopes that each fit strictly inside the next.
    ///
    /// Sorting by CPU ascending reduces one of the two dimensions to input order,
    /// leaving an improving-chain question on memory. The secondary key is
    /// **descending** on purpose: two envelopes with the same CPU must never
    /// chain, and putting the larger memory first is what makes the improving
    /// scan skip over them. An ascending secondary key looks identical and
    /// silently reports nesting that does not exist.
    public func deepestEnvelopeNesting(_ envelopes: [ResourceEnvelope]) -> Int {
        let ordered = envelopes.sorted {
            $0.cpuMillicores != $1.cpuMillicores
                ? $0.cpuMillicores < $1.cpuMillicores
                : $0.memoryMebibytes > $1.memoryMebibytes
        }
        return tailsScan(ordered.map(\.memoryMebibytes)).tails.count
    }

    /// The fewest builds to drop so the remaining scores rise to one peak and
    /// then fall.
    ///
    /// Run the Part 3 scan forwards for the longest improving chain ending at
    /// each build, then run it over the reversed scores for the longest chain
    /// starting at each build and falling away from it. A build can be the peak
    /// only when both sides have something on them, so both lengths must be at
    /// least two; the peak itself is counted twice, hence the subtraction.
    public func minimumRemovalsForPeakShape(_ builds: [BuildResult]) throws(ChainError) -> Int {
        guard !builds.isEmpty else { throw .emptyHistory }

        let scores = builds.map(\.score)
        let rising = tailsScan(scores).lengthEndingAt
        let falling = Array(tailsScan(scores.reversed()).lengthEndingAt.reversed())

        var bestKept = 0
        for index in builds.indices where rising[index] >= 2 && falling[index] >= 2 {
            bestKept = max(bestKept, rising[index] + falling[index] - 1)
        }
        guard bestKept > 0 else { throw .noValidPeak }
        return builds.count - bestKept
    }

    // MARK: Shared machinery

    /// The patience scan, run once and reporting both of the things Parts 3 and 4
    /// need from it: the final tails array, and the length of the longest
    /// improving chain ending at each position.
    ///
    /// The second falls straight out of the first: a value placed at tails index
    /// `p` ends a chain of length `p + 1`, because tails is sorted and every
    /// earlier slot holds a value it could sit on top of.
    private func tailsScan(_ values: [Int]) -> (tails: [Int], lengthEndingAt: [Int]) {
        var tails: [Int] = []
        var lengthEndingAt = Array(repeating: 0, count: values.count)

        for index in values.indices {
            let value = values[index]
            let position = lowerBound(tails, value)
            if position == tails.count {
                tails.append(value)
            } else {
                tails[position] = value
            }
            lengthEndingAt[index] = position + 1
        }

        return (tails, lengthEndingAt)
    }

    /// The first index of `sorted` holding a value greater than or equal to
    /// `value`, found by halving rather than scanning.
    ///
    /// A linear search would return the same index and would turn the whole scan
    /// back into quadratic work while still passing every test. The comparison is
    /// the strictness knob: `<` here keeps chains strictly improving, and `<=`
    /// would allow equal scores to chain.
    private func lowerBound(_ sorted: [Int], _ value: Int) -> Int {
        var low = 0
        var high = sorted.count
        while low < high {
            let middle = low + (high - low) / 2
            if sorted[middle] < value {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }
}
