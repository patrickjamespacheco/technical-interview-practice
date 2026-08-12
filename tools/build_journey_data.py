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
SOURCE_DIR_NAME = "journey-sources"
LESSON_DIR_NAME = "journey-lessons"
EXECUTION_DIR_NAME = "journey-execution"
GUIDES_PATH = Path("journey/problem_guides.yaml")
LEGACY_EXAMPLE_EXCEPTIONS = {
    "python-01": "pre-existing stub has no usage example",
    "python-02": "pre-existing stub has no usage example",
    "react-01": "pre-existing stub has no usage example block",
    "react-02": "pre-existing stub has seed data but no usage example block",
    "react-03": "pre-existing stub has seed data but no usage example block",
    "react-04": "pre-existing stub has seed data but no usage example block",
    "react-05": "pre-existing stub describes interactions but has no usage example block",
    "swift-03": "pre-existing stub has no usage example block",
}
LEGACY_PART_COUNT_EXCEPTIONS = {"python-01": 4}
LEGACY_PART_TITLES = {
    "python-12": ["Contract and alert-config management", "Alert schedule and due alerts", "Sent alerts and upcoming alerts"],
    "python-13": ["Contract creation, fields, and transitions", "Audit queries and bulk advancement", "Lifecycle metrics and overdue contracts"],
    "python-14": ["Base contract management", "Amendments and effective contracts", "Value history and amendment summary"],
    "python-17": ["Canonical ingestion and lookups", "Settlement matching", "Batch reconciliation"],
}
PART_RE = re.compile(r"\bPART\s+(\d+)\s+[—-]\s+(.+?)(?:\s{2,}\([^\n]*\))?\s*$", re.I | re.M)
# Part markers inside test files. Test suites are ordered by part (an authoring
# rule), so each file states where one part's suites end and the next begins.
PYTHON_TEST_PART_RE = re.compile(r"^[ \t]*#[ \t─=-]*Part[ \t]+(\d+)[ \t]*[—–:-]", re.I | re.M)
PYTHON_TEST_SUITE_RE = re.compile(r"^class[ \t]+(Test\w+)", re.M)
SWIFT_TEST_SUITE_RE = re.compile(
    r"@Suite\(\s*\"(Part\s+(\d+)[^\"]*)\"\s*\)\s*(?:@[\w(). :]+\s*)*(?:public\s+|final\s+|private\s+)*(?:struct|class|actor)\s+(\w+)",
    re.I,
)
REACT_TEST_SUITE_RE = re.compile(r"test\.describe\(\s*['\"](Part\s+(\d+)[^'\"]*)", re.I)
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


# Markers a candidate never leaves in a working answer: they are how each stub
# says "not written yet". Their presence in a shipped payload means the stub was
# pasted in place of a solution.
UNIMPLEMENTED_MARKER_RE = re.compile(
    r"throw\s+[\w.]*notImplemented"
    r"|\.(?:failure|failed)\(\s*\.notImplemented\s*\)"
    r"|raise\s+NotImplementedError"
    r"|NotImplementedError\("
    r"|\bTODO\b",
    re.I,
)
FIX_THE_PAYLOAD = "paste an implementation verified by tools/verify_reference_answers.sh"


def _code_fingerprint(text: str) -> str:
    """Whitespace-insensitive identity, so a reformatted stub is still the stub."""
    return re.sub(r"\s+", " ", text).strip()


def assert_real_implementation(label: str, code: str, stub_source: str) -> None:
    """Reject a shipped code payload that is the unimplemented stub."""
    if _code_fingerprint(code) == _code_fingerprint(stub_source):
        raise JourneyDataError(f"{label}: this is the unimplemented problem stub, not a solution; {FIX_THE_PAYLOAD}")
    marker = UNIMPLEMENTED_MARKER_RE.search(code)
    if marker:
        raise JourneyDataError(f"{label}: still contains the stub's unimplemented marker {marker.group(0)!r}; {FIX_THE_PAYLOAD}")


