"""
=============================================================================
INTERVIEW PROBLEM 16: Build Pipeline Scheduler
Difficulty: Senior Software Engineer | Estimated time: 45 min
=============================================================================

CONTEXT
-------
You are building the scheduling core of a CI/CD system. A pipeline contains
jobs connected by dependencies. Independent jobs may run concurrently, while
downstream jobs wait for every dependency to succeed. When several jobs become
ready together, higher-priority work should be dispatched first without making
equal-priority ordering unpredictable.

For this problem you are building a BuildPipelineScheduler class.
Store all state in instance variables initialized in `__init__`.
Class-level variables will bleed between tests and between
BuildPipelineScheduler instances — avoid them.
You choose the internal data structures; the public interface is what matters.

JOB STATUSES
------------
"queued"   — registered, but not yet dispatched
"running"  — returned by next_ready_jobs
"succeeded" — completed successfully
"failed"   — completed unsuccessfully
"cancelled" — cannot run because a dependency failed or was cancelled

# Example
# scheduler = BuildPipelineScheduler()
# scheduler.add_job("lint", priority=10, dependencies=[])
# scheduler.add_job("unit", priority=10, dependencies=["lint"])
# scheduler.add_job("package", priority=100, dependencies=["unit"])
# scheduler.next_ready_jobs(5)            # -> [job dict for "lint"]
# scheduler.complete_job("lint", True)
# scheduler.next_ready_jobs(5)            # -> [job dict for "unit"]
# scheduler.complete_job("unit", False)
# scheduler.get_job_status("package")
# # -> {"status": "cancelled", "blocked_reason": BlockedReason(
# #        dependency_id="unit", dependency_status="failed")}
=============================================================================
"""

from dataclasses import dataclass
from enum import Enum
from typing import Optional


class DependencyStateKind(Enum):
    READY = "ready"
    WAITING = "waiting"
    BLOCKED = "blocked"


@dataclass(frozen=True)
class BlockedReason:
    """Why a queued job can no longer run."""

    dependency_id: str
    dependency_status: str


@dataclass(frozen=True)
class DependencyState:
    """The complete result of evaluating a job's direct dependencies."""

    kind: DependencyStateKind
    waiting_on: tuple[str, ...] = ()
    blocked_reason: Optional[BlockedReason] = None


class BuildPipelineScheduler:
    def __init__(self):
        raise NotImplementedError

    # ---------------------------------------------------------------------
    # PART 1 — Registration and dependency state  (~15 min)
    # ---------------------------------------------------------------------

    def add_job(self, job_id: str, priority: int, dependencies: list[str]) -> dict:
        """
        Register and return a queued job.

        Each dependency must already be registered. Raise ValueError for a
        duplicate job ID, an unknown dependency, or a dependency cycle
        (including a job depending on itself). Do not retain the caller's
        mutable dependencies list.
        """
        raise NotImplementedError

    def get_job_status(self, job_id: str) -> dict:
        """
        Return {"status": str, "blocked_reason": BlockedReason | None}.
        Return a new dict so callers cannot mutate scheduler state.
        Raise KeyError if job_id is unknown.
        """
        raise NotImplementedError

    def dependency_state(self, job_id: str) -> DependencyState:
        """
        Evaluate the job's direct dependencies and return a rich result.

        READY means every dependency succeeded. WAITING includes, in declared
        order, dependencies that have not reached a terminal state. BLOCKED
        carries a typed reason naming the first declared dependency that failed
        or was cancelled. A job with no dependencies is READY.

        Raise KeyError if job_id is unknown.
        """
        raise NotImplementedError

    # ---------------------------------------------------------------------
    # PART 2 — Stable priority dispatch  (~10 min)
    # ---------------------------------------------------------------------

    def next_ready_jobs(self, limit: int) -> list[dict]:
        """
        Dispatch at most `limit` queued jobs whose dependency_state is READY.

        Order by priority descending, then registration order ascending. Mark
        every returned job as "running" before returning it. Call
        dependency_state for readiness; do not duplicate graph traversal.
        Return job dicts with job_id, priority, dependencies, and status.

        Raise ValueError if limit is negative. A zero limit returns [].
        """
        raise NotImplementedError

    # ---------------------------------------------------------------------
    # PART 3 — Completion and transitive cancellation  (~20 min)
    # ---------------------------------------------------------------------

    def complete_job(self, job_id: str, succeeded: bool) -> dict:
        """
        Complete a running job as "succeeded" or "failed" and return status.

        A failure transitively cancels every queued downstream job that is now
        BLOCKED. Store the BlockedReason returned by dependency_state; do not
        recreate failure reasoning in the cancellation logic. Running jobs are
        never retroactively cancelled.

        Repeating the same completion is idempotent and returns the existing
        status. Raise ValueError for a conflicting repeat or for a job that has
        not been dispatched by next_ready_jobs. Raise KeyError if unknown.
        """
        raise NotImplementedError
