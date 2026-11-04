import hashlib
import importlib.util
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("feature_build", Path(__file__).resolve().parents[1] / "prepare-ios-features.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class FeatureBuildTests(unittest.TestCase):
    def generate(self, photo=None, video=None, environment=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            settings = {"PHOTO": photo, "VIDEO": video}
            (root / ".env").write_text("".join(
                f'export AQUARESTORE_BATCH_{kind}_UNLOCK_CODE="{code}"\n'
                for kind, code in settings.items() if code is not None))
            output = root / "app" / "BatchGate.plist"
            with patch.dict(os.environ, environment or {}, clear=True):
                module.generate(root, output)
            return plistlib.loads(output.read_bytes()), output.read_bytes()

    def assertCode(self, values, feature, code):
        expected = hashlib.pbkdf2_hmac("sha256", code.encode(), bytes.fromhex(values[feature + "Salt"]), 120000).hex()
        self.assertEqual(expected, values[feature + "Verifier"])

    def test_missing_settings_enable_features_independently(self):
        values, _ = self.generate()
        self.assertEqual(values["photoVerifier"], "")
        self.assertEqual(values["videoVerifier"], "")
        values, _ = self.generate(photo="photos")
        self.assertCode(values, "photo", "photos")
        self.assertEqual(values["videoVerifier"], "")
        values, _ = self.generate(video="videos")
        self.assertEqual(values["photoVerifier"], "")
        self.assertCode(values, "video", "videos")

    def test_only_independent_salted_verifiers_are_packaged(self):
        code = "sample-測試-5678"
        first, raw = self.generate(photo=code, video="video-only")
        second, _ = self.generate(photo=code, video="video-only")
        self.assertNotIn(code.encode(), raw)
        self.assertNotIn(b"video-only", raw)
        self.assertNotEqual(first["photoSalt"], second["photoSalt"])
        self.assertNotEqual(first["photoSalt"], first["videoSalt"])
        self.assertCode(first, "photo", code)
        self.assertCode(first, "video", "video-only")

    def test_debug_uses_actual_bundle_identifier_for_both_features(self):
        package = "com.aquarestore.app.debug"
        values, raw = self.generate(photo="release-photo", video="release-video", environment={
            "CONFIGURATION": "Debug", "PRODUCT_BUNDLE_IDENTIFIER": package})
        self.assertCode(values, "photo", package)
        self.assertCode(values, "video", package)
        self.assertNotIn(package.encode(), raw)

    def test_release_environment_overrides_dotenv_independently(self):
        values, _ = self.generate(photo="file-photo", video="file-video", environment={
            "CONFIGURATION": "Release", "AQUARESTORE_BATCH_PHOTO_UNLOCK_CODE": "environment-photo"})
        self.assertCode(values, "photo", "environment-photo")
        self.assertCode(values, "video", "file-video")
