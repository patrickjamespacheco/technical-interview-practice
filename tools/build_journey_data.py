#!/usr/bin/env python3
"""Build the file://-safe journey data artifact from repository sources."""

from __future__ import annotations

import argparse
import ast
import json
import re
import sys
from pathlib import Path
from typing import Any


OUTPUT_NAME = "journey-data.js"
GUIDES_PATH = Path("journey/problem_guides.yaml")
LEGACY_EXAMPLE_EXCEPTIONS = {
    "python-01": "pre-existing stub has no usage example",
    "react-02": "pre-existing stub has seed data but no usage example block",
}
LEGACY_PART_COUNT_EXCEPTIONS = {"python-01": 4}
PART_RE = re.compile(r"\bPART\s+(\d+)\s+[—-]\s+(.+?)(?:\s{2,}\([^\n]*\))?\s*$", re.I | re.M)
EXAMPLE_RE = re.compile(
    r"(?:^\s*(?:[#*]\s*)?EXAMPLE\s*$\s*(?:^\s*(?:[#*]\s*)?-{3,}\s*$)?|^\s*#\s*Example\s*$)",
    re.I | re.M,
)


class JourneyDataError(ValueError):
    pass


def _object_no_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise JourneyDataError(f"duplicate key {key!r} in structured data")
        result[key] = value
    return result


def parse_guides(path: Path) -> dict[str, Any]:
    """Parse the JSON-compatible YAML file without a third-party dependency."""
    try:
        return json.loads(path.read_text(), object_pairs_hook=_object_no_duplicates)
    except FileNotFoundError as exc:
        raise JourneyDataError(f"guide file does not exist: {path}") from exc
    except json.JSONDecodeError as exc:
        raise JourneyDataError(f"invalid guide YAML/JSON at {path}:{exc.lineno}:{exc.colno}: {exc.msg}") from exc


def _extract_array(source: str) -> str:
    marker = re.search(r"\bconst\s+PROBLEMS\s*=\s*\[", source)
    if not marker:
        raise JourneyDataError("index.html: could not find `const PROBLEMS = [...]`")
    start = source.index("[", marker.start())
    depth = 0
    quote = None
    escaped = False
    for index in range(start, len(source)):
        char = source[index]
        if quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
        elif char in "\"'":
            quote = char
        elif char == "[":
            depth += 1
        elif char == "]":
            depth -= 1
            if depth == 0:
                return source[start : index + 1]
    raise JourneyDataError("index.html: PROBLEMS array is not closed")


def parse_problems(path: Path) -> list[dict[str, Any]]:
    literal = _extract_array(path.read_text())
    literal = re.sub(r"([{,]\s*)([A-Za-z_$][\w$]*)(\s*:)", r'\1"\2"\3', literal)
    literal = re.sub(r",\s*([}\]])", r"\1", literal)
    try:
        problems = json.loads(literal, object_pairs_hook=_object_no_duplicates)
    except json.JSONDecodeError as exc:
        raise JourneyDataError(f"index.html: PROBLEMS is not a supported literal: {exc.msg}") from exc
    if not isinstance(problems, list):
        raise JourneyDataError("index.html: PROBLEMS must be an array")
    return problems


def problem_identity(problem: dict[str, Any]) -> tuple[str, str, str]:
    path = str(problem.get("path", ""))
    match = re.search(r"problem_(\d+)_([a-z0-9_]+)\.(py|jsx|tsx|swift)$", path)
    if not match:
        raise JourneyDataError(f"bad problem path {path!r}; expected problem_NN_slug.<language extension>")
    number, slug, extension = match.groups()
    language = str(problem.get("language", ""))
    expected = {"python": "py", "react": ("jsx", "tsx"), "swift": "swift"}.get(language)
    if expected is None or extension not in ((expected,) if isinstance(expected, str) else expected):
        raise JourneyDataError(f"bad problem path {path!r}; extension does not match language {language!r}")
    return f"{language}-{number}", number, slug


def _clean_comment_text(value: str) -> str:
    lines = []
    for line in value.splitlines():
        line = re.sub(r"^\s*(?:/\*+|\*|//|#)\s?", "", line)
        line = re.sub(r"\s*\*/\s*$", "", line)
        if not re.fullmatch(r"[-=─\s]+", line):
            lines.append(line.rstrip())
    return "\n".join(lines).strip()


