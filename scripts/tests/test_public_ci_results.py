"""CI results of this public repository are public: nothing built with the private core may reach them.
Run: python3 -m unittest discover -s scripts/tests -v
"""
import os
from pathlib import Path
import re
import subprocess
import unittest

PROJECT = Path(__file__).resolve().parents[2]
WORKFLOWS = PROJECT / ".github" / "workflows"
FILTER = PROJECT / "scripts" / "hide-core-source.sh"


def steps(workflow):
    """The text of each step, cut at the next step, job or end of file."""
    text = (WORKFLOWS / workflow).read_text()
    return re.findall(r"^ +- (?:uses|name|run):.*?(?=^ +- (?:uses|name|run):|^  [a-z][a-z-]*:|\Z)", text, re.M | re.S)


class PublicCiResultsTest(unittest.TestCase):
    def test_uploads_are_only_for_builds_with_the_public_stub(self):
        # CodeQL builds only with the stub, and its results go to code scanning instead of artifacts.
        for workflow in sorted(path.name for path in WORKFLOWS.glob("*.yml")):
            for step in steps(workflow):
                if "upload-artifact@" in step:
                    self.assertRegex(step, r"if:.*env\.HAS_CORE != 'true'", f"{workflow}: {step}")

    def test_steps_that_compile_core_on_macos_hide_compiler_source(self):
        checked = 0
        for step in steps("ios.yml"):
            if re.search(r"\b(swift test|xcodebuild test|tools/parity/test\.sh)\b", step):
                checked += 1
                self.assertIn("hide-core-source.sh", step)
                # Without pipefail the filter's success would hide a failed build.
                self.assertRegex(step, r"shell: bash\b")
        self.assertEqual(checked, 3)

    def run_filter(self, text, has_core):
        env = {key: value for key, value in os.environ.items() if key != "HAS_CORE"}
        env["HAS_CORE"] = has_core
        return subprocess.run([FILTER], input=text, capture_output=True, text=True, env=env, check=True).stdout

    def test_filter_removes_source_lines_and_keeps_the_message(self):
        message = "core/ios/App/Thing.swift:45:35: warning: 'x' was deprecated\n"
        source = "  44 |     let a = 1\n  45 |     let b = 0.25\n     |     `- warning: 'x' was deprecated\n"
        self.assertEqual(self.run_filter(message + source + "Test passed\n", "true"), message + "Test passed\n")

    def test_filter_leaves_a_stub_build_alone(self):
        text = "  45 |     let b = 0.25\n"
        self.assertEqual(self.run_filter(text, "false"), text)


if __name__ == "__main__":
    unittest.main()
