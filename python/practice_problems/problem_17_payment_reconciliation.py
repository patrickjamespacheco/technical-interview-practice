"""
=============================================================================
INTERVIEW PROBLEM 17: Payment Reconciliation Engine
Difficulty: Senior Software Engineer | Estimated time: 45 min
=============================================================================

CONTEXT
-------
You are building a reconciliation engine for a payment platform. Internal
charges must be compared with settlement records received from a processor.
References are the strongest signal, but some settlements arrive without one
and must be matched using amount and date proximity. More than one plausible
charge is a real ambiguity and must never be silently resolved.

For this problem you are building a PaymentReconciliationEngine class.
Store all state in instance variables initialized in `__init__`.
Class-level variables will bleed between tests and between engine instances —
avoid them. You choose the internal data structures; the public interface is
what matters.

MONEY AND DATES
---------------
All monetary values are `decimal.Decimal` objects. Never accept or convert a
`float`: binary floating-point cannot represent many base-10 currency values
exactly (for example, 0.1 + 0.2 is not exactly 0.3), which can create false
matches or discrepancies. Raise TypeError when an amount is not a Decimal.

Dates are ISO-8601 date strings such as "2026-04-10". Use
`date.fromisoformat()` for date-window arithmetic. IDs are readable strings.

DATA MODEL
----------
Charge:
  {
    "charge_id": str,
    "amount": Decimal,
    "charge_date": str,
  }

Settlement:
  {
    "settlement_id": str,
    "amount": Decimal,
    "settlement_date": str,
    "reference": str | None,  # when present, an internal charge_id
  }

MatchResult:
  {
    "status": "matched" | "ambiguous" | "unmatched",
    "reason": "exact_reference" | "amount_date_window" |
              "multiple_candidates" | "no_candidates",
    "settlement_id": str,
    "matched_charge_id": str | None,
    "candidates": list[Charge],
  }

# Example
# engine = PaymentReconciliationEngine()
# engine.ingest_charge("charge-alpha", Decimal("25.00"), "2026-04-10")
# engine.ingest_charge("charge-beta", Decimal("25.00"), "2026-04-11")
# engine.ingest_settlement("settlement-open", Decimal("25.00"), "2026-04-11")
# engine.match_settlement("settlement-open", date_window_days=2)["status"]
# # -> "ambiguous" (both $25 charges are candidates)
# engine.ingest_settlement(
#     "settlement-ref", Decimal("25.00"), "2026-04-11", "charge-alpha"
# )
# engine.match_settlement("settlement-ref", 2)["matched_charge_id"]
# # -> "charge-alpha"
# engine.ingest_settlement("settlement-24", Decimal("24.00"), "2026-04-11")
# engine.match_settlement("settlement-24", 2)["status"]  # -> "unmatched"

=============================================================================
PART 1 — Canonical ingestion and lookups
=============================================================================
"""

from decimal import Decimal
from typing import Optional


class PaymentReconciliationEngine:
    """Ingests canonical payment records and reconciles processor batches."""

    def __init__(self):
        raise NotImplementedError

    # ── Part 1 ────────────────────────────────────────────────────────────────

    def ingest_charge(
        self, charge_id: str, amount: Decimal, charge_date: str
    ) -> dict:
        """
        Store and return a charge.

        Re-ingesting an identical record is idempotent and returns the
        canonical stored charge. Raise ValueError if charge_id already exists
        with different data. Raise TypeError if amount is not a Decimal.
        """
        raise NotImplementedError

    def ingest_settlement(
        self,
        settlement_id: str,
        amount: Decimal,
        settlement_date: str,
        reference: Optional[str] = None,
    ) -> dict:
        """
        Store and return a processor settlement.

        Re-ingesting an identical record is idempotent and returns the
        canonical stored settlement. Raise ValueError if settlement_id already
        exists with different data. Raise TypeError if amount is not Decimal.
        A reference, when provided, is an internal charge_id.
        """
        raise NotImplementedError

    def get_charge(self, charge_id: str) -> Optional[dict]:
        """Return a copy of the charge, or None when charge_id is unknown."""
        raise NotImplementedError

    def get_settlement(self, settlement_id: str) -> Optional[dict]:
        """Return a copy of the settlement, or None when its ID is unknown."""
        raise NotImplementedError

    # ── Part 2 ────────────────────────────────────────────────────────────────

    def match_settlement(
        self, settlement_id: str, date_window_days: int
    ) -> dict:
        """
        Return a rich MatchResult for one canonical settlement.

        Matching precedence:
        1. If `reference` names an existing charge, return a matched result
           with reason "exact_reference". Reference matching takes precedence
           over amount and date checks.
        2. Otherwise find charges with the exact Decimal amount whose
           charge_date is within `date_window_days` (inclusive, in either
           direction) of settlement_date.
        3. One candidate is matched with reason "amount_date_window"; more
           than one is ambiguous with reason "multiple_candidates"; none is
           unmatched with reason "no_candidates".

        `candidates` contains copies of all plausible charges, sorted by
        charge_id. A matched result has exactly one candidate and sets
        matched_charge_id. Ambiguous and unmatched results set it to None.

        Raise KeyError for an unknown settlement_id and ValueError when
        date_window_days is negative.
        """
        raise NotImplementedError

    # ── Part 3 ────────────────────────────────────────────────────────────────

    def reconcile_batch(
        self, settlement_ids: list[str], date_window_days: int
    ) -> dict:
        """
        Reconcile a batch by calling `match_settlement` exactly once for each
        supplied settlement ID and folding those MatchResults into:

          {
            "counts": {"matched": int, "ambiguous": int, "unmatched": int},
            "discrepancies_by_reason": {
                reason: [settlement_id, ...],
            },
            "audit_by_reason": {
                reason: [
                    {
                      "settlement_id": str,
                      "status": str,
                      "matched_charge_id": str | None,
                      "candidate_charge_ids": list[str],
                    }, ...
                ],
            },
          }

        Only ambiguous and unmatched outcomes are discrepancies. All outcomes
        appear in the audit. Reason keys and entries within every group are
        sorted lexicographically, making output stable regardless of input
        order. Do not re-run matching logic or mutate ingested records.
        """
        raise NotImplementedError