def validate_execution(key: str, execution: Any, stub_source: str) -> None:
    required = {"timeBudget", "navigation", "solution", "coding", "verification", "code"}
    if not isinstance(execution, dict) or set(execution) != required:
        raise JourneyDataError(f"guide {key}.execution: fields must be exactly {sorted(required)}")
    budget = execution["timeBudget"]
    if not isinstance(budget, dict) or set(budget) != {"navigation", "solution", "coding", "verification"}:
        raise JourneyDataError(f"guide {key}.execution.timeBudget: require all four phases")
    if not all(isinstance(value, int) and value > 0 for value in budget.values()) or sum(budget.values()) != 45:
        raise JourneyDataError(f"guide {key}.execution.timeBudget: positive minute values must total 45")
    phase_fields = {
        "navigation": {"say", "questions", "assumptions", "edgeCases", "restate"},
        "solution": {"pitch", "dataStructures", "types", "composition", "tradeoff", "trap"},
        "coding": {"order", "commentary", "checkIn"},
        "verification": {"walkthroughs", "tests", "complexity", "moreTime"},
    }
    for phase, fields in phase_fields.items():
        value = execution[phase]
        if not isinstance(value, dict) or set(value) != fields:
            raise JourneyDataError(f"guide {key}.execution.{phase}: fields must be exactly {sorted(fields)}")
        for field, content in value.items():
            if isinstance(content, str):
                valid = bool(content.strip())
            else:
                valid = isinstance(content, list) and bool(content) and all(isinstance(item, str) and item.strip() for item in content)
            if not valid:
                raise JourneyDataError(f"guide {key}.execution.{phase}.{field}: expected non-empty text or text list")
    if not isinstance(execution["code"], str) or not execution["code"].strip():
        raise JourneyDataError(f"guide {key}.execution.code: expected a full non-empty implementation")
    assert_real_implementation(f"guide {key}.execution.code", execution["code"], stub_source)


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
        if re.fullmatch(r"\s*\*/\s*", line):
            continue
        line = re.sub(r"^\s*(?:/\*+|\*|//|#)\s?", "", line)
        line = re.sub(r"\s*\*/\s*$", "", line)
        if not re.fullmatch(r"[-=─\s]+", line):
            lines.append(line.rstrip())
    return "\n".join(lines).strip()


def _legacy_part_positions(source: str, titles: list[str]) -> list[tuple[int, int, int, str]]:
    positions = []
    for number, title in enumerate(titles, 1):
        match = re.search(rf"^\s*#\s*─+\s*Part\s+{number}\s*─+.*$", source, re.I | re.M)
        if not match:
            return []
        positions.append((number, match.start(), match.end(), title))
    return positions


def parse_parts(source: str, expected_count: int, path: Path, legacy_titles: list[str] | None = None) -> list[dict[str, Any]]:
    matches = []
    seen = set()
    for match in PART_RE.finditer(source):
        number = int(match.group(1))
        if number not in seen:
            seen.add(number)
            matches.append(match)
    expected = set(range(1, expected_count + 1))
    if seen != expected and legacy_titles:
        positions = _legacy_part_positions(source, legacy_titles)
        if len(positions) == expected_count:
            parts = []
            for index, (number, _start, heading_end, title) in enumerate(positions):
                end = positions[index + 1][1] if index + 1 < len(positions) else len(source)
                parts.append({"part": number, "title": title, "contract": _clean_comment_text(source[heading_end:end])})
            return parts
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