def parse_parts(source: str, expected_count: int, path: Path) -> list[dict[str, Any]]:
    matches = []
    seen = set()
    for match in PART_RE.finditer(source):
        number = int(match.group(1))
        if number not in seen:
            seen.add(number)
            matches.append(match)
    expected = set(range(1, expected_count + 1))
    if seen != expected:
        missing = sorted(expected - seen)
        extra = sorted(seen - expected)
        details = []
        if missing:
            details.append(f"missing Part(s) {', '.join(map(str, missing))}")
        if extra:
            details.append(f"unexpected Part(s) {', '.join(map(str, extra))}")
        raise JourneyDataError(f"{path}: {'; '.join(details)}; use `PART N — Title` headings")
    parts = []
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(source)
        body = _clean_comment_text(source[match.end() : end])
        body = re.split(r"\n\s*(?:PROVIDED|YOUR WORK|={20,})", body, maxsplit=1)[0].strip()
        parts.append({"part": int(match.group(1)), "title": match.group(2).strip(), "contract": body})
    return sorted(parts, key=lambda part: part["part"])


def parse_example(source: str) -> str | None:
    match = EXAMPLE_RE.search(source)
    if not match:
        return None
    tail = source[match.end() :]
    tail = re.split(r"(?:^\s*(?:[#*]\s*)?={20,}\s*$|^\s*(?:[#*]\s*)?PART\s+1\b)", tail, maxsplit=1, flags=re.M | re.I)[0]
    example = _clean_comment_text(tail)
    return example or None


def parse_suites(source: str, language: str) -> list[str]:
    if language == "python":
        return re.findall(r"^class\s+(Test\w+)", source, re.M)
    if language == "react":
        return re.findall(r"test\.describe\(\s*['\"]([^'\"]+)", source)
    if language == "swift":
        return re.findall(r"@Suite\(\s*['\"]([^'\"]+)", source)
    return []


def derive_commands(language: str, number: str, slug: str, stub_path: str, test_path: str) -> dict[str, str]:
    if language == "python":
        answer = f"python/practice_problem_answers/my_answer_{number}_{slug}.py"
        test_command = f"./run_tests.sh -f {answer} -c pytest {test_path} -v"
    elif language == "react":
        answer = f"react/my_answer_{number}_{slug}.jsx"
        test_command = f"./run_tests.sh -f {answer} -c npm run test:{number}"
    elif language == "swift":
        answer = f"swift/practice_problem_answers/my_answer_{number}_{slug}.swift"
        test_command = f"./run_tests.sh -f {answer} -c swift test"
    else:
        raise JourneyDataError(f"unsupported language {language!r}")
    return {
        "answerPath": answer,
        "copyCommand": f"cp {stub_path} {answer}",
        "openCommand": f"code {stub_path}",
        "testCommand": test_command,
    }


def validate_guide(key: str, guide: Any, part_count: int) -> None:
    if not isinstance(guide, dict):
        raise JourneyDataError(f"guide {key}: expected an object")
    allowed = {"approach", "verify"}
    unknown = set(guide) - allowed
    if unknown:
        raise JourneyDataError(f"guide {key}: unknown field(s): {', '.join(sorted(unknown))}")
    if set(guide) != allowed:
        raise JourneyDataError(f"guide {key}: required fields are `approach` and `verify`")
    serialized = json.dumps(guide)
    if re.search(r"```|<pre\b|<code\b", serialized, re.I):
        raise JourneyDataError(f"guide {key}: code blocks are forbidden; guides may contain hints, never solution code")
    if re.search(r"\b(?:full|complete|reference)\s+(?:solution|implementation)\b", serialized, re.I):
        raise JourneyDataError(f"guide {key}: text appears to offer a full/reference solution")
    approach = guide["approach"]
    if not isinstance(approach, list):
        raise JourneyDataError(f"guide {key}.approach: expected a list")
    expected_parts = set(range(1, part_count + 1))
    actual_parts = {item.get("part") for item in approach if isinstance(item, dict)}
    if actual_parts != expected_parts or len(approach) != part_count:
        raise JourneyDataError(f"guide {key}: missing or duplicate part; expected exactly {sorted(expected_parts)}, got {sorted(p for p in actual_parts if isinstance(p, int))}")
    for item in approach:
        part = item.get("part")
        required = {"part", "prompt", "concepts", "steps", "pitfalls"}
        if set(item) != required:
            raise JourneyDataError(f"guide {key} part {part}: fields must be exactly {sorted(required)}")
        if not isinstance(item["prompt"], str) or not item["prompt"].strip():
            raise JourneyDataError(f"guide {key} part {part}: prompt must be a non-empty string")
        if "\n" in item["prompt"] or len(item["prompt"]) > 240:
            raise JourneyDataError(f"guide {key} part {part}: prompt must be one short line (240 characters maximum)")
        for field in ("concepts", "steps", "pitfalls"):
            if not isinstance(item[field], list) or not item[field] or not all(isinstance(value, str) and value.strip() for value in item[field]):
                raise JourneyDataError(f"guide {key} part {part}: {field} must be a non-empty string list")
            if any("\n" in value or len(value) > 240 for value in item[field]):
                raise JourneyDataError(f"guide {key} part {part}: {field} entries must be short single-line hints (240 characters maximum)")
    verify = guide["verify"]
    failures = verify.get("commonFailures") if isinstance(verify, dict) and set(verify) == {"commonFailures"} else None
    if not isinstance(failures, list) or not failures:
        raise JourneyDataError(f"guide {key}.verify.commonFailures: expected a non-empty list")
    for index, failure in enumerate(failures, 1):
        if not isinstance(failure, dict) or set(failure) != {"symptom", "cause", "check"} or not all(isinstance(v, str) and v.strip() for v in failure.values()):
            raise JourneyDataError(f"guide {key}.verify.commonFailures[{index}]: require non-empty symptom/cause/check strings")
        if any("\n" in value or len(value) > 240 for value in failure.values()):
            raise JourneyDataError(f"guide {key}.verify.commonFailures[{index}]: values must be short single lines (240 characters maximum)")


