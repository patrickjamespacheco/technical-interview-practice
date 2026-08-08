"""Tests for Problem 16: Build Pipeline Scheduler.

Run from the repository root:
    pytest python/tests/test_problem_16_build_pipeline_scheduler.py -v
"""

import pytest

from practice_problems.problem_16_build_pipeline_scheduler import (
    BlockedReason,
    BuildPipelineScheduler,
    DependencyStateKind,
)


SEEDED_JOBS = (
    ("seed-lint", 20, []),
    ("seed-unit", 30, ["seed-lint"]),
    ("seed-package", 90, ["seed-unit"]),
    ("seed-docs", 10, []),
)


@pytest.fixture
def fresh_scheduler():
    return BuildPipelineScheduler()


@pytest.fixture
def scheduler():
    subject = BuildPipelineScheduler()
    for job_id, priority, dependencies in SEEDED_JOBS:
        subject.add_job(job_id, priority, list(dependencies))
    return subject


# ---------------------------------------------------------------------------
# PART 1 — Registration and dependency state
# ---------------------------------------------------------------------------

class TestRegistration:
    def test_registers_queued_job(self, fresh_scheduler):
        job = fresh_scheduler.add_job("registration-compile", 40, [])
        assert job == {
            "job_id": "registration-compile",
            "priority": 40,
            "dependencies": [],
            "status": "queued",
        }
        assert fresh_scheduler.get_job_status("registration-compile") == {
            "status": "queued",
            "blocked_reason": None,
        }

    def test_copies_dependencies(self, fresh_scheduler):
        fresh_scheduler.add_job("copy-base", 1, [])
        dependencies = ["copy-base"]
        job = fresh_scheduler.add_job("copy-child", 2, dependencies)
        dependencies.append("not-registered")
        assert job["dependencies"] == ["copy-base"]

    def test_dependency_state_is_rich(self, fresh_scheduler):
        fresh_scheduler.add_job("state-base", 1, [])
        fresh_scheduler.add_job("state-child", 2, ["state-base"])
        state = fresh_scheduler.dependency_state("state-child")
        assert state.kind is DependencyStateKind.WAITING
        assert state.waiting_on == ("state-base",)
        assert state.blocked_reason is None


class TestDuplicateId:
    def test_rejects_duplicate_job_id(self, fresh_scheduler):
        fresh_scheduler.add_job("duplicate-target", 1, [])
        with pytest.raises(ValueError):
            fresh_scheduler.add_job("duplicate-target", 99, [])


class TestMissingDependency:
    def test_rejects_unknown_dependency(self, fresh_scheduler):
        with pytest.raises(ValueError):
            fresh_scheduler.add_job("missing-child", 5, ["missing-parent"])


class TestCycleDetection:
    def test_rejects_self_dependency_cycle(self, fresh_scheduler):
        with pytest.raises(ValueError, match="cycle"):
            fresh_scheduler.add_job("cycle-self", 5, ["cycle-self"])


class TestInstanceIsolation:
    def test_instances_do_not_share_jobs(self, fresh_scheduler, scheduler):
        fresh_scheduler.add_job("isolation-only", 1, [])
        with pytest.raises(KeyError):
            scheduler.get_job_status("isolation-only")


# ---------------------------------------------------------------------------
# PART 2 — Stable priority dispatch
# ---------------------------------------------------------------------------

class TestReadyFiltering:
    def test_returns_only_jobs_with_succeeded_dependencies(self, scheduler):
        ready = scheduler.next_ready_jobs(10)
        assert [job["job_id"] for job in ready] == ["seed-lint", "seed-docs"]
        assert all(job["status"] == "running" for job in ready)

    def test_calls_part_one_dependency_query(self, fresh_scheduler, monkeypatch):
        fresh_scheduler.add_job("query-seam", 1, [])
        original = fresh_scheduler.dependency_state
        calls = []

        def recording_query(job_id):
            calls.append(job_id)
            return original(job_id)

        monkeypatch.setattr(fresh_scheduler, "dependency_state", recording_query)
        fresh_scheduler.next_ready_jobs(1)
        assert calls == ["query-seam"]


class TestStablePriorityOrdering:
    def test_priority_descending_then_insertion_order(self, fresh_scheduler):
        fresh_scheduler.add_job("order-low", 1, [])
        fresh_scheduler.add_job("order-first-high", 50, [])
        fresh_scheduler.add_job("order-second-high", 50, [])
        ready = fresh_scheduler.next_ready_jobs(10)
        assert [job["job_id"] for job in ready] == [
            "order-first-high", "order-second-high", "order-low"
        ]


