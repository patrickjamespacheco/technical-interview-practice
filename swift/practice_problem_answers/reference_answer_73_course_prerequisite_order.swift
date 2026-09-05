public struct Course: Equatable, Sendable {
    public let id: String
    public let prerequisites: [String]

    public init(id: String, prerequisites: [String] = []) {
        self.id = id
        self.prerequisites = prerequisites
    }
}

public enum CoursePlanError: Error, Equatable, Sendable {
    case cycleDetected
    case notImplemented
}

public struct CoursePlanner: Sendable {
    public init() {}

    // Part 1: the order is a projection of one Kahn traversal.
    public func order(_ courses: [Course]) throws(CoursePlanError) -> [String] {
        try traverse(courses).order
    }

    // Part 2: reuse the ordering contract, including its cycle check.
    public func canFinish(_ courses: [Course]) throws(CoursePlanError) -> Bool {
        do {
            _ = try order(courses)
            return true
        } catch {
            if error == .cycleDetected { return false }
            throw error
        }
    }

    // Part 3: the same traversal also records the ready frontier per wave.
    public func parallelWaves(_ courses: [Course]) throws(CoursePlanError) -> [[String]] {
        try traverse(courses).waves
    }

    private func traverse(_ courses: [Course]) throws(CoursePlanError)
        -> (order: [String], waves: [[String]]) {
        var inDegree: [String: Int] = [:]
        var dependents: [String: [String]] = [:]
        for course in courses {
            inDegree[course.id] = course.prerequisites.count
            for prerequisite in course.prerequisites {
                dependents[prerequisite, default: []].append(course.id)
            }
        }

        // Include every source, even isolated courses in another component.
        var queue = courses.filter { inDegree[$0.id] == 0 }.map(\.id)
        var head = 0
        var waves: [[String]] = []
        while head < queue.count {
            // New arrivals are ready for the next wave, not this one.
            let waveEnd = queue.count
            waves.append(Array(queue[head..<waveEnd]))
            while head < waveEnd {
                let id = queue[head]
                head += 1
                for dependent in dependents[id, default: []] {
                    inDegree[dependent, default: 0] -= 1
                    if inDegree[dependent] == 0 {
                        queue.append(dependent)
                    }
                }
            }
        }

        // A blocked remainder proves a cycle; it may also contain courses
        // downstream of that cycle, so it is not a list of cycle members.
        guard queue.count == courses.count else { throw .cycleDetected }
        return (order: queue, waves: waves)
    }
}