def source_part_ranges(source: str, expected_count: int, legacy_titles: list[str] | None = None) -> list[dict[str, Any]]:
    """Return honest source excerpts bounded by canonical part headings.

    Some React and Swift stubs put requirements in one leading comment and the
    implementation surface later in the file. In those cases the excerpt is
    intentionally just that part's requirement text; the complete stub remains
    available alongside it.
    """
    matches = []
    seen = set()
    for match in PART_RE.finditer(source):
        number = int(match.group(1))
        if number not in seen and 1 <= number <= expected_count:
            seen.add(number)
            matches.append(match)
    if len(seen) != expected_count and legacy_titles:
        positions = _legacy_part_positions(source, legacy_titles)
        return [
            {"part": number, "source": source[start:(positions[index + 1][1] if index + 1 < len(positions) else len(source))].rstrip() + "\n"}
            for index, (number, start, _end, _title) in enumerate(positions)
        ]
    excerpts = []
    for index, match in enumerate(matches):
        start = source.rfind("\n", 0, match.start()) + 1
        end = matches[index + 1].start() if index + 1 < len(matches) else len(source)
        # Stop requirement-only comment excerpts before provided implementation.
        boundary = re.search(r"^\s*(?:[/#* ]*)?(?:PROVIDED|YOUR WORK|={20,})", source[match.end():end], re.M)
        if boundary:
            end = match.end() + boundary.start()
        excerpts.append({"part": int(match.group(1)), "source": source[start:end].rstrip() + "\n"})
    return sorted(excerpts, key=lambda item: item["part"])


def implementation_surface(source: str, language: str) -> str | None:
    """Extract the shared code surface when all part contracts lead the file."""
    matches = list(PART_RE.finditer(source))
    if not matches or language == "python":
        return None
    tail_start = matches[-1].end()
    if language == "react":
        close = source.find("*/", tail_start)
        return source[close + 2:].lstrip("\n") if close >= 0 else None
    lines = source[tail_start:].splitlines(keepends=True)
    offset = tail_start
    for line in lines:
        stripped = line.strip()
        if stripped and not stripped.startswith("//") and not stripped.startswith("/*") and not stripped.startswith("*"):
            return source[offset:].lstrip("\n")
        offset += len(line)
    return None


def parse_example(source: str) -> str | None:
    match = EXAMPLE_RE.search(source)
    if not match:
        return None
    tail = source[match.end() :]
    tail = re.split(r"(?:^\s*(?:(?://|[#*])\s*)?={20,}\s*$|^\s*(?:(?://|[#*])\s*)?PART\s+1\b)", tail, maxsplit=1, flags=re.M | re.I)[0]
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


def parse_part_suites(source: str, language: str, part_count: int) -> list[list[dict[str, str]]]:
    """Group a test file's suites under the part each one covers.

    Returns one list per part, each entry carrying the suite's display `name`
    and the `selector` a runner filters on. Returns an empty list when the file
    does not mark every part, so the journey keeps its honest full-suite note
    instead of inventing a command that scopes to nothing.
    """
    buckets: dict[int, list[dict[str, str]]] = {}
    if language == "python":
        markers = [(match.start(), int(match.group(1)), None) for match in PYTHON_TEST_PART_RE.finditer(source)]
        classes = [(match.start(), None, match.group(1)) for match in PYTHON_TEST_SUITE_RE.finditer(source)]
        current = None
        for _position, part, suite in sorted(markers + classes):
            if part is not None:
                current = part
            elif current is not None:
                buckets.setdefault(current, []).append({"name": suite, "selector": suite})
    elif language == "swift":
        for match in SWIFT_TEST_SUITE_RE.finditer(source):
            buckets.setdefault(int(match.group(2)), []).append({"name": match.group(1), "selector": match.group(3)})
    elif language == "react":
        for match in REACT_TEST_SUITE_RE.finditer(source):
            part = int(match.group(2))
            buckets.setdefault(part, []).append({"name": match.group(1).strip(), "selector": f"Part {part}"})
    if set(buckets) != set(range(1, part_count + 1)):
        return []
    return [buckets[part] for part in range(1, part_count + 1)]


def swift_test_module(test_path: str) -> str:
    """The Swift Testing module a problem's suites live in, taken from its path."""
    parts = Path(test_path).parts
    if len(parts) < 3 or parts[0] != "swift" or parts[1] != "Tests":
        raise JourneyDataError(f"bad Swift test path {test_path!r}; expected swift/Tests/<Module>/<file>.swift")
    return parts[2]


