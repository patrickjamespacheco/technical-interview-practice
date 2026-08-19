"""Guards that every Swift problem module is actually wired into the toolchain.

Three lists are hand-maintained and nothing checks that they agree: the targets
in `swift/Package.swift`, the `-ef` same-file chain in `run_tests.sh`, and the
`case "$PROBLEM_ID"` target mapping directly below it. A module missing from the
first does not build; a module missing from either list in `run_tests.sh` makes
`./run_tests.sh -f swift/Sources/ProblemNN.../Problem.swift` fail with "unknown
Swift problem ID" long after the problem was written and reviewed.
"""

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SWIFT_SOURCES = ROOT / "swift" / "Sources"
SWIFT_TESTS = ROOT / "swift" / "Tests"
PACKAGE = ROOT / "swift" / "Package.swift"
RUNNER = ROOT / "run_tests.sh"


def swift_modules() -> list[str]:
    return sorted(path.name for path in SWIFT_SOURCES.glob("Problem*") if path.is_dir())


class SwiftPackageWiringTests(unittest.TestCase):
    def test_every_module_is_a_package_target(self):
        package = PACKAGE.read_text(encoding="utf-8")
        missing = [
            module
            for module in swift_modules()
            if f'.target(name: "{module}")' not in package
            or f'.library(name: "{module}", targets: ["{module}"])' not in package
        ]
        self.assertEqual(
            missing,
            [],
            "These swift/Sources modules have no .library product and .target in "
            "swift/Package.swift, so they are never built: " + ", ".join(missing),
        )

    def test_every_test_directory_is_a_package_test_target(self):
        package = PACKAGE.read_text(encoding="utf-8")
        missing = [
            path.name
            for path in sorted(SWIFT_TESTS.glob("Problem*"))
            if path.is_dir() and f'.testTarget(name: "{path.name}"' not in package
        ]
        self.assertEqual(
            missing,
            [],
            "These swift/Tests directories have no .testTarget in "
            "swift/Package.swift, so they never run: " + ", ".join(missing),
        )


class RunnerWiringTests(unittest.TestCase):
    """Both hand-maintained lists in run_tests.sh must name every module.

    The `-ef` chain maps an already-active source file back to its problem ID;
    the `case` block maps a problem ID forward to the file to substitute.
    Editing only the second is the easy mistake, and it produces a runner that
    refuses the very file it just wrote.
    """

    def test_every_module_appears_in_both_runner_lists(self):
        runner = RUNNER.read_text(encoding="utf-8")
        same_file_chain = set(
            re.findall(r'-ef "\$SWIFT_ROOT/Sources/(Problem\w+)/Problem\.swift"', runner)
        )
        target_mapping = set(
            re.findall(r'ACTIVE_REL="Sources/(Problem\w+)/Problem\.swift"', runner)
        )

        missing = [
            f"{module} (missing from: "
            + ", ".join(
                name
                for name, present in (
                    ("the -ef same-file chain", module in same_file_chain),
                    ("the PROBLEM_ID case mapping", module in target_mapping),
                )
                if not present
            )
            + ")"
            for module in swift_modules()
            if module not in same_file_chain or module not in target_mapping
        ]

        self.assertEqual(
            missing,
            [],
            "run_tests.sh keeps two hand-maintained lists of Swift modules and "
            "both must name every module in swift/Sources: " + "; ".join(missing),
        )

    def test_the_runner_lists_name_no_module_that_does_not_exist(self):
        runner = RUNNER.read_text(encoding="utf-8")
        named = set(
            re.findall(r'-ef "\$SWIFT_ROOT/Sources/(Problem\w+)/Problem\.swift"', runner)
        ) | set(re.findall(r'ACTIVE_REL="Sources/(Problem\w+)/Problem\.swift"', runner))
        stale = sorted(named - set(swift_modules()))
        self.assertEqual(
            stale,
            [],
            "run_tests.sh names Swift modules that no longer exist under "
            "swift/Sources: " + ", ".join(stale),
        )


if __name__ == "__main__":
    unittest.main()
