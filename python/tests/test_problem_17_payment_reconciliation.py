"""Tests for Problem 17: Payment Reconciliation Engine.

Run from the repository root:
    pytest python/tests/test_problem_17_payment_reconciliation.py -v
"""

from decimal import Decimal

import pytest

from practice_problems.problem_17_payment_reconciliation import (
    PaymentReconciliationEngine,
)


CHARGES = [
    ("charge-seed-alpha", Decimal("25.00"), "2026-04-10"),
    ("charge-seed-beta", Decimal("25.00"), "2026-04-12"),
    ("charge-seed-precision", Decimal("0.30"), "2026-04-15"),
]

SETTLEMENTS = [
    ("settlement-seed-ref", Decimal("25.00"), "2026-04-12", "charge-seed-alpha"),
    ("settlement-seed-window", Decimal("0.30"), "2026-04-15", None),
    ("settlement-seed-ambiguous", Decimal("25.00"), "2026-04-11", None),
    ("settlement-seed-unmatched", Decimal("24.00"), "2026-04-11", None),
]


@pytest.fixture
def fresh_engine():
    """An empty reconciliation engine."""
    return PaymentReconciliationEngine()


@pytest.fixture
def engine():
    """A seeded engine; fixture inputs are defensively copied."""
    subject = PaymentReconciliationEngine()
    for charge_id, amount, charge_date in list(CHARGES):
        subject.ingest_charge(charge_id, amount, charge_date)
    for settlement_id, amount, settlement_date, reference in list(SETTLEMENTS):
        subject.ingest_settlement(
            settlement_id, amount, settlement_date, reference
        )
    return subject


# ---------------------------------------------------------------------------
# PART 1 — Canonical ingestion and lookups
# ---------------------------------------------------------------------------


class TestIngestion:
    def test_ingests_and_looks_up_charge(self, fresh_engine):
        charge = fresh_engine.ingest_charge(
            "charge-ingest-one", Decimal("19.95"), "2026-05-01"
        )
        assert charge == {
            "charge_id": "charge-ingest-one",
            "amount": Decimal("19.95"),
            "charge_date": "2026-05-01",
        }
        assert fresh_engine.get_charge("charge-ingest-one") == charge

    def test_ingests_and_looks_up_settlement(self, fresh_engine):
        settlement = fresh_engine.ingest_settlement(
            "settlement-ingest-one",
            Decimal("19.95"),
            "2026-05-02",
            "charge-ingest-one",
        )
        assert settlement["settlement_id"] == "settlement-ingest-one"
        assert settlement["amount"] == Decimal("19.95")
        assert settlement["reference"] == "charge-ingest-one"
        assert fresh_engine.get_settlement("settlement-ingest-one") == settlement

    def test_unknown_lookups_return_none(self, fresh_engine):
        assert fresh_engine.get_charge("charge-ingest-missing") is None
        assert fresh_engine.get_settlement("settlement-ingest-missing") is None

    def test_rejects_float_amounts(self, fresh_engine):
        with pytest.raises(TypeError):
            fresh_engine.ingest_charge(
                "charge-ingest-float", 10.25, "2026-05-03"
            )
        with pytest.raises(TypeError):
            fresh_engine.ingest_settlement(
                "settlement-ingest-float", 10.25, "2026-05-03"
            )


class TestIdempotentReingest:
    def test_identical_charge_reingest_is_idempotent(self, fresh_engine):
        first = fresh_engine.ingest_charge(
            "charge-idempotent", Decimal("7.40"), "2026-05-04"
        )
        second = fresh_engine.ingest_charge(
            "charge-idempotent", Decimal("7.40"), "2026-05-04"
        )
        assert second == first

    def test_identical_settlement_reingest_is_idempotent(self, fresh_engine):
        first = fresh_engine.ingest_settlement(
            "settlement-idempotent", Decimal("7.40"), "2026-05-05", None
        )
        second = fresh_engine.ingest_settlement(
            "settlement-idempotent", Decimal("7.40"), "2026-05-05", None
        )
        assert second == first


