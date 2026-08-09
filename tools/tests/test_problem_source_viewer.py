import json
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
VIEWER = ROOT / "problem-source-viewer.js"


def tokenize(source: str, language: str) -> str:
    script = (
        "require(" + json.dumps(str(VIEWER)) + ");"
        "process.stdout.write(ProblemSourceViewer.tokenize("
        + json.dumps(source) + "," + json.dumps(language) + "));"
    )
    return subprocess.run(["node", "-e", script], check=True, capture_output=True, text=True).stdout


class ProblemSourceViewerTests(unittest.TestCase):
    def test_python_tokens_and_escapes_markup(self):
        html = tokenize('def parse(value: str = "<safe>"):\n    # note\n    return 42\n', "python")
        self.assertIn('tok-keyword">def', html)
        self.assertIn('tok-keyword">return', html)
        self.assertIn("&lt;safe&gt;", html)
        self.assertIn('tok-comment"># note', html)

    def test_jsx_tokens_without_treating_tags_as_markup(self):
        html = tokenize('const View = () => <button title="go">Save</button> // action', "react")
        self.assertIn('tok-keyword">const', html)
        self.assertIn("&lt;button", html)
        self.assertNotIn("<button", html)
        self.assertIn('tok-comment">// action', html)

    def test_swift_tokens(self):
        html = tokenize('public struct Ledger { let count: Int = 3 }', "swift")
        self.assertIn('tok-keyword">public', html)
        self.assertIn('tok-keyword">struct', html)
        self.assertIn('tok-type">Ledger', html)
        self.assertIn('tok-number">3', html)

    def test_unclosed_constructs_degrade_to_plain_escaped_text(self):
        html = tokenize('let awkward = "<not closed\n/* also not closed', "react")
        self.assertIn('&quot;' if False else '"&lt;not closed', html)
        self.assertNotIn('tok-string', html)
        self.assertNotIn('tok-comment', html)
        self.assertNotIn("<not closed", html)


if __name__ == "__main__":
    unittest.main()