def derive_commands(
    language: str,
    number: str,
    slug: str,
    stub_path: str,
    test_path: str,
    part_suites: list[list[dict[str, str]]] | None = None,
) -> dict[str, Any]:
    part_suites = part_suites or []
    if language == "python":
        answer = f"python/practice_problem_answers/my_answer_{number}_{slug}.py"
        test_command = f"./run_tests.sh -f {answer} -c pytest {test_path} -v"
        part_commands = [
            "./run_tests.sh -f {answer} -c pytest {selection} -v".format(
                answer=answer, selection=" ".join(f"{test_path}::{suite['selector']}" for suite in suites)
            )
            for suites in part_suites
        ]
    elif language == "react":
        answer = f"react/my_answer_{number}_{slug}.jsx"
        test_command = f"./run_tests.sh -f {answer} -c npm run test:{number}"
        part_commands = [
            '{base} -- -g "{pattern}"'.format(
                base=test_command, pattern="|".join(dict.fromkeys(suite["selector"] for suite in suites))
            )
            for suites in part_suites
        ]
    elif language == "swift":
        answer = f"swift/practice_problem_answers/my_answer_{number}_{slug}.swift"
        module = swift_test_module(test_path)
        test_command = f"./run_tests.sh -f {answer} -c swift test --filter {module}"
        part_commands = [
            "./run_tests.sh -f {answer} -c swift test {filters}".format(
                answer=answer, filters=" ".join(f"--filter {module}.{suite['selector']}" for suite in suites)
            )
            for suites in part_suites
        ]
    else:
        raise JourneyDataError(f"unsupported language {language!r}")
    return {
        "answerPath": answer,
        "copyCommand": f"cp {stub_path} {answer}",
        "openCommand": f"code {stub_path}",
        "testCommand": test_command,
        "partTestCommands": part_commands,
    }


def validate_guide(key: str, guide: Any, part_count: int, stub_source: str) -> None:
    if not isinstance(guide, dict):
        raise JourneyDataError(f"guide {key}: expected an object")
    allowed = {"approach", "verify", "lesson", "execution"}
    unknown = set(guide) - allowed
    if unknown:
        raise JourneyDataError(f"guide {key}: unknown field(s): {', '.join(sorted(unknown))}")
    if not {"approach", "verify"}.issubset(guide):
        raise JourneyDataError(f"guide {key}: required fields are `approach` and `verify`")
    # Practice-integrity checks deliberately inspect stages 1–4 only. A lesson
    # is the one place where a complete worked solution is expected.
    serialized = json.dumps({"approach": guide["approach"], "verify": guide["verify"]})
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
    lesson = guide.get("lesson")
    if lesson is None:
        if "execution" in guide:
            validate_execution(key, guide["execution"], stub_source)
        return
    if not isinstance(lesson, dict) or set(lesson) != {"parts", "reflection"}:
        raise JourneyDataError(f"guide {key}.lesson: fields must be exactly `parts` and `reflection`")
    if not isinstance(lesson["reflection"], str) or not lesson["reflection"].strip():
        raise JourneyDataError(f"guide {key}.lesson.reflection: expected a non-empty string")
    lesson_parts = lesson["parts"]
    if not isinstance(lesson_parts, list):
        raise JourneyDataError(f"guide {key}.lesson.parts: expected a list")
    actual_lesson_parts = {item.get("part") for item in lesson_parts if isinstance(item, dict)}
    if actual_lesson_parts != expected_parts or len(lesson_parts) != part_count:
        raise JourneyDataError(f"guide {key}.lesson: missing or duplicate part; expected exactly {sorted(expected_parts)}")
    for item in lesson_parts:
        part = item.get("part")
        if set(item) != {"part", "steps"} or not isinstance(item["steps"], list) or not item["steps"]:
            raise JourneyDataError(f"guide {key}.lesson part {part}: require `part` and a non-empty `steps` list")
        for index, step in enumerate(item["steps"], 1):
            if not isinstance(step, dict) or not {"explanation", "code"}.issubset(step) or set(step) - {"explanation", "code", "rejected"}:
                raise JourneyDataError(f"guide {key}.lesson part {part} step {index}: require explanation/code and optional rejected")
            for field in step:
                if not isinstance(step[field], str) or not step[field].strip():
                    raise JourneyDataError(f"guide {key}.lesson part {part} step {index}.{field}: expected a non-empty string")
            assert_real_implementation(f"guide {key}.lesson part {part} step {index}.code", step["code"], stub_source)
    if "execution" in guide:
        validate_execution(key, guide["execution"], stub_source)


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
        if problem["language"] == "swift" and "execution" not in guide:
            raise JourneyDataError(f"guide {key}: every catalogue Swift problem requires an interview execution sheet")
        stub_path = root / problem["path"]
        test_value = problem.get("test")
        if not stub_path.is_file():
            raise JourneyDataError(f"{key}: bad path; stub does not exist: {problem['path']}")
        if not test_value or not (root / test_value).is_file():
            raise JourneyDataError(f"{key}: bad path; test does not exist: {test_value!r}")
        source = stub_path.read_text()
        expected_parts = LEGACY_PART_COUNT_EXCEPTIONS.get(key, int(problem["parts"]))
        legacy_titles = LEGACY_PART_TITLES.get(key)
        parts = parse_parts(source, expected_parts, stub_path.relative_to(root), legacy_titles)
        example = parse_example(source)
        if not example and key not in LEGACY_EXAMPLE_EXCEPTIONS:
            raise JourneyDataError(f"{key}: absent usage example in {problem['path']}; add a canonical `# Example` block")
        validate_guide(key, guide, expected_parts, source)
        test_source = (root / test_value).read_text()
        part_suites = parse_part_suites(test_source, problem["language"], expected_parts)
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
            "sourceScript": f"{SOURCE_DIR_NAME}/{key}.js",
            "lessonAvailable": "lesson" in guide,
            "lessonScript": f"{LESSON_DIR_NAME}/{key}.js" if "lesson" in guide else None,
            "example": example,
            "exampleStatus": "canonical" if example else "legacy-missing",
            "parts": parts,
            "testSuites": parse_suites(test_source, problem["language"]),
            "partSuites": [[suite["name"] for suite in suites] for suites in part_suites],
            "commands": derive_commands(
                problem["language"], problem["number"], problem["slug"], problem["path"], test_value, part_suites
            ),
            "guide": {"approach": guide["approach"], "verify": guide["verify"]},
        }
    return result