class TestConflictingDuplicate:
    def test_conflicting_charge_duplicate_raises(self, fresh_engine):
        fresh_engine.ingest_charge(
            "charge-conflict", Decimal("8.00"), "2026-05-06"
        )
        with pytest.raises(ValueError):
            fresh_engine.ingest_charge(
                "charge-conflict", Decimal("8.01"), "2026-05-06"
            )

    def test_conflicting_settlement_duplicate_raises(self, fresh_engine):
        fresh_engine.ingest_settlement(
            "settlement-conflict", Decimal("8.00"), "2026-05-06", None
        )
        with pytest.raises(ValueError):
            fresh_engine.ingest_settlement(
                "settlement-conflict",
                Decimal("8.00"),
                "2026-05-06",
                "charge-conflict-other",
            )


class TestDecimalPrecision:
    def test_decimal_arithmetic_amount_matches_exactly(self, fresh_engine):
        precise_total = Decimal("0.10") + Decimal("0.20")
        assert precise_total == Decimal("0.30")
        assert 0.1 + 0.2 != 0.3  # the bug Decimal prevents in currency matching

        fresh_engine.ingest_charge(
            "charge-decimal-precision", precise_total, "2026-05-07"
        )
        stored = fresh_engine.get_charge("charge-decimal-precision")
        assert stored["amount"] == Decimal("0.30")
        assert isinstance(stored["amount"], Decimal)


# ---------------------------------------------------------------------------
# PART 2 — Rich settlement matching
# ---------------------------------------------------------------------------


class TestExactReferenceMatch:
    def test_reference_takes_precedence(self, fresh_engine):
        fresh_engine.ingest_charge(
            "charge-reference-target", Decimal("50.00"), "2026-05-01"
        )
        fresh_engine.ingest_charge(
            "charge-reference-decoy", Decimal("49.00"), "2026-05-20"
        )
        fresh_engine.ingest_settlement(
            "settlement-reference-match",
            Decimal("49.00"),
            "2026-05-20",
            "charge-reference-target",
        )

        result = fresh_engine.match_settlement("settlement-reference-match", 0)

        assert result["status"] == "matched"
        assert result["reason"] == "exact_reference"
        assert result["matched_charge_id"] == "charge-reference-target"
        assert [c["charge_id"] for c in result["candidates"]] == [
            "charge-reference-target"
        ]

    def test_unknown_settlement_raises(self, engine):
        with pytest.raises(KeyError):
            engine.match_settlement("settlement-reference-missing", 2)


class TestAmountWindowMatch:
    def test_unique_amount_and_inclusive_window_matches(self, engine):
        result = engine.match_settlement("settlement-seed-window", 0)
        assert result["status"] == "matched"
        assert result["reason"] == "amount_date_window"
        assert result["matched_charge_id"] == "charge-seed-precision"

    def test_unknown_reference_falls_back_to_amount_window(self, fresh_engine):
        fresh_engine.ingest_charge(
            "charge-window-fallback", Decimal("61.00"), "2026-06-02"
        )
        fresh_engine.ingest_settlement(
            "settlement-window-fallback",
            Decimal("61.00"),
            "2026-06-03",
            "charge-reference-unknown",
        )
        result = fresh_engine.match_settlement("settlement-window-fallback", 1)
        assert result["matched_charge_id"] == "charge-window-fallback"
        assert result["reason"] == "amount_date_window"

    def test_outside_window_is_unmatched(self, fresh_engine):
        fresh_engine.ingest_charge(
            "charge-window-outside", Decimal("71.00"), "2026-06-01"
        )
        fresh_engine.ingest_settlement(
            "settlement-window-outside", Decimal("71.00"), "2026-06-03"
        )
        result = fresh_engine.match_settlement("settlement-window-outside", 1)
        assert result["status"] == "unmatched"
        assert result["reason"] == "no_candidates"
        assert result["candidates"] == []

    def test_negative_window_raises(self, engine):
        with pytest.raises(ValueError):
            engine.match_settlement("settlement-seed-window", -1)


