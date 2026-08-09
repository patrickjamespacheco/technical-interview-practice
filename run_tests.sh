#!/usr/bin/env bash
# run_tests.sh — run a test command against a specific practice problem answer file.
#
# ── Python problems ───────────────────────────────────────────────────────────
# Usage:
#   ./run_tests.sh -f <path-to-answer.py> -c <pytest-command...>
#
# Examples:
#   ./run_tests.sh \
#     -f python/practice_problem_answers/cw_answer_03_permission_manager.py \
#     -c pytest python/tests/test_problem_03_permission_manager.py -v
#
#   ./run_tests.sh \
#     -f python/practice_problem_answers/cw_answer_03_permission_manager.py \
#     -c pytest python/tests/test_problem_03_permission_manager.py::TestCreateRole
#
# How it works (Python):
#   --answer <abs-path> is appended to the test command, causing conftest.py to
#   inject your answer module in place of the problem stub before test collection.
#
# ── React problems ────────────────────────────────────────────────────────────
# Usage:
#   ./run_tests.sh -f <path-to-answer.jsx> -c <npm-test-command...>
#
# Examples:
#   ./run_tests.sh \
#     -f react/practice_problems/problem_02_incident_dashboard.jsx \
#     -c npm run test:02
#
#   ./run_tests.sh \
#     -f react/practice_problems/problem_02_incident_dashboard.jsx \
#     -c npm run test:ui
#
# How it works (React):
#   The answer file is copied to react/src/App.jsx (which Vite serves), then
#   the Playwright command runs from the react/ directory. Vite is started
#   automatically by Playwright if it isn't already running.
#   react/src/App.jsx is restored to the placeholder after tests finish.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── parse arguments ──────────────────────────────────────────────────────────
ANSWER=""
CMD=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f)
            ANSWER="$2"
            shift 2
            ;;
        -c)
            shift
            CMD=("$@")
            break
            ;;
        *)
            echo "Error: unexpected argument '$1'"
            echo "Usage: $0 -f <answer-file> -c <test-command...>"
            exit 1
            ;;
    esac
done

if [[ -z "$ANSWER" ]]; then
    echo "Error: -f <answer-file> is required."
    echo "Usage: $0 -f <answer-file> -c <test-command...>"
    exit 1
fi

