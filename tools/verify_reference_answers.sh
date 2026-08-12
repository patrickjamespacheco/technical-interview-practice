#!/usr/bin/env bash
# verify_reference_answers.sh - prove that every Swift interview execution sheet
# ships an implementation that actually passes its own test suite.
#
# For each Swift catalogue problem this script:
#   1. extracts `execution.code` from journey/problem_guides.yaml,
#   2. checks it is byte-identical to the checked-in reference answer, and
#   3. builds every extracted sheet into the package and runs the whole suite.
#
# Usage:
#   ./tools/verify_reference_answers.sh
#
# Exit status is 0 only when every sheet compiles and every test passes.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_ROOT="$ROOT/swift"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/reference-answers.XXXXXX")"
BACKUP_DIR="$WORK_DIR/backup"
RESTORED=0

mkdir -p "$BACKUP_DIR"

restore() {
    if [[ "$RESTORED" -eq 0 ]]; then
        RESTORED=1
        for backup in "$BACKUP_DIR"/*.swift; do
            [[ -e "$backup" ]] || continue
            module="$(basename "$backup" .swift)"
            cp "$backup" "$SWIFT_ROOT/Sources/$module/Problem.swift"
        done
    fi
    rm -rf "$WORK_DIR"
}
trap restore EXIT INT TERM HUP

# ── extract each sheet and compare it with the checked-in reference answer ────
python3 - "$ROOT" "$WORK_DIR" <<'PYTHON'
import json
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
work = pathlib.Path(sys.argv[2])
guides = json.loads((root / "journey" / "problem_guides.yaml").read_text())
problems = re.search(r"const\s+PROBLEMS\s*=\s*\[(.*?)\n\s*\];", (root / "index.html").read_text(), re.S)
if problems is None:
    sys.exit("error: could not read the PROBLEMS catalogue from index.html")
paths = dict(re.findall(r'path:\s*"(swift/practice_problems/problem_(\d+)_[a-z0-9_]+\.swift)"', problems.group(1)))

failures = []
manifest = []
for stub_path, number in sorted((path, number) for path, number in paths.items()):
    key = f"swift-{number}"
    slug = pathlib.Path(stub_path).stem
    execution = guides.get(key, {}).get("execution")
    if not execution or not execution.get("code", "").strip():
        failures.append(f"{key}: no execution.code in journey/problem_guides.yaml")
        continue
    code = execution["code"]
    reference = root / "swift" / "practice_problem_answers" / f"reference_answer_{slug.removeprefix('problem_')}.swift"
    if not reference.is_file():
        failures.append(f"{key}: missing reference answer {reference.relative_to(root)}")
        continue
    if reference.read_text().rstrip("\n") != code.rstrip("\n"):
        failures.append(f"{key}: execution.code differs from {reference.relative_to(root)}")
        continue
    target = work / f"{key}.swift"
    target.write_text(code if code.endswith("\n") else code + "\n")
    module_dirs = sorted((root / "swift" / "Sources").glob(f"Problem{number}*"))
    if len(module_dirs) != 1:
        failures.append(f"{key}: expected exactly one Sources/Problem{number}* module")
        continue
    manifest.append(f"{key}\t{module_dirs[0].name}\t{target}")

if failures:
    print("\n".join(f"error: {failure}" for failure in failures), file=sys.stderr)
    sys.exit(1)
(work / "manifest.tsv").write_text("\n".join(manifest) + "\n")
print(f"Extracted {len(manifest)} execution sheets; each matches its checked-in reference answer.")
PYTHON

# ── substitute every sheet into the package and run the whole suite once ──────
while IFS=$'\t' read -r key module source; do
    [[ -n "$key" ]] || continue
    cp "$SWIFT_ROOT/Sources/$module/Problem.swift" "$BACKUP_DIR/$module.swift"
    cp "$source" "$SWIFT_ROOT/Sources/$module/Problem.swift"
    echo "  $key -> Sources/$module/Problem.swift"
done < "$WORK_DIR/manifest.tsv"

echo ""
echo "Running the full Swift test suite against the execution sheets..."
cd "$SWIFT_ROOT"
set +e
swift test --scratch-path "$WORK_DIR/build" 2>&1 | tee "$WORK_DIR/test.log"
status="${PIPESTATUS[0]}"
set -e
cd "$ROOT"

restore

if [[ "$status" -ne 0 ]]; then
    echo ""
    echo "FAILED: at least one execution sheet does not pass its own suite." >&2
    exit "$status"
fi

echo ""
echo "OK: every Swift execution sheet compiles and passes its own test suite."
