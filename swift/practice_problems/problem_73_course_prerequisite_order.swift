// Problem 73: Course Prerequisite Order
// Swift 6, macOS 14+ | Mid-level | approximately 45 minutes
//
// Put courses in an order that completes each prerequisite before its course.
// Use Kahn's algorithm: an in-degree count and a queue of ready course IDs.
//
// Input is already valid: course IDs are unique, every prerequisite names a
// listed course, and no course repeats a prerequisite. A course may depend on
// itself; that is a cycle. Do not add input validation to this exercise.
// Any valid order is accepted. Within a parallel wave, any order is accepted.
// Empty input has an empty order, can finish, and has no waves.
//
// You choose the internal data structures — the public interface is what
// matters. The planner is stateless; keep traversal state local to each call.
// If you add stored state, use instance properties initialized in init, never
// mutable global or static properties.
//
/*
# Example
let planner = CoursePlanner()
let courses = [
    Course(id: "basics"),
    Course(id: "swift", prerequisites: ["basics"]),
    Course(id: "app", prerequisites: ["swift"]),
]
try planner.order(courses)          // -> ["basics", "swift", "app"]
try planner.canFinish(courses)      // -> true
try planner.parallelWaves(courses)  // -> [["basics"], ["swift"], ["app"]]
*/
//
// PART 1 — A valid order  (~22 min)
// Implement order for acyclic inputs. Emit each course exactly once, after
// every prerequisite. Include independent courses and disconnected components.
// Build one private traverse helper for the in-degree queue; order projects
// its order field. The helper's waves field may stay empty until Part 3.
// Aim for O(V + E) time and space, where V is courses and E is prerequisites.
// Array.removeFirst() shifts the queue: use an advancing head index instead.
// Functional tests cannot enforce the algorithm choice or its running time.
//
// PART 2 — Detect a cycle  (~8 min)
// Extend the shared traversal to throw CoursePlanError.cycleDetected when the
// queue empties before all courses have been emitted. Never return a partial
// order as success, even when a separate component can finish.
// Implement canFinish by calling order: true on success, false on a cycle.
// Propagate other errors (including the stub's notImplemented error).
// Part 1 tests use only acyclic inputs and do not call canFinish.
//
// PART 3 — Parallel waves  (~15 min)
// Extend the same traverse helper to collect waves, then project that field
// from parallelWaves. Each wave contains ALL courses ready at its start.
// Courses unlocked during that wave belong to the next one. Each course
// takes one wave; prerequisites must finish in strictly earlier waves.
// Freeze the queue's end at the start of a wave so newly appended IDs wait.
// Reuse Part 2's cycle check; cyclic input throws instead of returning partial
// waves. Keep order working without calling the later public method.

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

    // MARK: Part 1 — A valid order
    public func order(_ courses: [Course]) throws(CoursePlanError) -> [String] {
        throw .notImplemented
    }

    // MARK: Part 2 — Detect a cycle
    public func canFinish(_ courses: [Course]) throws(CoursePlanError) -> Bool {
        throw .notImplemented
    }

    // MARK: Part 3 — Parallel waves
    public func parallelWaves(_ courses: [Course]) throws(CoursePlanError) -> [[String]] {
        throw .notImplemented
    }

    // Shared seam: implement for Part 1, extend for Parts 2 and 3.
    private func traverse(_ courses: [Course]) throws(CoursePlanError)
        -> (order: [String], waves: [[String]]) {
        throw .notImplemented
    }
}