class TestLimitArgument:
    def test_limits_and_does_not_consume_extra_jobs(self, fresh_scheduler):
        fresh_scheduler.add_job("limit-one", 3, [])
        fresh_scheduler.add_job("limit-two", 2, [])
        fresh_scheduler.add_job("limit-three", 1, [])
        assert [j["job_id"] for j in fresh_scheduler.next_ready_jobs(2)] == [
            "limit-one", "limit-two"
        ]
        assert [j["job_id"] for j in fresh_scheduler.next_ready_jobs(2)] == [
            "limit-three"
        ]

    def test_zero_and_negative_limits(self, fresh_scheduler):
        fresh_scheduler.add_job("limit-zero", 1, [])
        assert fresh_scheduler.next_ready_jobs(0) == []
        with pytest.raises(ValueError):
            fresh_scheduler.next_ready_jobs(-1)


class TestMultipleDependencies:
    def test_waits_until_every_dependency_succeeds(self, fresh_scheduler):
        fresh_scheduler.add_job("multi-left", 5, [])
        fresh_scheduler.add_job("multi-right", 5, [])
        fresh_scheduler.add_job("multi-join", 100, ["multi-left", "multi-right"])
        ready = fresh_scheduler.next_ready_jobs(2)
        assert [job["job_id"] for job in ready] == ["multi-left", "multi-right"]
        state = fresh_scheduler.dependency_state("multi-join")
        assert state.kind is DependencyStateKind.WAITING
        assert state.waiting_on == ("multi-left", "multi-right")


# ---------------------------------------------------------------------------
# PART 3 — Completion and transitive cancellation
# ---------------------------------------------------------------------------

class TestSuccess:
    def test_success_unlocks_dependent(self, fresh_scheduler):
        fresh_scheduler.add_job("success-parent", 1, [])
        fresh_scheduler.add_job("success-child", 2, ["success-parent"])
        fresh_scheduler.next_ready_jobs(1)
        assert fresh_scheduler.complete_job("success-parent", True)["status"] == "succeeded"
        assert [j["job_id"] for j in fresh_scheduler.next_ready_jobs(1)] == ["success-child"]


class TestFailure:
    def test_failure_cancels_direct_dependent_with_typed_reason(self, fresh_scheduler):
        fresh_scheduler.add_job("failure-parent", 1, [])
        fresh_scheduler.add_job("failure-child", 2, ["failure-parent"])
        fresh_scheduler.next_ready_jobs(1)
        fresh_scheduler.complete_job("failure-parent", False)
        status = fresh_scheduler.get_job_status("failure-child")
        assert status["status"] == "cancelled"
        assert status["blocked_reason"] == BlockedReason("failure-parent", "failed")

    def test_cancellation_reuses_dependency_state_reason(self, fresh_scheduler, monkeypatch):
        fresh_scheduler.add_job("reason-parent", 1, [])
        fresh_scheduler.add_job("reason-child", 2, ["reason-parent"])
        fresh_scheduler.next_ready_jobs(1)
        original = fresh_scheduler.dependency_state
        calls = []

        def recording_query(job_id):
            calls.append(job_id)
            return original(job_id)

        monkeypatch.setattr(fresh_scheduler, "dependency_state", recording_query)
        fresh_scheduler.complete_job("reason-parent", False)
        assert "reason-child" in calls


class TestTransitiveCancellation:
    def test_cancels_all_downstream_jobs(self, fresh_scheduler):
        fresh_scheduler.add_job("transitive-root", 1, [])
        fresh_scheduler.add_job("transitive-middle", 2, ["transitive-root"])
        fresh_scheduler.add_job("transitive-leaf", 3, ["transitive-middle"])
        fresh_scheduler.next_ready_jobs(1)
        fresh_scheduler.complete_job("transitive-root", False)
        middle = fresh_scheduler.get_job_status("transitive-middle")
        leaf = fresh_scheduler.get_job_status("transitive-leaf")
        assert middle["blocked_reason"] == BlockedReason("transitive-root", "failed")
        assert leaf["blocked_reason"] == BlockedReason("transitive-middle", "cancelled")


class TestIdempotentCompletion:
    def test_same_completion_can_be_repeated(self, fresh_scheduler):
        fresh_scheduler.add_job("idempotent-success", 1, [])
        fresh_scheduler.next_ready_jobs(1)
        first = fresh_scheduler.complete_job("idempotent-success", True)
        second = fresh_scheduler.complete_job("idempotent-success", True)
        assert first == second == {"status": "succeeded", "blocked_reason": None}

    def test_conflicting_or_undispatched_completion_is_rejected(self, fresh_scheduler):
        fresh_scheduler.add_job("idempotent-conflict", 1, [])
        with pytest.raises(ValueError):
            fresh_scheduler.complete_job("idempotent-conflict", True)
        fresh_scheduler.next_ready_jobs(1)
        fresh_scheduler.complete_job("idempotent-conflict", True)
        with pytest.raises(ValueError):
            fresh_scheduler.complete_job("idempotent-conflict", False)
