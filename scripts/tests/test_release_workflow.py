"""Exercise release orchestration in isolated repos; network/signing are stubbed.
The real signing path is validated separately with release-github.sh --dry-run.
Run: python3 -m unittest discover -s scripts/tests -v
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[2]
REAL_GIT = shutil.which("git")


class ReleaseWorkflowTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="aquarestore-release-test-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.repo = self.base / "repo with spaces"
        (self.repo / "scripts").mkdir(parents=True)
        (self.repo / "android/app").mkdir(parents=True)
        for name in ("release-github.sh", "_signing-common.sh"):
            shutil.copy(PROJECT / "scripts" / name, self.repo / "scripts" / name)
        (self.repo / ".gitignore").write_text("dist/\n")
        (self.repo / "android/app/build.gradle.kts").write_text('        versionCode = 1\n        versionName = "1.0.0"\n')
        self.log = self.base / "calls.jsonl"
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.executable(self.bin / "gh", '''#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
with open(os.environ['TEST_RELEASE_LOG'], 'a') as f: f.write(json.dumps(['gh'] + args) + '\\n')
if args[:1] == ['api'] and 'matching-refs' in args[1]:
    if os.environ.get('TEST_EXISTING_TAG'): print('refs/tags/' + os.environ['TEST_EXISTING_TAG'])
if args[:2] == ['release', 'create'] and os.environ.get('TEST_UPLOAD_FAIL'): sys.exit(1)
if args[:2] == ['release', 'view']: print('https://github.com/example/aqua/releases/tag/v1.0.0')
''')
        self.executable(self.bin / "git", '''#!/usr/bin/env python3
import json, os, sys
if sys.argv[1:2] == ['push']:
    with open(os.environ['TEST_RELEASE_LOG'], 'a') as f: f.write(json.dumps(['git'] + sys.argv[1:]) + '\\n')
    sys.exit(0)
os.execv(os.environ['TEST_REAL_GIT'], [os.environ['TEST_REAL_GIT']] + sys.argv[1:])
''')
        self.executable(self.repo / "scripts/build-android-release.sh", '''#!/usr/bin/env python3
import os, pathlib, re
root = pathlib.Path(__file__).resolve().parents[1]
s = (root / 'android/app/build.gradle.kts').read_text()
v = re.search(r'versionName = "([^"]+)"', s).group(1)
c = re.search(r'versionCode = (\\d+)', s).group(1)
(root / 'dist').mkdir(exist_ok=True)
(root / 'dist' / f'AquaRestore-{v}-{c}.apk').write_bytes(b'workflow test only')
(root / 'dist' / f'AquaRestore-{v}-{c}.SHA256SUMS').write_text('workflow test only')
''')
        self.executable(self.repo / "scripts/build-android-play.sh", '''#!/usr/bin/env python3
import pathlib, re
root = pathlib.Path(__file__).resolve().parents[1]
s = (root / 'android/app/build.gradle.kts').read_text()
v = re.search(r'versionName = "([^"]+)"', s).group(1)
c = re.search(r'versionCode = (\\d+)', s).group(1)
(root / 'dist' / f'AquaRestore-{v}-{c}-play.aab').write_bytes(b'workflow test only')
''')
        self.env = os.environ.copy()
        self.env.update(PATH=str(self.bin) + os.pathsep + os.environ["PATH"], TEST_RELEASE_LOG=str(self.log), TEST_REAL_GIT=REAL_GIT)
        self.git("init", "-q")
        self.git("config", "user.name", "Release Test")
        self.git("config", "user.email", "test@example.invalid")
        self.git("add", ".")
        self.git("commit", "-qm", "Initial fixture")
        self.git("remote", "add", "origin", "git@github.com:example/aqua.git")

    @staticmethod
    def executable(path, source):
        path.write_text(source)
        path.chmod(0o755)

    def git(self, *args):
        return subprocess.check_output([REAL_GIT, *args], cwd=self.repo, text=True).strip()

    def run_release(self, *args):
        return subprocess.run(["bash", "scripts/release-github.sh", *args], cwd=self.repo,
                              env=self.env, capture_output=True, text=True, stdin=subprocess.DEVNULL)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_version_bump_sign_publish_order_and_assets(self):
        result = self.run_release("--version", "1.1.0")
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn('versionCode = 2', (self.repo / 'android/app/build.gradle.kts').read_text())
        self.assertEqual(self.git('rev-parse', 'HEAD'), self.git('rev-list', '-n1', 'v1.1.0'))
        calls = self.calls()
        push = next(i for i, c in enumerate(calls) if c[:2] == ['git', 'push'])
        create = next(i for i, c in enumerate(calls) if c[:3] == ['gh', 'release', 'create'])
        publish = next(i for i, c in enumerate(calls) if c[:3] == ['gh', 'release', 'edit'])
        self.assertLess(push, create)
        self.assertLess(create, publish)
        self.assertIn('--atomic', calls[push])
        self.assertIn('--draft', calls[create])
        self.assertTrue(any(x.endswith('AquaRestore-1.1.0-2.apk') for x in calls[create]))
        self.assertTrue(any(x.endswith('.SHA256SUMS') for x in calls[create]))
        self.assertIn('--draft=false', calls[publish])

    def test_play_bundle_matches_the_release_and_stays_off_github(self):
        result = self.run_release("--version", "1.1.0", "--play")
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertTrue((self.repo / 'dist/AquaRestore-1.1.0-2-play.aab').exists())
        self.assertIn('AquaRestore-1.1.0-2-play.aab', result.stdout)
        create = next(c for c in self.calls() if c[:3] == ['gh', 'release', 'create'])
        self.assertFalse(any(x.endswith('.aab') for x in create))

    def test_dry_run_never_writes_git_or_calls_github(self):
        before = self.git('rev-parse', 'HEAD')
        result = self.run_release('--dry-run')
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(before, self.git('rev-parse', 'HEAD'))
        self.assertEqual('', self.git('tag'))
        self.assertEqual([], self.calls())

    def test_dirty_tree_stops_before_build_or_push(self):
        (self.repo / 'uncommitted.txt').write_text('work in progress')
        result = self.run_release()
        self.assertNotEqual(0, result.returncode)
        self.assertFalse((self.repo / 'dist').exists())
        self.assertFalse(any(c[:2] == ['git', 'push'] for c in self.calls()))

    def test_existing_remote_tag_is_never_overwritten(self):
        self.env['TEST_EXISTING_TAG'] = 'v1.0.0'
        result = self.run_release()
        self.assertNotEqual(0, result.returncode)
        self.assertIn('never overwritten', result.stderr)
        self.assertFalse((self.repo / 'dist').exists())

    def test_upload_failure_does_not_publish(self):
        self.env['TEST_UPLOAD_FAIL'] = '1'
        result = self.run_release()
        self.assertNotEqual(0, result.returncode)
        self.assertFalse(any(c[:3] == ['gh', 'release', 'edit'] for c in self.calls()))

    def test_draft_stays_unpublished(self):
        result = self.run_release('--draft')
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertFalse(any(c[:3] == ['gh', 'release', 'edit'] for c in self.calls()))


class EnsureCoreTest(unittest.TestCase):
    """ensure_core: debug builds accept any populated core/; releases need a pushed private core."""
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="aquarestore-core-test-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.repo = self.base / "repo"
        (self.repo / "scripts").mkdir(parents=True)
        shutil.copy(PROJECT / "scripts" / "_signing-common.sh", self.repo / "scripts")
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
        shutil.copy(PROJECT / "scripts" / "_signing-common.sh", clone / "scripts")
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