class TestAmbiguityWithMultipleCandidates:
    def test_returns_all_candidates_in_stable_order(self, engine):
        result = engine.match_settlement("settlement-seed-ambiguous", 2)
        assert result["status"] == "ambiguous"
        assert result["reason"] == "multiple_candidates"
        assert result["matched_charge_id"] is None
        assert [candidate["charge_id"] for candidate in result["candidates"]] == [
            "charge-seed-alpha",
            "charge-seed-beta",
        ]


# ---------------------------------------------------------------------------
# PART 3 — Batch reconciliation and summaries
# ---------------------------------------------------------------------------


class TestBatchCounts:
    def test_counts_each_rich_outcome(self, engine):
        result = engine.reconcile_batch(
            [
                "settlement-seed-unmatched",
                "settlement-seed-ref",
                "settlement-seed-ambiguous",
                "settlement-seed-window",
            ],
            2,
        )
        assert result["counts"] == {
            "matched": 2,
            "ambiguous": 1,
            "unmatched": 1,
        }
        assert result["discrepancies_by_reason"] == {
            "multiple_candidates": ["settlement-seed-ambiguous"],
            "no_candidates": ["settlement-seed-unmatched"],
        }

    def test_consumes_match_results_without_reimplementing_matching(
        self, fresh_engine, monkeypatch
    ):
        calls = []

        def fake_match(settlement_id, date_window_days):
            calls.append((settlement_id, date_window_days))
            return {
                "status": "ambiguous",
                "reason": "multiple_candidates",
                "settlement_id": settlement_id,
                "matched_charge_id": None,
                "candidates": [
                    {"charge_id": "charge-canned-a"},
                    {"charge_id": "charge-canned-b"},
                ],
            }

        monkeypatch.setattr(fresh_engine, "match_settlement", fake_match)
        result = fresh_engine.reconcile_batch(
            ["settlement-fold-second", "settlement-fold-first"], 3
        )

        assert calls == [
            ("settlement-fold-second", 3),
            ("settlement-fold-first", 3),
        ]
        assert result["counts"]["ambiguous"] == 2
        assert result["discrepancies_by_reason"]["multiple_candidates"] == [
            "settlement-fold-first",
            "settlement-fold-second",
        ]


class TestStableAuditOrdering:
    def test_reason_groups_and_entries_are_sorted(self, engine):
        result = engine.reconcile_batch(
            [
                "settlement-seed-unmatched",
                "settlement-seed-window",
                "settlement-seed-ref",
                "settlement-seed-ambiguous",
            ],
            2,
        )
        assert list(result["audit_by_reason"]) == [
            "amount_date_window",
            "exact_reference",
            "multiple_candidates",
            "no_candidates",
        ]
        assert result["audit_by_reason"]["multiple_candidates"] == [
            {
                "settlement_id": "settlement-seed-ambiguous",
                "status": "ambiguous",
                "matched_charge_id": None,
                "candidate_charge_ids": [
                    "charge-seed-alpha",
                    "charge-seed-beta",
                ],
            }
        ]


class TestReconciliationDoesNotMutateFixtures:
    def test_batch_preserves_module_collections_and_canonical_records(self, engine):
        charges_before = list(CHARGES)
        settlements_before = list(SETTLEMENTS)
        charge_before = engine.get_charge("charge-seed-alpha")
        settlement_before = engine.get_settlement("settlement-seed-ambiguous")

        engine.reconcile_batch(
            ["settlement-seed-ambiguous", "settlement-seed-ref"], 2
        )

        assert CHARGES == charges_before
        assert SETTLEMENTS == settlements_before
        assert engine.get_charge("charge-seed-alpha") == charge_before
        assert engine.get_settlement("settlement-seed-ambiguous") == settlement_before
