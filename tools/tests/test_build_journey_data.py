import contextlib
import copy
import io
import json
import shutil
import tempfile
import unittest
from pathlib import Path

import sys

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import build_journey_data as builder  # noqa: E402


ROOT = TOOLS.parent


class JourneyGeneratorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        for relative in [
            "index.html",
            "journey/problem_guides.yaml",
            "python/practice_problems/problem_01_geofence_alert_engine.py",
            "python/practice_problems/problem_03_permission_manager.py",
            "python/tests/test_problem_01_geofence_alert_engine.py",
            "python/tests/test_problem_03_permission_manager.py",
            "react/practice_problems/problem_02_incident_dashboard.jsx",
            "react/tests/test_problem_02_incident_dashboard.spec.js",
            "swift/practice_problems/problem_18_inventory_reservation_ledger.swift",
            "swift/Tests/Problem18InventoryReservationLedgerTests/Problem18InventoryReservationLedgerTests.swift",
            "swift/practice_problems/problem_05_medication_titration.swift",
            "swift/Tests/Problem05MedicationTitrationTests/Problem05MedicationTitrationTests.swift",
            "swift/practice_problems/problem_10_dispatch_manager.swift",
            "swift/Tests/Problem10DispatchManagerTests/Problem10DispatchManagerTests.swift",
            "swift/practice_problems/problem_13_contract_lifecycle.swift",
            "swift/practice_problems/problem_15_tic_tac_toe_engine.swift",
            "swift/Tests/Problem13ContractLifecycleTests/Problem13ContractLifecycleTests.swift",
            "swift/Tests/Problem15TicTacToeEngineTests/Problem15TicTacToeEngineTests.swift",
            "swift/practice_problems/problem_02_api_rate_limiter.swift",
            "swift/Tests/Problem02APIRateLimiterTests/Problem02APIRateLimiterTests.swift",
            "swift/practice_problems/problem_11_coverage_tracker.swift",
            "swift/Tests/Problem11CoverageTrackerTests/Problem11CoverageTrackerTests.swift",
            "swift/practice_problems/problem_19_offline_telemetry_batch_processor.swift",
            "swift/Tests/Problem19OfflineTelemetryBatchProcessorTests/Problem19OfflineTelemetryBatchProcessorTests.swift",
            "swift/practice_problems/problem_21_versioned_payload_migration.swift",
            "swift/Tests/Problem21VersionedPayloadMigrationTests/Problem21VersionedPayloadMigrationTests.swift",
        ]:
            destination = self.root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, destination)
        # Source artifacts cover the complete catalogue, not only authored journeys.
        for problem in builder.parse_problems(ROOT / "index.html"):
            for relative in (problem["path"], problem.get("test")):
                if not relative:
                    continue
                destination = self.root / relative
                if not destination.exists():
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(ROOT / relative, destination)
        data = builder.build_data(self.root)
        for path, content in builder.generated_outputs(data, self.root).items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)

    def tearDown(self):
        self.temp.cleanup()

    def guides(self):
        return json.loads((self.root / "journey/problem_guides.yaml").read_text())

    def write_guides(self, guides):
        (self.root / "journey/problem_guides.yaml").write_text(json.dumps(guides))

    def check_error(self):
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            status = builder.main(["--check", "--root", str(self.root)])
        self.assertEqual(status, 1)
        return stderr.getvalue()

    def test_parses_catalogue_parts_examples_and_suite_names(self):
        data = builder.build_data(self.root)
        self.assertEqual(set(data), {"python-01", "python-03", "react-02", "swift-02", "swift-05", "swift-10", "swift-11", "swift-13", "swift-15", "swift-18", "swift-19", "swift-21"})
        self.assertEqual([part["title"] for part in data["python-03"]["parts"]], [
            "Flat role/permission model", "Role inheritance", "Scoped permissions with wildcards"
        ])
        self.assertIn("pm = PermissionManager()", data["python-03"]["example"])
        self.assertIn("TestCreateRole", data["python-03"]["testSuites"])
        self.assertEqual(data["python-03"]["sourceScript"], "journey-sources/python-03.js")
        self.assertEqual(data["react-02"]["testSuites"], ["Problem 02 — Incident Dashboard"])
        self.assertEqual(data["swift-15"]["testSuites"], [
            "Part 1 — Generic board analysis",
            "Part 2 — Mutating moves and value semantics",
            "Part 3 — Configurable dimensions and win runs",
        ])
        self.assertNotIn("public struct Board", data["swift-15"]["example"])

    def test_derives_identity_paths_and_language_commands(self):
        data = builder.build_data(self.root)
        python = data["python-03"]
        react = data["react-02"]
        swift = data["swift-13"]
        self.assertEqual(python["id"], "python-03")
        self.assertEqual(python["commands"]["answerPath"], "python/practice_problem_answers/my_answer_03_permission_manager.py")
        self.assertIn("pytest python/tests/test_problem_03_permission_manager.py -v", python["commands"]["testCommand"])
        self.assertEqual(react["commands"]["copyCommand"], "cp react/practice_problems/problem_02_incident_dashboard.jsx react/my_answer_02_incident_dashboard.jsx")
        self.assertTrue(react["commands"]["testCommand"].endswith("npm run test:02"))
        self.assertEqual(swift["commands"]["answerPath"], "swift/practice_problem_answers/my_answer_13_contract_lifecycle.swift")
        self.assertTrue(swift["commands"]["testCommand"].endswith("swift test"))
        self.assertEqual(data["swift-02"]["commands"]["answerPath"], "swift/practice_problem_answers/my_answer_02_api_rate_limiter.swift")

    def test_rejects_solution_code_block(self):
        guides = self.guides()
        guides["python-03"]["approach"][0]["steps"][0] = "```python\nclass CompleteSolution: pass\n```"
        self.write_guides(guides)
        with self.assertRaisesRegex(builder.JourneyDataError, "code blocks are forbidden"):
            builder.build_data(self.root)

    def test_check_rejects_stale_output(self):
        (self.root / "journey-data.js").write_text("stale\n")
        self.assertIn("stale generated output", self.check_error())

    def test_check_rejects_stale_on_demand_source(self):
        (self.root / "journey-sources/python-03.js").write_text("stale\n")
        self.assertIn("journey-sources/python-03.js differs", self.check_error())

    def test_source_payload_contains_stub_tests_and_part_excerpts(self):
        data = builder.build_data(self.root)
        rendered = builder.render_source("python-03", builder.build_source_records(self.root)["python-03"], self.root)
        self.assertIn('window.PROBLEM_SOURCES["python-03"]', rendered)
        self.assertIn("def create_role", rendered)
        self.assertIn("TestCreateRole", rendered)
        self.assertIn("PART 2", rendered)
        swift = builder.build_source_records(self.root)["swift-15"]
        self.assertIn("public struct Board", builder.render_source("swift-15", swift, self.root))

    def test_check_rejects_missing_part(self):
        guides = self.guides()
        guides["python-03"]["approach"].pop()
        self.write_guides(guides)
        self.assertIn("missing or duplicate part", self.check_error())

    def test_check_rejects_duplicate_key(self):
        original = (self.root / "journey/problem_guides.yaml").read_text().strip()
        body = original[1:-1]
        (self.root / "journey/problem_guides.yaml").write_text("{" + body + "," + body.split(',\n  \"react-02\"', 1)[0] + "}")
        self.assertIn("duplicate key 'python-03'", self.check_error())

    def test_check_rejects_bad_path(self):
        index = (self.root / "index.html").read_text()
        index = index.replace("python/practice_problems/problem_03_permission_manager.py", "python/practice_problems/problem_03_missing.py", 1)
        (self.root / "index.html").write_text(index)
        self.assertIn("bad path", self.check_error())

    def test_check_rejects_absent_usage_example(self):
        path = self.root / "python/practice_problems/problem_03_permission_manager.py"
        source = path.read_text()
        start = source.index("EXAMPLE\n-------")
        end = source.index("=============================================================================", start)
        path.write_text(source[:start] + source[end:])
        self.assertIn("absent usage example", self.check_error())

    def test_check_rejects_schema_violation(self):
        guides = self.guides()
        del guides["python-03"]["approach"][0]["prompt"]
        self.write_guides(guides)
        self.assertIn("fields must be exactly", self.check_error())


if __name__ == "__main__":
    unittest.main()