def render(data: dict[str, Any]) -> str:
    return "// Generated by tools/build_journey_data.py; do not edit.\nwindow.JOURNEY_PROBLEMS = " + json.dumps(data, indent=2, ensure_ascii=False) + ";\n"


def render_source(key: str, problem: dict[str, Any], root: Path) -> str:
    payload = {
        "id": key,
        "language": problem["language"],
        "stub": {"path": problem["stubPath"], "source": (root / problem["stubPath"]).read_text()},
        "test": {"path": problem["testPath"], "source": (root / problem["testPath"]).read_text()} if problem.get("testPath") else None,
        "parts": source_part_ranges(
            (root / problem["stubPath"]).read_text(),
            int(problem["expectedParts"]),
            LEGACY_PART_TITLES.get(key),
        ),
        "implementationSurface": implementation_surface((root / problem["stubPath"]).read_text(), problem["language"]),
    }
    return "// Generated by tools/build_journey_data.py; do not edit.\nwindow.PROBLEM_SOURCES = window.PROBLEM_SOURCES || {};\nwindow.PROBLEM_SOURCES[" + json.dumps(key) + "] = " + json.dumps(payload, ensure_ascii=False) + ";\n"


def render_lesson(key: str, lesson: dict[str, Any]) -> str:
    return "// Generated by tools/build_journey_data.py; do not edit.\nwindow.PROBLEM_LESSONS = window.PROBLEM_LESSONS || {};\nwindow.PROBLEM_LESSONS[" + json.dumps(key) + "] = " + json.dumps(lesson, ensure_ascii=False) + ";\n"