if [[ ${#CMD[@]} -eq 0 ]]; then
    echo "Error: -c <test-command> is required."
    echo "Usage: $0 -f <answer-file> -c <test-command...>"
    exit 1
fi

if [[ ! -f "$ANSWER" ]]; then
    echo "Error: file not found: $ANSWER"
    exit 1
fi

ANSWER_ABS="$(cd "$(dirname "$ANSWER")" && pwd)/$(basename "$ANSWER")"

if [[ "$ANSWER_ABS" == *.swift ]]; then
    SWIFT_ROOT="$REPO_ROOT/swift"
    ANSWER_BASENAME="$(basename "$ANSWER_ABS")"
    SAME_FILE=0
    if [[ "$ANSWER_ABS" -ef "$SWIFT_ROOT/Sources/Problem03PermissionManager/Problem.swift" ]]; then
        PROBLEM_ID="03_permission_manager"
        SAME_FILE=1
    elif [[ "$ANSWER_ABS" -ef "$SWIFT_ROOT/Sources/Problem18InventoryReservationLedger/Problem.swift" ]]; then
        PROBLEM_ID="18_inventory_reservation_ledger"
        SAME_FILE=1
    elif [[ "$ANSWER_ABS" -ef "$SWIFT_ROOT/Sources/Problem05MedicationTitration/Problem.swift" ]]; then
        PROBLEM_ID="05_medication_titration"
        SAME_FILE=1
    elif [[ "$ANSWER_ABS" -ef "$SWIFT_ROOT/Sources/Problem10DispatchManager/Problem.swift" ]]; then
        PROBLEM_ID="10_dispatch_manager"
        SAME_FILE=1
    elif [[ "$ANSWER_ABS" -ef "$SWIFT_ROOT/Sources/Problem13ContractLifecycle/Problem.swift" ]]; then
        PROBLEM_ID="13_contract_lifecycle"
        SAME_FILE=1
    elif [[ "$ANSWER_ABS" -ef "$SWIFT_ROOT/Sources/Problem15TicTacToeEngine/Problem.swift" ]]; then
        PROBLEM_ID="15_tic_tac_toe_engine"
        SAME_FILE=1
    elif [[ "$ANSWER_ABS" -ef "$SWIFT_ROOT/Sources/Problem02APIRateLimiter/Problem.swift" ]]; then
        PROBLEM_ID="02_api_rate_limiter"
        SAME_FILE=1
    elif [[ "$ANSWER_ABS" -ef "$SWIFT_ROOT/Sources/Problem11CoverageTracker/Problem.swift" ]]; then
        PROBLEM_ID="11_coverage_tracker"
        SAME_FILE=1
    elif [[ "$ANSWER_ABS" -ef "$SWIFT_ROOT/Sources/Problem19OfflineTelemetryBatchProcessor/Problem.swift" ]]; then
        PROBLEM_ID="19_offline_telemetry_batch_processor"
        SAME_FILE=1
    elif [[ "$ANSWER_BASENAME" =~ (^|_)([0-9][0-9]_[a-z0-9_]+)\.swift$ ]]; then
        PROBLEM_ID="${BASH_REMATCH[2]}"
    else
        echo "Error: Swift answer filename must end in NN_<name>.swift."
        exit 1
    fi
    case "$PROBLEM_ID" in
        02_api_rate_limiter) ACTIVE_REL="Sources/Problem02APIRateLimiter/Problem.swift" ;;
        03_permission_manager) ACTIVE_REL="Sources/Problem03PermissionManager/Problem.swift" ;;
        18_inventory_reservation_ledger) ACTIVE_REL="Sources/Problem18InventoryReservationLedger/Problem.swift" ;;
        05_medication_titration) ACTIVE_REL="Sources/Problem05MedicationTitration/Problem.swift" ;;
        10_dispatch_manager) ACTIVE_REL="Sources/Problem10DispatchManager/Problem.swift" ;;
        13_contract_lifecycle) ACTIVE_REL="Sources/Problem13ContractLifecycle/Problem.swift" ;;
        15_tic_tac_toe_engine) ACTIVE_REL="Sources/Problem15TicTacToeEngine/Problem.swift" ;;
        11_coverage_tracker) ACTIVE_REL="Sources/Problem11CoverageTracker/Problem.swift" ;;
        19_offline_telemetry_batch_processor) ACTIVE_REL="Sources/Problem19OfflineTelemetryBatchProcessor/Problem.swift" ;;
        *) echo "Error: unknown Swift problem ID '$PROBLEM_ID'; no target mapping exists."; exit 1 ;;
    esac
    if [[ "${CMD[0]}" != "swift" || "${CMD[1]:-}" != "test" ]]; then
        echo "Error: Swift answers require a 'swift test' command."
        exit 1
    fi

    ACTIVE="$SWIFT_ROOT/$ACTIVE_REL"

    LOCK_DIR="$SWIFT_ROOT/.answer-run.lock"
    TMP_DIR="$SWIFT_ROOT/.runner-tmp"
    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
        echo "Error: another Swift answer run is active (lock: swift/.answer-run.lock)."
        exit 1
    fi
    mkdir -p "$TMP_DIR" "$SWIFT_ROOT/.build/answer-runs"
    BACKUP="$(mktemp "$TMP_DIR/problem.XXXXXX")"
    SCRATCH="$SWIFT_ROOT/.build/answer-runs/$$"
    COPIED=0
    COMMAND_PID=""

    cleanup() {
        status=$?
        trap - EXIT INT TERM HUP
        if [[ -n "$COMMAND_PID" ]]; then kill "$COMMAND_PID" 2>/dev/null || true; fi
        if [[ "$COPIED" -eq 1 && -f "$BACKUP" ]]; then cp "$BACKUP" "$ACTIVE"; fi
        rm -f "$BACKUP"
        rmdir "$TMP_DIR" 2>/dev/null || true
        rm -rf "$SCRATCH"
        rmdir "$SWIFT_ROOT/.build/answer-runs" 2>/dev/null || true
        rmdir "$LOCK_DIR" 2>/dev/null || true
        exit "$status"
    }
    trap cleanup EXIT INT TERM HUP

    if [[ "$SAME_FILE" -eq 0 ]]; then
        cp "$ACTIVE" "$BACKUP"
        cp "$ANSWER_ABS" "$ACTIVE"
        COPIED=1
    fi
    SWIFT_CMD=(swift test --scratch-path "$SCRATCH" "${CMD[@]:2}")
    if [[ "$SAME_FILE" -eq 1 ]]; then
        echo "Answer : $ANSWER → $ACTIVE_REL (already active; no copy)"
    else
        echo "Answer : $ANSWER → $ACTIVE_REL"
    fi
    echo "Command: ${SWIFT_CMD[*]}"
    echo ""
    cd "$SWIFT_ROOT"
    "${SWIFT_CMD[@]}" &
    COMMAND_PID=$!
    set +e
    wait "$COMMAND_PID"
    command_status=$?
    set -e
    COMMAND_PID=""
    exit "$command_status"
fi

# ── React mode: .jsx / .tsx answer files ─────────────────────────────────────
if [[ "$ANSWER_ABS" == *.jsx || "$ANSWER_ABS" == *.tsx ]]; then
    REACT_APP="$REPO_ROOT/react/src/App.jsx"
    PLACEHOLDER="$REPO_ROOT/react/src/App.jsx.bak"

    # Back up current App.jsx so we can restore it when done
    cp "$REACT_APP" "$PLACEHOLDER"

    cleanup() {
        cp "$PLACEHOLDER" "$REACT_APP"
        rm -f "$PLACEHOLDER"
    }
    trap cleanup EXIT

    cp "$ANSWER_ABS" "$REACT_APP"

    echo "Answer : $ANSWER → react/src/App.jsx"
    echo "Command: ${CMD[*]}"
    echo ""

    cd "$REPO_ROOT/react"
    "${CMD[@]}"
    exit $?
fi

# ── Python mode: .py answer files ────────────────────────────────────────────

# activate venv if present
if [[ -f "$REPO_ROOT/.venv/bin/activate" ]]; then
    source "$REPO_ROOT/.venv/bin/activate"
fi

echo "Answer : $ANSWER"
echo "Command: ${CMD[*]} --answer $ANSWER_ABS"
echo ""

cd "$REPO_ROOT"
"${CMD[@]}" --answer "$ANSWER_ABS"
