"""ensure_core (AquaRestore's source check, in release-settings.sh) against a real private-core layout.
Run: python3 -m unittest discover -s scripts/tests -v
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[2]
REAL_GIT = shutil.which("git")


class EnsureCoreTest(unittest.TestCase):
    """ensure_core: debug builds accept any populated core/; releases need a pushed private core."""
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="aquarestore-core-test-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.repo = self.base / "repo"
        (self.repo / "scripts").mkdir(parents=True)
        for name in ("_signing-common.sh", "release-settings.sh"):
            shutil.copy(PROJECT / "scripts" / name, self.repo / "scripts")
        self.env = dict(os.environ, GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="protocol.file.allow", GIT_CONFIG_VALUE_0="always")

    def git(self, cwd, *args):
        return subprocess.check_output([REAL_GIT, "-c", "user.name=T", "-c", "user.email=t@example.invalid", *args],
                                       cwd=cwd, text=True, env=self.env, stderr=subprocess.STDOUT).strip()

    def ensure(self, *args):
        return subprocess.run(["bash", "-c", '. scripts/_signing-common.sh; ensure_core "$@"', "ensure", *args],
                              cwd=self.repo, env=self.env, capture_output=True, text=True)

    def private_core(self):
        """A bare 'AquaRestore-Core' with one commit, mounted at core/ like the real submodule."""
        remote = self.base / "core.git"
        seed = self.base / "seed"
        (seed / "android/main").mkdir(parents=True)
        (seed / "android/main/Grade.kt").write_text("// core\n")
        self.git(self.base, "init", "-q", "--bare", "-b", "main", str(remote))
        self.git(seed, "init", "-q", "-b", "main")
        self.git(seed, "add", ".")
        self.git(seed, "commit", "-qm", "core")
        self.git(seed, "push", "-q", str(remote), "main")
        self.git(self.repo, "init", "-q")
        self.git(self.repo, "submodule", "add", "-q", str(remote), "core")
        self.git(self.repo, "commit", "-qam", "Add core")

    def test_stub_core_builds_debug_but_never_releases(self):
        (self.repo / "core/android/main").mkdir(parents=True)
        self.assertEqual(0, self.ensure().returncode)
        result = self.ensure("--release")
        self.assertNotEqual(0, result.returncode)
        self.assertIn("public stub", result.stderr)

    def test_missing_core_explains_what_to_run(self):
        result = self.ensure()
        self.assertNotEqual(0, result.returncode)
        self.assertIn("use-core-stub.sh", result.stderr)

    def test_fresh_clone_fetches_core(self):
        self.private_core()
        clone = self.base / "clone"
        self.git(self.base, "clone", "-q", str(self.repo), str(clone))
        (clone / "scripts").mkdir(exist_ok=True)
        for name in ("_signing-common.sh", "release-settings.sh"):
            shutil.copy(PROJECT / "scripts" / name, clone / "scripts")
        self.repo = clone
        self.assertFalse((clone / "core/android/main").exists())
        result = self.ensure("--release")
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertTrue((clone / "core/android/main/Grade.kt").exists())

    def test_release_refuses_unpushed_or_uncommitted_core(self):
        self.private_core()
        self.assertEqual(0, self.ensure("--release").returncode)
        (self.repo / "core/android/main/Grade.kt").write_text("// tuned\n")
        self.assertIn("uncommitted", self.ensure("--release").stderr)
        self.git(self.repo / "core", "commit", "-qam", "Tune")
        self.assertIn("not at the commit", self.ensure("--release").stderr)
        self.git(self.repo, "commit", "-qam", "Update core")
        self.assertIn("not on AquaRestore-Core", self.ensure("--release").stderr)
        self.git(self.repo / "core", "push", "-q", "origin", "HEAD:main")
        result = self.ensure("--release")
        self.assertEqual(0, result.returncode, result.stderr)


if __name__ == '__main__':
    unittest.main()