def render_execution(key: str, execution: dict[str, Any]) -> str:
    return "// Generated by tools/build_journey_data.py; do not edit.\nwindow.INTERVIEW_EXECUTION = window.INTERVIEW_EXECUTION || {};\nwindow.INTERVIEW_EXECUTION[" + json.dumps(key) + "] = " + json.dumps(execution, ensure_ascii=False) + ";\n"


def build_source_records(root: Path) -> dict[str, dict[str, Any]]:
    records = {}
    for catalogue_problem in parse_problems(root / "index.html"):
        key, _, _ = problem_identity(catalogue_problem)
        stub_path = root / catalogue_problem["path"]
        test_value = catalogue_problem.get("test")
        if not stub_path.is_file():
            raise JourneyDataError(f"{key}: bad path; stub does not exist: {catalogue_problem['path']}")
        if test_value and not (root / test_value).is_file():
            raise JourneyDataError(f"{key}: bad path; test does not exist: {test_value!r}")
        records[key] = {
            "language": catalogue_problem["language"],
            "stubPath": catalogue_problem["path"],
            "testPath": test_value,
            "expectedParts": LEGACY_PART_COUNT_EXCEPTIONS.get(key, int(catalogue_problem["parts"])),
        }
    return records


def generated_outputs(data: dict[str, Any], root: Path) -> dict[Path, str]:
    outputs = {root / OUTPUT_NAME: render(data)}
    for key, problem in build_source_records(root).items():
        outputs[root / SOURCE_DIR_NAME / f"{key}.js"] = render_source(key, problem, root)
    guides = parse_guides(root / GUIDES_PATH)
    for key, guide in guides.items():
        if "lesson" in guide:
            outputs[root / LESSON_DIR_NAME / f"{key}.js"] = render_lesson(key, guide["lesson"])
        if "execution" in guide:
            outputs[root / EXECUTION_DIR_NAME / f"{key}.js"] = render_execution(key, guide["execution"])
    return outputs


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail if journey-data.js is stale or inputs are invalid")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1], help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    root = args.root.resolve()
    try:
        data = build_data(root)
        outputs = generated_outputs(data, root)
        if args.check:
            for output, content in outputs.items():
                name = output.relative_to(root)
                if not output.exists():
                    raise JourneyDataError(f"stale generated output: {name} is missing; run `python3 tools/build_journey_data.py`")
                if output.read_text() != content:
                    raise JourneyDataError(f"stale generated output: {name} differs; run `python3 tools/build_journey_data.py`")
            for directory in (SOURCE_DIR_NAME, LESSON_DIR_NAME, EXECUTION_DIR_NAME):
                expected = {path.resolve() for path in outputs if path.parent.name == directory}
                actual = {path.resolve() for path in (root / directory).glob("*.js")} if (root / directory).exists() else set()
                if actual != expected:
                    raise JourneyDataError(f"stale generated output: {directory} contains unexpected files; run `python3 tools/build_journey_data.py`")
            lesson_count = sum(path.parent.name == LESSON_DIR_NAME for path in outputs)
            execution_count = sum(path.parent.name == EXECUTION_DIR_NAME for path in outputs)
            print(f"OK: {OUTPUT_NAME}, {len(outputs) - lesson_count - execution_count - 1} source files, {lesson_count} lesson files, and {execution_count} execution sheets are current")
        else:
            for directory in (SOURCE_DIR_NAME, LESSON_DIR_NAME, EXECUTION_DIR_NAME):
                output_dir = root / directory
                output_dir.mkdir(exist_ok=True)
                expected_names = {path.name for path in outputs if path.parent.name == directory}
                for stale in output_dir.glob("*.js"):
                    if stale.name not in expected_names:
                        stale.unlink()
            for output, content in outputs.items():
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_text(content)
            lesson_count = sum(path.parent.name == LESSON_DIR_NAME for path in outputs)
            execution_count = sum(path.parent.name == EXECUTION_DIR_NAME for path in outputs)
            print(f"Wrote {OUTPUT_NAME}, {len(outputs) - lesson_count - execution_count - 1} source files, {lesson_count} lesson files, and {execution_count} execution sheets")
        return 0
    except JourneyDataError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
