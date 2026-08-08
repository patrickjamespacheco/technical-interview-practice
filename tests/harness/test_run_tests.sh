#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$ROOT/run_tests.sh"
ACTIVE="$ROOT/swift/Sources/Problem03PermissionManager/Problem.swift"
REFERENCE="$ROOT/swift/practice_problem_answers/reference_answer_03_permission_manager.swift"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/swift-harness.XXXXXX")"
ORIGINAL_SUM="$(shasum -a 256 "$ACTIVE" | awk '{print $1}')"
cleanup_harness() {
    rm -rf "$TEST_TMP"
    rmdir "$ROOT/swift/.answer-run.lock" 2>/dev/null || true
}
trap cleanup_harness EXIT

fail() { echo "not ok - $1" >&2; exit 1; }
pass() { echo "ok - $1"; }
assert_restored() {
    local actual
    actual="$(shasum -a 256 "$ACTIVE" | awk '{print $1}')"
    [[ "$actual" == "$ORIGINAL_SUM" ]] || fail "$1 (active source changed)"
}

# A fake Swift executable makes dispatch-only checks fast and deterministic.
mkdir -p "$TEST_TMP/bin"
cp "$REFERENCE" "$TEST_TMP/answer with spaces_03_permission_manager.swift"
printf '#!/usr/bin/env bash\nexit "${FAKE_SWIFT_STATUS:-0}"\n' > "$TEST_TMP/bin/swift"
chmod +x "$TEST_TMP/bin/swift"

PATH="$TEST_TMP/bin:$PATH" "$RUNNER" \
    -f "$TEST_TMP/answer with spaces_03_permission_manager.swift" -c swift test >/dev/null
assert_restored "mapping and paths containing spaces"
pass "filename maps to the literal target and paths containing spaces work"

PATH="$TEST_TMP/bin:$PATH" "$RUNNER" -f "$ACTIVE" -c swift test >"$TEST_TMP/same.out"
grep -q "already active; no copy" "$TEST_TMP/same.out" || fail "same-file refusal message"
assert_restored "same-file run"
pass "the active source runs without being copied onto itself"

cp "$REFERENCE" "$TEST_TMP/my_answer_99_unknown.swift"
if PATH="$TEST_TMP/bin:$PATH" "$RUNNER" -f "$TEST_TMP/my_answer_99_unknown.swift" -c swift test >"$TEST_TMP/unknown.out" 2>&1; then
    fail "unknown ID was accepted"
fi
grep -q "unknown Swift problem ID" "$TEST_TMP/unknown.out" || fail "unknown ID message"
assert_restored "unknown ID rejection"
pass "unknown IDs fail before mutation"

set +e
FAKE_SWIFT_STATUS=37 PATH="$TEST_TMP/bin:$PATH" "$RUNNER" -f "$REFERENCE" -c swift test >/dev/null
status=$?
set -e
[[ "$status" -eq 37 ]] || fail "command exit status (wanted 37, got $status)"
assert_restored "exit status"
pass "runner returns the command's own exit status"

cp "$REFERENCE" "$TEST_TMP/broken_answer_03_permission_manager.swift"
printf '\nthis is deliberately invalid Swift\n' >> "$TEST_TMP/broken_answer_03_permission_manager.swift"
if "$RUNNER" -f "$TEST_TMP/broken_answer_03_permission_manager.swift" -c swift test --filter Problem03PermissionManagerTests >"$TEST_TMP/compile.out" 2>&1; then
    fail "deliberate compile failure passed"
fi
assert_restored "compile failure"
pass "compile failure restores the active source byte-for-byte"

printf '#!/usr/bin/env bash\ntrap "exit 143" TERM\nsleep 30\n' > "$TEST_TMP/bin/swift"
chmod +x "$TEST_TMP/bin/swift"
PATH="$TEST_TMP/bin:$PATH" "$RUNNER" -f "$REFERENCE" -c swift test >"$TEST_TMP/signal.out" 2>&1 &
runner_pid=$!
for _ in {1..100}; do [[ -d "$ROOT/swift/.answer-run.lock" ]] && break; sleep 0.02; done
kill -TERM "$runner_pid"
set +e
wait "$runner_pid"
set -e
assert_restored "signal cleanup"
[[ ! -d "$ROOT/swift/.answer-run.lock" ]] || fail "signal cleanup left lock"
pass "killing the runner restores the active source byte-for-byte"

mkdir "$ROOT/swift/.answer-run.lock"
if PATH="$TEST_TMP/bin:$PATH" "$RUNNER" -f "$REFERENCE" -c swift test >"$TEST_TMP/lock.out" 2>&1; then
    fail "lock collision was accepted"
fi
grep -q "another Swift answer run is active" "$TEST_TMP/lock.out" || fail "lock collision message"
rmdir "$ROOT/swift/.answer-run.lock"
pass "lock collisions produce a clear refusal"

# Routing checks use harmless commands and prove all four extensions still dispatch.
printf 'x' > "$TEST_TMP/route.py"
"$RUNNER" -f "$TEST_TMP/route.py" -c bash -c '[[ "$PWD" != */react ]]' ignored >/dev/null
for extension in jsx tsx; do
    cp "$ROOT/react/src/App.jsx" "$TEST_TMP/route.$extension"
    "$RUNNER" -f "$TEST_TMP/route.$extension" -c bash -c '[[ "$PWD" == */react ]]' >/dev/null
done
printf '#!/usr/bin/env bash\n[[ "$PWD" == */swift ]]\n' > "$TEST_TMP/bin/swift"
chmod +x "$TEST_TMP/bin/swift"
PATH="$TEST_TMP/bin:$PATH" "$RUNNER" -f "$REFERENCE" -c swift test >/dev/null
pass ".py, .jsx, .tsx, and .swift dispatch to their established working directories"

echo "All harness tests passed."
