"""Guards that keep the practice suites' pass/fail signal honest.

These do not test the generator. They test the test suites themselves, because
the failures they catch are silent: the suite still runs, still reports a
number, and the number means nothing.
"""

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PYTHON_TESTS = ROOT / "python" / "tests"
REACT_TESTS = ROOT / "react" / "tests"
PLAYWRIGHT_CONFIG = ROOT / "react" / "playwright.config.js"
SWIFT_TESTS = ROOT / "swift" / "Tests"

# A constant index into a named value, e.g. `results[2]` or `summary[0]`.
LITERAL_SUBSCRIPT = re.compile(r"\b[A-Za-z_]\w*(?:\.\w+)*\[\d+\]")

# Matches a live (uncommented) import of the answers package, in either the
# `from practice_problem_answers...` or `import practice_problem_answers...`
# form, with or without a `python.` prefix.
ANSWER_IMPORT = re.compile(
    r"^\s*(?:from|import)\s+(?:python\.)?practice_problem_answers\b",
    re.MULTILINE,
)


class PythonTestImportTests(unittest.TestCase):
    """Python suites must import the stub, never a checked-in answer.

    `python/conftest.py` injects the `--answer` module under the *stub's*
    module path. A test file that imports an answer path never sees that
    injection, so `--answer` is silently ignored and every run grades the
    checked-in answer instead of the candidate's. This is not hypothetical:
    `test_problem_02_api_rate_limiter.py` did exactly this, and an
    unimplemented stub scored 30 of its 34 tests as passing.
    """

    def test_no_test_file_imports_an_answer_module(self):
        offenders = []
        for path in sorted(PYTHON_TESTS.glob("test_problem_*.py")):
            if ANSWER_IMPORT.search(path.read_text(encoding="utf-8")):
                offenders.append(path.relative_to(ROOT).as_posix())

        self.assertEqual(
            offenders,
            [],
            "These test files import an answer module, which disables the "
            "--answer injection in python/conftest.py and makes their results "
            "meaningless. Import practice_problems.problem_NN_<name> instead "
            "and select an answer with run_tests.sh -f: " + ", ".join(offenders),
        )

    def test_every_problem_test_imports_its_own_stub(self):
        missing = []
        for path in sorted(PYTHON_TESTS.glob("test_problem_*.py")):
            stub_module = "practice_problems." + path.stem[len("test_") :]
            if stub_module not in path.read_text(encoding="utf-8"):
                missing.append(path.relative_to(ROOT).as_posix())

        self.assertEqual(
            missing,
            [],
            "These test files never reference their own problem stub module: "
            + ", ".join(missing),
        )


class ReactDeterminismTests(unittest.TestCase):
    """React suites must control time and chance rather than tolerate them.

    The mock APIs reject 15-20% of the time and inject random records on an
    interval. Retries or inflated timeouts would only make an unreliable
    signal slower, so the specs pin the clock and `Math.random` instead - see
    react/tests/helpers/deterministic.js.
    """

    def test_playwright_config_does_not_enable_retries(self):
        config = PLAYWRIGHT_CONFIG.read_text(encoding="utf-8")
        self.assertNotRegex(
            config,
            r"^\s*retries\s*:",
            "playwright.config.js must not set retries. A test that only "
            "passes on a retry is a test whose red means nothing; make the "
            "spec deterministic instead.",
        )

    def test_every_spec_installs_the_determinism_helper(self):
        specs = sorted(REACT_TESTS.glob("test_problem_*.spec.js"))
        self.assertTrue(specs, "no React specs found")

        missing = []
        for path in specs:
            source = path.read_text(encoding="utf-8")
            if "helpers/deterministic.js" not in source:
                missing.append(path.relative_to(ROOT).as_posix())

        self.assertEqual(
            missing,
            [],
            "These React specs do not use tests/helpers/deterministic.js, so "
            "they are exposed to the mocks' random rejections and background "
            "intervals: " + ", ".join(missing),
        )

    def test_no_spec_relies_on_a_bare_ticking_clock(self):
        """`page.clock.install()` alone does not pause time.

        It installs fake timers that keep advancing with real time, so a
        debounce or interval can still fire between two assertions. Pausing is
        what makes the control real, and `pauseClock` is the only thing that
        does it.
        """
        offenders = []
        for path in sorted(REACT_TESTS.glob("test_problem_*.spec.js")):
            source = path.read_text(encoding="utf-8")
            if "page.clock.install(" in source and "pauseClock" not in source:
                offenders.append(path.relative_to(ROOT).as_posix())

        self.assertEqual(
            offenders,
            [],
            "These React specs call page.clock.install() without pausing the "
            "clock, which leaves fake timers ticking in real time: "
            + ", ".join(offenders),
        )


class SwiftTrapTests(unittest.TestCase):
    """Swift suites must assert a count before indexing into a result.

    Swift Testing runs the whole package in one process. A subscript that
    traps against the empty stub does not fail that test, it kills the run -
    including every other problem's tests - and reports no summary at all.
    `Problem21VersionedPayloadMigrationTests` did exactly this, so an
    unfiltered `swift test` could not complete.
    """

    def test_no_test_indexes_a_result_without_requiring_its_size(self):
        offenders = []
        for path in sorted(SWIFT_TESTS.glob("*/*.swift")):
            source = path.read_text(encoding="utf-8")
            # Helpers and fixtures above the first @Test build their own values;
            # only assertions inside a test can be reached with an empty stub.
            for chunk in source.split("@Test")[1:]:
                subscript = LITERAL_SUBSCRIPT.search(chunk)
                if subscript and "#require(" not in chunk[: subscript.start()]:
                    line = source[: source.index(chunk) + subscript.start()].count("\n") + 1
                    offenders.append(f"{path.relative_to(ROOT).as_posix()}:{line}")

        self.assertEqual(
            offenders,
            [],
            "These assertions index into a value the implementation produced "
            "without first establishing its size, so against the unimplemented "
            "stub they trap and take down the entire test process. Add "
            "`try #require(values.count == N)` before the subscript: "
            + ", ".join(offenders),
        )


if __name__ == "__main__":
    unittest.main()