def build_data(root: Path) -> dict[str, Any]:
    problems = parse_problems(root / "index.html")
    guides = parse_guides(root / GUIDES_PATH)
    result: dict[str, Any] = {}
    catalogue: dict[str, dict[str, Any]] = {}
    for problem in problems:
        key, number, slug = problem_identity(problem)
        if key in catalogue:
            raise JourneyDataError(f"duplicate problem identity {key!r} in index.html")
        catalogue[key] = {**problem, "number": number, "slug": slug}
    unknown_guides = set(guides) - set(catalogue)
    if unknown_guides:
        raise JourneyDataError(f"guide key(s) not found in index.html: {', '.join(sorted(unknown_guides))}")
    for key, guide in guides.items():
        problem = catalogue[key]
        stub_path = root / problem["path"]
        test_value = problem.get("test")
        if not stub_path.is_file():
            raise JourneyDataError(f"{key}: bad path; stub does not exist: {problem['path']}")
        if not test_value or not (root / test_value).is_file():
            raise JourneyDataError(f"{key}: bad path; test does not exist: {test_value!r}")
        source = stub_path.read_text()
        expected_parts = LEGACY_PART_COUNT_EXCEPTIONS.get(key, int(problem["parts"]))
        parts = parse_parts(source, expected_parts, stub_path.relative_to(root))
        example = parse_example(source)
        if not example and key not in LEGACY_EXAMPLE_EXCEPTIONS:
            raise JourneyDataError(f"{key}: absent usage example in {problem['path']}; add a canonical `# Example` block")
        validate_guide(key, guide, expected_parts)
        test_source = (root / test_value).read_text()
        result[key] = {
            "id": key,
            "title": problem["title"],
            "description": problem["description"],
            "language": problem["language"],
            "industry": problem["industry"],
            "tags": problem["tags"],
            "level": problem["level"],
            "stubPath": problem["path"],
            "testPath": test_value,
            "example": example,
            "exampleStatus": "canonical" if example else "legacy-missing",
            "parts": parts,
            "testSuites": parse_suites(test_source, problem["language"]),
            "commands": derive_commands(problem["language"], problem["number"], problem["slug"], problem["path"], test_value),
            "guide": guide,
        }
    return result


def render(data: dict[str, Any]) -> str:
    return "// Generated by tools/build_journey_data.py; do not edit.\nwindow.JOURNEY_PROBLEMS = " + json.dumps(data, indent=2, ensure_ascii=False) + ";\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail if journey-data.js is stale or inputs are invalid")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1], help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    root = args.root.resolve()
    try:
        content = render(build_data(root))
        output = root / OUTPUT_NAME
        if args.check:
            if not output.exists():
                raise JourneyDataError(f"stale generated output: {OUTPUT_NAME} is missing; run `python3 tools/build_journey_data.py`")
            if output.read_text() != content:
                raise JourneyDataError(f"stale generated output: {OUTPUT_NAME} differs; run `python3 tools/build_journey_data.py`")
            print(f"OK: {OUTPUT_NAME} is current")
        else:
            output.write_text(content)
            print(f"Wrote {output.relative_to(root)}")
        return 0
    except JourneyDataError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
